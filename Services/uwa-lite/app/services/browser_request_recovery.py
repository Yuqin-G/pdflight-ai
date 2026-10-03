"""Request-triggered browser recovery without background internet polling."""

from __future__ import annotations

import asyncio
import os
import time
from dataclasses import dataclass
from typing import Any, Callable, Optional
from urllib.parse import urlsplit

from app.core.config import get_logger
from app.services.process_restart import schedule_browser_recovery_restart


logger = get_logger("BROWSER.RECOVERY")
_ERROR_PAGE_PREFIXES = ("chrome-error://", "about:neterror")
_REQUEST_STATE_KEY = "_uwa_browser_preflight_complete"
_QWEN_HOSTS = {"chat.qwen.ai", "www.chat.qwen.ai"}
_NETWORK_STATE_JS = r"""
return (() => {
  const key = '__uwaRequestRecoveryNetworkState';
  let state = window[key];
  if (!state) {
    state = { offlineSeen: navigator.onLine === false };
    window.addEventListener('offline', () => { state.offlineSeen = true; });
    window.addEventListener('online', () => { state.onlineSeen = true; });
    window[key] = state;
  }
  return {
    online: navigator.onLine !== false,
    offlineSeen: state.offlineSeen === true,
  };
})();
""".strip()


class BrowserRequestRecoveryUnavailable(RuntimeError):
    """Raised after the bounded soft-recovery attempt cannot restore CDP."""


class BrowserNetworkUnavailable(RuntimeError):
    """Raised when the Qwen page reports that the machine is currently offline."""


@dataclass(frozen=True)
class BrowserRecoveryResult:
    ready: bool
    recovered: bool = False
    created_page: bool = False
    reloaded_error_pages: int = 0
    reloaded_network_pages: int = 0


class BrowserRequestRecovery:
    def __init__(
        self,
        *,
        timeout_seconds: Optional[float] = None,
        retry_delay_seconds: Optional[float] = None,
        network_grace_seconds: Optional[float] = None,
        restart_scheduler: Callable[[str], Any] = schedule_browser_recovery_restart,
    ) -> None:
        configured_timeout = timeout_seconds
        if configured_timeout is None:
            try:
                configured_timeout = float(
                    os.getenv("BROWSER_REQUEST_RECOVERY_TIMEOUT_SECONDS", "8")
                )
            except (TypeError, ValueError):
                configured_timeout = 8.0
        self.timeout_seconds = max(1.0, float(configured_timeout))
        configured_retry_delay = retry_delay_seconds
        if configured_retry_delay is None:
            try:
                configured_retry_delay = float(
                    os.getenv("BROWSER_REQUEST_RECOVERY_RETRY_DELAY_SECONDS", "0.4")
                )
            except (TypeError, ValueError):
                configured_retry_delay = 0.4
        self.retry_delay_seconds = max(0.0, float(configured_retry_delay))
        configured_network_grace = network_grace_seconds
        if configured_network_grace is None:
            try:
                configured_network_grace = float(
                    os.getenv("BROWSER_REQUEST_NETWORK_GRACE_SECONDS", "5")
                )
            except (TypeError, ValueError):
                configured_network_grace = 5.0
        self.network_grace_seconds = max(0.0, float(configured_network_grace))
        self._restart_scheduler = restart_scheduler
        self._lock = asyncio.Lock()
        self._restart_scheduled = False

    async def ensure_ready(
        self,
        browser: Any,
        request: Any = None,
    ) -> BrowserRecoveryResult:
        if self._request_was_checked(request):
            return BrowserRecoveryResult(ready=True)

        async with self._lock:
            if self._request_was_checked(request):
                return BrowserRecoveryResult(ready=True)
            try:
                result = await asyncio.wait_for(
                    asyncio.to_thread(self._ensure_ready_sync, browser),
                    timeout=self.timeout_seconds,
                )
            except BrowserNetworkUnavailable:
                # Restarting the local process cannot restore an offline network.
                raise
            except BrowserRequestRecoveryUnavailable as exc:
                self._schedule_restart_once(str(exc))
                raise
            except asyncio.TimeoutError as exc:
                message = (
                    f"浏览器软恢复超过 {self.timeout_seconds:g} 秒，"
                    "已安排受控重启"
                )
                self._schedule_restart_once(message)
                raise BrowserRequestRecoveryUnavailable(message) from exc
            except Exception as exc:
                message = f"浏览器软恢复失败: {exc}"
                self._schedule_restart_once(message)
                raise BrowserRequestRecoveryUnavailable(message) from exc

            self._mark_request_checked(request)
            if result.recovered:
                logger.warning(
                    "请求到达时已完成浏览器软恢复 "
                    f"(created_page={result.created_page}, "
                    f"reloaded_error_pages={result.reloaded_error_pages}, "
                    f"reloaded_network_pages={result.reloaded_network_pages})"
                )
            return result

    def _ensure_ready_sync(self, browser: Any) -> BrowserRecoveryResult:
        was_connected = bool(getattr(browser, "_connected", True))
        previous_handle = getattr(browser, "browser_handle", None)
        health_recovered = False
        health = {}
        try:
            health_attempts = int(os.getenv("BROWSER_REQUEST_RECOVERY_ATTEMPTS", "3"))
        except (TypeError, ValueError):
            health_attempts = 3
        health_attempts = max(1, min(5, health_attempts))
        for attempt in range(health_attempts):
            health = browser.health_check() or {}
            if bool(health.get("connected")):
                health_recovered = attempt > 0
                break
            if attempt + 1 < health_attempts and self.retry_delay_seconds > 0:
                time.sleep(self.retry_delay_seconds)
        if not bool(health.get("connected")):
            detail = str(health.get("error") or "无法连接到浏览器")
            raise BrowserRequestRecoveryUnavailable(detail)

        handle = browser.get_browser_handle()
        if handle is None or not hasattr(handle, "_run_cdp"):
            raise BrowserRequestRecoveryUnavailable("浏览器 CDP 句柄不可用")

        target_result = handle._run_cdp("Target.getTargets") or {}
        target_infos = target_result.get("targetInfos")
        if not isinstance(target_infos, list):
            raise BrowserRequestRecoveryUnavailable("浏览器目标列表不可用")

        page_targets = [
            item
            for item in target_infos
            if isinstance(item, dict)
            and str(item.get("type") or "").strip().lower() == "page"
        ]
        created_page = False
        if not page_targets:
            created = handle._run_cdp("Target.createTarget", url="about:blank") or {}
            target_id = str(created.get("targetId") or "").strip()
            if not target_id:
                raise BrowserRequestRecoveryUnavailable("浏览器没有页面且无法创建空白页面")
            created_page = True
            self._reset_tab_pool(browser, "request_recovery_empty_browser")

        reloaded_error_pages = 0
        for item in page_targets:
            page_url = str(item.get("url") or "").strip().lower()
            if not page_url.startswith(_ERROR_PAGE_PREFIXES):
                continue
            target_id = str(item.get("targetId") or "").strip()
            if not target_id:
                continue
            try:
                tab = handle.get_tab(target_id)
                tab.run_cdp("Page.reload", ignoreCache=False)
                reloaded_error_pages += 1
            except Exception as exc:
                logger.debug(f"重载网络错误页失败 ({target_id}): {exc}")

        reloaded_network_pages = 0
        for item in page_targets:
            page_url = str(item.get("url") or "").strip()
            try:
                hostname = str(urlsplit(page_url).hostname or "").strip().lower()
            except Exception:
                hostname = ""
            if hostname not in _QWEN_HOSTS:
                continue
            target_id = str(item.get("targetId") or "").strip()
            if not target_id:
                continue
            try:
                tab = handle.get_tab(target_id)
                network_state = tab.run_js(_NETWORK_STATE_JS) or {}
            except Exception as exc:
                logger.debug(f"读取 Qwen 页面网络状态失败 ({target_id}): {exc}")
                continue
            if network_state.get("online") is False:
                deadline = time.monotonic() + self.network_grace_seconds
                while network_state.get("online") is False and time.monotonic() < deadline:
                    time.sleep(max(0.05, self.retry_delay_seconds))
                    try:
                        network_state = tab.run_js(_NETWORK_STATE_JS) or {}
                    except Exception as exc:
                        logger.debug(f"等待 Qwen 页面恢复联网失败 ({target_id}): {exc}")
                        break
                if network_state.get("online") is False:
                    raise BrowserNetworkUnavailable("Qwen 页面检测到当前仍处于断网状态")
            if not bool(network_state.get("offlineSeen")):
                continue
            try:
                tab.run_cdp("Page.reload", ignoreCache=False)
                reloaded_network_pages += 1
            except Exception as exc:
                logger.debug(f"恢复联网后重载 Qwen 页面失败 ({target_id}): {exc}")

        if reloaded_error_pages or reloaded_network_pages:
            self._reset_tab_pool(browser, "request_recovery_network_state")

        handle_changed = previous_handle is not None and previous_handle is not handle
        return BrowserRecoveryResult(
            ready=True,
            recovered=(
                not was_connected
                or health_recovered
                or handle_changed
                or created_page
                or reloaded_error_pages > 0
                or reloaded_network_pages > 0
            ),
            created_page=created_page,
            reloaded_error_pages=reloaded_error_pages,
            reloaded_network_pages=reloaded_network_pages,
        )

    @staticmethod
    def _reset_tab_pool(browser: Any, reason: str) -> None:
        reset = getattr(browser, "_shutdown_tab_pool_for_reconnect", None)
        if callable(reset):
            reset(reason)

    @staticmethod
    def _request_was_checked(request: Any) -> bool:
        state = getattr(request, "state", None)
        return bool(getattr(state, _REQUEST_STATE_KEY, False)) if state is not None else False

    @staticmethod
    def _mark_request_checked(request: Any) -> None:
        state = getattr(request, "state", None)
        if state is not None:
            setattr(state, _REQUEST_STATE_KEY, True)

    def _schedule_restart_once(self, reason: str) -> None:
        if self._restart_scheduled:
            return
        self._restart_scheduled = True
        self._restart_scheduler(reason)


browser_request_recovery = BrowserRequestRecovery()

"""Small, supervised process-restart hooks shared by runtime recovery paths."""

from __future__ import annotations

import asyncio
import os
import threading

from app.core.config import get_logger


logger = get_logger("PROCESS.RESTART")
_schedule_lock = threading.Lock()
_browser_recovery_restart_scheduled = False


def schedule_browser_recovery_restart(reason: str, delay_seconds: float = 1.0) -> bool:
    """Exit with code 4 after the current error response has time to flush.

    The launcher treats code 4 as a request to revalidate/relaunch Chromium before
    starting the API child again. Repeated failures share one scheduled exit.
    """
    global _browser_recovery_restart_scheduled
    with _schedule_lock:
        if _browser_recovery_restart_scheduled:
            return False
        _browser_recovery_restart_scheduled = True

    async def trigger_restart() -> None:
        await asyncio.sleep(max(0.2, float(delay_seconds or 1.0)))
        logger.error(f"浏览器请求恢复失败，交由启动器重建浏览器连接: {reason}")
        os._exit(4)

    try:
        asyncio.get_running_loop().create_task(
            trigger_restart(),
            name="browser-recovery-process-restart",
        )
        return True
    except Exception:
        with _schedule_lock:
            _browser_recovery_restart_scheduled = False
        raise

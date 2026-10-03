"""受控浏览器保障：端口探测 → 建 target → 必要时拉起 Chrome。

DrissionPage 只能连接已有调试端口的浏览器，且浏览器至少要有一个
页面 target；本模块在 core 的 _connect 失败前兜底，让 lite 服务可以
脱离完整版 UWA 的 start.py 独立工作。
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
import urllib.error
import urllib.request

_CHROME_CANDIDATES = (
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
)

_LAUNCH_ARGS = (
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows",
    "--disable-features=CalculateNativeWinOcclusion,AutomaticTabDiscarding,TabFreeze,IntensiveWakeUpThrottling",
    "--disable-renderer-backgrounding",
    "--no-default-browser-check",
    "--no-first-run",
)


def _http_json(url: str, timeout: float = 2.0, method: str = "GET"):
    req = urllib.request.Request(url, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8", "replace"))
    except Exception:
        return None


def debug_port_alive(port: int) -> bool:
    return bool(_http_json(f"http://127.0.0.1:{port}/json/version"))


def target_count(port: int) -> int:
    targets = _http_json(f"http://127.0.0.1:{port}/json/list")
    return len(targets) if isinstance(targets, list) else 0


def ensure_target(port: int) -> bool:
    """浏览器在跑但没有任何页面时，创建一个空白 target。"""
    if target_count(port) > 0:
        return True
    created = _http_json(
        f"http://127.0.0.1:{port}/json/new?about:blank",
        timeout=5.0,
        method="PUT",
    )
    return bool(created and created.get("id"))


def _find_browser_executable() -> str | None:
    for path in _CHROME_CANDIDATES:
        if os.path.exists(path):
            return path
    return shutil.which("google-chrome") or shutil.which("chromium")


def launch_browser(port: int, profile_dir: str) -> bool:
    exe = _find_browser_executable()
    if not exe:
        return False
    args = [
        exe,
        f"--remote-debugging-port={port}",
        f"--user-data-dir={profile_dir}",
        *_LAUNCH_ARGS,
        "about:blank",
    ]
    subprocess.Popen(
        args,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 30
    while time.time() < deadline:
        if debug_port_alive(port) and ensure_target(port):
            return True
        time.sleep(0.5)
    return False


def ensure_browser_running(port: int, profile_dir: str) -> bool:
    """保证 9222 上有可连接的受控浏览器。返回是否可以连接。"""
    if not debug_port_alive(port):
        return launch_browser(port, profile_dir)
    return ensure_target(port)

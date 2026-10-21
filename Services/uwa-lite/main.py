"""uwa-lite — PDFlight 随附的精简版 Universal Web API。

只保留网页端聊天桥接链路：OpenAI 兼容 chat completions、标签页池、
会话绑定（conversation_key）与浏览器工作流引擎。GUI、更新器、
Anthropic/Codex 兼容层与命令配置面板均已移除。

浏览器 profile 通过 BROWSER_PROFILE_DIR 指定，默认使用 PDFlight
Application Support 下的 chrome_profile（保留已登录站点会话）。
"""

import asyncio
import logging
import os
import sys
import threading
from contextlib import asynccontextmanager
from pathlib import Path

_ROOT = Path(__file__).resolve().parent
os.chdir(_ROOT)  # config/、日志等相对路径锚定到本目录

# 环境默认值（在导入 app.core.config 之前设置，.env 仍可覆盖）
os.environ.setdefault("APP_HOST", "127.0.0.1")
os.environ.setdefault("APP_PORT", "8199")
os.environ.setdefault("AUTH_ENABLED", "false")
os.environ.setdefault("DASHBOARD_ENABLED", "false")
os.environ.setdefault("AUTO_UPDATE_ENABLED", "false")
_APP_SUPPORT = Path.home() / "Library/Application Support/dev.pdflight.reader"
os.environ.setdefault(
    "BROWSER_PROFILE_DIR",
    str(_APP_SUPPORT / "chrome_profile")
    if (_APP_SUPPORT / "chrome_profile").exists()
    else "chrome_profile",
)
os.environ.setdefault(
    "CONVERSATION_BINDINGS_DB",
    str(_APP_SUPPORT / "conversation_bindings.sqlite3")
    if (_APP_SUPPORT / "conversation_bindings.sqlite3").exists()
    else "config/conversation_bindings.sqlite3",
)

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.core import get_browser
from app.core.config import AppConfig, get_logger
import browser_ensure

logger = get_logger("UWA-LITE")


def _profile_dir() -> str:
    raw = os.environ.get("BROWSER_PROFILE_DIR", "chrome_profile")
    return str((_ROOT / raw).resolve()) if not os.path.isabs(raw) else raw


def _patch_browser_connect() -> None:
    """给 BrowserCore._connect 加自动拉起/补 target 兜底。"""
    from app.core.browser.connection import BrowserConnectionMixin

    original = BrowserConnectionMixin._connect

    def _connect_with_ensure(self):
        port = int(getattr(self, "port", None) or os.environ.get("BROWSER_PORT", 9333))
        if not browser_ensure.debug_port_alive(port):
            logger.info(f"[browser] 调试端口 {port} 无响应，拉起受控浏览器")
            if not browser_ensure.ensure_browser_running(port, _profile_dir()):
                return False
        elif not browser_ensure.ensure_target(port):
            logger.debug(f"[browser] 端口 {port} 存活但无法创建 target")
        return original(self)

    BrowserConnectionMixin._connect = _connect_with_ensure


_patch_browser_connect()

logging.basicConfig(
    level=getattr(logging, AppConfig.get_log_level(), logging.INFO),
    format="%(message)s",
)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    try:
        from app.utils.file_paste import cleanup_temp_dir

        cleanup_temp_dir()
    except Exception:
        pass

    def _probe_browser() -> None:
        try:
            health = get_browser(auto_connect=False).health_check()
            if health.get("connected"):
                logger.info("[startup] 受控浏览器已连接")
            else:
                logger.info("[startup] 受控浏览器暂未连接（首次请求时再重试）")
        except Exception as e:
            logger.warning(f"[startup] 浏览器健康检查失败: {e}")

    threading.Thread(target=_probe_browser, daemon=True).start()

    try:
        from app.services.command_engine import command_engine

        command_engine.ensure_scheduler_running()
    except Exception as e:
        logger.debug(f"[startup] 命令调度器未启动（忽略）: {e}")

    yield

    try:
        from app.services.command_engine import command_engine

        command_engine.shutdown()
    except Exception:
        pass


app = FastAPI(title="uwa-lite", version="0.1.0", lifespan=lifespan)

if AppConfig.is_cors_enabled():
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

from app.api.chat import router as chat_router
from app.api.tab_routes import router as tab_router

app.include_router(chat_router)
app.include_router(tab_router)


@app.get("/health", include_in_schema=False)
async def health():
    try:
        browser = get_browser(auto_connect=False)
        browser_health = await asyncio.to_thread(browser.health_check)
        connected = bool(browser_health.get("connected"))
    except Exception:
        connected = False
    return {"status": "ok", "service": "uwa-lite", "browser_connected": connected}


@app.get("/", include_in_schema=False)
async def root():
    return {"service": "uwa-lite", "docs": "/docs", "health": "/health"}


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content={"error": {"message": "请求参数校验失败", "details": exc.errors()[:5]}},
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host=AppConfig.get_host(),
        port=AppConfig.get_port(),
        log_level=AppConfig.get_log_level().lower(),
    )

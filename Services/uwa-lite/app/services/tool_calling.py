"""uwa-lite stub: 函数调用支持已裁掉。

PDFlight 从不发送 tools 字段,has_tool_calling_request 恒为 False,
所有 tool-call 路径因而不可达;其余符号仅为满足 import 存在。
"""

from __future__ import annotations

from typing import Any, Dict

_UNAVAILABLE = "tool calling is not available in uwa-lite"


def has_tool_calling_request(*args: Any, **kwargs: Any) -> bool:
    return False


def get_tool_calling_allow_media_postprocess() -> bool:
    return False


def extract_tool_calling_assistant_content(response: Dict[str, Any]) -> str:
    choices = response.get("choices") if isinstance(response, dict) else None
    if isinstance(choices, list) and choices:
        message = choices[0].get("message") if isinstance(choices[0], dict) else None
        if isinstance(message, dict):
            return str(message.get("content") or "")
    return ""


def build_tool_completion_response(*args: Any, **kwargs: Any) -> Any:
    raise RuntimeError(_UNAVAILABLE)


async def complete_tool_calling_roundtrip_async(*args: Any, **kwargs: Any) -> Any:
    raise RuntimeError(_UNAVAILABLE)


def decode_browser_non_stream_payload(payload: Any) -> Dict[str, Any]:
    return payload if isinstance(payload, dict) else {}


def iter_tool_stream_chunks(*args: Any, **kwargs: Any) -> Any:
    raise RuntimeError(_UNAVAILABLE)


def normalize_tool_request(*args: Any, **kwargs: Any) -> Any:
    raise RuntimeError(_UNAVAILABLE)


def summarize_messages_for_debug(*args: Any, **kwargs: Any) -> str:
    return ""

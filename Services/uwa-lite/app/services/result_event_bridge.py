"""uwa-lite stub: Arena 结果事件桥接已裁掉。

返回 None 让调用方走未启用分支,行为与完整版未装桥接时一致。
"""

from __future__ import annotations

from typing import Any, Optional


def create_result_event_handler(*args: Any, **kwargs: Any) -> Optional[Any]:
    return None


def emit_arena_snapshot_event(*args: Any, **kwargs: Any) -> None:
    return None

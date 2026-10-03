"""uwa-lite stub: 命令引擎已裁掉。

原引擎提供外部命令调度、网络拦截钩子和工作流中断;lite 服务不需要,
stub 以安全默认值满足 core/api 里的探测调用,所有检查恒为“无命令”。
"""

from __future__ import annotations

from typing import Any


class _CommandEngineStub:
    # ---- scheduler lifecycle (main.py) ----
    def ensure_scheduler_running(self) -> None:
        return None

    def shutdown(self) -> None:
        return None

    def is_scheduler_running(self) -> bool:
        return False

    # ---- session / interception probes (core browser, tab pool) ----
    def has_network_interception_for_session(self, *args: Any, **kwargs: Any) -> bool:
        return False

    def get_network_listen_pattern(self, *args: Any, **kwargs: Any) -> None:
        return None

    def check_workflow_triggers_now(self, *args: Any, **kwargs: Any) -> bool:
        return False

    def workflow_interrupt_requested(self, *args: Any, **kwargs: Any) -> bool:
        return False

    def should_block_request_for_session(self, *args: Any, **kwargs: Any) -> bool:
        return False

    def handle_network_event(self, *args: Any, **kwargs: Any) -> None:
        return None

    def handle_pending_workflow_interrupts(self, *args: Any, **kwargs: Any) -> None:
        return None

    def evict_session(self, *args: Any, **kwargs: Any) -> None:
        return None

    # ---- workflow runtime bookkeeping ----
    def begin_workflow_runtime(self, *args: Any, **kwargs: Any) -> None:
        return None

    def finish_workflow_runtime(self, *args: Any, **kwargs: Any) -> None:
        return None

    def update_workflow_runtime_step(self, *args: Any, **kwargs: Any) -> None:
        return None

    def update_workflow_target_side(self, *args: Any, **kwargs: Any) -> None:
        return None

    def schedule_deferred_workflow_commands(self, *args: Any, **kwargs: Any) -> None:
        return None

    def check_triggers(self, *args: Any, **kwargs: Any) -> None:
        return None

    def submit_background_task(self, *args: Any, **kwargs: Any) -> None:
        return None

    def emit_external_command_result_event(self, *args: Any, **kwargs: Any) -> None:
        return None

    # ---- priority helpers (browser workflow) ----
    def _get_request_priority_baseline(self) -> int:
        return 0

    def _normalize_priority(self, priority: Any, *args: Any, **kwargs: Any) -> Any:
        return priority


command_engine = _CommandEngineStub()

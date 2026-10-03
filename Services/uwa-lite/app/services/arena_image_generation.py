"""uwa-lite stub: Arena 图像生成已裁掉。

保留调用方需要的符号;所有 arena 判定恒为 False/None,
非 arena 请求路径行为与完整版一致。
"""

from __future__ import annotations

from typing import Any, List, Optional


ARENA_NON_RETRYABLE_CODES = frozenset()
ARENA_PROMPT_REJECTED_CODE = "arena_prompt_rejected"
ARENA_NATIVE_STOP_SELECTOR = ""


class ArenaImageGenerationError(Exception):
    pass


class ArenaImageGenerationGuard:
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        pass

    def observe(self, *args: Any, **kwargs: Any) -> None:
        return None

    def native_stop_present(self) -> bool:
        return False

    def detect_terminal_error(self) -> Optional[ArenaImageGenerationError]:
        return None


def capture_arena_result_baseline(*args: Any, **kwargs: Any) -> None:
    return None


def is_arena_image_generation_request(*args: Any, **kwargs: Any) -> bool:
    return False


def is_arena_page_url(*args: Any, **kwargs: Any) -> bool:
    return False


def is_interrupted_stream_reason(*args: Any, **kwargs: Any) -> bool:
    return False


def is_visible_arena_stop(*args: Any, **kwargs: Any) -> bool:
    return False


def validate_generated_images(images: Any, *args: Any, **kwargs: Any) -> List[Any]:
    return list(images) if isinstance(images, (list, tuple)) else []

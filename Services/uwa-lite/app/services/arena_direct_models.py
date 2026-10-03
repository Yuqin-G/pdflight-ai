"""uwa-lite stub: LMArena 直连模型目录已裁掉。

保留 OpenAI 模型条目的通用构造;arena 专属目录查询一律返回空,
模型路由回退到普通站点匹配。
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional


def build_openai_model_entries(
    models: List[Dict[str, Any]], *, created: int
) -> List[Dict[str, Any]]:
    entries: List[Dict[str, Any]] = []
    for model in models or []:
        if not isinstance(model, dict):
            continue
        public_id = str(model.get("id") or model.get("model_name") or "").strip()
        if not public_id:
            continue
        entries.append({
            "id": public_id,
            "object": "model",
            "created": int(created),
            "owned_by": "universal-web-api",
            "display_name": str(model.get("display_name") or public_id),
        })
    return entries


def get_arena_direct_catalog_for_tab(*args: Any, **kwargs: Any) -> Optional[Dict[str, Any]]:
    return None


def get_arena_direct_model_public_id(model: Any) -> str:
    return str(model or "").strip()


def list_arena_direct_models(*args: Any, **kwargs: Any) -> List[Dict[str, Any]]:
    return []


def match_arena_direct_model(*args: Any, **kwargs: Any) -> Optional[str]:
    return None


def resolve_arena_direct_model(*args: Any, **kwargs: Any) -> Optional[str]:
    return None


def get_model_catalog_preset(*args: Any, **kwargs: Any) -> Optional[Dict[str, Any]]:
    return None

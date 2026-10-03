"""Validation and extraction for explicit local PDF chat attachments."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List


MAX_PDF_ATTACHMENTS_PER_REQUEST = 4
MAX_PDF_ATTACHMENT_BYTES = 100 * 1024 * 1024


class PDFChatAttachmentError(ValueError):
    """Raised when a requested local PDF attachment is not safe to upload."""


def validate_pdf_attachment_path(raw_path: Any) -> str:
    path_text = str(raw_path or "").strip()
    if not path_text:
        raise PDFChatAttachmentError("PDF attachment path is empty")

    candidate = Path(path_text).expanduser()
    if not candidate.is_absolute():
        raise PDFChatAttachmentError("PDF attachment path must be absolute")

    try:
        resolved = candidate.resolve(strict=True)
    except OSError as exc:
        raise PDFChatAttachmentError("PDF attachment does not exist") from exc

    if not resolved.is_file() or resolved.suffix.lower() != ".pdf":
        raise PDFChatAttachmentError("Only local PDF files can be attached")

    try:
        size = resolved.stat().st_size
    except OSError as exc:
        raise PDFChatAttachmentError("PDF attachment cannot be read") from exc
    if size <= 0:
        raise PDFChatAttachmentError("PDF attachment is empty")
    if size > MAX_PDF_ATTACHMENT_BYTES:
        raise PDFChatAttachmentError("PDF attachment exceeds the 100 MB limit")

    try:
        with resolved.open("rb") as stream:
            signature = stream.read(5)
    except OSError as exc:
        raise PDFChatAttachmentError("PDF attachment cannot be read") from exc
    if signature != b"%PDF-":
        raise PDFChatAttachmentError("The selected file is not a valid PDF")

    return str(resolved)


def normalize_pdf_attachment_paths(raw_paths: Any) -> List[str]:
    if raw_paths is None:
        return []
    if not isinstance(raw_paths, list):
        raise PDFChatAttachmentError("pdf_attachments must be a list")
    if len(raw_paths) > MAX_PDF_ATTACHMENTS_PER_REQUEST:
        raise PDFChatAttachmentError(
            f"At most {MAX_PDF_ATTACHMENTS_PER_REQUEST} PDF files can be attached"
        )

    normalized: List[str] = []
    seen = set()
    for item in raw_paths:
        raw_path = item.get("path") if isinstance(item, dict) else item
        path = validate_pdf_attachment_path(raw_path)
        if path in seen:
            continue
        seen.add(path)
        normalized.append(path)
    return normalized


def attach_pdf_paths_to_latest_user_message(
    messages: List[Dict[str, Any]],
    paths: List[str],
) -> List[Dict[str, Any]]:
    """Add private local-file content parts without leaking paths into prompt text."""
    if not paths:
        return messages

    target_index = next(
        (
            index
            for index in range(len(messages) - 1, -1, -1)
            if isinstance(messages[index], dict)
            and str(messages[index].get("role") or "user").strip().lower() == "user"
        ),
        None,
    )
    if target_index is None:
        raise PDFChatAttachmentError("A PDF attachment requires a user message")

    updated = [dict(message) if isinstance(message, dict) else message for message in messages]
    target = updated[target_index]
    content = target.get("content", "")
    if isinstance(content, list):
        parts = list(content)
    else:
        parts = []
        if str(content or ""):
            parts.append({"type": "text", "text": str(content)})
    for path in paths:
        parts.append(
            {
                "type": "file_path",
                "file_path": {
                    "path": path,
                    "name": Path(path).name,
                    "mime_type": "application/pdf",
                },
            }
        )
    target["content"] = parts
    return updated


def extract_pdf_paths_from_messages(messages: List[Dict[str, Any]]) -> List[str]:
    paths: List[str] = []
    seen = set()
    for message in messages or []:
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for part in content:
            if not isinstance(part, dict) or part.get("type") != "file_path":
                continue
            value = part.get("file_path")
            raw_path = value.get("path") if isinstance(value, dict) else value
            path = validate_pdf_attachment_path(raw_path)
            if path not in seen:
                seen.add(path)
                paths.append(path)
    return paths


__all__ = [
    "PDFChatAttachmentError",
    "attach_pdf_paths_to_latest_user_message",
    "extract_pdf_paths_from_messages",
    "normalize_pdf_attachment_paths",
    "validate_pdf_attachment_path",
]

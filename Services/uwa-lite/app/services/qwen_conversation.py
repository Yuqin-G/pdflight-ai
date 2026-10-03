"""Qwen web-conversation metadata operations."""

from __future__ import annotations

from typing import Any

from app.services.conversation_bindings import normalize_conversation_title


_RENAME_ACTIVE_CONVERSATION_JS = r"""
return (async () => {
  const desired = String(arguments[0] || '').trim();
  if (!desired) return {ok: false, state: 'empty_title'};
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const waitFor = async (fn, timeout = 5000) => {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
      const value = fn();
      if (value) return value;
      await sleep(100);
    }
    return null;
  };
  const text = (element) => String(element?.textContent || '').trim();
  const activeItem = await waitFor(() => {
    const activeLink = document.querySelector(
      'a.chat-item-drag-active, .chat-item-drag-active, .chat-item-drag-web-active'
    );
    return activeLink?.closest('.chat-item-drag') || null;
  });
  if (!activeItem) return {ok: false, state: 'active_chat_missing'};
  const label = activeItem.querySelector('.chat-item-drag-link-content-tip-text');
  if (text(label) === desired) return {ok: true, state: 'unchanged', title: desired};
  const menuButton = activeItem.querySelector('button[aria-label="Chat Menu"]');
  if (!menuButton) return {ok: false, state: 'menu_button_missing'};
  menuButton.click();
  const renameItem = await waitFor(() => [...document.querySelectorAll('[role="menuitem"]')]
    .find((element) => ['重命名', 'Rename'].includes(text(element))));
  if (!renameItem) return {ok: false, state: 'rename_action_missing'};
  renameItem.click();
  const dialog = await waitFor(() => [...document.querySelectorAll('[role="dialog"]')]
    .find((element) => /重命名|rename/i.test(text(element))));
  if (!dialog) return {ok: false, state: 'rename_dialog_missing'};
  const input = dialog.querySelector('input, textarea');
  if (!input) return {ok: false, state: 'rename_input_missing'};
  input.focus();
  const prototype = input instanceof HTMLTextAreaElement
    ? HTMLTextAreaElement.prototype
    : HTMLInputElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
  if (setter) setter.call(input, desired);
  else input.value = desired;
  input.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText', data: desired}));
  input.dispatchEvent(new Event('change', {bubbles: true}));
  const confirmButton = [...dialog.querySelectorAll('button')].find((element) =>
    ['确认', '保存', '重命名', 'Confirm', 'Save', 'Rename'].includes(text(element))
    && !element.disabled
  );
  if (!confirmButton) return {ok: false, state: 'rename_confirm_missing'};
  confirmButton.click();
  const renamed = await waitFor(() => {
    const currentActive = document.querySelector(
      'a.chat-item-drag-active, .chat-item-drag-active, .chat-item-drag-web-active'
    );
    const currentLabel = currentActive?.closest('.chat-item-drag')
      ?.querySelector('.chat-item-drag-link-content-tip-text');
    return text(currentLabel) === desired ? currentLabel : null;
  }, 6000);
  return renamed
    ? {ok: true, state: 'renamed', title: desired}
    : {ok: false, state: 'rename_not_observed'};
})();
"""


def rename_qwen_conversation(tab: Any, title: object) -> dict[str, Any]:
    normalized_title = normalize_conversation_title(title)
    if not normalized_title:
        return {"ok": False, "state": "empty_title"}
    result = tab.run_js(_RENAME_ACTIVE_CONVERSATION_JS, normalized_title, timeout=15)
    return result if isinstance(result, dict) else {"ok": False, "state": "invalid_result"}


__all__ = ["rename_qwen_conversation"]

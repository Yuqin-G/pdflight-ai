import tempfile
import unittest
from pathlib import Path

from app.core.browser.prompt import BrowserPromptMixin
from app.services.conversation_bindings import ConversationBindingStore, plan_bound_request


class VerbatimPromptTests(unittest.TestCase):
    def test_bound_user_turn_is_literal_even_if_proxy_drops_extension(self):
        text = "  保留首尾空格\n\n第二行  "
        with tempfile.TemporaryDirectory() as tmp:
            store = ConversationBindingStore(Path(tmp) / "bindings.sqlite3")
            for key in ("pdflight:conversation:test", "session-legacy"):
                plan = plan_bound_request(store=store, key=key, route_domain="chat.qwen.ai",
                                          messages=[{"role": "user", "content": text}])
                self.assertTrue(plan.messages[0]["pdflight_verbatim"])
                self.assertEqual(BrowserPromptMixin()._build_prompt_from_messages(plan.messages), text)
                store.bind(key=key, route_domain="chat.qwen.ai",
                           conversation_url=f"https://chat.qwen.ai/c/{key.replace(':', '-')}")
                resumed = plan_bound_request(store=store, key=key, route_domain="chat.qwen.ai",
                                             messages=[{"role": "user", "content": text}])
                self.assertTrue(resumed.reuse_current_conversation)
                self.assertEqual(BrowserPromptMixin()._build_prompt_from_messages(resumed.messages), text)

    def test_explicit_image_and_pdf_do_not_add_placeholder_text(self):
        messages = [{"role": "user", "pdflight_verbatim": True, "content": [
            {"type": "text", "text": "原文\n"},
            {"type": "image_url", "image_url": {"url": "data:image/png;base64,AA=="}},
            {"type": "file_path", "path": "/tmp/example.pdf"},
        ]}]
        self.assertEqual(BrowserPromptMixin()._build_prompt_from_messages(messages), "原文\n")

    def test_existing_multi_message_requests_keep_role_formatting(self):
        messages = [{"role": "system", "content": "system instruction"},
                    {"role": "user", "content": "user text"}]
        self.assertEqual(BrowserPromptMixin()._build_prompt_from_messages(messages),
                         "system: system instruction\n\nuser: user text")


if __name__ == "__main__":
    unittest.main()

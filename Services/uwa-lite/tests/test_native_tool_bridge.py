import json
import unittest

from app.services.tool_calling import (
    build_browser_messages_for_tools,
    complete_tool_calling_roundtrip_async,
    has_tool_calling_request,
    iter_tool_stream_chunks,
    normalize_tool_request,
)


class NativeToolBridgeTests(unittest.IsolatedAsyncioTestCase):
    async def test_browser_tool_call_and_result_round_trip(self):
        tools = [{"type": "function", "function": {"name": "pdf_reading", "description": "Read a PDF page", "parameters": {"type": "object", "properties": {"page": {"type": "integer"}}, "required": ["page"]}}}]
        normalized, choice = normalize_tool_request(tools=tools)
        self.assertTrue(has_tool_calling_request(messages=[], tools=tools))
        captured = []

        async def browser(messages):
            captured.extend(messages)
            return json.dumps({"mode": "tool_calls", "tool_calls": [{"name": "pdf_reading", "arguments": {"page": 1}}]})

        parsed = await complete_tool_calling_roundtrip_async([{"role": "user", "content": "Read page one"}], normalized, choice, False, browser)
        self.assertEqual(parsed["tool_calls"][0]["function"]["name"], "pdf_reading")
        self.assertTrue(any("pdf_reading" in message["content"] for message in captured))
        chunks = list(iter_tool_stream_chunks("test-model", parsed))
        self.assertTrue(any('"tool_calls"' in chunk for chunk in chunks))
        self.assertTrue(chunks[-1].strip().endswith("[DONE]"))
        call = parsed["tool_calls"][0]
        follow_up = build_browser_messages_for_tools([
            {"role": "assistant", "content": None, "tool_calls": [call]},
            {"role": "tool", "tool_call_id": call["id"], "content": "page one result"},
        ], normalized, choice, False)
        self.assertTrue(any("page one result" in message["content"] for message in follow_up))


if __name__ == "__main__":
    unittest.main()

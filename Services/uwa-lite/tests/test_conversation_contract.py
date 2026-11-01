"""Regression checks for native session -> actual Qwen web thread continuity."""
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from fastapi.responses import JSONResponse, StreamingResponse
from app.api import chat, tab_routes as routes
from app.services.conversation_bindings import ConversationBindingStore, is_conversation_url, plan_bound_request
URL = 'https://chat.qwen.ai/c/6cb0ae10-3ab8-4829-9726-98589c734bee'

class ContractTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = ConversationBindingStore(Path(self.tmp.name) / 'bindings.sqlite3')

    def test_native_session_aliases(self):
        for cls in [chat.ChatRequest, routes.ChatRequest]:
            for name in ['conversation_key', 'session_id', 'client_session_id', 'clientSessionId']:
                with self.subTest(cls=cls.__module__, name=name):
                    self.assertEqual(cls(model='qwen', messages=[], **{name: 'native-thread'}).conversation_key, 'native-thread')
            self.assertIsNone(cls(model='qwen', messages=[]).conversation_key)

    def test_guest_is_not_a_durable_conversation(self):
        self.assertFalse(is_conversation_url('chat.qwen.ai', 'https://chat.qwen.ai/c/guest'))
        self.assertFalse(is_conversation_url('chat.qwen.ai', 'http://chat.qwen.ai/c/owned'))
        self.assertTrue(is_conversation_url('chat.qwen.ai', URL))
        self.assertTrue(is_conversation_url('chat.qwen.ai', URL.replace('/c/', '/chat/')))

    def test_restart_continuation_sends_only_latest_user(self):
        self.store.bind(key='native-thread', route_domain='chat.qwen.ai', conversation_url=URL)
        restarted = ConversationBindingStore(self.store.database_path)
        messages = [{'role': 'system', 'content': 'PDF context'}, {'role': 'user', 'content': 'old'}, {'role': 'assistant', 'content': 'old answer'}, {'role': 'user', 'content': 'new'}]
        plan = plan_bound_request(store=restarted, key='native-thread', route_domain='chat.qwen.ai', messages=messages)
        self.assertEqual(plan.conversation_url, URL)
        self.assertTrue(plan.reuse_current_conversation)
        self.assertEqual(plan.messages, [messages[-1]])

    def test_runtime_context_is_not_a_new_user_turn(self):
        self.store.bind(key='native-thread', route_domain='chat.qwen.ai', conversation_url=URL)
        user = {'role':'user','name':'dsh_user','content':'actual entered question'}
        technical = {'role':'user','name':'dsh_context','content':'runtime context cleared'}
        plan = plan_bound_request(store=self.store, key='native-thread', route_domain='chat.qwen.ai', messages=[user, technical])
        self.assertEqual(plan.messages, [user])

    def test_lookup_metadata_strips_tokens(self):
        from app.services.conversation_bindings import conversation_metadata
        data = conversation_metadata('native-thread', URL + '?access_token=test#secret', 'continued')
        self.assertEqual(data['conversation_url'], URL)
        binding = self.store.bind(key='native-thread', route_domain='chat.qwen.ai', conversation_url=URL + '?access_token=test#secret')
        self.assertEqual(binding.conversation_url, URL)

    def test_qwen_workflow_clicks_verified_send_button(self):
        config = json.loads((Path(__file__).resolve().parents[1] / 'config/sites.json').read_text())
        for preset in config['chat.qwen.ai']['presets'].values():
            steps = preset['workflow']
            fill = next(i for i, step in enumerate(steps) if step.get('action') == 'FILL_INPUT')
            self.assertEqual((steps[fill+1]['action'], steps[fill+1]['target']), ('CLICK','send_btn'))

    async def _run_bound(self, streaming=False, late_url=False, url_sequence=None):
        browser = SimpleNamespace(tab_pool=SimpleNamespace(create_shared_site_tab=lambda *a, **k: {'ok': True, 'tab': {'persistent_index': 17, 'url': 'https://chat.qwen.ai/'}}))
        payload = {'id': 'chatcmpl-probe', 'object': 'chat.completion', 'choices': [{'index': 0, 'message': {'role': 'assistant', 'content': 'READY'}, 'finish_reason': 'stop'}]}
        if streaming:
            async def source():
                for delta,finish in [({'role':'assistant'},None),({'content':'READY'},None),({},'stop')]:
                    yield 'data: ' + json.dumps({'id':'chatcmpl-probe','object':'chat.completion.chunk','choices':[{'index':0,'delta':delta,'finish_reason':finish}]}) + '\n\n'
                yield 'data: [DONE]\n\n'
            result = StreamingResponse(source(), media_type='text/event-stream')
        else:
            result = JSONResponse(payload)
        ctx = SimpleNamespace(request_id='contract-test')
        with patch.object(routes, 'conversation_binding_store', self.store), patch.object(routes.request_manager, 'create_request', return_value=ctx), patch.object(routes.request_manager, 'record_request_input'), patch.object(routes, '_build_tab_resolution_headers', return_value={}), patch.object(routes, '_restore_bound_conversation_tab_url', return_value={'ok': True, 'url': 'https://chat.qwen.ai/'}), patch.object(routes, '_chat_with_resolved_tab', AsyncMock(return_value=result)), patch.object(routes, '_get_live_tab_url_by_index', return_value=URL, side_effect=url_sequence or ((['https://chat.qwen.ai/'] + [URL] * 8) if late_url else None)):
            response = await routes._chat_with_conversation_binding(None, routes.ChatRequest(model='qwen', messages=[{'role':'user','content':'READY'}], conversation_key='native-thread'), browser=browser, route_domain='chat.qwen.ai')
            if streaming:
                chunks = [c.decode() if isinstance(c, bytes) else c async for c in response.body_iterator]
                return ''.join(chunks)
            return response

    async def test_new_thread_is_not_sent_if_fresh_page_cannot_be_verified(self):
        browser = SimpleNamespace(tab_pool=SimpleNamespace(create_shared_site_tab=lambda *a, **k: {'ok': True, 'tab': {'persistent_index': 17}}))
        send = AsyncMock()
        with patch.object(routes, 'conversation_binding_store', self.store), patch.object(routes, '_restore_bound_conversation_tab_url', return_value={'ok': False}), patch.object(routes, '_chat_with_resolved_tab', send):
            with self.assertRaises(routes.HTTPException) as error:
                await routes._chat_with_conversation_binding(None, routes.ChatRequest(model='qwen', messages=[{'role':'user','content':'test'}], conversation_key='native-thread'), browser=browser, route_domain='chat.qwen.ai')
        self.assertEqual(error.exception.detail, 'new_conversation_page_not_ready')
        send.assert_not_called()

    async def test_old_url_during_new_stream_does_not_cancel_response_or_steal_binding(self):
        old_url = 'https://chat.qwen.ai/c/existing-thread'
        self.store.bind(key='other-thread', route_domain='chat.qwen.ai', conversation_url=old_url)
        wire = await self._run_bound(streaming=True, url_sequence=[old_url, URL, URL, URL, URL])
        frames = [json.loads(frame[6:]) for frame in wire.split('\n\n') if frame.startswith('data: {')]
        self.assertIsNone(frames[0]['conversation_url'])
        self.assertEqual(frames[-1]['conversation_url'], URL)
        self.assertEqual(self.store.get('other-thread').conversation_url, old_url)
        self.assertEqual(self.store.get('native-thread').conversation_url, URL)
        self.assertTrue(wire.endswith('data: [DONE]\n\n'))

    async def test_json_exposes_persisted_web_url(self):
        response = await self._run_bound()
        data = json.loads(response.body)
        self.assertEqual(data['conversation_url'], URL)
        self.assertEqual(data['conversation_id'], URL.rsplit('/', 1)[-1])
        self.assertEqual(data['client_session_id'], 'native-thread')
        self.assertEqual(response.headers['X-UWA-Conversation-URL'], URL)
        self.assertEqual(self.store.get('native-thread').conversation_url, URL)

    async def test_sse_first_final_and_lookup_have_metadata(self):
        wire = await self._run_bound(streaming=True, late_url=True)
        frames = [json.loads(frame[6:]) for frame in wire.split('\n\n') if frame.startswith('data: {')]
        self.assertEqual(frames[0]['client_session_id'], 'native-thread')
        self.assertIsNone(frames[0]['conversation_url'])
        self.assertEqual(frames[-1]['conversation_url'], URL)
        self.assertTrue(wire.endswith('data: [DONE]\n\n'))
        with patch.object(routes, 'conversation_binding_store', self.store):
            data = await routes.get_conversation_binding(client_session_id='native-thread', conversation_key=None, authenticated=True)
        self.assertEqual(data['conversation_url'], URL)

if __name__ == '__main__':
    unittest.main()

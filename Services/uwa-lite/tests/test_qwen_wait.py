"""Qwen streams must not stop merely because the page is still thinking."""
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from app.core.network_monitor import NetworkMonitor, NetworkMonitorTimeout
from app.core.parsers.qwen_parser import QwenParser

class Tab:
    def __init__(self, active): self.active = active
    def ele(self, selector, timeout=0):
        if self.active and '停止' in selector:
            return SimpleNamespace(states=SimpleNamespace(is_displayed=True))
        return None

class QwenWaitTests(unittest.TestCase):
    def monitor(self, active, stop):
        return NetworkMonitor(Tab(active), SimpleNamespace(), QwenParser(), stop_checker=stop,
            stream_config={'respect_generating_indicator': True, 'hard_timeout': 10,
                'network': {'listen_pattern': 'api/v2/chat/completions', 'first_response_timeout': .01}})

    def test_actual_qwen_configuration_reaches_monitors(self):
        from app.services.config import config_engine
        for preset in config_engine.sites['chat.qwen.ai']['presets']:
            config = config_engine.get_site_stream_config('chat.qwen.ai', preset)
            self.assertTrue(config.get('respect_generating_indicator'))
            self.assertEqual(config['hard_timeout'], 1800)
            self.assertEqual(NetworkMonitor(Tab(True), SimpleNamespace(), QwenParser(), stream_config=config)._first_response_timeout, 120)

    def test_visible_stop_button_prevents_first_response_timeout(self):
        signals = iter([False, False, True])
        monitor = self.monitor(True, lambda: next(signals, True))
        with patch.object(monitor, '_wait_for_response', return_value=None), patch.object(monitor, '_append_network_debug_trace'):
            self.assertEqual(list(monitor._stream_output_phase('test')), [])

    def test_no_stop_button_preserves_real_timeout(self):
        monitor = self.monitor(False, lambda: False)
        with patch.object(monitor, '_wait_for_response', return_value=None):
            with self.assertRaises(NetworkMonitorTimeout):
                list(monitor._stream_output_phase('test'))

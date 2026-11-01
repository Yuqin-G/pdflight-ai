import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

from app.core.workflow.text_input import TextInputHandler


class AttachmentTimeoutTests(unittest.TestCase):
    def test_unfinished_upload_returns_failure_instead_of_raising(self):
        monitor = Mock()
        monitor.wait_until_ready.return_value = {"success": False, "reason": "timeout"}
        handler = object.__new__(TextInputHandler)
        handler._check_cancelled = lambda: False
        handler._attachment_monitor = monitor
        handler._upload_file_via_site_targets = lambda _: True
        handler._has_confirmed_upload_signal = lambda: False
        handler.get_upload_signal_timeout = lambda default: 0
        handler.get_upload_signal_grace = lambda default: 0
        with tempfile.TemporaryDirectory() as directory:
            pdf = Path(directory) / "test.pdf"
            pdf.write_bytes(b"%PDF-1.4\n%%EOF\n")
            self.assertFalse(handler.attach_files([str(pdf)]))
        monitor.wait_until_ready.assert_called_once()


if __name__ == "__main__":
    unittest.main()

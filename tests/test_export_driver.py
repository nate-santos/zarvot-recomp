"""Offline checks: rejected or unknown RPC replies must not start a false export."""

import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "export_driver", pathlib.Path(__file__).parents[1] / "scripts" / "export-recomp.py")
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


def reply(value):
    return {"result": {"content": [{"type": "text", "text": json.dumps(value)}]}}


class ExportDriverTests(unittest.TestCase):
    def test_acceptance_is_not_completion(self):
        with patch.object(driver, "rpc", return_value=reply({"success": True})):
            self.assertIn("completion still pending", driver.request_action({}))

    def test_missing_dialog_is_rejected(self):
        with patch.object(driver, "rpc", return_value=reply(
                {"success": False, "error": "No GameExportDialog is currently open"})):
            with self.assertRaisesRegex(RuntimeError, "No GameExportDialog"):
                driver.request_action({})

    def test_protocol_errors_and_unknown_replies_are_rejected(self):
        for response in ({"error": {"code": -32601}}, {"result": {"isError": True}},
                         {}, reply({"progress": 10})):
            with self.subTest(response=response), patch.object(driver, "rpc", return_value=response):
                with self.assertRaises(RuntimeError):
                    driver.request_action({})

    def test_timeout_is_allowed_only_for_modal_open(self):
        with patch.object(driver, "rpc", side_effect=TimeoutError):
            self.assertIn("expected", driver.request_action({}, allow_modal_timeout=True))
            with self.assertRaisesRegex(RuntimeError, "timed out"):
                driver.request_action({})

    def test_connection_reset_is_never_success(self):
        with patch.object(driver, "rpc", side_effect=ConnectionResetError):
            with self.assertRaises(ConnectionResetError):
                driver.request_action({}, allow_modal_timeout=True)

    def test_explicit_hybrid_backend_is_forwarded(self):
        with tempfile.TemporaryDirectory() as temporary:
            rom = pathlib.Path(temporary) / "synthetic.nsp"
            rom.touch()
            out = pathlib.Path(temporary) / "output"
            argv = ["export-recomp.py", "--rom", str(rom), "--out", str(out),
                    "--backend", "hybrid", "source"]
            with patch.object(driver.sys, "argv", argv), patch.object(driver.time, "sleep"), \
                    patch.object(driver, "rpc", return_value=reply({"success": True})) as rpc:
                self.assertEqual(driver.main(), 0)
                action = rpc.call_args.args[1]["arguments"]
                self.assertEqual(action["backend"], "hybrid")
                self.assertEqual(action["rom_path"], str(rom.resolve()))
                self.assertEqual(action["format"], "source")


if __name__ == "__main__":
    unittest.main()

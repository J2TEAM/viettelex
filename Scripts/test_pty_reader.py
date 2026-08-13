import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("pty-reader.py")
SPEC = importlib.util.spec_from_file_location("pty_reader", MODULE_PATH)
pty_reader = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pty_reader)


class TerminalLineTests(unittest.TestCase):
    def test_reconstructs_backspace_and_multibyte_replacement(self):
        state = pty_reader.TerminalLine()
        lines = []
        for byte in b"a\x7f" + "á".encode() + b"\r":
            line = state.feed(bytes([byte]))
            if line is not None:
                lines.append(line)
        self.assertEqual(lines, ["á"])

    def test_backspace_at_start_is_safe(self):
        state = pty_reader.TerminalLine()
        self.assertIsNone(state.feed(b"\x7f"))
        self.assertEqual(state.feed(b"\r"), "")

    def test_crlf_is_one_line_boundary(self):
        state = pty_reader.TerminalLine()
        lines = []
        for byte in b"first\r\nsecond\n":
            line = state.feed(bytes([byte]))
            if line is not None:
                lines.append(line)
        self.assertEqual(lines, ["first", "second"])

    def test_load_expected_repeats_corpus_in_order(self):
        with tempfile.TemporaryDirectory() as directory:
            corpus = Path(directory) / "cases.json"
            corpus.write_text(
                json.dumps(
                    [
                        {"name": "a", "keys": "as", "expected": "á"},
                        {"name": "b", "keys": "dd", "expected": "đ"},
                    ]
                ),
                encoding="utf-8",
            )
            self.assertEqual(
                pty_reader.load_expected(corpus, 2),
                [("a", "á"), ("b", "đ"), ("a", "á"), ("b", "đ")],
            )


if __name__ == "__main__":
    unittest.main()

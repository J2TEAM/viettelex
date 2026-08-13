#!/usr/bin/env python3
# pty-reader.py — run INSIDE the terminal being measured. Puts the tty in raw
# mode and logs one line per received byte: "<CLOCK_UPTIME_RAW ns> <hex byte>".
# CLOCK_UPTIME_RAW is mach_absolute_time's clock — the same one the poster
# (pty-poster.swift, DispatchTime.uptimeNanoseconds) stamps with, so the two
# logs subtract directly with no cross-clock skew.
#
# Usage:
#   python3 pty-reader.py /tmp/pty-arrivals.log
#   python3 pty-reader.py /tmp/pty-arrivals.log \
#       --corpus Scripts/terminal-regression-cases.json --repeats 10
import argparse
import codecs
import json
import os
import sys
import termios
import time
import tty


class TerminalLine:
    """Reconstruct visible text from raw terminal bytes."""

    def __init__(self):
        self.characters = []
        self.decoder = codecs.getincrementaldecoder("utf-8")("strict")
        self.last_was_carriage_return = False

    def feed(self, byte):
        if byte == b"\n" and self.last_was_carriage_return:
            self.last_was_carriage_return = False
            return None
        self.last_was_carriage_return = byte == b"\r"
        if byte in (b"\x08", b"\x7f"):
            self.decoder.reset()
            if self.characters:
                self.characters.pop()
            return None
        if byte in (b"\r", b"\n"):
            self.decoder.reset()
            line = "".join(self.characters)
            self.characters.clear()
            return line
        decoded = self.decoder.decode(byte)
        if decoded:
            self.characters.extend(decoded)
        return None


def load_expected(corpus_path, repeats):
    with open(corpus_path, encoding="utf-8") as handle:
        cases = json.load(handle)
    if not isinstance(cases, list) or not cases:
        raise ValueError("corpus must be a non-empty JSON array")
    expected = []
    for _ in range(repeats):
        for case in cases:
            if not isinstance(case, dict) or not case.get("name") or "expected" not in case:
                raise ValueError("every corpus case needs name and expected")
            expected.append((case["name"], case["expected"]))
    return expected


def parse_args(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("log")
    parser.add_argument("--corpus")
    parser.add_argument("--repeats", type=int, default=1)
    args = parser.parse_args(argv)
    if args.repeats < 1:
        parser.error("--repeats must be greater than zero")
    return args


def main(argv=None):
    args = parse_args(argv)
    expected = load_expected(args.corpus, args.repeats) if args.corpus else None
    failures = 0
    completed = 0
    state = TerminalLine()
    with open(args.log, "w", buffering=1) as log:
        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            while True:
                byte = os.read(fd, 1)
                timestamp = time.clock_gettime_ns(time.CLOCK_UPTIME_RAW)
                if not byte or byte == b"\x03" or (expected is None and byte == b"q"):
                    break
                log.write(f"{timestamp} {byte.hex()}\n")
                line = state.feed(byte)
                if line is None or expected is None:
                    continue
                name, wanted = expected[completed]
                completed += 1
                if line == wanted:
                    print(f"PASS {completed}/{len(expected)} {name}: {line!r}")
                else:
                    failures += 1
                    print(
                        f"FAIL {completed}/{len(expected)} {name}: "
                        f"expected {wanted!r}, received {line!r}"
                    )
                if completed == len(expected):
                    break
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
    if expected is not None:
        if completed != len(expected):
            print(f"FAIL incomplete: received {completed}/{len(expected)} cases")
            return 1
        print(f"Result: {len(expected) - failures}/{len(expected)} passed")
    return int(failures != 0)


if __name__ == "__main__":
    raise SystemExit(main())

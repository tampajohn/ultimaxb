#!/usr/bin/env python3
"""Compare Swift rendering byte-for-byte with the Python decoder on local assets."""
import argparse
from contextlib import ExitStack
from pathlib import Path
import subprocess
import tempfile
from preview_mul import Client, render

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--binary", type=Path, default=Path(".build/release/UltimaMac"))
parser.add_argument("--client", type=Path, default=Path("uo1998-client"))
args = parser.parse_args()
with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
    client = Client(args.client, stack)
    for x, y, statics in [(1435, 1695, True), (1435, 1695, False), (0, 0, True)]:
        expected = Path(directory) / "python.bmp"
        actual = Path(directory) / "swift.bmp"
        render(client, expected, x, y, 24, statics)
        command = [str(args.binary.resolve()), "--legacy-terrain", "--client", str(args.client.resolve()),
                   "--render", str(actual), "--x", str(x), "--y", str(y)]
        if not statics:
            command.append("--land-only")
        subprocess.run(command, check=True)
        if actual.read_bytes() != expected.read_bytes():
            raise SystemExit(f"FAIL: render differs at {x},{y}, statics={statics}")
        print(f"PASS: identical BMP at {x},{y}, statics={statics}")

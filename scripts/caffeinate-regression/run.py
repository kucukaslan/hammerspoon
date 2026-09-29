#!/usr/bin/env python3
"""Compile actual caffeinate source against an existing LuaSkin framework.

Default: test the current checkout. --source selects another libcaffeinate.m.
--expect-null-crash verifies the unpatched baseline in a child process.
"""
import argparse
from pathlib import Path
import signal
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--frameworks', default='/Applications/Hammerspoon.app/Contents/Frameworks')
parser.add_argument('--source', type=Path)
parser.add_argument('--expect-null-crash', action='store_true')
args = parser.parse_args()
folder = Path(__file__).resolve().parent
source = (args.source or folder.parent.parent / 'extensions/caffeinate/libcaffeinate.m').resolve()
with tempfile.TemporaryDirectory(prefix='hs-caffeinate-test-') as tmp:
    binary = str(Path(tmp) / 'current-assertions')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-F' + args.frameworks,
                    '-framework', 'LuaSkin', '-framework', 'Cocoa',
                    '-framework', 'Carbon', '-framework', 'IOKit',
                    '-Wl,-rpath,' + args.frameworks,
                    '-DCAFFEINATE_SOURCE="' + str(source) + '"',
                    str(folder / 'current_assertions.m'), '-o', binary], check=True)
    for scenario in ('error', 'empty', 'populated', 'null'):
        result = subprocess.run([binary, scenario], capture_output=True, text=True)
        expected = -signal.SIGTRAP if scenario == 'null' and args.expect_null_crash else 0
        if result.returncode != expected:
            raise SystemExit(f'FAIL {scenario}: expected {expected}, got {result.returncode}\n'
                             + result.stdout + result.stderr)
        print(result.stdout.strip() or 'PASS: baseline null result reproduced SIGTRAP')

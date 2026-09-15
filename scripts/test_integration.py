"""Run real PoB2 core checks with synthetic fixtures and an explicit Mac app."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, default=os.environ.get('POB2_MAC_APP'))
parser.add_argument('--core', type=Path, default=os.environ.get('POB2_CORE_SRC'))
args = parser.parse_args()
if not args.app or not args.core:
    parser.error('Pass --app and --core, or set POB2_MAC_APP and POB2_CORE_SRC')
core = Path(args.core).expanduser().resolve()
if not (core / 'HeadlessWrapper.lua').is_file():
    parser.error('--core must point to the directory containing HeadlessWrapper.lua')
for directory in ('test-user', 'test-output/stat-comparison'):
    (ROOT / directory).mkdir(parents=True, exist_ok=True)
subprocess.run([sys.executable, str(ROOT / 'run_lua.py'), str(ROOT / 'integration_game.lua'),
                '--app', str(Path(args.app).expanduser().resolve())], cwd=core, check=True)

"""Validate distributable assets, source provenance and public file hygiene."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import install
from build_assets import common_han


def main():
    install.validate_payload(ROOT / 'payload')
    charset = set((ROOT / 'charset.txt').read_text())
    glyphs = set(re.findall(r'^\["([^"\\]+)"\]', (ROOT / 'payload/font.lua').read_text(), re.M))
    assert charset <= glyphs, 'Rebuild Noto atlas for added characters'
    assert common_han() <= glyphs, 'Atlas must cover all 6,763 common Han characters'
    font = ROOT / 'fonts/NotoSansCJKsc-Regular.otf'
    font_info = json.loads((ROOT / 'fonts/source.json').read_text())
    assert hashlib.sha256(font.read_bytes()).hexdigest() == font_info['sha256']
    manifest = json.loads((ROOT / 'data/source-manifest.json').read_text())
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, 'Source snapshot changed; review and refresh manifest: ' + name
    result = subprocess.run(['git', '-C', str(ROOT), 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], capture_output=True)
    if result.returncode:
        raise RuntimeError('Initialize this repository with git init before running its public-file check')
    names = set(result.stdout.decode().split('\0')) - {''}
    forbidden = {'backups', 'test-user', 'test-output', 'research', '__pycache__', '.git', 'dist', 'build'}
    home_path = re.compile(rb'/(?:Users|home)/[^/\s]+/')
    for name in names:
        path = ROOT / name
        assert not (set(path.relative_to(ROOT).parts) & forbidden), 'Private/generated file: ' + name
        assert path.name not in {'installation.json', '.DS_Store', '.env'}, name
        assert path.suffix not in {'.dmg', '.zip', '.p12', '.key', '.pem'}, name
        assert path.stat().st_size < 25 * 1024 * 1024, 'Unexpected large source file: ' + name
        if path.suffix not in ('.png', '.otf'):
            raw = path.read_bytes()
            assert not home_path.search(raw), 'Absolute home path in ' + name
            assert (b'-----BEGIN ' + b'PRIVATE KEY-----') not in raw, name
    print(f'PASS public repository: {len(names)} files, {len(charset)} glyphs; sources and font hashes verified')


if __name__ == '__main__':
    main()

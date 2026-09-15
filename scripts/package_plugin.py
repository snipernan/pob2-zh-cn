"""Create an installable plugin ZIP from an explicit file allowlist."""
from pathlib import Path
import hashlib
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import install

install.validate_payload(ROOT / 'payload')
version = install.plugin_version(ROOT / 'payload')
assert version
output = ROOT / 'dist' / f'pob2-zh-cn-plugin-{version}.zip'
output.parent.mkdir(exist_ok=True)
files = [ROOT / n for n in ('install.py', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'CHANGELOG.md',
         '安装或更新汉化.command', '检查汉化状态.command', '卸载汉化.command', 'fonts/LICENSE')]
files += sorted(p for p in (ROOT / 'payload').iterdir() if p.suffix in ('.lua', '.png') and p.name != 'custom.lua')
files += sorted((ROOT / 'licenses').glob('*.txt'))
files += sorted((ROOT / 'docs').glob('*.md'))
prefix = f'pob2-zh-cn-plugin-{version}/'
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        assert path.is_file() and not path.is_symlink(), path
        archive.write(path, prefix + path.relative_to(ROOT).as_posix())
    archive.writestr(prefix + 'README.md', f'''# PoB2 简体中文插件 {version}

适用于已验证的 Apple Silicon Mac 原生 PoB2 0.23.1。
先启动原版一次，保存配装并退出，再在本目录执行 `python3 install.py`。
重新打开 PoB2；F10 切换中英文。状态：`python3 install.py --status`；卸载：`python3 install.py --uninstall`。
需要 Python 3.9+；也可双击对应 `.command` 文件。

安装与限制见 docs/INSTALL.md，第三方内容许可见 THIRD_PARTY_NOTICES.md。
这是预生成安装资源包，开发源码请从提供此 ZIP 的 GitHub 项目取得。
''')
hash_value = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix('.zip.sha256').write_text(hash_value + '  ' + output.name + '\n')
print(output)

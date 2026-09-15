"""Install a display-only hook in the Mac port's writable Lua entry.

The signed .app, build XML, settings, and calculation modules are never changed.
--status inspects files only; it cannot establish what a running PoB has loaded.
"""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import tempfile
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parent
DEFAULT = Path.home() / 'Library/Application Support/PathOfBuildingMacPoE2'
MARKER = re.compile(r'\r?\n-- BEGIN POB2 ZH-CN (LOAD|CALLBACK|BOOTSTRAP)\r?\n.*?-- END POB2 ZH-CN\r?\n', re.S)
GLYPH = re.compile(r'^\["(?:[^"\\]|\\.)+"\]\s*=\s*\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\},?\s*$', re.M)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def atomic_write(path, data):
    """Replace one file without exposing a partially written entry."""
    if isinstance(data, str):
        data = data.encode('utf-8')
    fd, name = tempfile.mkstemp(prefix='.pob-zh-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
        os.chmod(name, path.stat().st_mode & 0o777 if path.exists() else 0o644)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def read_text(path):
    # Do not normalize unrelated line endings when modifying mac_entry.lua.
    return path.read_bytes().decode('utf-8')


def clean_entry(original):
    clean = MARKER.sub('', original)
    if 'BEGIN POB2 ZH-CN' in clean or 'END POB2 ZH-CN' in clean:
        raise RuntimeError('汉化入口标记不完整，已停止；没有修改文件。')
    return clean


def launch_supported(source):
    patterns = (r'^\s*launch\s*=\s*\{\s*\}', r'^\s*function\s+launch:OnInit\s*\(',
                r'^\s*function\s+launch:OnKeyDown\s*\(')
    return all(len(re.findall(pattern, source, re.M)) == 1 for pattern in patterns)


def hooks(destination):
    lua_path = json.dumps(str(destination), ensure_ascii=False)
    return '''
-- BEGIN POB2 ZH-CN BOOTSTRAP
do
    local root = ROOT_PATH
    local ok, result = pcall(function()
        local plugin = assert(loadfile(root .. "/init.lua"))(root)
        plugin.installCallbacks()
    end)
    if not ok then ConPrintf("Chinese plugin could not load: %s", tostring(result)) end
end
-- END POB2 ZH-CN
'''.replace('ROOT_PATH', lua_path)


def check_png(path, expected_size):
    """Check dimensions and chunk integrity without loading a GUI or Lua code."""
    raw = path.read_bytes()
    if not raw.startswith(b'\x89PNG\r\n\x1a\n'):
        raise RuntimeError(f'字体图集不是有效 PNG：{path.name}')
    offset, kinds = 8, []
    while offset + 12 <= len(raw):
        length = struct.unpack('>I', raw[offset:offset + 4])[0]
        kind = raw[offset + 4:offset + 8]
        end = offset + 8 + length
        if end + 4 > len(raw):
            break
        body = raw[offset + 8:end]
        crc = struct.unpack('>I', raw[end:end + 4])[0]
        if zlib.crc32(kind + body) & 0xffffffff != crc:
            raise RuntimeError(f'字体图集校验失败：{path.name}')
        if not kinds:
            if kind != b'IHDR' or length != 13 or struct.unpack('>II', body[:8]) != (expected_size, expected_size):
                raise RuntimeError(f'字体图集尺寸与 font.lua 不一致：{path.name}')
        kinds.append(kind)
        offset = end + 4
        if kind == b'IEND':
            if length == 0 and b'IDAT' in kinds and offset == len(raw):
                return
            break
    raise RuntimeError(f'字体图集不完整：{path.name}')


def validate_payload(payload, names=None):
    required = {'init.lua', 'dictionary.lua', 'font.lua'}
    files = {p.name: p for p in payload.iterdir()
             if p.suffix in ('.lua', '.png') and (names is None or p.name in names)}
    if 'init.lua' in files and 'game_text.lua' in read_text(files['init.lua']):
        required.update({'game_text.lua', 'game_dictionary.lua', 'skills_cn.lua'})
    if 'game_text.lua' in files and 'equipment_dictionary.lua' in read_text(files['game_text.lua']):
        required.add('equipment_dictionary.lua')
    if 'init.lua' in files and 'tree_cn.lua' in read_text(files['init.lua']):
        required.add('tree_cn.lua')
    if 'init.lua' in files and 'equipment_cn.lua' in read_text(files['init.lua']):
        required.add('equipment_cn.lua')
    if 'init.lua' in files and 'update_guard.lua' in read_text(files['init.lua']):
        required.add('update_guard.lua')
    if 'init.lua' in files and 'mac_input.lua' in read_text(files['init.lua']):
        required.add('mac_input.lua')
    if 'init.lua' in files and 'stat_compare_cn.lua' in read_text(files['init.lua']):
        required.add('stat_compare_cn.lua')
    if 'init.lua' in files and 'tooltip_cn.lua' in read_text(files['init.lua']):
        required.add('tooltip_cn.lua')
    missing = required - files.keys()
    if missing:
        raise RuntimeError('汉化资源缺失：' + ', '.join(sorted(missing)))
    for name, path in files.items():
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            raise RuntimeError(f'汉化资源不是非空普通文件：{name}')
    font = read_text(files['font.lua'])
    size_match = re.search(r'\bsize\s*=\s*(\d+)', font)
    cell_match = re.search(r'\bcell\s*=\s*(\d+)', font)
    glyphs = GLYPH.findall(font)
    glyph_records = re.findall(r'^\s*\[.*\]\s*=', font, re.M)
    if not size_match or not cell_match or not glyphs or len(glyphs) != len(glyph_records):
        raise RuntimeError('font.lua 缺少可识别的图集尺寸或字形记录。')
    size, cell = int(size_match[1]), int(cell_match[1])
    if size <= 0 or cell <= 0 or cell > size:
        raise RuntimeError('font.lua 图集尺寸无效。')
    pages = set()
    for page, x, y, width in glyphs:
        page, x, y = int(page), int(x), int(y)
        if page < 1 or x + cell > size or y + cell > size or not 0 < float(width) <= cell:
            raise RuntimeError('font.lua 包含超出图集范围的字形。')
        pages.add(page)
    for page in sorted(pages):
        name = f'font-{page}.png'
        if name not in files:
            raise RuntimeError(f'font.lua 引用的字体图集缺失：{name}')
        check_png(files[name], size)
    return files


def core_version(target):
    for name in ('manifest.xml', 'Manifest.xml'):
        manifest = target / 'src' / name
        if manifest.is_file():
            try:
                version = ET.fromstring(manifest.read_bytes()).find('Version')
                return version.get('number') if version is not None else None
            except (ET.ParseError, OSError):
                return None
    return None


def plugin_version(payload):
    try:
        match = re.search(r'\bversion\s*=\s*[\'\"]([^\'\"]+)', read_text(payload / 'init.lua'))
        return match[1] if match else None
    except (OSError, UnicodeError):
        return None


def status(target, *, payload_root=None, metadata_root=None):
    """Return actual disk state. installation.json is advisory, never proof."""
    target = Path(target).expanduser().resolve()
    payload = Path(payload_root) if payload_root is not None else ROOT / 'payload'
    metadata = Path(metadata_root) if metadata_root is not None else ROOT
    destination = target / 'PoB2Chinese'
    entry = target / 'src/Launch.lua'
    result = dict(target=str(target), core_version=core_version(target),
                  plugin_version=plugin_version(payload), entry='missing_file',
                  resources='not_installed', disabled=(destination / 'disabled').exists(),
                  runtime='unknown', restart_confirmation_required=True,
                  entry_file='src/Launch.lua', legacy_entry='missing_file',
                  missing_resources=[], mismatched_resources=[], installation_record='missing')
    if entry.is_file():
        try:
            original = read_text(entry)
            clean = clean_entry(original)
            expected = hooks(destination)
            if original.count(expected) == 1 and len(MARKER.findall(original)) == 1:
                result['entry'] = 'installed' if launch_supported(clean) else 'unsupported'
            elif MARKER.search(original):
                result['entry'] = 'modified_or_incomplete'
            else:
                result['entry'] = 'missing_hook' if launch_supported(clean) else 'unsupported'
        except (OSError, UnicodeError, RuntimeError) as error:
            result['entry'] = 'modified_or_incomplete'
            result['entry_error'] = str(error)
    legacy = target / 'src/mac_entry.lua'
    if legacy.is_file():
        try:
            original = read_text(legacy)
            result['legacy_entry'] = 'legacy_hook_present' if clean_entry(original) != original else 'clean'
        except (OSError, UnicodeError, RuntimeError):
            result['legacy_entry'] = 'modified_or_incomplete'
    try:
        files = validate_payload(payload)
        for name, source in files.items():
            installed = destination / name
            if not installed.is_file():
                result['missing_resources'].append(name)
            elif sha256(installed.read_bytes()) != sha256(source.read_bytes()):
                result['mismatched_resources'].append(name)
        result['resources'] = ('missing' if result['missing_resources'] else
                               'mismatch' if result['mismatched_resources'] else 'matched')
    except (OSError, UnicodeError, RuntimeError) as error:
        result['resources'] = 'payload_invalid'
        result['payload_error'] = str(error)
    record = metadata / 'installation.json'
    if record.exists():
        try:
            data = json.loads(read_text(record))
            if not isinstance(data, dict):
                raise ValueError('Installation record must be an object')
            if Path(data.get('target', '')).resolve() != target:
                result['installation_record'] = 'different_target'
            elif result['entry'] != 'installed' or data.get('entry_file') != 'src/Launch.lua':
                result['installation_record'] = 'stale'
            elif data.get('installed_sha256') != sha256(entry.read_bytes()):
                result['installation_record'] = 'entry_changed'
            else:
                result['installation_record'] = 'matches_entry'
        except (ValueError, OSError, TypeError):
            result['installation_record'] = 'invalid'
    return result


def print_status(result):
    print(f"PoB2 数据目录：{result['target']}")
    print(f"本地核心版本：{result['core_version'] or '无法读取'}；本插件版本：{result['plugin_version'] or '无法读取'}")
    entries = {'missing_file': 'Launch.lua 不存在', 'missing_hook': '汉化入口缺失（未安装或被核心更新覆盖）',
               'installed': '汉化入口完整', 'unsupported': '入口结构不兼容，需检查',
               'modified_or_incomplete': '汉化入口被修改或不完整，需检查'}
    resources = {'not_installed': '尚未安装', 'missing': '已安装资源有缺失', 'mismatch': '已安装资源与当前插件不一致',
                 'matched': '已安装资源与当前插件匹配', 'payload_invalid': '本地插件资源校验失败'}
    print('Launch.lua 入口：' + entries[result['entry']])
    if result['legacy_entry'] in ('legacy_hook_present', 'modified_or_incomplete'):
        print('mac_entry.lua 仍有旧版汉化入口或不完整标记；请重新安装以迁移。')
    print('资源：' + resources[result['resources']])
    for key, label in (('missing_resources', '缺失'), ('mismatched_resources', '不同')):
        if result[key]:
            print(label + '：' + ', '.join(sorted(result[key])))
    if result.get('payload_error'):
        print(result['payload_error'])
    print('语言偏好：' + ('已禁用中文；启动后按 F10 切换' if result['disabled'] else '中文已启用（磁盘偏好）'))
    if result['installation_record'] == 'stale':
        print('安装记录已过期：installation.json 不能代表当前入口状态。')
    print('核心更新可能覆盖 Launch.lua；更新后可再次运行此检查，缺失时重新安装汉化。')
    print('当前进程是否已加载：无法由磁盘状态确认。安装/更新后请保存配装、正常退出并重开，再检查界面。')


def install(target, uninstall=False, *, payload_root=None, metadata_root=None):
    target = Path(target).expanduser().resolve()
    payload = Path(payload_root) if payload_root is not None else ROOT / 'payload'
    metadata = Path(metadata_root) if metadata_root is not None else ROOT
    launch_entry = target / 'src/Launch.lua'
    legacy_entry = target / 'src/mac_entry.lua'
    originals, cleaned = {}, {}
    for entry in (launch_entry, legacy_entry):
        if not entry.exists() and (entry == legacy_entry or uninstall):
            continue
        if entry.is_symlink():
            raise RuntimeError(f'{entry.name} 是符号链接，未修改。')
        originals[entry] = entry.read_bytes()
        cleaned[entry] = clean_entry(originals[entry].decode('utf-8')).encode('utf-8')
    if uninstall:
        changed = []
        try:
            for entry, clean in cleaned.items():
                if clean != originals[entry]:
                    atomic_write(entry, clean)
                    changed.append(entry)
        except Exception:
            for entry in reversed(changed):
                atomic_write(entry, originals[entry])
            raise
        print('新旧汉化入口已卸载；下次启动恢复英文。备份、词典和语言偏好保留。')
        return
    if not launch_supported(cleaned[launch_entry].decode('utf-8')):
        raise RuntimeError('不支持此 Launch.lua：缺少唯一的 launch、OnInit 或 OnKeyDown 定义。没有修改文件。')
    files = validate_payload(payload)  # All validation precedes installed-file changes.
    destination = target / 'PoB2Chinese'
    if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
        raise RuntimeError('PoB2Chinese 不是普通目录，未修改。')
    updated = dict(cleaned)
    updated[launch_entry] += hooks(destination).encode('utf-8')
    backup_dir = metadata / 'backups'
    backup_dir.mkdir(parents=True, exist_ok=True)
    backups = {}
    for entry, original in originals.items():
        backup = backup_dir / f'{entry.stem}-{sha256(original)[:12]}.lua'
        if not backup.exists():
            atomic_write(backup, original)
        backups[entry] = backup
    record = {
        'installed_at': datetime.now().astimezone().isoformat(),
        'target': str(target), 'entry_file': 'src/Launch.lua',
        'backup': str(backups[launch_entry]), 'core_version': core_version(target),
        'plugin_version': plugin_version(payload),
        'original_sha256': sha256(originals[launch_entry]),
        'installed_sha256': sha256(updated[launch_entry]),
        'entries': {str(entry.relative_to(target)): {
            'backup': str(backups[entry]), 'original_sha256': sha256(originals[entry]),
            'installed_sha256': sha256(updated[entry]),
        } for entry in originals},
        'payload_sha256': {name: sha256(path.read_bytes()) for name, path in files.items()},
        'runtime_loaded': 'unknown',
    }
    with tempfile.TemporaryDirectory(prefix='.pob-zh-install-', dir=target) as temp:
        stage, previous = Path(temp) / 'new', Path(temp) / 'previous'
        if destination.exists():
            shutil.copytree(destination, stage, symlinks=True)
        else:
            stage.mkdir()
        for name, source in files.items():
            staged_file = stage / name
            if staged_file.is_symlink():
                staged_file.unlink()
            shutil.copy2(source, staged_file)
        validate_payload(stage, names=files)
        if any(sha256((stage / name).read_bytes()) != digest for name, digest in record['payload_sha256'].items()):
            raise RuntimeError('复制期间插件资源发生变化，已停止。请重新安装。')
        if any(entry.read_bytes() != original for entry, original in originals.items()):
            raise RuntimeError('安装期间 Lua 入口已被其他程序修改，已停止。请重试。')
        resources_replaced, changed_entries = False, []
        try:
            if destination.exists():
                os.replace(destination, previous)
            os.replace(stage, destination)
            resources_replaced = True
            for entry, data in updated.items():
                if data != originals[entry]:
                    atomic_write(entry, data)
                    changed_entries.append(entry)
            atomic_write(metadata / 'installation.json', json.dumps(record, ensure_ascii=False, indent=2) + '\n')
        except Exception:
            for entry in reversed(changed_entries):
                atomic_write(entry, originals[entry])
            if resources_replaced:
                shutil.rmtree(destination)
            if previous.exists():
                os.replace(previous, destination)
            raise
    print(f'汉化已安装到 {destination}，入口位于 src/Launch.lua。')
    print('保存当前配装后正常退出并重新打开 PoB2，即可生效。F10 切换中英文。')
    print('重启加载新版插件后，常规核心更新会自动恢复汉化入口；更新后可运行“检查汉化状态.command”。')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', type=Path, default=DEFAULT)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--uninstall', action='store_true')
    mode.add_argument('--status', action='store_true', help='只读检查入口、资源、偏好和本地核心版本')
    parser.add_argument('--json', action='store_true', help='以 JSON 输出 --status 检查结果')
    args = parser.parse_args()
    if args.json and not args.status:
        parser.error('--json 只能与 --status 一起使用')
    try:
        if args.status:
            result = status(args.target)
            print(json.dumps(result, ensure_ascii=False, indent=2)) if args.json else print_status(result)
        else:
            install(args.target, args.uninstall)
    except (OSError, UnicodeError, RuntimeError) as error:
        parser.exit(1, f'操作未完成：{error}\n')

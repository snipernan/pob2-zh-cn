"""Installer regression tests. Every target, payload, backup and record is temporary."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import struct
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
import zlib

import install as installer

LAUNCH = (b'#@ SimpleGraphic\r\n-- upstream file\r\nlaunch = { }\r\n'
          b'SetMainObject(launch)\r\nfunction launch:OnInit()\r\nend\r\n'
          b'function launch:OnKeyDown(key)\r\nend\r\n')
MAC = b'-- original mac entry\ndofile("Launch.lua")\n-- after\n'
OLD_LOAD = b'\n-- BEGIN POB2 ZH-CN LOAD\nlocal pobChinese = {}\n-- END POB2 ZH-CN\n'
OLD_CALLBACK = b'\n-- BEGIN POB2 ZH-CN CALLBACK\n-- old callback\n-- END POB2 ZH-CN\n'


def png(size=4):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress((b'\0' + b'\xff' * size * 4) * size)) + chunk(b'IEND', b''))


def snapshot(path):
    return {str(p.relative_to(path)): p.read_bytes() for p in path.rglob('*') if p.is_file()}


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory(prefix='pob-zh-install-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.target = self.root / 'target'
        (self.target / 'src').mkdir(parents=True)
        self.entry = self.target / 'src/Launch.lua'
        self.mac = self.target / 'src/mac_entry.lua'
        self.entry.write_bytes(LAUNCH)
        self.mac.write_bytes(MAC)
        (self.target / 'src/manifest.xml').write_text('<PoBVersion><Version number="0.23.1" platform="macos"/></PoBVersion>')
        self.payload = self.root / 'payload'
        self.payload.mkdir()
        (self.payload / 'init.lua').write_text("return { version = '0.2.0', installCallbacks = function() end }")
        (self.payload / 'dictionary.lua').write_text('return {}')
        (self.payload / 'font.lua').write_text('return { cell = 2, size = 4, glyphs = {\n["中"]={1,0,0,2},\n["文"]={2,2,2,2},\n}}\n')
        for number in (1, 2):
            (self.payload / f'font-{number}.png').write_bytes(png())
        self.metadata = self.root / 'metadata'
        self.destination = self.target / 'PoB2Chinese'
        self.kw = dict(payload_root=self.payload, metadata_root=self.metadata)
        self.output = io.StringIO()
        self.capture = redirect_stdout(self.output)
        self.capture.__enter__()
        self.addCleanup(self.capture.__exit__, None, None, None)

    def install(self, **kwargs):
        return installer.install(self.target, **self.kw, **kwargs)

    def status(self):
        return installer.status(self.target, **self.kw)

    def test_missing_game_translation_module_preserves_working_install(self):
        self.install()
        (self.payload / 'init.lua').write_text("local game = assert(loadfile(root .. '/game_text.lua'))(root)")
        before = snapshot(self.target)
        with self.assertRaisesRegex(RuntimeError, 'game_'):
            self.install()
        self.assertEqual(snapshot(self.target), before)

    def test_missing_tree_translation_modules_preserve_working_install(self):
        self.install()
        before = snapshot(self.target)
        for module in ('tree_cn', 'tooltip_cn', 'equipment_cn', 'mac_input', 'stat_compare_cn'):
            with self.subTest(module=module):
                (self.payload / 'init.lua').write_text(f"local tree = assert(loadfile(root .. '/{module}.lua'))(P, game)")
                with self.assertRaisesRegex(RuntimeError, module):
                    self.install()
                self.assertEqual(snapshot(self.target), before)

    def test_missing_equipment_dictionary_preserves_working_install(self):
        self.install()
        before = snapshot(self.target)
        (self.payload / 'game_text.lua').write_text("return dofile(root .. '/equipment_dictionary.lua')")
        with self.assertRaisesRegex(RuntimeError, 'equipment_dictionary'):
            self.install()
        self.assertEqual(snapshot(self.target), before)

    def test_idempotent_install_migrates_old_hooks_and_copies_all_pages(self):
        self.mac.write_bytes(MAC.replace(b'dofile("Launch.lua")', OLD_LOAD + b'dofile("Launch.lua")' + OLD_CALLBACK))
        legacy = self.mac.read_bytes()
        self.install()
        first = self.entry.read_bytes()
        self.assertTrue(first.startswith(LAUNCH))
        self.assertEqual(first.count(b'-- BEGIN POB2 ZH-CN BOOTSTRAP'), 1)
        self.assertEqual(self.mac.read_bytes(), MAC)
        record = json.loads((self.metadata / 'installation.json').read_text())
        self.assertEqual(Path(record['entries']['src/mac_entry.lua']['backup']).read_bytes(), legacy)
        self.assertEqual(Path(record['backup']).read_bytes(), LAUNCH)
        for number in (1, 2):
            self.assertEqual((self.destination / f'font-{number}.png').read_bytes(), png())
        self.install()
        self.assertEqual(self.entry.read_bytes(), first)
        self.assertEqual(self.mac.read_bytes(), MAC)
        self.assertEqual(self.status()['entry'], 'installed')
        self.assertEqual(self.status()['resources'], 'matched')
        self.assertEqual(self.status()['core_version'], '0.23.1')

    def test_repeated_launcher_reset_of_mac_entry_does_not_remove_hook(self):
        self.install()
        for _ in range(2):
            self.mac.write_bytes(MAC)
            self.assertEqual(self.status()['entry'], 'installed')
            self.assertEqual(self.status()['legacy_entry'], 'clean')

    def test_status_is_read_only_and_detects_core_update_overwrite(self):
        self.install()
        self.entry.write_bytes(LAUNCH + b'-- upstream update\n')
        before = snapshot(self.root)
        state = self.status()
        self.assertEqual(snapshot(self.root), before)
        self.assertEqual(state['entry'], 'missing_hook')
        self.assertEqual(state['installation_record'], 'stale')
        self.assertEqual(state['resources'], 'matched')
        self.assertEqual(state['runtime'], 'unknown')
        self.assertTrue(state['restart_confirmation_required'])
        self.install()
        self.assertTrue(self.entry.read_bytes().startswith(LAUNCH + b'-- upstream update\n'))
        self.assertEqual(self.status()['entry'], 'installed')

    def test_disabled_preference_and_custom_files_survive_reinstall(self):
        self.install()
        (self.destination / 'disabled').write_text('disabled\n')
        (self.destination / 'custom.lua').write_bytes(b'')
        (self.destination / 'my-notes.txt').write_text('keep me')
        self.install()
        self.assertTrue(self.status()['disabled'])
        self.assertEqual((self.destination / 'custom.lua').read_bytes(), b'')
        self.assertEqual((self.destination / 'my-notes.txt').read_text(), 'keep me')

    def test_uninstall_both_hooks_is_idempotent_and_preserves_unrelated_changes(self):
        self.install()
        self.entry.write_bytes(self.entry.read_bytes() + b'-- unrelated Launch update\n')
        self.mac.write_bytes(MAC + OLD_LOAD + OLD_CALLBACK + b'-- unrelated mac update\n')
        self.install(uninstall=True)
        self.install(uninstall=True)
        self.assertEqual(self.entry.read_bytes(), LAUNCH + b'-- unrelated Launch update\n')
        self.assertEqual(self.mac.read_bytes(), MAC + b'-- unrelated mac update\n')
        self.assertTrue((self.destination / 'font-2.png').exists())

    def test_uninstall_does_not_require_upstream_launch_shape(self):
        self.install()
        self.entry.write_bytes(self.entry.read_bytes().replace(b'function launch:OnInit()', b'function changed()'))
        self.install(uninstall=True)
        self.assertEqual(self.entry.read_bytes(), LAUNCH.replace(b'function launch:OnInit()', b'function changed()'))

    def test_missing_referenced_page_refuses_before_modifying_files(self):
        (self.payload / 'font-2.png').unlink()
        before = snapshot(self.root)
        with self.assertRaisesRegex(RuntimeError, 'font-2.png'):
            self.install()
        self.assertEqual(snapshot(self.root), before)
        self.assertFalse(self.destination.exists())

    def test_corrupt_or_wrong_size_png_cannot_replace_working_installation(self):
        self.install()
        before_target, before_metadata = snapshot(self.target), snapshot(self.metadata)
        for broken in (png(8), png()[:-7], png()[:40] + b'bad checksum' + png()[52:]):
            with self.subTest(broken=broken[:16]):
                (self.payload / 'font-2.png').write_bytes(broken)
                with self.assertRaises(RuntimeError):
                    self.install()
                self.assertEqual(snapshot(self.target), before_target)
                self.assertEqual(snapshot(self.metadata), before_metadata)

    def test_missing_unsupported_or_malformed_entry_refuses_without_writes(self):
        for body in (b'-- unsupported entry\n', LAUNCH + b'\n-- BEGIN POB2 ZH-CN BOOTSTRAP\n-- truncated\n'):
            with self.subTest(body=body[-20:]):
                self.entry.write_bytes(body)
                before = snapshot(self.root)
                with self.assertRaises(RuntimeError):
                    self.install()
                self.assertEqual(snapshot(self.root), before)
        self.entry.unlink()
        with self.assertRaises(FileNotFoundError):
            self.install()
        self.assertEqual(self.status()['entry'], 'missing_file')

    def test_entry_write_failure_rolls_back_resources_and_old_hook_cleanup(self):
        self.install()
        self.mac.write_bytes(MAC + OLD_LOAD + OLD_CALLBACK)
        before = snapshot(self.target)
        (self.payload / 'dictionary.lua').write_text('return { changed = true }')
        original_write = installer.atomic_write
        def fail_mac(path, data):
            if path == self.mac:
                raise OSError('simulated write failure')
            return original_write(path, data)
        with patch.object(installer, 'atomic_write', side_effect=fail_mac):
            with self.assertRaisesRegex(OSError, 'simulated'):
                self.install()
        self.assertEqual(snapshot(self.target), before)

    def test_metadata_write_failure_rolls_back_entry_and_resources(self):
        self.install()
        record_before = (self.metadata / 'installation.json').read_bytes()
        self.entry.write_bytes(LAUNCH)
        before = snapshot(self.target)
        (self.payload / 'dictionary.lua').write_text('return { changed = true }')
        original_write = installer.atomic_write
        def fail_metadata(path, data):
            if path.name == 'installation.json':
                raise OSError('simulated metadata failure')
            return original_write(path, data)
        with patch.object(installer, 'atomic_write', side_effect=fail_metadata):
            with self.assertRaisesRegex(OSError, 'simulated'):
                self.install()
        self.assertEqual(snapshot(self.target), before)
        self.assertEqual((self.metadata / 'installation.json').read_bytes(), record_before)

    def test_initial_entry_failure_leaves_no_installed_directory(self):
        before = snapshot(self.target)
        original_write = installer.atomic_write
        def fail_entry(path, data):
            if path == self.entry:
                raise OSError('simulated initial entry failure')
            return original_write(path, data)
        with patch.object(installer, 'atomic_write', side_effect=fail_entry):
            with self.assertRaises(OSError):
                self.install()
        self.assertEqual(snapshot(self.target), before)
        self.assertFalse(self.destination.exists())

    def test_status_reports_missing_and_mismatched_installed_resources(self):
        self.install()
        (self.destination / 'font-2.png').unlink()
        (self.destination / 'dictionary.lua').write_text('different')
        state = self.status()
        self.assertEqual(state['missing_resources'], ['font-2.png'])
        self.assertEqual(state['mismatched_resources'], ['dictionary.lua'])
        self.assertEqual(state['resources'], 'missing')

    def test_missing_or_invalid_manifest_and_metadata_do_not_crash_status(self):
        (self.target / 'src/manifest.xml').write_text('broken xml')
        self.metadata.mkdir()
        (self.metadata / 'installation.json').write_text('broken json')
        self.assertIsNone(self.status()['core_version'])
        self.assertEqual(self.status()['installation_record'], 'invalid')
        (self.metadata / 'installation.json').write_text('[]')
        self.assertEqual(self.status()['installation_record'], 'invalid')

    def test_invalid_atlas_reference_is_not_silently_skipped(self):
        path = self.payload / 'font.lua'
        path.write_text(path.read_text().replace('["文"]={2,', '["文"]={-2,'))
        before = snapshot(self.root)
        with self.assertRaises(RuntimeError):
            self.install()
        self.assertEqual(snapshot(self.root), before)

    def test_uninstall_can_clean_legacy_hook_when_launch_file_is_missing(self):
        self.entry.unlink()
        self.mac.write_bytes(MAC + OLD_LOAD + OLD_CALLBACK)
        self.install(uninstall=True)
        self.assertEqual(self.mac.read_bytes(), MAC)


if __name__ == '__main__':
    # Explicitly ensure test fixtures never replace the live installation record/backups.
    real_record = installer.ROOT / 'installation.json'
    before_record = real_record.read_bytes() if real_record.exists() else None
    before_backups = snapshot(installer.ROOT / 'backups')
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(InstallerTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    assert (real_record.read_bytes() if real_record.exists() else None) == before_record
    assert snapshot(installer.ROOT / 'backups') == before_backups
    raise SystemExit(not result.wasSuccessful())

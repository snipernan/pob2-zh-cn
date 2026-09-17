"""Exercise core replacement in an isolated install, then restart and uninstall."""
import argparse
import contextlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import install

ROOT = Path(__file__).resolve().parent
# CI's small updater contract; --core instead runs that installed core's exact file.
CONTRACT = '''local path = ...
local f = assert(io.open(path)); local ops = f:read('*a'); f:close(); os.remove(path)
for line in ops:gmatch('[^\\n]+') do
 local source,target=line:match('move "(.*)" "(.*)"')
 local src=assert(io.open(source,'rb')); local bytes=src:read('*a'); src:close()
 local dst=assert(io.open(target,'wb')); assert(dst:write(bytes)); assert(dst:close()); os.remove(source)
end
'''
CLEAN = '''#@ SimpleGraphic
launch = { }
function launch:OnInit() end
function launch:OnKeyDown(key) end
'''
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--core', type=Path)
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='pob2-update-guard-') as tmp:
    target = (Path(tmp) / '中文 user').resolve()
    (target / 'src').mkdir(parents=True)
    (target / 'src/Launch.lua').write_text(CLEAN)
    (target / 'src/mac_entry.lua').write_text('dofile("Launch.lua")\n')
    (target / 'src/manifest.xml').write_text('<PoBVersion><Version number="0.23.1"/></PoBVersion>')
    metadata = Path(tmp) / 'metadata'
    with contextlib.redirect_stdout(io.StringIO()):
        install.install(target, metadata_root=metadata)
    (target / 'PoB2Chinese/disabled').write_text('disabled\n')
    (target / 'settings.xml').write_text('<settings>personal fixture</settings>\n')
    (target / 'clean.lua').write_text(CLEAN)
    updater = (args.core / 'UpdateApply.lua').read_text() if args.core else CONTRACT
    (target / 'UpdateApply.lua').write_text(updater)
    env = os.environ.copy()
    env['POB2_GUARD_FIXTURE'] = str(target)
    def run(script):
        subprocess.run([sys.executable, str(ROOT / 'run_lua.py'), str(script)], env=env, check=True)
    run(ROOT / 'tests_update_guard.lua')
    assert not list((target / 'src').glob('*.pob-zh-*')), 'Temporary files left behind'
    status = install.status(target, metadata_root=metadata)
    assert status['entry'] == 'installed' and status['resources'] == 'matched', status
    # New interpreter: the updated Launch.lua executes the restored installer hook.
    restart = target / 'restart.lua'
    restart.write_text('''function DrawString() end
function DrawStringWidth() return 0 end
function DrawStringCursorIndex() return 1 end
function GetDrawColor() return 1,1,1,1 end
function SetDrawColor() end
function NewImageHandle() return {} end
function DrawImage() end
function LoadModule() end
function ConPrintf(...) error(string.format(...)) end
common={classes={}}
local root=assert(os.getenv('POB2_GUARD_FIXTURE'))
dofile(root..'/src/Launch.lua')
assert(PoB2Chinese.version=='PLUGIN_VERSION' and not PoB2Chinese.enabled)
assert(PoB2Chinese.translate('Save')=='Save')
PoB2Chinese.enabled=true
assert(PoB2Chinese.translate('Save')=='保存')
assert(PoB2Chinese.callbackLaunch==launch)
print('PASS restart: restored entry loads Chinese callbacks and preserves saved preference')
'''.replace('PLUGIN_VERSION', install.plugin_version(ROOT / 'payload')))
    run(restart)
    with contextlib.redirect_stdout(io.StringIO()):
        install.install(target, True, metadata_root=metadata)
    assert 'BEGIN POB2 ZH-CN' not in (target / 'src/Launch.lua').read_text()
    assert 'newer upstream core' in (target / 'src/Launch.lua').read_text()
    assert (target / 'settings.xml').read_text() == '<settings>personal fixture</settings>\n'
    print('PASS uninstall after update: new core and user data preserved')

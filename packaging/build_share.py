"""Build a portable, clean PoB2 Chinese app from verified manifest files."""
from pathlib import Path
import argparse,hashlib,json,plistlib,shutil,subprocess,sys,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent.parent
PLUGIN=ROOT
sys.path.insert(0,str(PLUGIN))
import install
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app',type=Path,required=True,help='Original native Apple Silicon PoB2 app')
parser.add_argument('--core',type=Path,required=True,help='Verified 0.23.1 runtime src directory')
parser.add_argument('--launcher-source',type=Path,required=True,help='Compatible upstream macos/launcher.cpp')
parser.add_argument('--output-dir',type=Path,default=ROOT/'build/share-0.6.2')
parser.add_argument('--dmg',action='store_true',help='Also produce and verify a compressed DMG')
args=parser.parse_args()
if sys.platform!='darwin':parser.error('Mac app packaging requires macOS and Xcode command-line tools')
CORE=args.core.expanduser().resolve()
ORIGINAL=args.app.expanduser().resolve()
BUILD=args.output_dir.expanduser().resolve()
launcher_source=args.launcher_source.expanduser().resolve()
for required in (CORE/'manifest.xml',ORIGINAL/'Contents/Resources/src/mac_entry.lua',launcher_source):
    if not required.is_file():parser.error('Missing build input: '+str(required))
for library in (ORIGINAL/'Contents/MacOS').glob('*.dylib'):
    subprocess.run(['lipo',str(library),'-verify_arch','arm64'],check=True)
if BUILD == ROOT or ROOT.is_relative_to(BUILD) or BUILD.is_relative_to(ORIGINAL) or BUILD.is_relative_to(CORE):
    parser.error('Output directory must be separate from the repository root and build inputs')
STAGE=BUILD/'image'
APP=STAGE/'PoB2 简体中文.app'
SUPPORT='PathOfBuildingMacPoE2Chinese'
BUNDLE_VERSION='pob2-0.23.1-zh-0.6.2-public-1'
STAGE.mkdir(parents=True,exist_ok=True)
if APP.exists():
    raise SystemExit('The staging app already exists; use the existing build or explicitly archive it before rebuilding.')
install.validate_payload(PLUGIN/'payload')
shutil.copytree(ORIGINAL,APP,copy_function=shutil.copyfile)
res=APP/'Contents/Resources'
shutil.rmtree(res/'src')
(res/'src').mkdir()
manifest=ET.parse(CORE/'manifest.xml').getroot()
assert manifest.find('Version').get('number')=='0.23.1'
files={}
for entry in manifest.findall('File'):
    name=entry.get('name');path=Path(name)
    assert not path.is_absolute() and '..' not in path.parts
    source=CORE/path
    assert source.is_file() and not source.is_symlink(),name
    raw=source.read_bytes()
    if name=='Launch.lua': raw=install.clean_entry(raw.decode()).encode()
    # The upstream updater accepts LF or CRLF text. Reject any other local edits.
    variants=[raw,raw.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')]
    assert any(hashlib.sha1(v).hexdigest()==entry.get('sha1') for v in variants),name
    dest=res/'src'/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)
    files[name]=hashlib.sha256(raw).hexdigest()
shutil.copyfile(CORE/'manifest.xml',res/'src/manifest.xml')
(res/'PoB2Chinese').mkdir()
for source in (PLUGIN/'payload').iterdir():
    if source.suffix in ('.lua','.png'):
        shutil.copyfile(source,res/'PoB2Chinese'/source.name)
install.validate_payload(res/'PoB2Chinese')
fonts=res/'Fonts';fonts.mkdir()
for name in ('NotoSansCJKsc-Regular.otf','LICENSE'):shutil.copyfile(ROOT/'fonts'/name,fonts/name)
managed=sorted(p.name for p in (res/'PoB2Chinese').iterdir())
bootstrap=(ROOT/'packaging/bundle_bootstrap.lua.in').read_text()
upstream=(ORIGINAL/'Contents/Resources/src/mac_entry.lua').read_text()
assert upstream.count('dofile("Launch.lua")')==1
# The sharing copy keeps the public core updater; a new original .app download
# does not include this add-on, so do not advertise replacement as a CN update.
upstream=upstream.replace('local current = parseVersion(os.getenv("POB_MAC_VERSION"))','local current = nil -- Chinese bundle updates are distributed as a complete DMG')
entry=bootstrap.replace('@PAYLOAD_FILES@','{'+','.join(json.dumps(n) for n in managed)+'}').replace('@UPSTREAM_ENTRY@',upstream)
(res/'src/mac_entry.lua').write_text(entry)
launcher=APP/'Contents/MacOS/Path of Building - PoE2'
subprocess.run(['clang++','-std=c++17','-O2','-arch','arm64','-mmacosx-version-min=11.0',
    '-DPOB_APP_SUPPORT_DIR="'+SUPPORT+'"','-DPOB_BUNDLE_VERSION_STRING="'+BUNDLE_VERSION+'"',
    '-DPOB_MAC_VERSION_STRING="zh-v0.6.2"',str(launcher_source),'-o',str(launcher)],check=True)
info=APP/'Contents/Info.plist'
with info.open('rb') as f:pl=plistlib.load(f)
pl.update(CFBundleIdentifier='local.pob2.chinese',CFBundleName='PoB2 简体中文',CFBundleDisplayName='PoB2 简体中文',
    CFBundleShortVersionString='0.6.2',CFBundleVersion='60201',LSMinimumSystemVersion='11.0')
with info.open('wb') as f:plistlib.dump(pl,f)
# No personal settings, source research caches or hardcoded local account path.
for p in (res/'src').rglob('*'):
    if p.is_file() and p.suffix in ('.lua','.xml','.txt','.json'):
        assert str(Path.home()).encode() not in p.read_bytes(),str(p.relative_to(APP))
for p in (res/'PoB2Chinese').iterdir():
    if p.suffix=='.lua':assert str(Path.home()).encode() not in p.read_bytes(),p.name
# Preserve upstream notices, and disclose the derivative packaging/source data.
notices=res/'Chinese-Notices';notices.mkdir()
shutil.copyfile(res/'src/LICENSE.md',notices/'UPSTREAM-LICENSE.md')
shutil.copyfile(launcher_source,notices/'launcher.cpp')
shutil.copyfile(ROOT/'packaging/bundle_bootstrap.lua.in',notices/'bundle_bootstrap.lua.in')
(notices/'README.txt').write_text('''PoB2 简体中文个人分享版，非官方发行版。
核心：PathOfBuildingCommunity/PathOfBuilding-PoE2 0.23.1
Mac 移植：https://github.com/stevschmid/PathOfBuilding-Mac
引擎：https://github.com/stevschmid/PathOfBuilding-SimpleGraphic
汉化 v0.6.2：中文显示、搜索及输入适配；不改变核心计算。
游戏文字来源：腾讯国服公开交易目录和词缀 API；https://poe2db.tw/cn/ 。
沿用已验证国服译文；部分 UI 指标与旧版文字经过人工校对。
PoE2DB Wiki 内容按其注明的 CC BY-NC-SA 3.0 等适用条款；其他游戏文本权利仍属原权利人。
本包保留来源说明，仅作个人非商业分享。
中文字体：Noto Sans CJK SC，https://github.com/notofonts/noto-cjk ，SIL OFL 1.1；完整字体及许可证在 ../Fonts/。
mac_input.lua 在本进程的 GLFW 字符回调中保留 UTF-8，无全局键盘监听。
''')
# Clean copying strips extended attributes without altering the source bundle.
for p in APP.rglob('*'):
    if p.name=='.DS_Store':p.unlink()
(STAGE/'Applications').symlink_to('/Applications',target_is_directory=True)
(BUILD/'core-file-manifest.json').write_text(json.dumps({'coreVersion':'0.23.1','files':files},indent=2)+'\n')
print('Built',APP,'with',len(files),'verified core files and',len(managed),'Chinese resources')

shutil.copyfile(ROOT/'packaging/使用说明.txt',STAGE/'使用说明.txt')
shutil.copyfile(ROOT/'THIRD_PARTY_NOTICES.md',notices/'THIRD_PARTY_NOTICES.md')
shutil.copyfile(ROOT/'LICENSE',notices/'PLUGIN-LICENSE.txt')
for name in ('docs', 'fonts', 'licenses'):(notices/name).mkdir()
shutil.copyfile(ROOT/'docs/DATA_SOURCES.md',notices/'docs/DATA_SOURCES.md')
shutil.copyfile(ROOT/'fonts/LICENSE',notices/'fonts/LICENSE')
shutil.copyfile(ROOT/'licenses/PathOfBuilding-NOTICES.txt',notices/'licenses/PathOfBuilding-NOTICES.txt')
# Ad-hoc signing checks bundle integrity; it does not provide notarization.
for library in sorted((APP/'Contents/MacOS').glob('*.dylib')):
    subprocess.run(['codesign','--force','--sign','-','--timestamp=none',str(library)],check=True)
subprocess.run(['codesign','--force','--sign','-','--timestamp=none','--options','runtime',
    '--entitlements',str(ROOT/'packaging/entitlements.plist'),str(APP)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(APP)],check=True)
if args.dmg:
    image=BUILD/'PoB2-0.23.1-zh-CN-0.6.2-AppleSilicon.dmg'
    subprocess.run(['hdiutil','create','-volname','PoB2 简体中文 0.6.2','-srcfolder',str(STAGE),
        '-format','UDZO','-imagekey','zlib-level=9',str(image)],check=True)
    subprocess.run(['hdiutil','verify',str(image)],check=True)
    image.with_suffix('.dmg.sha256').write_text(hashlib.sha256(image.read_bytes()).hexdigest()+'  '+image.name+'\n')
    print(image)

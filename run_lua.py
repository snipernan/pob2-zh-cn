"""Run one Lua test with LuaJIT, or the exact native library in POB2_MAC_APP."""
import argparse
import ctypes as C
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('script', type=Path)
    parser.add_argument('--app', type=Path, default=os.environ.get('POB2_MAC_APP'))
    args = parser.parse_args()
    script = args.script.resolve()
    if not script.is_file():
        parser.error('Lua script does not exist: ' + str(script))
    if args.app:
        app = Path(args.app).expanduser().resolve()
    else:
        app = next((p for p in (Path('/Applications/Path of Building - PoE2.app'),
                   Path.home() / 'Applications/Path of Building - PoE2.app') if p.is_dir()), None)
    if app is None:
        command = shutil.which('luajit')
        if not command:
            parser.error('Install LuaJIT for unit tests, or set POB2_MAC_APP to your native PoB2 .app')
        return subprocess.call([command, str(script)])
    lib = app / 'Contents/MacOS'
    if not (lib / 'libSimpleGraphic.dylib').is_file():
        parser.error('The selected app has no libSimpleGraphic.dylib')
    os.environ['POB2_MAC_LIB'] = str(lib)
    for directory in ('test-user', 'test-output/stat-comparison'):
        (ROOT / directory).mkdir(parents=True, exist_ok=True)
    for name in ('libGLESv2.dylib', 'libEGL.dylib'):
        C.CDLL(str(lib / name), mode=C.RTLD_GLOBAL)
    lua = C.CDLL(str(lib / 'libSimpleGraphic.dylib'), mode=C.RTLD_GLOBAL)
    lua.luaL_newstate.restype = C.c_void_p
    lua.luaL_openlibs.argtypes = [C.c_void_p]
    lua.luaL_loadfile.argtypes = [C.c_void_p, C.c_char_p]
    lua.luaL_loadfile.restype = C.c_int
    lua.lua_pcall.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int]
    lua.lua_pcall.restype = C.c_int
    lua.lua_tolstring.argtypes = [C.c_void_p, C.c_int, C.c_void_p]
    lua.lua_tolstring.restype = C.c_char_p
    lua.lua_close.argtypes = [C.c_void_p]
    state = lua.luaL_newstate()
    if not state:
        raise RuntimeError('Could not initialize LuaJIT')
    lua.luaL_openlibs(state)
    try:
        result = lua.luaL_loadfile(state, str(script).encode())
        if not result:
            result = lua.lua_pcall(state, 0, -1, 0)
        if result:
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
    finally:
        lua.lua_close(state)
    return 0


if __name__ == '__main__':
    sys.exit(main())

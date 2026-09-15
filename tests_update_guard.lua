-- Run through test_update_guard.py: every writable path is a temporary fixture.
local root = assert(os.getenv('POB2_GUARD_FIXTURE'))
local project = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
local target, cleanFile = root .. '/src/Launch.lua', root .. '/clean.lua'
local function read(path)
    local f = assert(io.open(path, 'rb')); local s = f:read('*a'); f:close(); return s
end
local function write(path, value)
    local f = assert(io.open(path, 'wb')); assert(f:write(value)); assert(f:close())
end
local clean, installed = read(cleanFile), read(target)
local hook = installed:sub(#clean + 1)
local pluginRoot = root .. '/PoB2Chinese'
-- Exercise the public init.lua LoadModule wrapper, not just the repair helper.
function DrawString() end
function DrawStringWidth(_, _, s) return #s end
function DrawStringCursorIndex() return 1 end
function GetDrawColor() return 1, 1, 1, 1 end
function SetDrawColor() end
function NewImageHandle() return {} end
function DrawImage() end
common = { classes = {} }
launch = { OnKeyDown = function() return 'original' end }
local action
function LoadModule(name, ...)
    if name == 'UpdateApply' then
        if action == 'throw' then error('upstream update failure') end
        if action == 'actual' then
            local result = assert(loadfile(root .. '/UpdateApply.lua'))(...)
            return result, 'kept', nil, 17
        end
        if type(action) == 'function' then action() end
    end
    return nil, 'kept', nil, 17
end
local P = assert(loadfile(pluginRoot .. '/init.lua'))(pluginRoot)
local U = P.updates
local function reset() write(target, installed); P.enabled = true end
local function update(value)
    action = function() write(target, value) end
    local a,b,c,d = LoadModule('UpdateApply', 'fixture')
    assert(a == nil and b == 'kept' and c == nil and d == 17, 'Preserve multiple return values')
end
local newer = clean .. '\n-- newer upstream core with its own changes\n'
update(newer)
assert(read(target) == newer .. hook and U.state == 'restored', 'Preserve all updated bytes and append one hook: '..tostring(U.state)..' '..tostring(U.lastError))
update(clean)
assert(read(target) == installed, 'Consecutive update restores exactly one hook')
local crlf = newer:gsub('\n', '\r\n')
update(crlf)
assert(read(target) == crlf .. hook, 'Preserve updated CRLF bytes')
update(clean)
action = function() end; LoadModule('UpdateApply')
assert(read(target) == installed and U.state == 'unchanged', 'Update without entry replacement is idempotent')
P.enabled = false; update(newer)
assert(read(target) == newer .. hook, 'Disabled Chinese display retains automatic loading')
assert(read(pluginRoot .. '/disabled') == 'disabled\n', 'Preserve language preference')
-- On a fresh Lua state, the restored core loads the plugin through its own hook.
local sentinel = root .. '/settings.xml'; local settings = read(sentinel)
-- User uninstall while the current process still exists.
write(target, clean); update(newer)
assert(read(target) == newer and U.state == 'skipped', 'Uninstalled entry stays uninstalled')
-- Bundled entry has no standalone marker and retains its separate loader.
write(target, clean); update(clean)
assert(read(target) == clean and U.state == 'skipped', 'No standalone hook for complete app')
reset(); action = 'throw'
local ok,err = pcall(LoadModule, 'UpdateApply')
assert(not ok and tostring(err):find('upstream update failure', 1, true))
assert(read(target) == installed, 'Original update error propagates')
reset(); local incompatible = 'launch = {}\nreturn launch\n'; update(incompatible)
assert(read(target) == incompatible and U.state == 'needs_reinstall', 'Keep incompatible core untouched')
reset(); local invalid = clean .. '\nthis is invalid lua!\n'; update(invalid)
assert(read(target) == invalid and U.state == 'needs_reinstall', 'Keep invalid core untouched')
reset(); local foreign = newer .. '\n-- BEGIN POB2 ZH-CN BOOTSTRAP\nforeign=true\n-- END POB2 ZH-CN\n'
update(foreign)
assert(read(target) == foreign and U.state == 'needs_reinstall', 'Preserve foreign marker for review')
-- Exercise failed final replacement and temporary-file cleanup.
reset(); local rename = os.rename
os.rename = function() return nil, 'simulated rename failure' end
update(newer); os.rename = rename
assert(read(target) == newer and U.state == 'needs_reinstall', 'Failed rename preserves current core')
-- Failed temporary writes and symlinks preserve the updated destination.
reset(); local openBeforeFailure = io.open
io.open = function(path, mode)
    if path:find('.pob-zh-', 1, true) and mode == 'wb' then return nil, 'simulated write failure' end
    return openBeforeFailure(path, mode)
end
update(newer); io.open = openBeforeFailure
assert(read(target) == newer and U.state == 'needs_reinstall', 'Temporary write failure preserves core')
reset(); local ffi = require('ffi'); ffi.cdef('int symlink(const char *, const char *);')
local external = root .. '/symlink-destination.lua'; write(external, newer)
action = function() os.remove(target); assert(ffi.C.symlink(external, target) == 0) end
LoadModule('UpdateApply')
assert(read(external) == newer and U.state == 'needs_reinstall', 'Symlink destination stays untouched')
os.remove(target)
reset(); action = function() os.remove(target) end; LoadModule('UpdateApply')
assert(io.open(target, 'rb') == nil and U.state == 'needs_reinstall', 'Missing updated entry stays missing')
-- Simulate a concurrent writer after temporary bytes have been written.
reset(); local nativeOpen = io.open
io.open = function(path, mode)
    local f = nativeOpen(path, mode)
    if path:find('.pob-zh-', 1, true) and mode == 'wb' then
        return {write=function(_,...) return f:write(...) end,close=function()
            local result=f:close(); write(target, newer .. '-- concurrent edit\n'); return result end}
    end
    return f
end
update(newer); io.open = nativeOpen
assert(read(target) == newer .. '-- concurrent edit\n' and U.state == 'needs_reinstall', 'Keep concurrent edits')
-- Final scenario uses either the exact installed updater or the CI contract fixture.
reset(); write(root .. '/incoming.lua', newer)
write(root .. '/operations.txt', 'move "' .. root .. '/incoming.lua" "' .. target .. '"\n')
action = 'actual'; LoadModule('UpdateApply', root .. '/operations.txt')
assert(read(target) == newer .. hook and U.state == 'restored', 'Actual updater finishes before repair')
assert(read(sentinel) == settings, 'User settings untouched')
print('PASS update guard: updated bytes, repeated updates, return values, preferences, uninstall, bundle scope, errors, incompatible core, concurrent writes, atomic failure and actual update path')

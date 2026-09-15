-- Preserve an installed standalone bootstrap across a completed core update.
-- The snapshot is taken immediately before UpdateApply, so an uninstalled
-- plugin or the bundle's separate loader never gets a new Launch.lua hook.
local root = ...
local U = { state = 'idle' }
local support = root:match('^(.*)/PoB2Chinese$')
local entry = support and (support .. '/src/Launch.lua')
local beginMark, endMark = '-- BEGIN POB2 ZH-CN', '-- END POB2 ZH-CN'
local native
local function platform()
    if native then return native end
    local ffi = require('ffi')
    assert(ffi.os == 'OSX' or ffi.os == 'Linux', 'Unsupported update guard platform')
    ffi.cdef[[int mkstemp(char *template); int close(int fd);
        long readlink(const char *path, char *buf, unsigned long size);]]
    native = { ffi = ffi, C = ffi.C }
    return native
end
local function regular(path)
    local api = platform()
    return api.C.readlink(path, api.ffi.new('char[1]'), 1) < 0
end
local function read(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('*a'); f:close(); return s
end
local function occurrences(s, token)
    local n, pos = 0, 1
    while true do
        local _, finish = s:find(token, pos, true)
        if not finish then return n end
        n, pos = n + 1, finish + 1
    end
end
local function supported(s)
    local patterns = {'^%s*launch%s*=%s*{%s*}', '^%s*function%s+launch:OnInit%s*%(',
        '^%s*function%s+launch:OnKeyDown%s*%('}
    for _, pattern in ipairs(patterns) do
        local count = 0
        for line in (s .. '\n'):gmatch('(.-)\n') do
            if line:match(pattern) then count = count + 1 end
        end
        if count ~= 1 then return false end
    end
    return loadstring(s:gsub('^#[^\n]*\n', ''), '@Chinese-update-validation') ~= nil
end
local function warn(message)
    U.state, U.lastError = 'needs_reinstall', tostring(message)
    if ConPrintf then ConPrintf('Chinese update hook: %s. Please reinstall the plugin after restarting.', U.lastError) end
end
function U.capture()
    U.state, U.lastError = 'skipped', nil
    if not entry then return nil end
    local ok, result = pcall(function()
        if not regular(entry) then return nil end
        local s = read(entry)
        if not s or occurrences(s, beginMark) ~= 1 or occurrences(s, endMark) ~= 1 then return nil end
        local hook = s:match('(\r?\n%-%- BEGIN POB2 ZH%-CN BOOTSTRAP\r?\n.-%-%- END POB2 ZH%-CN\r?\n)')
        if not hook or not hook:find('local root = ' .. string.format('%q', root) .. '\n', 1, true) then return nil end
        if not supported(s) then return nil end
        return { hook = hook }
    end)
    if not ok then warn(result); return nil end
    if result then U.state = 'captured' end
    return result
end
function U.restore(snapshot)
    if not snapshot then return end
    local temporary
    local ok, err = pcall(function()
        assert(regular(entry), 'Updated entry is a symlink')
        local current = assert(read(entry), 'Updated entry is missing')
        if occurrences(current, beginMark) > 0 or occurrences(current, endMark) > 0 then
            assert(occurrences(current, beginMark) == 1 and occurrences(current, endMark) == 1
                and current:find(snapshot.hook, 1, true), 'Updated entry has different plugin markers')
            U.state = 'unchanged'
            return
        end
        assert(supported(current), 'Updated Launch.lua structure or syntax needs review')
        local bytes = current .. snapshot.hook
        local api = platform()
        local template = api.ffi.new('char[?]', #entry + 32, entry .. '.pob-zh-XXXXXX')
        local fd = api.C.mkstemp(template)
        assert(fd >= 0, 'Could not create temporary entry')
        temporary = api.ffi.string(template)
        api.C.close(fd)
        local f = assert(io.open(temporary, 'wb'))
        local written, writeErr = f:write(bytes)
        local closed, closeErr = f:close()
        assert(written, writeErr); assert(closed, closeErr)
        assert(read(temporary) == bytes, 'Temporary entry verification failed')
        assert(regular(entry) and read(entry) == current, 'Entry changed during repair')
        assert(os.rename(temporary, entry))
        temporary = nil
        U.state = 'restored'
    end)
    if temporary then os.remove(temporary) end
    if not ok then warn(err) end
end
return U

-- Preserve GLFW's committed Unicode scalars across SimpleGraphic's ASCII-only
-- CallKeyHandler. The original callback still owns focus, console and ImGui
-- routing; only the synchronous Lua OnChar payload is restored to UTF-8.
local I = { state = 'waiting' }
local pending, callback, previous, window, native, ffi
local function encode(n)
    if n < 0 or n > 0x10ffff or n >= 0xd800 and n <= 0xdfff then return nil end
    if n < 0x80 then return string.char(n) end
    if n < 0x800 then return string.char(0xc0 + math.floor(n / 64), 0x80 + n % 64) end
    if n < 0x10000 then
        return string.char(0xe0 + math.floor(n / 4096), 0x80 + math.floor(n / 64) % 64, 0x80 + n % 64)
    end
    return string.char(0xf0 + math.floor(n / 262144), 0x80 + math.floor(n / 4096) % 64,
        0x80 + math.floor(n / 64) % 64, 0x80 + n % 64)
end
local function resolve()
    ffi = require('ffi')
    if ffi.os ~= 'OSX' then I.state = 'unsupported'; return end
    ffi.cdef[[
        typedef struct GLFWwindow GLFWwindow;
        typedef void (*PoBCNCharCallback)(GLFWwindow*, unsigned int);
        GLFWwindow* glfwGetCurrentContext(void);
        PoBCNCharCallback glfwSetCharCallback(GLFWwindow*, PoBCNCharCallback);
    ]]
    local ok = pcall(function() return ffi.C.glfwGetCurrentContext end)
    if ok then native = ffi.C; return end
    -- Use the running app's module search paths, never a second GLFW library.
    for pattern in package.cpath:gmatch('[^;]+') do
        local path = pattern:gsub('%?', 'libSimpleGraphic')
        local found, lib = pcall(ffi.load, path)
        if found and pcall(function() return lib.glfwGetCurrentContext end) then native = lib; return end
    end
    error('The running SimpleGraphic library does not expose GLFW character callbacks')
end
local function onNativeChar(w, codepoint)
    local saved = pending
    pending = codepoint >= 128 and encode(tonumber(codepoint)) or nil
    -- Keep the native callback chain: it may intentionally consume input.
    local ok, err = pcall(previous, w, codepoint)
    pending = saved
    if not ok then I.lastError = tostring(err); I.state = 'callback-error' end
end
-- FFI -> Lua -> original native callback -> Lua is deliberately reentrant.
-- Never trace the function making the callback-capable native call.
if jit then jit.off(onNativeChar, true) end
function I.attach()
    if I.state ~= 'waiting' then return I.state == 'attached' end
    local ok, err = pcall(function()
        if not native then resolve() end
        if not native then return end
        local w = native.glfwGetCurrentContext()
        if w == nil then return end -- Headless checks / window not created yet.
        callback = ffi.cast('PoBCNCharCallback', onNativeChar)
        previous = native.glfwSetCharCallback(w, callback)
        if previous == nil then
            native.glfwSetCharCallback(w, nil)
            callback:free(); callback = nil
            error('No native character callback to preserve')
        end
        window, I.state = w, 'attached'
    end)
    if not ok then
        I.state, I.lastError = 'unavailable', tostring(err)
        if ConPrintf then ConPrintf('PoB2 Chinese input bridge: %s', I.lastError) end
    end
    return I.state == 'attached'
end
function I.detach()
    if window and native.glfwGetCurrentContext() == window then
        local current = native.glfwSetCharCallback(window, previous)
        -- Another owner may have installed its own chain after ours. Do not
        -- overwrite it or free a callback which that chain can still invoke.
        if current ~= callback then native.glfwSetCharCallback(window, current)
        else callback:free(); callback = nil end
    end
    window, I.state = nil, 'detached'
end
function I.install(owner)
    if I.owner == owner then return end
    I.owner = owner
    local char, frame, exit = owner.OnChar, owner.OnFrame, owner.OnExit
    owner.OnChar = function(self, key, ...)
        if char then return char(self, pending or key, ...) end
    end
    owner.OnFrame = function(self, ...)
        I.attach()
        if frame then return frame(self, ...) end
    end
    owner.OnExit = function(self, ...)
        I.detach()
        if exit then return exit(self, ...) end
    end
end
return I

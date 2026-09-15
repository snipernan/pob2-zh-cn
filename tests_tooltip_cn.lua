-- Run after integration.lua: exercise the real Tooltip layout and F10 cache.
local root = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
local wrap = assert(loadfile(root .. '/payload/tooltip_cn.lua'))()
local P = assert(PoB2Chinese)
local utf8 = require('lua-utf8')
assert(P.enabled)
local function nowrap(text, width)
    assert(wrap(text, 16, width, 'VAR', P.measure) == text, 'Keep English, fitting text and existing newlines unchanged')
end
nowrap('A very long English sentence without Chinese', 25)
nowrap('生命 +25%\n\n魔力\n', 300)
nowrap('生命', 0)
local sample = '^7' .. string.rep('生命护盾', 8) .. '^xAABBCC+(60-79)%  -12.5%  ^1技能伤害' .. string.rep('火焰抗性', 8)
local wrapped = wrap(sample, 16, 140, 'VAR', P.measure)
assert(wrapped ~= sample)
assert(wrapped:gsub('\n', '') == sample, 'Only insert newlines: preserve every original UTF-8 byte, color code, space, sign and number')
assert(wrapped:find('+(60-79)%', 1, true) and wrapped:find('-12.5%', 1, true), 'Keep ranges and signed percentages whole')
for line in (wrapped .. '\n'):gmatch('(.-)\n') do
    assert(P.measure(16, 'VAR', line) <= 140, 'Every Chinese presentation line must fit its width')
    local ok, length = pcall(utf8.len, line)
    assert(ok and length, 'Do not split UTF-8 characters')
end

local before = assert(build:SaveDB('test'))
local tooltip, height = new('Tooltip'), 16
tooltip.maxWidth = 152
local function show(text)
    if tooltip:CheckForUpdate(text) then
        tooltip.maxWidth = 152 -- Clear resets width, matching the native caller.
        tooltip:AddLine(height, text, 'VAR')
    end
    local result, count = {}, 0
    for _, line in ipairs(tooltip.lines) do
        if line.text then
            count = count + 1; result[#result + 1] = line.text
            assert(P.measure(height, 'VAR', line.text) <= 140, 'Real Tooltip lines fit maxWidth minus padding')
        end
    end
    return table.concat(result), count
end
local displayed, count = show(sample)
assert(displayed == sample and count > 1, 'Real Tooltip receives all text as multiple complete lines')
local blockHeight = 0
for _, block in ipairs(tooltip.blocks) do blockHeight = blockHeight + block.height end
assert(blockHeight == count * (height + 2), 'Native layout counts the height of every inserted line')
tooltip:Draw(20, 20, 20, 20, { x = 0, y = 0, width = 1920, height = 1080 })

local longStat = '+50 to maximum Life'
assert(show(longStat):find('生命上限', 1, true))
P.toggle()
-- English wrapping is the original PoB behavior, so only inspect its text/cache.
if tooltip:CheckForUpdate(longStat) then tooltip:AddLine(height, longStat) end
local english = {}; for _, line in ipairs(tooltip.lines) do if line.text then english[#english + 1] = line.text end end
assert(table.concat(english) == longStat, 'F10 must regenerate English instead of reusing wrapped Chinese')
P.toggle()
assert(show(longStat):find('生命上限', 1, true))
assert(build:SaveDB('test') == before, 'Line wrapping and F10 must not change the exported build')
print('PASS real tooltip: Chinese width/height, UTF-8/color/number preservation, cached F10 refresh and unchanged export')

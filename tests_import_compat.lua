local root = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
local C = dofile(root .. '/payload/import_compat.lua')
for _, element in ipairs({ 'Fire', 'Cold', 'Lightning', 'Chaos' }) do
    for _, value in ipairs({ '+22', '+37', '+0' }) do
        assert(C.canonical(element .. ' Resistance is ' .. value .. '%') == value .. '% to ' .. element .. ' Resistance')
    end
end
for _, line in ipairs({ 'Fire Resistance is 75%', 'Fire Resistance is -37%', 'Maximum Fire Resistance is +75%',
    'Your Fire Resistance is +22%', 'Fire Resistance is unaffected by Area Penalties',
    'Fire Resistance is +22% while moving', 'Fire Resistance is +22%\nOther modifier',
    'Fire Resistance is +22.5%', '+22% to Fire Resistance', 'Strength is +22%' }) do
    assert(not C.canonical(line), line)
end
local calls = {}
local parser = C.wrap(function(line, flag)
    calls[#calls + 1] = line
    assert(flag == 'flag')
    if line == '+22% to Fire Resistance' then return { 'canonical' } end
    return nil, line
end)
local mods, extra = parser('Fire Resistance is +22%', 'flag')
assert(mods[1] == 'canonical' and not extra and #calls == 2)
local native = { 'native wins' }
assert(C.wrap(function() return native end)('Fire Resistance is +22%') == native)
assert(C.wrap(function() return {} end)('Fire Resistance is +0%'))
mods, extra = C.wrap(function(line) return nil, line end)('Fire Resistance is +22%')
assert(not mods and extra == 'Fire Resistance is +22%', 'Preserve unsupported results if the canonical form also fails')
mods, extra = C.wrap(function(line) return { 'partial' }, line end)('Fire Resistance is +22%')
assert(mods[1] == 'partial' and extra == 'Fire Resistance is +22%')
print('PASS import compatibility: explicit-plus forms, native precedence, unsupported and partial fallbacks')

if not build then return end
for _, element in ipairs({ 'Fire', 'Cold', 'Lightning', 'Chaos' }) do
    for _, value in ipairs({ 22, 37, 0 }) do
        local line = element .. ' Resistance is ' .. string.format('%+d', value) .. '%'
        local parsed, remaining = modLib.parseMod(line)
        assert(parsed and not remaining, line)
        assert(#parsed == 1 and parsed[1].name == element .. 'Resist' and parsed[1].type == 'BASE'
            and parsed[1].value == value, 'Must be an additive resistance: ' .. line)
    end
    local overridden = modLib.parseMod(element .. ' Resistance is -37%')
    assert(overridden[1].type == 'OVERRIDE' and overridden[1].value == -37, 'Preserve native fixed-resistance mechanics')
end
local raw = [[Rarity: UNIQUE
Ventor's Gamble
Gold Ring
Implicits: 1
8% increased Rarity of Items found
+71 to maximum Life
+10 to Spirit
9% increased Rarity of Items found
Fire Resistance is +22%
Cold Resistance is +32%
Lightning Resistance is +37%]]
local converted = new('Item', raw)
assert(converted.raw == raw, 'Item source retains converter text')
local tooltip = new('Tooltip')
build.itemsTab:AddItemTooltip(tooltip, converted)
local texts = {}
for _, line in ipairs(tooltip.lines) do
    if line.text then texts[#texts + 1] = line.text end
end
local tooltipText = table.concat(texts, '\n')
assert(not tooltipText:find('Not supported', 1, true), tooltipText)
assert(tooltipText:find('火焰抗性', 1, true) and tooltipText:find('22', 1, true), tooltipText)
local function load(itemText)
    loadBuildFromXML([[<PathOfBuilding2><Build targetVersion="0_1" level="65" className="Sorceress" ascendClassName="None"/>
<Items><Item id="1">]] .. itemText .. [[</Item><ItemSet id="1"><Slot name="Ring 1" itemId="1"/></ItemSet></Items></PathOfBuilding2>]], 'Chinese name fixture')
    runCallback('OnFrame')
    local output = {}
    for key, value in pairs(build.calcsTab.mainOutput) do
        if type(value) == 'number' then output[key] = value end
    end
    return output
end
local baseline = load('Rarity: NORMAL\nGold Ring\nImplicits: 0')
local actual = load(raw)
assert(actual.FireResistTotal == baseline.FireResistTotal + 22)
assert(actual.ColdResistTotal == baseline.ColdResistTotal + 32)
assert(actual.LightningResistTotal == baseline.LightningResistTotal + 37)
assert(build:SaveDB('code'):find('Fire Resistance is +22%', 1, true), 'Export preserves original source')
PoB2Chinese.toggle(); runCallback('OnFrame')
assert(build.calcsTab.mainOutput.FireResistTotal == actual.FireResistTotal, 'Input compatibility stays active in English')
PoB2Chinese.toggle()
local canonical = raw:gsub('(%a+ Resistance) is ([+-]%d+)%%', '%2%% to %1')
local expected = load(canonical)
for key, value in pairs(actual) do
    assert(value == expected[key] or (value ~= value and expected[key] ~= expected[key]), 'Calculation mismatch: ' .. key)
end
print('PASS real imported item: BASE resistance +22/+32/+37, Chinese tooltip, original export, canonical calculation equivalence')
local name = '周年庆门徒'
local edit = new('EditControl', nil, {0, 0, 300, 20}, '')
for ch in name:gmatch('[\194-\244][\128-\191]+') do edit:OnChar(ch) end
assert(edit.buf == name, 'Real control preserves composed UTF-8 characters')
build.buildName, build.dbFileName = edit.buf, root .. '/test-user/' .. edit.buf .. '.xml'
assert(not build:SaveDBFile())
local f = assert(io.open(build.dbFileName, 'rb'))
local saved = f:read('*a'); f:close()
loadBuildFromXML(saved, name)
runCallback('OnFrame')
assert(build.buildName == name and build.itemsTab.items[1].raw:find('+22%% to Fire Resistance'))
assert(os.remove(root .. '/test-user/' .. name .. '.xml'))
print('PASS real Chinese name: EditControl input, UTF-8 filename save and build reload')

local root = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
local G = assert(loadfile(root .. '/payload/game_text.lua'))(root .. '/payload')
local count, unsupported = 0, {}
for _, entry in ipairs(G.affixes) do
    local index = 0
    local input = entry.en:gsub('#', function() index=index+1; return tostring(index * 17) end)
    index = 0
    local expected = entry.zh:gsub('#', function() index=index+1; return tostring(entry.order[index] * 17) end)
    local actual = G.translateAffix(input)
    if actual == nil then unsupported[#unsupported+1] = entry.en
    else assert(actual == expected, entry.en .. '\nexpected '..expected..'\nactual '..actual); count=count+1 end
end
assert(#unsupported == 0, 'Ambiguous/unmatched verified templates: '..table.concat(unsupported,'\n'))
assert(G.translateAffix('+50 to maximum Life') == '+50 生命上限')
assert(G.translateAffix('-50 to maximum Life') == '-50 生命上限')
assert(G.translateAffix('+(60-79) to maximum Life') == '+(60-79) 生命上限')
assert(G.translateAffix('0.5% of Life Regenerated per second') == nil, 'Unknown wording remains English')
assert(G.translateAffix('+25% to Fire Resistance') == '火焰抗性 +25%')
assert(G.translateAffix('Adds (3-6) to (10-20) Physical Damage') == '附加 (3-6) - (10-20) 物理伤害')
assert(G.translateAffix('Adds 3 to 10 Physical Damage') == '附加 3 - 10 物理伤害')
assert(G.translateAffix('Adds # to # Physical Damage') == '附加 # - # 物理伤害')
assert(G.translateAffix('Save: +50 to maximum Life') == nil, 'Never translate a substring of a custom message')
assert(G.translateAffix('+1.2.3 to maximum Life') == nil, 'Malformed numbers remain literal')
assert(G.translateText('^x8888FF+50 to maximum Life') == '^x8888FF+50 生命上限^x8888FF')
assert(G.translateSkill('Fireball') == '火球')
assert(G.translateSkill('Contagion') == '瘟疫')
assert(G.translateSkill('Unsupported custom skill') == nil)
local atlas, skills = dofile(root .. '/payload/font.lua'), 0
local function glyphs(text)
    for ch in text:gmatch('[\194-\244][\128-\191]+') do assert(atlas.glyphs[ch], 'Missing glyph: '..ch) end
end
for _, entry in pairs(G.skillsById) do skills=skills+1; glyphs(entry.zh) end
for _, entry in ipairs(G.affixes) do glyphs(entry.zh) end
local equipmentNames, equipmentFlavours = 0, 0
for _, name in ipairs({'equipmentBases','equipmentUniques','equipmentAugments','equipmentEmotions','equipmentTypes'}) do
    for _, entry in pairs(assert(G[name])) do
        equipmentNames=equipmentNames+1; glyphs(entry.zh)
        if entry.flavour then
            equipmentFlavours=equipmentFlavours+1
            for _, line in ipairs(entry.flavour.zh) do glyphs(line) end
        end
        for _, block in ipairs(entry.effectBlocks or {}) do glyphs(block.zh) end
    end
end
for _, entry in ipairs(G.equipmentAffixes) do glyphs(entry.zh) end
print('PASS equipment glyphs: '..equipmentNames..' labels; '..equipmentFlavours..' flavour blocks; '..#G.equipmentAffixes..' supplemental modifiers')
local treeNames, treeStats, treeBlocks, treeVariants = 0, 0, 0, 0
local function treeRecord(entry, variant)
    if entry.zh then treeNames = treeNames + 1; glyphs(entry.zh) end
    for _, stat in ipairs(entry.stats) do
        if stat.verification == 'official-trade2-exact-numeric-stat-template' then
            assert(G.translateAffix(stat.en) == stat.zh, 'Tree stat does not match official runtime template: ' .. stat.en)
        end
        glyphs(stat.zh); treeStats = treeStats + 1
    end
    for _, block in ipairs(entry.statBlocks or {}) do
        assert(#block.en > 0 and #block.zh > 0 and #block.versions > 0)
        for _, line in ipairs(block.zh) do glyphs(line) end
        treeBlocks = treeBlocks + 1
    end
    if variant then assert(entry.currentStats); treeVariants = treeVariants + 1 end
    for _, choice in ipairs(entry.variants or {}) do treeRecord(choice, true) end
end
for _, entry in pairs(G.treeById) do treeRecord(entry) end
assert(treeNames > 0 and treeStats > 0, 'Tree corpus must not be empty')
print('PASS tree corpus: '..treeNames..' base/variant names; '..treeStats..' versioned stats; '..treeBlocks..' complete blocks; '..treeVariants..' variants; official templates and all glyphs')
print('PASS game text: '..count..' official affix templates with distinct capture values; '..skills..' skill IDs; sign/range/decimal/unknown/glyph checks')

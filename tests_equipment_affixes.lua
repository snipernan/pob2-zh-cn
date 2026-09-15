local root = assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)/'))
local G = assert(loadfile(root..'/payload/game_text.lua'))(root..'/payload')
local count = 0
for _, entry in ipairs(G.equipmentAffixes) do
    local slot = 0
    local input = entry.en:gsub('#',function() slot=slot+1;return tostring(slot*19+0.5) end)
    slot=0
    local expected = entry.zh:gsub('#',function() slot=slot+1;return tostring(entry.order[slot]*19+0.5) end)
    local official = G.translateAffix(input)
    assert(G.translateEquipmentAffix(input)==(official or expected), 'Supplemental slot/precedence mismatch: '..input)
    count=count+1
end
assert(count>0,'Equipment supplemental corpus is empty')
assert(G.translateEquipmentAffix('+25% to Fire Resistance')==G.translateAffix('+25% to Fire Resistance'))
assert(G.translateEquipmentAffix('Adds (3-6) to (10-20) Physical Damage')=='附加 (3-6) - (10-20) 物理伤害')
assert(G.translateEquipmentAffix('My item: +25% to Fire Resistance')==nil)
assert(G.translateEquipmentAffix('+1.2.3 to maximum Life')==nil)
assert(G.translateEquipmentAffix('21% increased Spirit'), 'PoE2DB equipment Spirit wording should be available')
assert(not G.translateText('21% increased Spirit'), 'Equipment-specific supplementation must not affect other UI domains')
assert(G.translateEquipmentText('^x8888FF21% increased Spirit'):find('21',1,true))
assert(G.translateEquipmentAffix('25% INCREASED ARMOUR')==G.translateEquipmentAffix('25% increased Armour'), 'Capitalization does not alter an equipment modifier')
local block={lines={'Gain # Cold Surges','and # Fire Surges'},zh='获得 # 次烈焰涌动和 # 次冰霜涌动',order={2,1}}
assert(G.translateEquipmentBlock(block,{'^x8888FFGain 3 Cold Surges','and (6-9) Fire Surges'})=='获得 (6-9) 次烈焰涌动和 3 次冰霜涌动')
assert(G.translateEquipmentBlock(block,{'Gain 3 Cold Surges','and 6 Lightning Surges'})==nil)
assert(G.translateEquipmentBlock(block,{'Gain 3 Cold Surges'})==nil)
assert(G.translateEquipmentBlock(block,{'Gain 1.2.3 Cold Surges','and 6 Fire Surges'})==nil)
print('PASS equipment affixes: '..count..' templates, distinct decimals, official precedence, scope, signs/ranges and custom text')

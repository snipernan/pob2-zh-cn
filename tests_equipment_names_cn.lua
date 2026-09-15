-- Standalone identity/control probes plus actual runtime tests when integration
-- has loaded PoB2Chinese. No item is added/equipped or written back to the build.
local root = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
do
    local oldData, oldColor, oldMain, oldItemLib = data, colorCodes, main, itemLib
    local base, rune = {}, { Weapon = {} }
    local customEmotion = { name = 'Fixture Emotion' }
    data = { itemBases = { ['Fixture Ring'] = base }, itemMods = { Runes = { ['Fixture Rune'] = rune } },
        emotions = { customEmotion } }
    colorCodes, main = { NORMAL = '^7', MAGIC = '^1', RARE = '^3', UNIQUE = '^6', RELIC = '^9' },
        { notSupportedTooltipText = ' ^8(Not supported in PoB yet)' }
    local P = { enabled = true, revision = 0, translate = function(s) return s end }
    function P.withLiteralText(_, fn, ...) return fn(...) end
    local G = {
        equipmentBases = { ['Fixture Ring'] = { en = 'Fixture Ring', zh = '测试戒指' } },
        equipmentUniques = { ['Fixture Unique, Fixture Ring'] = { en = 'Fixture Unique', base = 'Fixture Ring', zh = '测试传奇',
            flavour = { en = { 'First flavour sentence', 'Second flavour sentence' }, zh = { '完整风味文字' } },
            effectBlocks = { { lines = { 'Fixture grants # Life', 'Fixture spends # Mana' },
                zh = '消耗 # 魔力时，获得 # 生命', order = { 2, 1 } } } } },
        equipmentAugments = { ['Fixture Rune'] = { en = 'Fixture Rune', zh = '测试符文' } },
        equipmentEmotions = { ['Fixture Emotion'] = { en = 'Fixture Emotion', zh = '测试情感' } },
        translateEquipmentAffix = function(text)
            if text == 'Fixture adds 12 life' then return '测试附加 12 生命' end
        end,
        translateEquipmentText = function(text)
            if text == '^1Fixture adds 12 life' then return '^1测试附加 12 生命' end
        end,
    }
    function G.matchEquipmentBlockLine(block, index, text)
        assert(not text:find(main.notSupportedTooltipText, 1, true), 'Block matcher receives no native warning suffix')
        if not block.lines[index] then return nil end
        local clean = text:gsub('%^x%x%x%x%x%x%x', ''):gsub('%^%d', '')
        local pattern = block.lines[index]:gsub('#', '([+-]?%%d+%%.?%%d*)')
        local value = clean:match('^' .. pattern .. '$')
        return value and { value }
    end
    function G.translateEquipmentBlock(block, texts)
        local values = {}
        for index, text in ipairs(texts) do
            local captures = G.matchEquipmentBlockLine(block, index, text)
            if not captures then return nil end
            for _, value in ipairs(captures) do values[#values + 1] = value end
        end
        local slot = 0
        local translated = block.zh:gsub('#', function() slot = slot + 1; return values[block.order[slot]] end)
        return (texts[1]:match('^(%^%d)') or '') .. translated
    end
    local E = assert(loadfile(root .. '/payload/equipment_cn.lua'))(P, G)
    local function item(rarity, title)
        return { name = title and title .. ', Fixture Ring' or 'Fixture Ring', title = title,
            baseName = 'Fixture Ring', base = base, rarity = rarity, namePrefix = '', nameSuffix = '' }
    end
    local normal, rare, unique = item('NORMAL'), item('RARE', 'Fixture Unique'), item('UNIQUE', 'Fixture Unique')
    assert(E.name(normal) == '测试戒指')
    assert(E.name(rare) == 'Fixture Unique, 测试戒指', 'A custom rare title must not become a unique title')
    assert(E.name(unique) == '测试传奇, 测试戒指')
    unique.title = 'User title'
    assert(not E.uniqueTitle(unique) and E.name(unique) == unique.name, 'Inconsistent parsed identity remains literal')
    unique.title = 'Fixture Unique'
    normal.base = {}
    assert(E.name(normal) == 'Fixture Ring', 'Reject a replaced base object with a coincidental name')
    normal.base = base
    local magic = item('MAGIC')
    magic.namePrefix, magic.nameSuffix, magic.name = 'Heavy ', ' of Testing', 'Heavy Fixture Ring of Testing'
    assert(E.name(magic) == 'Heavy 测试戒指 of Testing', 'Translate the parsed base span only')
    local rows = { GetRowValue = function(_, _, _, value) return '^3' .. value.name .. "  (Used in 'Fixture Ring')" end }
    local tooltipClass = { AddItemTooltip = function(self, tip, value)
        tip.center = true
        if value.title then tip:AddLine(20, '^3' .. value.title); tip:AddLine(20, '^3' .. value.baseName)
        else tip:AddLine(20, '^7' .. value.name) end
        tip:AddSeparator()
        if self.modifiers then
            for index, line in ipairs(self.modifiers) do
                if self.separatorAt == index then tip:AddSeparator() end
                tip:AddLine(16, line, self.font or 'FONTIN SC')
                if self.failAfter == index then error('intentional partial block failure') end
            end
        else tip:AddLine(16, self.modifier or 'Some original item modifier') end
        for _, line in ipairs(self.flavour or {}) do tip:AddLine(16, '^6' .. line, 'FONTIN SC ITALIC') end
        tip:AddSeparator()
        if self.fail then error('intentional item tooltip failure') end
    end }
    local fakeDrop = {
        UpdateSearch = function(self) self.searchInfos = {}; self.matchCount = 0 end,
        UpdateMatchCount = function(self)
            self.matchCount = 0; for _, info in ipairs(self.searchInfos) do if info.matches then self.matchCount = self.matchCount + 1 end end
        end,
        Draw = function(self)
            self.drawn = self.list[1].label
            if self.tooltipFunc then self.tooltipFunc(self.tip, 'DROP', 1, self.list[1]) end
            if self.fail then error('intentional dropdown failure') end
        end,
        OnSearchKeyDown = function() end,
        DrawSearchHighlights = function() end,
    }
    E.protectClasses({ ItemsTab = tooltipClass, SharedItemListControl = rows, DropDownControl = fakeDrop })
    assert(rows.GetRowValue({}, 1, 1, rare) == "^3Fixture Unique, 测试戒指  (Used in 'Fixture Ring')",
        'Translate item identity only; preserve a colliding user item-set title')
    local function tip()
        return { lines = {}, AddLine = function(self, _, text) self.lines[#self.lines + 1] = text end, AddSeparator = function() end }
    end
    local t = tip()
    tooltipClass.AddItemTooltip({}, t, rare)
    assert(t.lines[1] == '^3Fixture Unique' and t.lines[2] == '^3测试戒指')
    local originalLine, originalSeparator = t.AddLine, t.AddSeparator
    assert(not pcall(tooltipClass.AddItemTooltip, { fail = true }, t, unique))
    assert(t.AddLine == originalLine and t.AddSeparator == originalSeparator, 'Restore tooltip methods after errors')
    local ft = tip()
    tooltipClass.AddItemTooltip({ flavour = { 'First flavour sentence', 'Second flavour sentence' } }, ft, unique)
    assert(ft.lines[4] == '^6完整风味文字' and #ft.lines == 4, 'Translate the complete flavour block without pairing its different Chinese line count')
    ft = tip()
    tooltipClass.AddItemTooltip({ flavour = { 'First flavour sentence', 'Changed second sentence' } }, ft, unique)
    assert(ft.lines[4] == '^6First flavour sentence' and ft.lines[5] == '^6Changed second sentence',
        'A changed flavour block retains the full original text')
    ft = tip()
    tooltipClass.AddItemTooltip({ modifier = '^1Fixture adds 12 life' .. main.notSupportedTooltipText }, ft, unique)
    assert(ft.lines[3] == '^1测试附加 12 生命' .. main.notSupportedTooltipText,
        'An exact native unsupported suffix preserves the translated number, colour and original warning')
    ft = tip()
    tooltipClass.AddItemTooltip({ modifier = '^1Fixture adds 12 life (Different warning)' }, ft, unique)
    assert(ft.lines[3] == '^1Fixture adds 12 life (Different warning)', 'Do not guess arbitrary warning suffixes')
    local firstEffect, secondEffect = '^1Fixture grants +12.5 Life', '^1Fixture spends -3 Mana'
    ft = tip()
    tooltipClass.AddItemTooltip({ modifiers = { firstEffect .. main.notSupportedTooltipText,
        secondEffect .. main.notSupportedTooltipText }, flavour = { 'First flavour sentence', 'Second flavour sentence' } }, ft, unique)
    assert(ft.lines[3] == '^1消耗 -3 魔力时，获得 +12.5 生命' .. main.notSupportedTooltipText and #ft.lines == 4,
        'Complete equipment blocks reorder live numeric captures and retain one native warning')
    assert(ft.lines[4] == '^6完整风味文字', 'Effect buffering does not consume or split the following flavour block')
    ft = tip()
    tooltipClass.AddItemTooltip({ modifiers = { '^1Fixture grants 200 Life', '^1Fixture spends 10 Mana' } }, ft, unique)
    assert(ft.lines[3] == '^1消耗 10 魔力时，获得 200 生命' and #ft.lines == 3,
        'The same identity-bound block uses current rolled values, not source example numbers')
    ft = tip()
    tooltipClass.AddItemTooltip({ modifiers = { firstEffect, '^1Fixture spends -3 Spirit' } }, ft, unique)
    assert(ft.lines[3] == firstEffect and ft.lines[4] == '^1Fixture spends -3 Spirit',
        'A changed second modifier returns the entire buffered English block in order')
    ft = tip()
    tooltipClass.AddItemTooltip({ modifiers = { firstEffect, secondEffect }, separatorAt = 2 }, ft, unique)
    assert(ft.lines[3] == firstEffect and ft.lines[4] == secondEffect,
        'A tooltip separator prevents joining distinct modifier groups')
    ft = tip()
    tooltipClass.AddItemTooltip({ modifiers = { firstEffect .. '\n' .. secondEffect } }, ft, unique)
    assert(ft.lines[3] == firstEffect .. '\n' .. secondEffect, 'Do not infer native line boundaries inside arbitrary text')
    ft = tip()
    tooltipClass.AddItemTooltip({ modifiers = { firstEffect, secondEffect } }, ft, rare)
    assert(ft.lines[3] == firstEffect and ft.lines[4] == secondEffect, 'A custom rare title cannot acquire unique effect blocks')
    ft = tip()
    tooltipClass.AddItemTooltip({ modifiers = { firstEffect, secondEffect }, font = 'FONTIN SC ITALIC' }, ft, unique)
    assert(ft.lines[3] == firstEffect and ft.lines[4] == secondEffect, 'Flavour and other display roles cannot match an effect block')
    ft = tip()
    originalLine, originalSeparator = ft.AddLine, ft.AddSeparator
    assert(not pcall(tooltipClass.AddItemTooltip, { modifiers = { firstEffect, secondEffect }, failAfter = 1 }, ft, unique))
    assert(ft.lines[3] == firstEffect and #ft.lines == 3 and ft.AddLine == originalLine and ft.AddSeparator == originalSeparator,
        'A native exception flushes an incomplete effect and restores tooltip methods')
    local blockTranslator, blockMatcher = G.translateEquipmentBlock, G.matchEquipmentBlockLine
    G.translateEquipmentBlock = function() return nil end
    ft = tip()
    tooltipClass.AddItemTooltip({ modifiers = { firstEffect, secondEffect } }, ft, unique)
    assert(ft.lines[3] == firstEffect and ft.lines[4] == secondEffect and #ft.lines == 4,
        'A complete-line match still requires final numeric and whole-block validation before translation')
    G.translateEquipmentBlock = function() error('intentional block translator failure') end
    ft = tip()
    originalLine, originalSeparator = ft.AddLine, ft.AddSeparator
    assert(not pcall(tooltipClass.AddItemTooltip, { modifiers = { firstEffect, secondEffect } }, ft, unique))
    assert(ft.lines[3] == firstEffect and ft.lines[4] == secondEffect and #ft.lines == 4
        and ft.AddLine == originalLine and ft.AddSeparator == originalSeparator,
        'A whole-block validation exception retains every original modifier')
    G.translateEquipmentBlock = blockTranslator
    G.matchEquipmentBlockLine = function(block, index, text)
        if index == 2 then error('intentional block line matcher failure') end
        return blockMatcher(block, index, text)
    end
    ft = tip()
    assert(not pcall(tooltipClass.AddItemTooltip, { modifiers = { firstEffect, secondEffect } }, ft, unique))
    assert(ft.lines[3] == firstEffect and ft.lines[4] == secondEffect and #ft.lines == 4,
        'A line validator exception also retains the line that triggered validation')
    G.matchEquipmentBlockLine = blockMatcher
    itemLib = { formatModLine = function(line, dbMode)
        assert(dbMode, 'Database block aliases use the same ranges as its native tooltip')
        return line.display or line.line
    end }
    -- Keep explicit integer return values, as native item tooltips can repeat a
    -- line for more than one selected combination of item variants.
    unique.GetModLineVariantCount = function(self, line)
        if not line.variant or self.variant == line.variant then return 1 end
        return 0
    end
    unique.variant = 1
    unique.explicitModLines = { { line = 'unformatted source', display = firstEffect },
        { line = secondEffect .. main.notSupportedTooltipText, variant = 1 },
        { line = 'Fixture spends -3 Spirit', variant = 2 } }
    assert(E.effectBlockTexts(unique)[1] == '^1消耗 -3 魔力时，获得 +12.5 生命',
        'Block search uses the active native display and strips its warning before validation')
    unique.variant = 2
    assert(#E.effectBlockTexts(unique) == 0, 'An unselected variant cannot inject a Chinese modifier-block search alias')
    unique.variant = 1
    unique.implicitModLines, unique.explicitModLines = { unique.explicitModLines[1] }, { unique.explicitModLines[2] }
    assert(#E.effectBlockTexts(unique) == 0, 'Search never joins implicit and explicit modifier groups')
    unique.implicitModLines, unique.explicitModLines = {}, {}
    unique.buffModLines = { { line = firstEffect }, { line = secondEffect, variant = 1 } }
    assert(E.effectBlockTexts(unique)[1] == '^1消耗 -3 魔力时，获得 +12.5 生命',
        'Charm buff modifiers are an independent verified Chinese block-search source')
    unique.variant = 2
    assert(#E.effectBlockTexts(unique) == 0, 'Charm buff blocks also exclude inactive variants')
    local source = { { name = 'Fixture Ring', label = 'Fixture Ring', base = base } }
    local drop = setmetatable({ list = source, searchTerm = '测试', tip = tip() }, { __index = fakeDrop })
    drop.tooltipFunc = function(_, _, _, value) assert(value == source[1], 'Tooltip receives the original database row') end
    drop:UpdateSearch()
    assert(drop.matchCount == 1)
    drop:Draw()
    assert(drop.drawn == '测试戒指' and drop.list == source and source[1].label == 'Fixture Ring')
    drop.fail = true
    assert(not pcall(drop.Draw, drop))
    assert(drop.list == source and source[1].label == 'Fixture Ring', 'Error path restores the original selector list')
    drop.fail = nil
    local runeValue = { name = 'Fixture Rune', label = 'Adds 10 Fire Damage', slot = 'Weapon', lines = { 'Adds 10 Fire Damage' } }
    assert(E.dropdownLabel({}, 1, runeValue) == '测试符文  Adds 10 Fire Damage')
    local emotionValue = { emotion = customEmotion, label = 'Fixture Emotion ^8[Add 1]' }
    assert(E.dropdownLabel({}, 1, emotionValue) == '测试情感 ^8[Add 1]')
    assert(E.dropdownLabel({}, 1, { label = 'Fixture Ring' }) == nil, 'An ordinary dropdown label is not an item identity')
    local modRow = { label = 'Fixture Ring   ^8[Fixture adds 12 life/Unknown second effect]',
        mod = { 'Fixture adds 12 life', 'Unknown second effect' } }
    assert(E.dropdownLabel({ _pobCnEquipmentAffix = true }, 1, modRow)
        == 'Fixture Ring   ^8[测试附加 12 生命/Unknown second effect]',
        'A known equipment modifier selector translates each proven effect while preserving affix names and unknown text')
    assert(E.dropdownLabel({}, 1, modRow) == nil, 'Equipment modifier mappings do not apply to arbitrary dropdown rows')
    P.enabled = false
    drop:UpdateSearch()
    assert(drop.matchCount == 0, 'Chinese aliases stop matching in English mode')
    assert(E.name(unique) == unique.name and source[1].label == 'Fixture Ring')
    data, colorCodes, main, itemLib = oldData, oldColor, oldMain, oldItemLib
    print('PASS equipment identity probes: rare titles, base pointers, magic spans, suffix literals, complete effect/flavour blocks, numeric captures, variant-filtered block search, detached dropdown values, error cleanup, augment/emotion scope, language fallback')
end

if not PoB2Chinese then return end
local P, E = PoB2Chinese, assert(PoB2Chinese.equipment)
E.protectClasses(common.classes)
E.protectBuild(build)
assert(P.enabled)
local tab, before = build.itemsTab, assert(build:SaveDB('test'))
local function outputs()
    local result = {}
    for key, value in pairs(build.calcsTab.mainOutput) do if type(value) == 'number' then result[#result + 1] = key .. '=' .. tostring(value) end end
    table.sort(result)
    return table.concat(result, '\n')
end
local numbersBefore = outputs()
local function textOf(tip)
    local rows = {}
    for _, line in ipairs(tip.lines) do if line.text then rows[#rows + 1] = StripEscapes(line.text) end end
    return table.concat(rows, '\n')
end
local normal = new('Item', 'Rarity: NORMAL\nGold Ring\nImplicits: 0\n+50 to maximum Life')
local rare = new('Item', 'Rarity: RARE\nFireball\nGold Ring\nImplicits: 0\n+50 to maximum Life')
local baseZh = assert(E.baseName('Gold Ring', normal.base), 'Gold Ring needs verified source data')
local normalRaw, rareRaw = normal:BuildRaw(), rare:BuildRaw()
local tip = new('Tooltip')
tab:AddItemTooltip(tip, rare, nil, false, 500)
assert(StripEscapes(tip.lines[1].text) == 'Fireball', 'An actual rare title must remain user text')
assert(textOf(tip):find(baseZh, 1, true), 'Actual item header translates its parsed base')
assert(textOf(tip):find('+50 生命上限', 1, true))
local warningSetting, previousExtra = main.notSupportedModTooltips, normal.explicitModLines[1].extra
main.notSupportedModTooltips = true
normal.explicitModLines[1].extra = 'unsupported fixture remainder'
tip:Clear(true)
tab:AddItemTooltip(tip, normal, nil, false, 500)
assert(textOf(tip):find('+50 生命上限', 1, true)
    and textOf(tip):find('(Not supported in PoB yet)', 1, true),
    'The real item formatter warning must not prevent a verified signed modifier from translating')
normal.explicitModLines[1].extra, main.notSupportedModTooltips = previousExtra, warningSetting
local selectedUnique
for _, value in pairs(main.uniqueDB.list) do
    if E.uniqueTitle(value) and value.base.type == 'Ring' then selectedUnique = value; break end
end
assert(selectedUnique, 'At least one loaded unique must have a verified complete identity')
local uniqueRaw = selectedUnique.raw
tip:Clear(true)
tab:AddItemTooltip(tip, selectedUnique, nil, true, 500)
assert(textOf(tip):find(E.uniqueTitle(selectedUnique), 1, true), 'The real unique tooltip renders its verified title')
local db = tab.controls.uniqueDB
local query, mode, listFlag = db.controls.search.buf, db.controls.searchMode.selIndex, db.listBuildFlag
local filtersBefore = {}
for _, field in ipairs({ 'slot', 'type', 'league', 'requirement', 'obtainable' }) do
    filtersBefore[field] = db.controls[field].selIndex
    db.controls[field].selIndex = field == 'obtainable' and 2 or 1
end
db.controls.searchMode.selIndex = 2
db.controls.search:SetText(E.uniqueTitle(selectedUnique), true)
local chineseMatch = db:DoesItemMatchFilters(selectedUnique)
assert(chineseMatch, 'The unfiltered real DB must find a verified Chinese unique name')
db.controls.search:SetText(selectedUnique.title, true)
assert(db:DoesItemMatchFilters(selectedUnique) == chineseMatch, 'Chinese and English names retain identical native filters')
db.controls.search:SetText(E.uniqueTitle(selectedUnique), true)
db.controls.type.selIndex = 2
assert(not db:DoesItemMatchFilters(selectedUnique), 'A Chinese name must not bypass the Armour filter for a ring')
db.controls.type.selIndex = 1
db.controls.searchMode.selIndex = 3
assert(not db:DoesItemMatchFilters(selectedUnique), 'The Modifiers search mode must not silently search item names')
local selectedBlockItem, selectedBlockText
for _, value in pairs(main.uniqueDB.list) do
    local translated = E.effectBlockTexts(value)
    if translated[1] then selectedBlockItem, selectedBlockText = value, StripEscapes(translated[1]); break end
end
assert(selectedBlockItem and selectedBlockText, 'The real database needs one reachable, verified multi-line equipment block')
local blockRaw = selectedBlockItem:BuildRaw()
db.controls.search:SetText(selectedBlockText, true)
assert(db:DoesItemMatchFilters(selectedBlockItem), 'Native Modifiers search finds the complete current-variant Chinese block: '..selectedBlockItem.name..' / '..selectedBlockText)
local blockSearches=0
for _,item in pairs(main.uniqueDB.list) do
    for _,text in ipairs(E.effectBlockTexts(item)) do
        db.controls.search:SetText(StripEscapes(text),true)
        assert(db:DoesItemMatchFilters(item),'Literal full-block search, including native parenthesized ranges: '..item.name..' / '..text)
        blockSearches=blockSearches+1
    end
end
assert(blockSearches>0)
db.controls.search:SetText(selectedBlockText,true)
db.controls.searchMode.selIndex = 2
assert(not db:DoesItemMatchFilters(selectedBlockItem), 'Names-only search cannot gain a modifier-block alias')
assert(selectedBlockItem:BuildRaw() == blockRaw, 'Preparing block search aliases preserves the exact raw unique item')
db.controls.searchMode.selIndex = 2
local paste, key = Paste, IsKeyDown
Paste = function() return E.uniqueTitle(selectedUnique) end
IsKeyDown = function(k) return k == 'CTRL' end
db.controls.search:SetText('', true)
db.controls.search:OnKeyDown('v')
Paste, IsKeyDown = paste, key
assert(db.controls.search.buf == E.uniqueTitle(selectedUnique), 'Actual DB paste retains UTF-8')
local glyph = E.uniqueTitle(selectedUnique):match('[\194-\244][\128-\191]+')
db.controls.search:SetText(glyph .. glyph, true)
db.controls.search:OnKeyDown('BACK')
assert(db.controls.search.buf == glyph, 'Actual DB Backspace deletes a complete UTF-8 glyph')
local selector = new('DropDownControl', nil, { 0, 0, 200, 20 },
    { { name = 'Gold Ring', label = 'Gold Ring', base = normal.base } })
selector.searchTerm = baseZh
selector:UpdateSearch()
assert(selector:GetMatchCount() == 1, 'Real craft-base search finds the Chinese name')
selector.dropped = true
local sourceList, sourceValue = selector.list, selector.list[1]
selector:Draw({ x = 0, y = 0, width = 1920, height = 1080 })
assert(selector.list == sourceList and selector.list[1] == sourceValue and sourceValue.label == 'Gold Ring',
    'Drawing a translated craft selector preserves the exact original list and row')
local callbackValue
selector.selFunc = function(_, value) callbackValue = value end
selector.selIndex = 0
selector:SetSel(1)
assert(callbackValue == selector.list[1] and callbackValue.name == 'Gold Ring',
    'Selecting a translated result passes the canonical English row to the native callback')
selector.searchTerm = 'Gold Ring'
selector:UpdateSearch()
assert(selector:GetMatchCount() == 1, 'Original English base search continues to work')
local slot = new('ItemSlotControl', nil, 0, 0, tab, 'Ring 1')
local detachedTab = { items = { [-991] = normal } }
slot.itemsTab, slot.items, slot.list = detachedTab, { 0, -991 }, { 'None', '^7Gold Ring' }
slot.searchTerm = baseZh
slot:UpdateSearch()
assert(slot:GetMatchCount() == 1 and slot:DropIndexToListIndex(1) == 2,
    'A Chinese equipment-slot match retains its original item ID/index mapping')
assert(slot.items[2] == -991 and slot.list[2] == '^7Gold Ring')
P.toggle()
assert(E.name(normal) == normal.name)
tip:Clear(true)
tab:AddItemTooltip(tip, normal)
assert(textOf(tip):find('Gold Ring', 1, true) and not textOf(tip):find(baseZh, 1, true))
P.toggle()
assert(E.name(normal) == baseZh)
db.controls.search:SetText(query, true)
db.controls.searchMode.selIndex, db.listBuildFlag = mode, listFlag
for field, index in pairs(filtersBefore) do db.controls[field].selIndex = index end
assert(normal:BuildRaw() == normalRaw and rare:BuildRaw() == rareRaw and selectedUnique.raw == uniqueRaw,
    'Presentation/search must preserve complete item text')
assert(outputs() == numbersBefore, 'Item presentation/search must preserve all calculated numbers')
assert(build:SaveDB('test') == before, 'Item presentation/search must preserve the exported build')
print('PASS actual equipment names: rare custom title, base/unique tooltips, native DB filters and UTF-8, craft-base search/callback identity, F10, raw items/calculations/export unchanged')

-- Run after integration.lua in its isolated, actual PoB runtime.
local P = assert(PoB2Chinese)
local A, game = assert(P.tree), assert(P.game)
assert(P.enabled)
A.protectClasses(common.classes)
A.protectBuild(build)
build.viewMode = 'TREE'
runCallback('OnFrame')
local tab, viewer = build.treeTab, build.treeTab.viewer
local control = tab.controls.treeSearch
assert(control._pobCnTreeSearch, 'The actual tree search instance must be configured')
local function treeSnapshot()
    local rows = {}
    for id, node in pairs(build.spec.nodes) do
        rows[#rows + 1] = table.concat({ tostring(id), node.name or '', node.dn or '',
            table.concat(node.sd or {}, '\n'), tostring(node.alloc), tostring(node.allocMode) }, '\t')
    end
    table.sort(rows)
    return table.concat(rows, '\n')
end
local function outputs()
    local rows = {}
    for key, value in pairs(build.calcsTab.mainOutput) do
        if type(value) == 'number' then rows[#rows + 1] = key .. '=' .. tostring(value) end
    end
    table.sort(rows)
    return table.concat(rows, '\n')
end
local nameNode, entry, unknown, statNode, statEntry
for _, node in pairs(build.spec.nodes) do
    local e = A.entryForNode(node, build)
    if e and e.zh and node.type ~= 'ClassStart' and node.type ~= 'OnlyImage' and not node.unlockConstraint then
        nameNode, entry = node, e
    end
    if not (e and e.zh) and node.dn and P.translate(node.dn) ~= node.dn then unknown = node end
    if e and e.stats and e.stats[1] and not node.unlockConstraint and node.type == 'Normal' then
        for _, stat in ipairs(e.stats) do
            for _, line in ipairs(node.sd or {}) do
                local changedText, changedCount = line:gsub('%d+%.?%d*', '123', 1)
                if line == stat.en and game.translateAffix(line) == stat.zh and changedCount == 1
                    and game.translateAffix(changedText) and game.translateAffix(changedText) ~= stat.zh then
                    statNode, statEntry = node, stat
                end
            end
        end
    end
end
assert(nameNode and entry, 'At least one verified current-tree name must be testable')
if not unknown then
    -- Complete coverage can remove the naturally occurring overlap. Reproduce
    -- a jewel-replaced title on a detached node without changing the real tree.
    unknown = setmetatable({}, getmetatable(nameNode))
    for key, value in pairs(nameNode) do unknown[key] = value end
    unknown.dn = 'Fireball'
    assert(not A.entryForNode(unknown, build))
end
assert(P.translate(unknown.dn) ~= unknown.dn, 'Exercise an unverified title that overlaps another display dictionary')
assert(statNode and statEntry, 'At least one official node modifier must be testable')
local dataBefore, numbersBefore = treeSnapshot(), outputs()
local queryBefore, paramsBefore = viewer.searchStr, viewer.searchParams
local savedBefore, flagBefore = viewer.searchStrSaved, tab.searchFlag
local before = assert(build:SaveDB('test'))
local tip = new('Tooltip')
local function textOf(tooltip)
    local lines = {}
    for _, line in ipairs(tooltip.lines) do
        if line.text then lines[#lines + 1] = StripEscapes(line.text) end
    end
    return table.concat(lines, '\n')
end
local function showName(node)
    if tip:CheckForUpdate(node) then viewer:AddNodeName(tip, node, build) end
    return textOf(tip)
end
assert(showName(nameNode):find(entry.zh, 1, true), 'Real node title uses the verified source name')
P.toggle()
assert(showName(nameNode):find(nameNode.dn, 1, true), 'F10 invalidates the cached title')
assert(not showName(nameNode):find(entry.zh, 1, true))
P.toggle()
assert(showName(nameNode):find(entry.zh, 1, true))

tip:Clear(true)
viewer:AddNodeName(tip, unknown, build)
assert(StripEscapes(tip.lines[1].text) == unknown.dn, 'Unverified titles bypass the legacy UI dictionary')
local oldDraw, sawLiteral = DrawString, false
DrawString = function(x, y, align, height, font, text)
    if text == tip.lines[1].text then
        sawLiteral = true
        assert(P.translate(text) == text, 'Cached title remains literal when drawn later')
    end
    return oldDraw(x, y, align, height, font, text)
end
tip:Draw(20, 20, 20, 20, { x = 0, y = 0, width = 1920, height = 1080 })
DrawString = oldDraw
assert(sawLiteral)

local debugBefore, flavourBefore = launch.devModeAlt, main.showFlavourText
launch.devModeAlt, main.showFlavourText = true, false
tip:Clear(true)
viewer:AddNodeName(tip, nameNode, build)
assert(textOf(tip):find(entry.zh .. ' [' .. nameNode.id .. ']', 1, true), 'Debug node ID remains attached to Chinese title')
launch.devModeAlt, main.showFlavourText = debugBefore, flavourBefore
local renamed = setmetatable({}, getmetatable(nameNode)); for key, value in pairs(nameNode) do renamed[key] = value end
renamed.dn = nameNode.dn .. ' changed by a jewel'
assert(not A.entryForNode(renamed, build), 'Jewel-overwritten display names cannot reuse the old title')
assert(not A.entryForNode(nameNode, { spec = { treeVersion = 'unverified-version' } }), 'Reject an unverified tree version')

-- Exercise colour-state preservation and cleanup when an upstream method
-- throws, without replacing or mutating any real passive-tree data.
local probeClass = {
    AddNodeName = function(self, tooltip, node)
        tooltip:AddLine(24, '^7' .. node.dn .. '^1')
        if self.fail then error('intentional name probe') end
    end,
    AddNodeTooltip = function() error('intentional tooltip probe') end,
    DoesNodeMatchSearchParams = function() error('intentional search probe') end,
    Draw = function() end,
}
A.protectClasses({ PassiveTreeView = probeClass })
local probe = setmetatable({}, { __index = probeClass })
local probeTip = new('Tooltip')
probe:AddNodeName(probeTip, nameNode, build)
assert(probeTip.lines[1].text:sub(1, 2) == '^7' and probeTip.lines[1].text:sub(-2) == '^1', 'Keep initial/final colour escapes')
local ownAddLine = rawget(probeTip, 'AddLine')
probe.fail = true
assert(not pcall(probe.AddNodeName, probe, probeTip, nameNode, build))
assert(rawget(probeTip, 'AddLine') == ownAddLine, 'Restore AddLine after a title error')
assert(not pcall(probe.AddNodeTooltip, probe, probeTip, nameNode, build))
assert(rawget(probeTip, 'AddLine') == ownAddLine, 'Restore AddLine after a tooltip error')
local originalParams = { entry.zh, 'unmatched' }
probe.searchParams = originalParams
assert(not pcall(probe.DoesNodeMatchSearchParams, probe, build, nameNode))
assert(probe.searchParams == originalParams, 'Restore search parameters after an upstream error')

local differences = viewer.showStatDifferences
viewer.showStatDifferences = false
tip:Clear(true)
viewer:AddNodeTooltip(tip, statNode, build, 0)
assert(textOf(tip):find(statEntry.zh, 1, true), 'Real tooltip renders its current official modifier')
-- A display-only numeric change must not be replaced by the old stat string.
local changed = setmetatable({}, getmetatable(statNode)); for key, value in pairs(statNode) do changed[key] = value end
changed.sd = {}; for index, line in ipairs(statNode.sd) do changed.sd[index] = line end
local replaced, expected
for index, line in ipairs(changed.sd) do
    if line == statEntry.en then
        local newLine, count = line:gsub('%d+%.?%d*', '123', 1)
        local translation = game.translateAffix(newLine)
        if count == 1 and translation and translation ~= statEntry.zh then
            changed.sd[index], replaced, expected = newLine, true, translation
        end
    end
end
assert(replaced, 'The numeric replacement test must run')
tip:Clear(true)
viewer:AddNodeTooltip(tip, changed, build, 0)
assert(textOf(tip):find(expected, 1, true), 'Changed numeric text is translated at its current value')
viewer.showStatDifferences = differences

control:SetText('', true)
control:Insert(entry.zh)
assert(control.buf == entry.zh and viewer.searchStr == entry.zh, 'Native search callback retains UTF-8 text')
runCallback('OnFrame')
assert(viewer.searchStrResults[nameNode.id], 'Chinese search drives the real native node highlight')
viewer.searchParams = { entry.zh, nameNode.type:lower() }
assert(viewer:DoesNodeMatchSearchParams(build, nameNode), 'Mixed Chinese/English terms retain AND semantics')
viewer.searchParams = { entry.zh, 'no-such-node-type-xyz' }
assert(not viewer:DoesNodeMatchSearchParams(build, nameNode), 'One Chinese hit must not bypass other terms')
viewer.searchParams = { '(' .. entry.zh .. '|no-such-name)' }
assert(viewer:DoesNodeMatchSearchParams(build, nameNode), 'Native OR syntax works with Chinese names')
viewer.searchParams = { '[' }
assert(not viewer:DoesNodeMatchSearchParams(build, nameNode), 'Malformed original patterns fail without an exception')
viewer.searchParams = { 'oil:', entry.zh }
assert(not viewer:DoesNodeMatchSearchParams(build, nameNode), 'Chinese name does not bypass the oil-only search mode')
viewer.searchParams = { statEntry.zh }
assert(viewer:DoesNodeMatchSearchParams(build, statNode), 'Official current stat text is searchable')
control:SetText(statEntry.zh, true)
runCallback('OnFrame')
assert(viewer.searchStrResults[statNode.id], 'Pasted full Chinese modifier preserves numeric/percent terms in the real search parser')
viewer.searchParams = { entry.zh }
local hidden = setmetatable({}, getmetatable(nameNode)); for key, value in pairs(nameNode) do hidden[key] = value end
hidden.type = 'ClassStart'
assert(not viewer:DoesNodeMatchSearchParams(build, hidden), 'Class starts remain excluded')
hidden.type = 'OnlyImage'
assert(not viewer:DoesNodeMatchSearchParams(build, hidden), 'Image-only nodes remain excluded')

local oldPaste, oldDown = Paste, IsKeyDown
control:SetText('', true)
Paste = function() return entry.zh end
IsKeyDown = function(key) return key == 'CTRL' end
control:OnKeyDown('v')
Paste, IsKeyDown = oldPaste, oldDown
assert(control.buf == entry.zh, 'Paste preserves Chinese rather than substituting question marks')
local glyph = assert(entry.zh:match('[\194-\244][\128-\191]+'))
control:SetText(glyph .. glyph, true)
control:OnKeyDown('BACK')
assert(control.buf == glyph, 'Backspace deletes one whole UTF-8 glyph')
control.caret = 1
control:OnKeyDown('DELETE')
assert(control.buf == '', 'Delete deletes one whole UTF-8 glyph')
control:SetText(entry.zh, true)
runCallback('OnFrame')
assert(viewer.searchStrResults[nameNode.id])
P.toggle(); runCallback('OnFrame')
assert(not viewer.searchStrResults[nameNode.id], 'F10 clears stale Chinese highlight matches')
P.toggle(); runCallback('OnFrame')
assert(viewer.searchStrResults[nameNode.id], 'F10 recomputes Chinese matches without editing the query')
control:SetText(nameNode.dn, true)
runCallback('OnFrame')
assert(viewer.searchStrResults[nameNode.id], 'Original English search still highlights the same node')
-- Probe complete source blocks independently of database coverage. English and
-- Chinese intentionally use different line counts/order: only the whole block
-- is verified, and no individual line pairing may be inferred from its index.
local sourceDir = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
local currentVersion = build.spec.treeVersion
local blockEntry = {
    en = 'Complete block fixture', zh = '完整效果', versions = { currentVersion },
    stats = {}, statBlocks = {{
        en = { 'Fixture grants 12% damage\nWhile active,', 'Fixture also grants 7 life' },
        zh = { '获得 7 生命', '生效时伤害提高 12%' }, versions = { currentVersion },
    }},
}
local blockNode = { id = -9182, dn = blockEntry.en, type = 'Keystone',
    sd = { 'Fixture grants 12% damage', 'While active,', 'Fixture also grants 7 life' }, finalModList = {} }
local fixtureGame = { treeById = { [tostring(blockNode.id)] = blockEntry } }
local fixtureAdapter = assert(loadfile(sourceDir .. '/payload/tree_cn.lua'))(P, fixtureGame)
local fixtureClass = {
    AddNodeName = function(self, tooltip, node) tooltip:AddLine(24, node.dn, 'FONTIN') end,
    AddNodeTooltip = function(self, tooltip, node)
        self:AddNodeName(tooltip, node, build)
        tooltip.center = false
        tooltip:AddLine(16, '')
        for i, line in ipairs(self.displayLines or node.sd) do
            tooltip:AddLine(16, '^7' .. line .. (i == 2 and main.notSupportedTooltipText or ''), 'FONTIN SC')
            if self.separatorAfter == i then tooltip:AddSeparator(14) end
            if self.failAfter == i then error('intentional partial block failure') end
        end
        tooltip:AddSeparator(14)
    end,
    DoesNodeMatchSearchParams = function(self, _, node)
        if node.type == 'ClassStart' or node.type == 'OnlyImage' then return false end
        return #self.searchParams == 0
    end,
    Draw = function() end,
}
fixtureAdapter.protectClasses({ PassiveTreeView = fixtureClass })
local fixtureViewer = setmetatable({}, { __index = fixtureClass })
local fixtureTip = new('Tooltip')
local function showFixture(node, incEffect)
    fixtureTip:Clear(true)
    fixtureViewer:AddNodeTooltip(fixtureTip, node or blockNode, build, incEffect or 0)
    return textOf(fixtureTip)
end
local blockZh = table.concat(blockEntry.statBlocks[1].zh, '\n')
local blockText = showFixture()
assert(blockText:find(blockZh, 1, true), 'Render the complete Chinese block with its original line order')
assert(not blockText:find('Fixture grants', 1, true), 'Do not repeat the English block')
local _, warnings = blockText:gsub('%(Not supported in PoB yet%)', '')
assert(warnings == 1, 'Preserve the native unsupported warning once without guessing Chinese line correspondence')
fixtureViewer.searchParams = { blockEntry.statBlocks[1].zh[1], blockEntry.statBlocks[1].zh[2] }
assert(fixtureViewer:DoesNodeMatchSearchParams(build, blockNode), 'All parts of the verified Chinese block are searchable')
local changedBlockNode = {}; for key, value in pairs(blockNode) do changedBlockNode[key] = value end
changedBlockNode.sd = { 'Fixture grants 13% damage', 'While active,', 'Fixture also grants 7 life' }
assert(not fixtureAdapter.statBlockForNode(changedBlockNode, blockEntry, build), 'Changed current values invalidate the complete block')
assert(not showFixture(changedBlockNode):find(blockZh, 1, true))
fixtureViewer.searchParams = { blockEntry.statBlocks[1].zh[1] }
assert(not fixtureViewer:DoesNodeMatchSearchParams(build, changedBlockNode), 'Changed blocks cannot match stale Chinese effects')
assert(not fixtureAdapter.statBlockForNode(blockNode, blockEntry, { spec = { treeVersion = 'unverified-version' } }))
fixtureViewer.displayLines = changedBlockNode.sd
local changedDisplay = showFixture()
assert(changedDisplay:find('13%% damage') and not changedDisplay:find(blockZh, 1, true), 'A display-time change cannot receive stale block numbers')
fixtureViewer.displayLines = { blockNode.sd[1] }
assert(not showFixture():find(blockZh, 1, true), 'An incomplete block remains untranslated')
fixtureViewer.displayLines = nil
fixtureViewer.separatorAfter = 1
assert(not showFixture():find(blockZh, 1, true), 'A separator prevents combining unrelated display sections')
fixtureViewer.separatorAfter = nil
fixtureViewer.failAfter = 1
local addBefore, separatorBefore = rawget(fixtureTip, 'AddLine'), rawget(fixtureTip, 'AddSeparator')
assert(not pcall(showFixture))
assert(rawget(fixtureTip, 'AddLine') == addBefore and rawget(fixtureTip, 'AddSeparator') == separatorBefore,
    'Restore both tooltip methods after an error in a partial block')
assert(textOf(fixtureTip):find(blockNode.sd[1], 1, true), 'Flush original partial text when the upstream builder errors')
fixtureViewer.failAfter = nil
changedBlockNode.sd, changedBlockNode.type = blockNode.sd, 'Normal'
assert(not showFixture(changedBlockNode, 20):find(blockZh, 1, true), 'Potential small-passive scaling must not use a fixed block')
changedBlockNode.finalModList = {{ name = 'JewelSmallPassiveSkillEffect', value = 10 }}
assert(not showFixture(changedBlockNode):find(blockZh, 1, true), 'Potential jewel scaling must not use a fixed block')
changedBlockNode.finalModList = {{ name = 'Life', parsedLine = 'Fixture adds 99 life' }}
assert(not showFixture(changedBlockNode):find(blockZh, 1, true), 'Potential added jewel stats cannot use an incomplete old block')
P.toggle()
assert(showFixture():find(blockNode.sd[1], 1, true), 'English mode retains all original block text')
P.toggle()
assert(showFixture():find(blockZh, 1, true))

-- A single-line mapping must retain the exact native warning as well.
blockEntry.statBlocks = {}
blockEntry.stats = {{ en = blockNode.sd[2], zh = '生效时', versions = { currentVersion } }}
local singleText = showFixture()
assert(singleText:find('生效时', 1, true) and singleText:find('(Not supported in PoB yet)', 1, true))
blockEntry.stats[1].versions = { 'unverified-version' }
assert(showFixture():find('While active,', 1, true), 'A stat cannot borrow text from a different tree version')

-- Attribute/class replacement nodes retain their base ID. Their display name
-- plus complete current English effects must select one verified option.
local variant = { en = 'Life Regeneration fixture', zh = '生命再生',
    versions = { currentVersion }, currentStats = { 'Fixture regenerates 0.2% life' }, stats = {} }
blockEntry.variants = { variant }
local variantNode = { id = blockNode.id, dn = variant.en, sd = { variant.currentStats[1] }, type = 'Normal' }
assert(fixtureAdapter.entryForNode(variantNode, build) == variant, 'Base ID resolves a verified current option')
variantNode.sd = { 'Fixture regenerates 0.3% life' }
assert(not fixtureAdapter.entryForNode(variantNode, build), 'Changed option values cannot borrow a title from another option')
blockEntry.en = variant.en
assert(not fixtureAdapter.entryForNode(variantNode, build), 'An unmatched variant does not fall back to a same-name base entry')
variantNode.sd = { variant.currentStats[1] }
blockEntry.variants[2] = variant
assert(not fixtureAdapter.entryForNode(variantNode, build), 'Ambiguous options cannot select arbitrary translated content')
blockEntry.variants[2] = nil
assert(not fixtureAdapter.entryForNode(variantNode, { spec = { treeVersion = 'unverified-version' } }))

-- Also exercise one new full block using the actual loaded tree and viewer.
for _, node in pairs(build.spec.nodes) do
    local e = A.entryForNode(node, build)
    local block = A.statBlockForNode(node, e, build)
    if block and node.type == 'Keystone' and not node.unlockConstraint then
        local savedDifference = viewer.showStatDifferences
        viewer.showStatDifferences = false
        tip:Clear(true)
        viewer:AddNodeTooltip(tip, node, build, 0)
        local compactActual, compactExpected = textOf(tip):gsub('%s', ''), block.zh:gsub('%s', '')
        assert(compactActual:find(compactExpected, 1, true), 'An actual keystone renders its verified full source block')
        viewer.searchParams = { block.zh }
        assert(viewer:DoesNodeMatchSearchParams(build, node), 'An actual keystone is searchable by its complete Chinese effect')
        viewer.showStatDifferences = savedDifference
        break
    end
end
print('PASS tree blocks/options: complete multiline mapping; current-value and version guards; warning retention; partial/error cleanup; dynamic-effect fallback; unique option matching')
assert(treeSnapshot() == dataBefore, 'Names, stats, IDs and allocations must remain unchanged')
assert(outputs() == numbersBefore, 'Node rendering/search/language must not change calculations')
control:SetText(queryBefore, true)
viewer.searchParams, viewer.searchStrSaved, tab.searchFlag = paramsBefore, savedBefore, flagBefore
assert(build:SaveDB('test') == before, 'Restoring the user query leaves the complete English export unchanged')
print('PASS real tree: verified titles/current modifiers; literal fallback; version/name guards; Chinese/English search and native highlights; UTF-8 paste/delete; F10; unchanged data, allocations, calculations and export')

-- Run after integration.lua in the same real PoB Lua state.
local root = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
local P = assert(PoB2Chinese)
local game = assert(P.game, 'The root plugin must expose P.game')
local A = P.skills or assert(loadfile(root .. '/payload/skills_cn.lua'))(P, game)
A.protectClasses(common.classes)
A.protectBuild(build)
assert(P.enabled, 'Run this test with Chinese enabled')

local function dataNames()
    local rows = {}
    for id, gem in pairs(build.data.gems) do
        rows[#rows + 1] = id .. '\t' .. gem.name .. '\t' .. (gem.grantedEffect and gem.grantedEffect.name or '')
    end
    table.sort(rows)
    return table.concat(rows, '\n')
end
local dataBefore = dataNames()
loadBuildFromXML([[<PathOfBuilding2>
<Build targetVersion="0_1" level="65" className="Sorceress" ascendClassName="None" mainSocketGroup="1" viewMode="SKILLS"/>
<Skills activeSkillSet="1"><SkillSet id="1"><Skill enabled="true" label="" mainActiveSkill="1">
<Gem nameSpec="Fireball" level="10" quality="0" enabled="true"/>
</Skill></SkillSet></Skills>
</PathOfBuilding2>]], 'CN skill adapter test')
runCallback('OnFrame')
local skills = build.skillsTab
local group = assert(skills.socketGroupList[1])
local gem = assert(group.gemList[1].gemData)
local zh = assert(A.nameForGem(gem), 'Fireball must have a verified official Chinese entry')
local selector = skills.gemSlots[1].nameSpec
assert(selector._className == 'GemSelectControl' and selector.inactiveText, 'Real constructor configured')
local view = { x = 0, y = 0, width = 1920, height = 1080 }
selector.hasFocus = false
selector:Draw(view, true)
assert(selector.buf == 'Fireball' and selector.inactiveText(selector.buf) == zh)
local offset = selector.controls.scrollBarH.offset
selector.controls.scrollBarH.offset = 17
selector:Draw(view, true)
assert(selector.controls.scrollBarH.offset == 17, 'Display restores the edit scroll offset')
selector.controls.scrollBarH.offset = offset

local exportBefore = assert(build:SaveDB('code'))
assert(A.groupDisplayLabel(group) == zh, 'Automatic group label uses verified name')
assert(group.displayLabel == 'Fireball' and group.label == '', 'Original group label untouched')
selector:OnFocusGained()
selector.hasFocus = true
selector:SetText('')
local filter = selector.filterPattern
selector:Insert(zh)
assert(selector.buf == zh and selector.filterPattern == filter, 'UTF-8 input retained; original filter restored')
assert(not selector.noMatches and #selector.list >= 1)
local fireballId = 'Default:' .. gem.id
local found
for _, id in ipairs(selector.list) do if id == fireballId then found = true end end
assert(found, 'Chinese exact search contains Fireball ID')
assert(build:SaveDB('code') == exportBefore, 'A Chinese search must not edit the equipped gem/export')
local oldPaste, oldDown = Paste, IsKeyDown
selector:SetText('')
Paste = function() return zh end
IsKeyDown = function(key) return key == 'CTRL' end
selector:OnKeyDown('v')
Paste, IsKeyDown = oldPaste, oldDown
assert(selector.buf == zh, 'Cmd/Ctrl+V retains Chinese instead of the upstream question-mark substitution')
local firstChar = zh:match('^[\194-\244][\128-\191]+')
selector:SetText(firstChar .. firstChar)
selector:OnKeyDown('BACK')
assert(selector.buf == firstChar, 'Backspace removes one UTF-8 character')
selector.caret = 1
selector:OnKeyDown('DELETE')
assert(selector.buf == '', 'Delete removes one UTF-8 character')
assert(group.gemList[1] and group.gemList[1].nameSpec == 'Fireball', 'Clearing a Chinese query must not delete the current gem')
selector:SetText(zh)
selector:BuildList(zh .. ':active')
found = false
for _, id in ipairs(selector.list) do
    if id == fireballId then found = true end
    assert(selector.gems[id] and not selector.gems[id].grantedEffect.support, 'Original active-tag filter retained')
end
assert(found)
selector:BuildList(zh .. ':support')
for _, id in ipairs(selector.list) do assert(id ~= fireballId, 'Support filter excludes an active Fireball') end
selector:BuildList(firstChar)
found = false
for _, id in ipairs(selector.list) do if id == fireballId then found = true end end
assert(found, 'Partial Chinese search works')

selector:BuildList(zh)
selector:SetText(zh)
selector:OnFocusLost()
assert(selector.buf == 'Fireball' and group.gemList[1].nameSpec == 'Fireball', 'Exact Chinese commit canonicalizes to English')
assert(group.gemList[1].gemData.id == gem.id)
selector.hasFocus = false
assert(selector.inactiveText(selector.buf) == zh)
runCallback('OnFrame')
local committedExport = assert(build:SaveDB('code'))
assert(committedExport:find('nameSpec="Fireball"', 1, true) and not committedExport:find(zh, 1, true))

selector:OnFocusGained()
selector:SetText('完全不存在的技能名称')
selector:BuildList(selector.buf)
assert(selector.noMatches)
selector:OnFocusLost()
assert(selector.buf == 'Fireball' and group.gemList[1].nameSpec == 'Fireball', 'No-match query must not delete current gem')

-- Verify duplicate-name safety with isolated selector entries. The game source
-- and dictionaries are never edited to manufacture the duplicate fixture.
local savedGems, savedList = selector.gems, selector.list
selector.gems = { [fireballId] = gem, ['Duplicate:' .. gem.id] = gem }
selector.list = { fireballId, 'Duplicate:' .. gem.id }
selector.sortCache.dps['Duplicate:' .. gem.id] = selector.sortCache.dps[fireballId]
selector.sortCache.canSupport['Duplicate:' .. gem.id] = selector.sortCache.canSupport[fireballId]
selector.initialBuf = 'Fireball'
selector.selIndex, selector.dropped = 0, true
selector:SetText(zh)
selector:OnKeyDown('RETURN')
assert(selector.buf == zh and selector.dropped, 'Ambiguous name requires a deliberate row selection')
selector:OnFocusLost()
assert(selector.buf == 'Fireball' and group.gemList[1].nameSpec == 'Fireball')
selector.gems, selector.list = savedGems, savedList
selector.sortCache.dps['Duplicate:' .. gem.id] = nil
selector.sortCache.canSupport['Duplicate:' .. gem.id] = nil

-- The user's label is literal even when it equals a translated gem name.
group.label, group.displayLabel = 'Fireball', 'Fireball'
assert(A.groupDisplayLabel(group) == 'Fireball')
build:RefreshSkillSelectControls(build.controls, 1, '')
local drop = build.controls.mainSocketGroup
assert(A.dropdownLiteralScope(drop).Fireball, 'Main-skill dropdown marks a user label literal')
assert(drop.list[1].label == 'Fireball')
local originalDraw, literalSeen = DrawString, false
DrawString = function(x, y, align, size, font, text)
    if text == 'Fireball' then literalSeen = P.translate(text) == text end
    return originalDraw(x, y, align, size, font, text)
end
drop:Draw(view, true)
DrawString = originalDraw
assert(literalSeen, 'Root literal scope protects custom skill-group text from the name dictionary')
assert(drop.list[1].label == 'Fireball', 'Display leaves source dropdown rows intact')
group.label = ''
build:RefreshSkillSelectControls(build.controls, 1, '')
assert(not A.dropdownLiteralScope(drop).Fireball)

-- F10 must cancel, rather than commit or delete, a query still being edited.
for _, query in ipairs({ firstChar, zh, '完全不存在的技能名称' }) do
    selector:SetText('Fireball')
    selector:OnFocusGained()
    selector.hasFocus = true
    local originalId, originalIndex = selector.gemId, selector.selIndex
    local originalList = table.concat(selector.list, '\n')
    local originalExport = assert(build:SaveDB('code'))
    selector:SetText(query)
    selector:BuildList(query)
    selector:UpdateGem()
    assert(selector.dropped and selector.buf == query)
    P.toggle()
    assert(not P.enabled and selector.buf == 'Fireball' and not selector.dropped, 'F10 cancels the pending Chinese query')
    assert(selector.gemId == originalId and selector.selIndex == originalIndex, 'F10 restores the previous gem selection')
    assert(table.concat(selector.list, '\n') == originalList, 'F10 restores the previous candidate list')
    selector:OnFocusLost()
    assert(group.gemList[1] and group.gemList[1].nameSpec == 'Fireball', 'F10 followed by focus loss cannot delete or replace the gem')
    assert(build:SaveDB('code') == originalExport, 'F10 during a query leaves the exported build unchanged')
    P.toggle()
    assert(P.enabled)
end

P.toggle()
assert(not P.enabled)
selector:SetText('Fireball')
selector.hasFocus = false
assert(selector.inactiveText(selector.buf) == 'Fireball', 'F10 restores English selected name')
assert(A.groupDisplayLabel(group) == 'Fireball')
selector:BuildList(zh)
assert(selector.noMatches, 'Disabled plugin retains upstream English search')
P.toggle()
assert(P.enabled and selector.inactiveText(selector.buf) == zh)
assert(dataNames() == dataBefore, 'No English gem names or granted-effect names changed')
assert(group.gemList[1].nameSpec == 'Fireball')
print('PASS real GemSelectControl: inactive Chinese names, literal English editing/export, UTF-8 input, exact/partial/tag searches, canonical commit, duplicate/no-match safety, custom labels, F10')

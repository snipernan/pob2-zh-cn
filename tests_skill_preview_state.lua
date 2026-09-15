-- Exercise the actual native candidate-preview function with a deterministic
-- calculator. No live build gem or source database record is edited.
local P = assert(PoB2Chinese)
local preview = assert(common.classes.GemSelectControl.CalcOutputWithThisGem)
local exportBefore = assert(build:SaveDB('preview-state'))
local originalData, candidateData = { name = 'Original fixture' }, { name = 'Preview fixture', naturalMaxLevel = 20 }
local active = { nameSpec = 'Fireball', level = 10, gemData = originalData, skillPart = 2, skillStageCount = 3 }
local support = { nameSpec = 'Support fixture', level = 5, gemData = originalData,
    skillMinion = 'UserSelectedMinion', skillMinionCalcs = 'UserCalcsMinion', skillMineCount = 4,
    displayEffect = { original = true }, retainedCache = { original = true } }
local originalDisplay = support.displayEffect
local group = { gemList = { active, support }, displayGemList = { active, support } }
local originalDisplayList = group.displayGemList
local skills = { displayGroup = group, socketGroupList = { group },
    ProcessGemLevel = function() return 20 end }
local selector = { skillsTab = skills, index = 2 }
local function mutate()
    -- A support candidate changes the active gem's summon and part selection;
    -- CalcActiveSkill really writes these persisted fields during DPS previews.
    active.skillMinion, active.skillPart, active.skillStageCount = 'LivingLightning', nil, nil
    support.skillMinion, support.skillMinionCalcs = nil, nil
    support.skillMinionItemSet, support.skillMinionSkillCalcs = 9, 12
    support.skillMineCount = nil
    support.retainedCache.generated = true
    support.newCalculationCache = 'keep this cache'
    group.displayGemList = { 'temporary display group' }
end
local function assertRestored()
    assert(active.skillMinion == nil and active.skillPart == 2 and active.skillStageCount == 3,
        'A support preview must restore persisted choices on the active gem in another slot')
    assert(support.skillMinion == 'UserSelectedMinion' and support.skillMinionCalcs == 'UserCalcsMinion')
    assert(support.skillMinionItemSet == nil and support.skillMinionSkillCalcs == nil and support.skillMineCount == 4)
    assert(support.gemData == originalData and support.level == 5 and support.displayEffect == originalDisplay)
    assert(group.gemList[2] == support and group.displayGemList == originalDisplayList)
    assert(support.retainedCache.generated and support.newCalculationCache == 'keep this cache',
        'State protection must not discard legitimate calculation caches')
end
local output = { CombinedDPS = 12345 }
local result = preview(selector, function()
    assert(support.gemData == candidateData and support.level == 20, 'The actual preview receives candidate data')
    mutate()
    return output
end, candidateData, false, {})
assert(result == output, 'Preserve the calculated preview result')
assertRestored()
assert(not pcall(preview, selector, function() mutate(); error('intentional preview failure') end, candidateData, false, {}))
assertRestored()
selector.index = 3
assert(not pcall(preview, selector, function()
    assert(group.gemList[3], 'Native preview creates a temporary gem for an empty slot')
    mutate()
    error('intentional empty-slot preview failure')
end, candidateData, false, {}))
assert(group.gemList[3] == nil, 'An exception must remove the temporary preview gem')
assertRestored()
assert(build:SaveDB('preview-state') == exportBefore, 'Preview regression probes must not change the actual exported build')
print('PASS native skill preview state: active/support persisted choices, existing and empty slots, success/errors, preview output preserved, unrelated caches retained')

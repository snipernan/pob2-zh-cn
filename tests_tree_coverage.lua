-- Run after integration_game.lua in the actual isolated PoB runtime.
-- This report deliberately does not assert complete coverage: missing source
-- text and intentional version/value guards are distinguished from adapter gaps.
local root = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
local P = assert(PoB2Chinese)
local A, game = assert(P.tree), assert(P.game)
local json = require('dkjson')
local report = {
    schema = 1,
    buildTreeVersion = build.spec.treeVersion,
    summaries = {},
    gaps = {},
}
local function lines(source)
    local result = {}
    for _, text in ipairs(source or {}) do
        if text:find('\n', 1, true) then
            for line in text:gmatch('[^\n]+') do result[#result + 1] = line end
        else result[#result + 1] = text end
    end
    return result
end
local function equal(left, right)
    if #left ~= #right then return false end
    for i, text in ipairs(left) do if text ~= right[i] then return false end end
    return true
end
local function allowed(entry, version)
    if entry.version and entry.version ~= version then return false end
    if not entry.versions then return true end
    if entry.versions[version] then return true end
    for _, value in ipairs(entry.versions) do if value == version then return true end end
    return false
end
local function sourceFor(node)
    return game.treeById[tostring(node.id)] or game.treeById[node.id]
end
local function sortedKeys(tableValue)
    local keys = {}
    for key in pairs(tableValue or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end
local function sourceCandidates(node, version)
    local source, candidates, nameVariants, validVariants = sourceFor(node), {}, {}, {}
    if source then
        if source.en == node.dn then candidates[#candidates + 1] = source end
        for _, variant in ipairs(source.variants or {}) do
            if variant.en == node.dn then
                candidates[#candidates + 1] = variant
                nameVariants[#nameVariants + 1] = variant
                if allowed(variant, version) and variant.currentStats
                    and equal(lines(variant.currentStats), node.sd or {}) then
                    validVariants[#validVariants + 1] = variant
                end
            end
        end
    end
    return source, candidates, nameVariants, validVariants
end
local function snapshotTree(tree, scope)
    local rows = {}
    for _, key in ipairs(sortedKeys(tree.nodes)) do
        local node = tree.nodes[key]
        rows[#rows + 1] = table.concat({ scope, tostring(key), node.name or '', node.dn or '',
            table.concat(node.sd or {}, '\n'), tostring(node.alloc), tostring(node.allocMode) }, '\t')
        for _, optionKey in ipairs(sortedKeys(node.options)) do
            local option = node.options[optionKey]
            rows[#rows + 1] = table.concat({ scope, tostring(key), tostring(optionKey), option.name or '',
                option.dn or '', table.concat(option.sd or {}, '\n') }, '\t')
        end
    end
    return table.concat(rows, '\n')
end
local function snapshot()
    local rows = { snapshotTree(build.spec, 'build') }
    for _, version in ipairs(sortedKeys(main.tree)) do
        rows[#rows + 1] = snapshotTree(main.tree[version], version)
    end
    for _, key in ipairs(sortedKeys(build.calcsTab.mainOutput)) do
        local value = build.calcsTab.mainOutput[key]
        if type(value) == 'number' then rows[#rows + 1] = key .. '=' .. tostring(value) end
    end
    return table.concat(rows, '\n')
end
local before, exportBefore = snapshot(), assert(build:SaveDB('test'))
local function inspect(node, context, summary, optionKey)
    if node.type == 'ClassStart' or node.type == 'OnlyImage' then
        summary.excluded = summary.excluded + 1
        return
    end
    summary.checked = summary.checked + 1
    local version = context.spec.treeVersion
    local actual = A.entryForNode(node, context)
    local block = A.statBlockForNode(node, actual, context)
    local source, candidates, namedVariants, validVariants = sourceCandidates(node, version)
    local reason, sourceNameAvailable
    for _, candidate in ipairs(candidates) do
        if allowed(candidate, version) and candidate.zh then sourceNameAvailable = true end
    end
    if actual and actual.zh then
        summary.titles = summary.titles + 1
    else
        summary.unknownTitles = summary.unknownTitles + 1
        if not source then reason = 'missing-node-source'
        elseif #candidates == 0 then reason = 'english-name-not-in-source'
        elseif #namedVariants > 0 and #validVariants == 0 then reason = 'variant-current-stats-or-version-mismatch'
        elseif #validVariants > 1 then reason = 'ambiguous-current-variant'
        elseif not sourceNameAvailable then reason = 'missing-title-or-unverified-version'
        else reason = 'title-data-present-but-unreachable' end
    end
    local unhandled, coveredLines, exactBlockAvailable = {}, 0, false
    for _, candidate in ipairs(candidates) do
        if allowed(candidate, version) then
            for _, possible in ipairs(candidate.statBlocks or {}) do
                if allowed(possible, version) and equal(lines(possible.en), node.sd or {}) then
                    exactBlockAvailable = true
                end
            end
        end
    end
    if block then
        summary.blocks = summary.blocks + 1
        coveredLines = #(node.sd or {})
    else
        for _, line in ipairs(node.sd or {}) do
            local translated
            for _, stat in ipairs(actual and actual.stats or {}) do
                if stat.en == line and allowed(stat, version) then translated = stat.zh; break end
            end
            translated = translated or (game.translateAffix and game.translateAffix(line))
            if translated then coveredLines = coveredLines + 1
            elseif line ~= '' then unhandled[#unhandled + 1] = line end
        end
    end
    summary.statLines = summary.statLines + #(node.sd or {})
    summary.translatedStatLines = summary.translatedStatLines + coveredLines
    if #unhandled == 0 then summary.completeEffects = summary.completeEffects + 1
    else summary.incompleteEffects = summary.incompleteEffects + 1 end
    if exactBlockAvailable and not block then summary.unreachableBlocks = summary.unreachableBlocks + 1 end
    if reason or #unhandled > 0 or (exactBlockAvailable and not block) then
        local candidateDetails = {}
        for _, candidate in ipairs(candidates) do
            candidateDetails[#candidateDetails + 1] = {
                en = candidate.en, zh = candidate.zh, versions = candidate.versions,
                currentStats = candidate.currentStats,
                blockEnglish = (function()
                    local result = {}
                    for _, candidateBlock in ipairs(candidate.statBlocks or {}) do
                        result[#result + 1] = { en = candidateBlock.en, versions = candidateBlock.versions }
                    end
                    return result
                end)(),
            }
        end
        report.gaps[#report.gaps + 1] = {
            scope = summary.scope, treeVersion = version,
            id = node.id, optionKey = optionKey and tostring(optionKey) or nil,
            type = node.type, english = node.dn, currentStats = lines(node.sd),
            titleIssue = reason, titleSourceAvailable = sourceNameAvailable or false,
            untranslatedStats = unhandled,
            exactBlockSourceAvailable = exactBlockAvailable,
            blockResolved = block ~= nil,
            candidates = candidateDetails,
        }
    end
end
local function summaryFor(scope, version)
    local summary = { scope = scope, treeVersion = version, checked = 0, excluded = 0,
        titles = 0, unknownTitles = 0, blocks = 0, statLines = 0, translatedStatLines = 0,
        completeEffects = 0, incompleteEffects = 0, unreachableBlocks = 0 }
    report.summaries[#report.summaries + 1] = summary
    return summary
end
local function inspectBaseNodes(nodes, version, scope)
    local summary = summaryFor(scope, version)
    local context = { spec = { treeVersion = version } }
    for _, key in ipairs(sortedKeys(nodes)) do inspect(nodes[key], context, summary) end
end
local function inspectOptions(tree, version)
    local summary = summaryFor('loaded-tree-options', version)
    local context = { spec = { treeVersion = version } }
    for _, key in ipairs(sortedKeys(tree.nodes)) do
        local base = tree.nodes[key]
        for _, optionKey in ipairs(sortedKeys(base.options)) do
            local option = base.options[optionKey]
            -- PassiveSpec:ReplaceNode keeps the existing base ID. Options
            -- inherit metadata from their base via __index; preserve that chain
            -- on a detached copy and do not invoke mutating ProcessStats.
            local detached = setmetatable({}, getmetatable(base))
            for field, value in pairs(base) do detached[field] = value end
            detached.id = base.id
            detached.dn = option.dn or option.name or base.dn
            detached.sd = lines(option.sd or option.stats or base.sd)
            inspect(detached, context, summary, optionKey)
        end
    end
end
inspectBaseNodes(build.spec.nodes, build.spec.treeVersion, 'current-build')
-- main.tree contains actual, already processed PassiveTree instances. Inspect
-- every loaded version without changing the selected class/tree or loading data.
for _, version in ipairs(sortedKeys(main.tree)) do
    local tree = main.tree[version]
    inspectBaseNodes(tree.nodes, version, 'loaded-tree-base')
    inspectOptions(tree, version)
end
assert(snapshot() == before, 'Coverage inspection must not mutate tree data, options, allocations or calculations')
assert(build:SaveDB('test') == exportBefore, 'Coverage inspection must not change the exported build')
local outputPath = root .. '/tree-runtime-coverage.json'
local output = assert(io.open(outputPath, 'w'))
output:write(assert(json.encode(report, { indent = true })), '\n')
output:close()
for _, summary in ipairs(report.summaries) do
    print(string.format('COVERAGE %s/%s: names %d/%d, complete effects %d/%d, lines %d/%d, unreachable blocks %d',
        summary.treeVersion, summary.scope, summary.titles, summary.checked,
        summary.completeEffects, summary.checked, summary.translatedStatLines, summary.statLines,
        summary.unreachableBlocks))
end
print('PASS non-mutating full runtime coverage inspection; report=' .. outputPath .. '; gaps=' .. #report.gaps)

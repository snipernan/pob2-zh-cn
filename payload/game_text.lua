-- Only exact, verified game text and anchored numeric templates are accepted.
-- All returned strings are presentation values; no stat or gem data is edited.
local root = ...
local G = dofile(root .. '/game_dictionary.lua')
for key, value in pairs(dofile(root .. '/equipment_dictionary.lua')) do
    assert(G[key] == nil, 'Duplicate equipment dictionary field: ' .. key)
    G[key] = value
end
local exact, buckets = {}, {}
local function normalize(text)
    return text:gsub('%s+', ' '):match('^%s*(.-)%s*$')
end
local function escape(text) return (text:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1')) end
local function bucket(text) return (text:match('%a+') or ''):lower() end
local function compile(entry)
    local en = normalize(entry.en)
    local parts, pos = {'^'}, 1
    entry.fixedPlus = {}
    for at in en:gmatch('()#') do
        local literal = en:sub(pos, at - 1)
        -- The sign is part of the displayed value, including the API's +# form.
        entry.fixedPlus[#entry.fixedPlus + 1] = literal:sub(-1) == '+'
        if literal:sub(-1) == '+' then literal = literal:sub(1, -2) end
        parts[#parts + 1] = escape(literal)
        parts[#parts + 1] = '([%+%-]?[%d%.%-%(%)#]+)'
        pos = at + 1
    end
    parts[#parts + 1] = escape(en:sub(pos)) .. '$'
    return table.concat(parts)
end
local function indexEntries(entries, exact, buckets)
for _, entry in ipairs(entries) do
    local key = normalize(entry.en)
    if #entry.order == 0 then
        if exact[key] and exact[key] ~= entry.zh then exact[key] = false
        elseif exact[key] == nil then exact[key] = entry.zh end
    else
        entry.pattern = compile(entry)
        local key = bucket(key)
        buckets[key] = buckets[key] or {}
        buckets[key][#buckets[key] + 1] = entry
    end
end
end
indexEntries(G.affixes, exact, buckets)
local equipmentExact, equipmentBuckets = {}, {}
indexEntries(G.equipmentAffixes or {}, equipmentExact, equipmentBuckets)
local officialFoldExact, officialFoldBuckets, equipmentFoldExact, equipmentFoldBuckets = {}, {}, {}, {}
local function foldedEntries(entries)
    local result = {}
    for _, entry in ipairs(entries) do
        result[#result+1] = {en=entry.en:lower(),zh=entry.zh,order=entry.order}
    end
    return result
end
indexEntries(foldedEntries(G.affixes), officialFoldExact, officialFoldBuckets)
indexEntries(foldedEntries(G.equipmentAffixes or {}), equipmentFoldExact, equipmentFoldBuckets)
local function numeric(value)
    if value == '#' then return true end
    if value:match('^[%+%-]%(') then value = value:sub(2) end
    if value:sub(1,1) == '(' and value:sub(-1) == ')' then value = value:sub(2,-2) end
    if not value:match('^[%+%-]?[%d%.]+$') then
        local left, right = value:match('^([%+%-]?[%d%.]+)%-([%+%-]?[%d%.]+)$')
        return left ~= nil and tonumber(left) ~= nil and tonumber(right) ~= nil
    end
    return tonumber(value) ~= nil
end
local function substitute(entry, values)
    local result, pos, index = {}, 1, 0
    for at in entry.zh:gmatch('()#') do
        index = index + 1
        local literal, value = entry.zh:sub(pos, at - 1), values[entry.order[index]]
        if literal:sub(-1) == '+' and value:match('^[%+%-]') then literal = literal:sub(1,-2) end
        result[#result + 1], result[#result + 2] = literal, value
        pos = at + 1
    end
    result[#result + 1] = entry.zh:sub(pos)
    return table.concat(result)
end
local function translateFrom(text, exact, buckets)
    if type(text) ~= 'string' or #text > 16384 then return nil end
    local key = normalize(text)
    if exact[key] ~= nil then return exact[key] or nil, true end
    local result
    for _, entry in ipairs(buckets[bucket(key)] or {}) do
        local values = {key:match(entry.pattern)}
        if #values == #entry.order then
            local valid = true
            for i, value in ipairs(values) do
                if not numeric(value) then valid = false; break end
                if entry.fixedPlus[i] and value:sub(1,1) == '+' then values[i] = value:sub(2) end
            end
            if valid then
                local translated = substitute(entry, values)
                -- Never pick arbitrarily if two templates give different outputs.
                if result and result ~= translated then return nil, true end
                result = translated
            end
        end
    end
    return result, result ~= nil
end
function G.translateAffix(text)
    local result = translateFrom(text, exact, buckets)
    return result
end
function G.translateEquipmentAffix(text)
    local result, matched = translateFrom(text, exact, buckets)
    if matched then return result end
    if type(text) ~= 'string' then return nil end
    result, matched = translateFrom(text:lower(), officialFoldExact, officialFoldBuckets)
    if matched then return result end
    result, matched = translateFrom(text, equipmentExact, equipmentBuckets)
    if matched then return result end
    local supplemental = translateFrom(text:lower(), equipmentFoldExact, equipmentFoldBuckets)
    return supplemental
end
function G.matchEquipmentBlockLine(block, index, text)
    if type(text)~='string' or #text>16384 or not block.lines[index] then return nil end
    block._compiledLines=block._compiledLines or {}
    local entry=block._compiledLines[index]
    if not entry then
        entry={en=block.lines[index]:lower()}
        entry.pattern=compile(entry)
        local _,n=entry.en:gsub('#','');entry.slots=n
        block._compiledLines[index]=entry
    end
    local clean=normalize(text:gsub('%^x%x%x%x%x%x%x',''):gsub('%^%d','')):lower()
    if entry.slots==0 then return clean==normalize(entry.en) and {} or nil end
    local values={clean:match(entry.pattern)}
    if #values~=entry.slots then return nil end
    for i,value in ipairs(values) do
        if not numeric(value) then return nil end
        if entry.fixedPlus[i] and value:sub(1,1)=='+' then values[i]=value:sub(2) end
    end
    return values
end
function G.translateEquipmentBlock(block, texts)
    if #texts~=#block.lines then return nil end
    local values={}
    for i,text in ipairs(texts) do
        local captures=G.matchEquipmentBlockLine(block,i,text)
        if not captures then return nil end
        for _,value in ipairs(captures) do values[#values+1]=value end
    end
    if #values~=#block.order then return nil end
    return substitute(block,values)
end
function G.translateSkill(text) return G.skillNames[text] end
local function colorAt(text, i)
    local rest = text:sub(i)
    return rest:match('^(%^x%x%x%x%x%x%x)') or rest:match('^(%^[0-9])')
end
local function translateText(text, affixTranslator)
    if type(text) ~= 'string' then return nil end
    local plain, prefix, visible, last, i = {}, {}, false, nil, 1
    while i <= #text do
        local code = colorAt(text,i)
        if code then
            last = code
            if not visible then prefix[#prefix+1] = code end
            i = i + #code
        else
            local ch = text:sub(i,i)
            plain[#plain+1] = ch
            if not visible and ch:match('%s') then prefix[#prefix+1] = ch else visible = true end
            i = i + 1
        end
    end
    local clean = table.concat(plain)
    local middle, trailing = clean:match('^%s*(.-)(%s*)$')
    local translated = G.translateSkill(middle) or affixTranslator(middle)
    if not translated then return nil end
    return table.concat(prefix) .. translated .. trailing .. (last or '')
end
function G.translateText(text) return translateText(text, G.translateAffix) end
function G.translateEquipmentText(text) return translateText(text, G.translateEquipmentAffix) end
return G

-- Verified mainland passive names are presentation/search aliases only.
-- Never replace node.name/dn/sd/mods, allocation state, or tree IDs.
local P, game = ...
local A = {}
local unpackValues = unpack or table.unpack
local function pack(...) return { n = select('#', ...), ... } end
local function returned(result)
    if not result[1] then error(result[2], 0) end
    return unpackValues(result, 2, result.n)
end
local function unicode(text) return type(text) == 'string' and text:find('[\128-\255]') ~= nil end
local function plain(text) return text:gsub('%^x%x%x%x%x%x%x', ''):gsub('%^%d', '') end
local function allowsVersion(versions, version)
    if not versions then return true end
    if versions[version or false] == true then return true end
    for _, allowed in ipairs(versions) do if allowed == version then return true end end
    return false
end

local function displayLines(lines)
    local result = {}
    for _, text in ipairs(lines or {}) do
        if type(text) ~= 'string' then return nil end
        -- Match PassiveTree:ProcessStats exactly. A source stat can span more
        -- than one display line, and Chinese does not have to use that split.
        if text:find('\n', 1, true) then
            for line in text:gmatch('[^\n]+') do result[#result + 1] = line end
        else result[#result + 1] = text end
    end
    return result
end
local function sameLines(left, right)
    if not left or not right or #left ~= #right then return false end
    for i, line in ipairs(left) do if line ~= right[i] then return false end end
    return true
end
local function validVersion(entry, version)
    return (not entry.version or entry.version == version) and allowsVersion(entry.versions, version)
end

function A.entryForNode(node, build)
    if not node or not game.treeById then return nil end
    local entry = game.treeById[tostring(node.id)] or game.treeById[node.id]
    if not entry then return nil end
    local version = build and build.spec and build.spec.treeVersion
    local candidate, hasVariantName
    for _, variant in ipairs(entry.variants or {}) do
        if variant.en == node.dn then
            hasVariantName = true
            if validVersion(variant, version) and variant.currentStats
                and sameLines(displayLines(variant.currentStats), node.sd or {}) then
                -- Same title/effects must identify one verified variant, never
                -- the arbitrary first matching class or attribute option.
                if candidate then return nil end
                candidate = variant
            end
        end
    end
    if hasVariantName then return candidate end
    if entry.en ~= node.dn or not validVersion(entry, version) then return nil end
    return entry
end

local function splitWarning(text)
    local warning = main and main.notSupportedTooltipText
    if type(warning) == 'string' and warning ~= '' and text:sub(-#warning) == warning then
        return text:sub(1, #text - #warning), warning
    end
    return text, ''
end
local function translateExact(text, translations)
    local body, warning = splitWarning(text)
    local clean = plain(body)
    local translated = translations[clean]
    if not translated then return text end
    -- Native colour codes may split a sentence. Keep its initial colour and
    -- final renderer state; English emphasis positions do not map to Chinese.
    text = body
    local prefix, final, offset = {}, nil, 1
    while true do
        local escape = text:sub(offset):match('^(%^x%x%x%x%x%x%x)') or text:sub(offset):match('^(%^[0-9])')
        if not escape then break end
        prefix[#prefix + 1] = escape; offset = offset + #escape
    end
    local i = 1
    while i <= #text do
        local escape = text:sub(i):match('^(%^x%x%x%x%x%x%x)') or text:sub(i):match('^(%^[0-9])')
        if escape then final = escape; i = i + #escape else i = i + 1 end
    end
    return table.concat(prefix) .. translated .. (final or '') .. warning
end

local function scopedTooltip(tooltip, translations, literal, block, fn, ...)
    local own, original = rawget(tooltip, 'AddLine'), tooltip.AddLine
    local ownSeparator, separator = rawget(tooltip, 'AddSeparator'), tooltip.AddSeparator
    local pending, blockDone = {}, false
    local function emit(args)
        local text = args[3]
        if P.enabled and type(text) == 'string' then
            if literal and literal[plain(text)] and P.withLiteralText then
                return P.withLiteralText({ [text] = true }, original, unpackValues(args, 1, args.n))
            end
            args[3] = translateExact(text, translations)
        end
        return original(unpackValues(args, 1, args.n))
    end
    local function flush(complete)
        if #pending == 0 then return end
        if complete then
            local first, warning = pending[1], ''
            for _, args in ipairs(pending) do
                local _, suffix = splitWarning(args[3])
                if suffix ~= '' then warning = suffix end
            end
            local body = splitWarning(first[3])
            first[3] = translateExact(body, { [plain(body)] = block.zh })
            original(unpackValues(first, 1, first.n))
            -- The source does not pair Chinese lines to English lines. Preserve
            -- the native unsupported warning once for the complete block.
            if warning ~= '' then
                first[3] = warning
                original(unpackValues(first, 1, first.n))
            end
            blockDone = true
        else
            for _, args in ipairs(pending) do emit(args) end
        end
        pending = {}
    end
    tooltip.AddLine = function(self, height, text, ...)
        local args = pack(self, height, text, ...)
        if P.enabled and block and not blockDone and type(text) == 'string'
            and select(1, ...) == 'FONTIN SC' and not self.center then
            local body = splitWarning(text)
            local expected = block.en[#pending + 1]
            if plain(body) == expected then
                pending[#pending + 1] = args
                if #pending == #block.en then flush(true) end
                return
            end
        end
        flush(false)
        return emit(args)
    end
    if separator then
        tooltip.AddSeparator = function(self, ...)
            flush(false)
            return separator(self, ...)
        end
    end
    local result = pack(pcall(fn, ...))
    -- Restore methods even when the original tooltip builder throws. Pending
    -- partial blocks retain the original lines, including their current values.
    local flushResult = pack(pcall(flush, false))
    tooltip.AddLine, tooltip.AddSeparator = own, ownSeparator
    if not flushResult[1] and result[1] then error(flushResult[2], 0) end
    return returned(result)
end

function A.statBlockForNode(node, entry, build)
    local candidate
    local version = build and build.spec and build.spec.treeVersion
    for _, block in ipairs(entry and entry.statBlocks or {}) do
        local lines = displayLines(block.en)
        if validVersion(block, version) and lines and #lines > 0 and #block.zh > 0
            and sameLines(lines, node.sd or {}) then
            if candidate then return nil end
            candidate = { en = lines, zh = table.concat(block.zh, '\n') }
        end
    end
    return candidate
end
local function mayChangeDisplayedStats(node, incSmallPassiveSkillEffect)
    if (incSmallPassiveSkillEffect or 0) > 0 and node.type == 'Normal'
        and not node.isAttribute and not node.ascendancyName then return true end
    for _, mod in ipairs(node.finalModList or {}) do
        if mod.parsedLine or mod.name == 'JewelSmallPassiveSkillEffect'
            or mod.name == 'JewelNotablePassiveSkillEffect' then return true end
    end
    return false
end

local function statTranslations(node, entry, build)
    local result = {}
    -- Require the current (possibly jewel-replaced) text as well as its ID and
    -- original English name. Stale text from a different version is not used.
    local current = {}
    for _, line in ipairs(node.sd or {}) do current[line] = true end
    for _, stat in ipairs(entry and entry.stats or {}) do
        if current[stat.en] and type(stat.zh) == 'string'
            and allowsVersion(stat.versions, build and build.spec and build.spec.treeVersion) then
            result[stat.en] = stat.zh
        end
    end
    return result
end

local function protectViewer(class)
    if not class or rawget(class, '_pobCnTree') or not class.AddNodeTooltip then return end
    class._pobCnTree = true
    local name, tooltip, matches, draw = class.AddNodeName, class.AddNodeTooltip, class.DoesNodeMatchSearchParams, class.Draw
    class.AddNodeName = function(self, tip, node, build, ...)
        if not P.enabled or not node or type(node.dn) ~= 'string' then return name(self, tip, node, build, ...) end
        local entry = A.entryForNode(node, build)
        local translations, literal = {}, {}
        local suffix = launch.devModeAlt and (' [' .. node.id .. ']') or ''
        if entry and entry.zh then translations[node.dn .. suffix] = entry.zh .. suffix
        else literal[node.dn .. suffix] = true end
        return scopedTooltip(tip, translations, literal, nil, name, self, tip, node, build, ...)
    end
    class.AddNodeTooltip = function(self, tip, node, build, ...)
        if not P.enabled then return tooltip(self, tip, node, build, ...) end
        local entry = A.entryForNode(node, build)
        local translations = statTranslations(node, entry, build)
        local block = not mayChangeDisplayedStats(node, select(1, ...)) and A.statBlockForNode(node, entry, build)
        return scopedTooltip(tip, translations, nil, block, tooltip, self, tip, node, build, ...)
    end
    class.DoesNodeMatchSearchParams = function(self, build, node, ...)
        local params = self.searchParams or {}
        if not P.enabled or params[1] == 'oil:' then return matches(self, build, node, ...) end
        local hasChinese = false
        for _, term in ipairs(params) do if unicode(term) then hasChinese = true; break end end
        if not hasChinese then return matches(self, build, node, ...) end
        local entry = A.entryForNode(node, build)
        local candidates = {}
        if entry and entry.zh then candidates[#candidates + 1] = entry.zh end
        local block = A.statBlockForNode(node, entry, build)
        if block then candidates[#candidates + 1] = block.zh end
        local translations = statTranslations(node, entry, build)
        for _, line in ipairs(node.sd or {}) do
            local translated = translations[line] or (game.translateAffix and game.translateAffix(line))
            if translated then candidates[#candidates + 1] = translated end
        end
        local remaining = {}
        for _, term in ipairs(params) do
            local found = false
            for _, candidate in ipairs(candidates) do
                -- A Chinese query can contain separate numeric tokens (15%).
                -- Match every token against its verified Chinese sentences,
                -- then let native matching process any remaining terms.
                local ok, result = pcall(function()
                    return candidate:find(term, 1, true) or candidate:matchOrPattern(term)
                end)
                if ok and result then found = true; break end
            end
            if not found then remaining[#remaining + 1] = term end
        end
        -- The original implementation still enforces hidden starts, unlocks,
        -- oil syntax, node type, English stats/mod names, and AND semantics.
        self.searchParams = remaining
        local result = pack(pcall(matches, self, build, node, ...))
        self.searchParams = params
        return returned(result)
    end
    class.Draw = function(self, ...)
        if self._pobCnTreeRevision ~= P.revision then
            self._pobCnTreeRevision = P.revision
            self.searchStrCached = nil
        end
        return draw(self, ...)
    end
end

function A.prepareSearchControl(control)
    if not control or rawget(control, '_pobCnTreeSearch') then return end
    control._pobCnTreeSearch = true
    local keyDown = control.OnKeyDown
    control.OnKeyDown = function(self, key, ...)
        if self:IsShown() and self:IsEnabled() then
            local pasting = key == 'v' and IsKeyDown('CTRL')
                or key == 'RIGHTBUTTON' and self.Object:IsMouseOver() and not self.disableRightClickPaste
            if pasting then
                local text = Paste()
                if unicode(text) then
                    if self.pasteFilter then text = self.pasteFilter(text) end
                    if self.sel and self.sel ~= self.caret then self:ReplaceSel(text)
                    else self:Insert(text) end
                    return self
                end
            end
            -- Upstream cursor movement is UTF-8 aware, but deletion/paste are
            -- byte-based. Fix this search instance even after F10 is pressed.
            if unicode(self.buf) and (not self.sel or self.sel == self.caret) then
                if key == 'BACK' and self.caret > 1 then
                    local start = self.caret - 1
                    while start > 1 and self.buf:byte(start) >= 128 and self.buf:byte(start) < 192 do start = start - 1 end
                    if self.caret - start > 1 then self.sel = start; self:ReplaceSel(''); return self end
                elseif key == 'DELETE' and self.caret <= #self.buf and self.buf:byte(self.caret) >= 192 then
                    local nextIndex = self.caret + 1
                    while nextIndex <= #self.buf and self.buf:byte(nextIndex) >= 128 and self.buf:byte(nextIndex) < 192 do nextIndex = nextIndex + 1 end
                    self.sel = nextIndex; self:ReplaceSel(''); return self
                end
            end
        end
        return keyDown(self, key, ...)
    end
end

function A.protectBuild(build)
    local tab = build and build.treeTab
    A.prepareSearchControl(tab and tab.controls and tab.controls.treeSearch)
end

function A.protectClasses(classes)
    if not classes then return end
    protectViewer(classes.PassiveTreeView)
    local tab = classes.TreeTab
    if tab and not rawget(tab, '_pobCnTreeTab') then
        tab._pobCnTreeTab = true
        local constructor = tab._constructor
        tab._constructor = function(self, ...)
            local result = pack(constructor(self, ...))
            A.prepareSearchControl(self.controls and self.controls.treeSearch)
            return unpackValues(result, 1, result.n)
        end
    end
end
return A

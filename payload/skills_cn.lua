-- Display and search aliases for verified mainland Chinese gem names.
-- Gem records, selected IDs, editable buffers, and exported names stay English.
local P, game = ...
local A = {}
local controls = setmetatable({}, { __mode = 'k' })
local unpackValues = unpack or table.unpack
local function pack(...) return { n = select('#', ...), ... } end
local function returned(values)
    if not values[1] then error(values[2], 0) end
    return unpackValues(values, 2, values.n)
end
local function hasUnicode(s) return type(s) == 'string' and s:find('[\128-\255]') ~= nil end
local function enabled() return P.enabled end

function A.nameForGem(gem, id)
    if not gem then return nil end
    id = id or gem.id
    if id then id = id:gsub('^%w+:', '') end
    local entry = id and game.skillsById and game.skillsById[id]
    if entry and entry.en == gem.name then return entry.zh end
    return game.skillNames and game.skillNames[gem.name]
end

local function inactiveName(self, buf)
    if not enabled() then return buf end
    local selected = self.gemId or (self.list and self.list[math.max(self.selIndex or 0, 1)])
    local gem = selected and self.gems[selected]
    if gem and gem.name == buf then return A.nameForGem(gem, selected) or buf end
    -- The selected ID is absent just after loading a build. Only an unambiguous
    -- exact English name may use the name dictionary in this state.
    return game.skillNames and game.skillNames[buf] or buf
end

local function prepare(self)
    controls[self] = true
    if self._pobCnInactive then return end
    self._pobCnInactive = true
    local original = self.inactiveText
    self.inactiveText = function(buf)
        local display = inactiveName(self, buf)
        if display ~= buf then return display end
        if type(original) == 'function' then return original(buf) end
        return original or buf
    end
end

-- Call before changing P.enabled. Cancelling an uncommitted search is solely
-- a UI operation: neither UpdateGem nor its model-editing callback is invoked.
function A.beforeLanguageToggle()
    if not enabled() then return 0 end
    local cancelled = 0
    for control in pairs(controls) do
        if control._pobCnSearch or (control.dropped and hasUnicode(control.buf)) then
            local state = control._pobCnQueryRestore
            control:SetText(state and state.buf or control.initialBuf or control.gemName or '')
            if state then
                for index = #control.list, 1, -1 do control.list[index] = nil end
                for index, id in ipairs(state.list) do control.list[index] = id end
                control.selIndex = state.selIndex
                control.gemId, control.gemName = state.gemId, state.gemName
                control.noMatches = state.noMatches
                control.searchStr, control.mode = state.searchStr, state.mode
                control.controls.scrollBar.offset = state.scrollOffset
            else
                control.selIndex = control.initialIndex or 0
                control.searchStr, control.mode = control.buf, ''
            end
            control.dropped, control.hoverSel = false, nil
            control._pobCnSearch, control._pobCnQueryRestore = nil, nil
            cancelled = cancelled + 1
        end
    end
    return cancelled
end

local function protectGem(class)
    if not class or rawget(class, '_pobCnSkills') or not rawget(class, 'BuildList') then return end
    class._pobCnSkills = true
    local preview = class.CalcOutputWithThisGem
    if preview then
        class.CalcOutputWithThisGem = function(self, ...)
            local group = self.skillsTab.displayGroup
            local gemList = group and group.gemList
            local originalGem = gemList and gemList[self.index]
            local displayGemList = group and group.displayGemList
            -- CalcActiveSkill selects/clears these persisted settings during
            -- candidate DPS calculations. A support preview can change the
            -- active gem in another slot, so protect all current skill groups.
            -- Other calculation caches remain intact.
            local fields = {
                'skillMinion', 'skillMinionCalcs', 'skillMinionItemSet', 'skillMinionItemSetCalcs',
                'skillMinionSkill', 'skillMinionSkillCalcs', 'skillPart', 'skillPartCalcs',
                'skillMineCount', 'skillMineCountCalcs', 'skillStageCount', 'skillStageCountCalcs',
            }
            local states, seen = {}, {}
            local function remember(gem)
                if not gem or seen[gem] then return end
                seen[gem] = true
                local values = {}
                for _, field in ipairs(fields) do values[field] = rawget(gem, field) end
                states[#states + 1] = { gem = gem, values = values }
            end
            for _, candidateGroup in ipairs(self.skillsTab.socketGroupList or {}) do
                for _, gem in ipairs(candidateGroup.gemList or {}) do remember(gem) end
            end
            for _, gem in ipairs(gemList or {}) do remember(gem) end
            local gemData, level, displayEffect
            if originalGem then
                gemData, level, displayEffect = rawget(originalGem, 'gemData'), rawget(originalGem, 'level'), rawget(originalGem, 'displayEffect')
            end
            local result = pack(pcall(preview, self, ...))
            for _, state in ipairs(states) do
                for _, field in ipairs(fields) do state.gem[field] = state.values[field] end
            end
            if gemList then gemList[self.index] = originalGem end
            if originalGem then
                originalGem.gemData, originalGem.level, originalGem.displayEffect = gemData, level, displayEffect
            end
            if group then group.displayGemList = displayGemList end
            return returned(result)
        end
    end
    local constructor = class._constructor
    class._constructor = function(self, ...)
        local result = pack(constructor(self, ...))
        prepare(self)
        return unpackValues(result, 1, result.n)
    end
    local draw = class.Draw
    class.Draw = function(self, ...)
        prepare(self)
        local scrollbar = self.controls and self.controls.scrollBarH
        local offset = scrollbar and scrollbar.offset
        -- A caret scrolled to the end of the longer English buffer must not
        -- hide the shorter inactive Chinese caption.
        if scrollbar and not self.hasFocus and enabled() then scrollbar.offset = 0 end
        local results = pack(pcall(draw, self, ...))
        if scrollbar then scrollbar.offset = offset end
        return returned(results)
    end
    -- Restrict the filter change to this selector's edit operation. Never alter
    -- the base EditControl filter or another control's raw input rules.
    for _, method in ipairs({ 'Insert', 'ReplaceSel' }) do
        local original = class[method]
        class[method] = function(self, ...)
            local filter, pattern = self.filter, self.filterPattern
            if enabled() then
                self.filter = "^ %a':%-\128-\255"
                self.filterPattern = '[' .. self.filter .. ']'
            end
            local results = pack(pcall(original, self, ...))
            self.filter, self.filterPattern = filter, pattern
            return returned(results)
        end
    end

    local buildList = class.BuildList
    class.BuildList = function(self, buf)
        prepare(self)
        local full = buf .. (self.mode or '')
        local term, tags = full:match('^([^:]*)(:.*)$')
        term = term or full
        if not enabled() or not hasUnicode(term) then
            if #buf > 0 or not enabled() then self._pobCnSearch, self._pobCnQueryRestore = nil, nil end
            return buildList(self, buf)
        end
        if not self._pobCnSearch then
            local list = {}; for index, id in ipairs(self.list) do list[index] = id end
            self._pobCnQueryRestore = {
                buf = self.initialBuf or self.gemName or '',
                list = list, selIndex = self.initialIndex or self.selIndex,
                gemId = self.gemId, gemName = self.gemName,
                noMatches = self.noMatches, searchStr = self.searchStr, mode = self.mode,
                scrollOffset = self.controls.scrollBar.offset,
            }
        end
        self._pobCnSearch = true
        -- Ask upstream to apply availability, support, tags, and DPS sorting.
        -- Filter the resulting IDs without replacing any gem data tables.
        self.mode = ''
        buildList(self, tags or '')
        local buckets = { {}, {}, {} }
        for _, id in ipairs(self.list) do
            local zh = A.nameForGem(self.gems[id], id)
            local start = zh and zh:find(term, 1, true)
            if start then
                local rank = zh == term and 1 or start == 1 and 2 or 3
                buckets[rank][#buckets[rank] + 1] = id
            end
        end
        for i = #self.list, 1, -1 do self.list[i] = nil end
        for _, bucket in ipairs(buckets) do
            for _, id in ipairs(bucket) do self.list[#self.list + 1] = id end
        end
        self.noMatches = #self.list == 0
        if self.noMatches then self.list[1] = '' end
        self.searchStr = full
    end

    local updateGem = class.UpdateGem
    class.UpdateGem = function(self, setText, addUndo, focusLost)
        if enabled() and (hasUnicode(self.buf) or (self._pobCnSearch and self.buf == '')) then
            -- Searching should not replace the current gem with the first
            -- candidate. Native mouse/Enter selection first writes English.
            if not focusLost then return end
            local selected, ambiguous
            for index, id in ipairs(self.list) do
                if A.nameForGem(self.gems[id], id) == self.buf then
                    if selected then ambiguous = true; break end
                    selected = index
                end
            end
            if selected and not ambiguous then
                self._pobCnSearch, self._pobCnQueryRestore = nil, nil
                self.selIndex = selected
                self:SetText(self.gems[self.list[selected]].name)
                return updateGem(self, setText, addUndo, focusLost)
            end
            -- An unfinished/ambiguous Chinese query is not a request to delete
            -- a gem. Restore the pre-search text; never pick an arbitrary ID.
            self:SetText(self.initialBuf or '')
            self._pobCnSearch, self._pobCnQueryRestore = nil, nil
            self.mode = ''
            buildList(self, self.buf)
            self.selIndex = 0
            return updateGem(self, true, false, false)
        end
        self._pobCnSearch, self._pobCnQueryRestore = nil, nil
        return updateGem(self, setText, addUndo, focusLost)
    end
    local focusLost = class.OnFocusLost
    class.OnFocusLost = function(self, ...)
        if enabled() and self.dropped and (hasUnicode(self.buf) or self._pobCnSearch) then
            self.dropped = false
            return self:UpdateGem(true, true, true)
        end
        return focusLost(self, ...)
    end
    local keyDown = class.OnKeyDown
    class.OnKeyDown = function(self, key, ...)
        if enabled() and self:IsShown() and self:IsEnabled() then
            if key == 'v' and IsKeyDown('CTRL') then
                local text = Paste()
                if hasUnicode(text) then
                    if self.pasteFilter then text = self.pasteFilter(text) end
                    if self.sel and self.sel ~= self.caret then self:ReplaceSel(text)
                    else self:Insert(text) end
                    return self
                end
            end
            -- Upstream backspace/delete remove one byte, despite UTF-8 cursor
            -- movement. Use its normal selection editor for one whole glyph.
            if hasUnicode(self.buf) and (not self.sel or self.sel == self.caret) then
                if key == 'BACK' and self.caret > 1 then
                    local start = self.caret - 1
                    while start > 1 and self.buf:byte(start) >= 128 and self.buf:byte(start) < 192 do start = start - 1 end
                    if self.caret - start > 1 then
                        self.sel = start; self:ReplaceSel(''); return self
                    end
                elseif key == 'DELETE' and self.caret <= #self.buf and self.buf:byte(self.caret) >= 192 then
                    local nextIndex = self.caret + 1
                    while nextIndex <= #self.buf and self.buf:byte(nextIndex) >= 128 and self.buf:byte(nextIndex) < 192 do nextIndex = nextIndex + 1 end
                    self.sel = nextIndex; self:ReplaceSel(''); return self
                end
            end
        end
        if enabled() and key == 'RETURN' and self.dropped and hasUnicode(self.buf) and (self.selIndex or 0) == 0 then
            local count = 0
            for _, id in ipairs(self.list) do
                if A.nameForGem(self.gems[id], id) == self.buf then count = count + 1 end
            end
            if count > 1 then return self end -- Require an explicit row choice.
        end
        -- The upstream keyboard method delegates paste to the EditControl
        -- parent proxy, which bypasses this subclass's Insert override.
        local filter, pattern = self.filter, self.filterPattern
        if enabled() then
            self.filter = "^ %a':%-\128-\255"
            self.filterPattern = '[' .. self.filter .. ']'
        end
        local results = pack(pcall(keyDown, self, key, ...))
        self.filter, self.filterPattern = filter, pattern
        return returned(results)
    end
end

-- An automatically generated group can contain several comma-separated gems.
-- Only exact dictionary entries are replaced; arbitrary labels are untouched.
function A.groupDisplayLabel(group)
    local label = group and group.displayLabel
    if not enabled() or type(label) ~= 'string' or (group.label and group.label:match('%S')) then return label end
    local pieces, start = {}, 1
    while true do
        local s, e = label:find(', ', start, true)
        local piece = label:sub(start, s and s - 1 or #label)
        pieces[#pieces + 1] = game.skillNames and game.skillNames[piece] or piece
        if not s then break end
        start = e + 1
    end
    return table.concat(pieces, ', ')
end

local function protectSkillList(class)
    if not class or rawget(class, '_pobCnSkillList') or not rawget(class, 'GetRowValue') then return end
    class._pobCnSkillList = true
    local getRow = class.GetRowValue
    class.GetRowValue = function(self, column, index, group, ...)
        local results = pack(getRow(self, column, index, group, ...))
        local original, display = group and group.displayLabel, A.groupDisplayLabel(group)
        if column == 1 and type(results[1]) == 'string' and display and display ~= original then
            local s, e = results[1]:find(original, 1, true)
            if s then results[1] = results[1]:sub(1, s - 1) .. display .. results[1]:sub(e + 1) end
        end
        return unpackValues(results, 1, results.n)
    end
end

-- The root display plugin merges this with its existing literal scopes.
function A.dropdownLiteralScope(control)
    local scope = {}
    for index, group in ipairs(control._pobCnSocketGroups or {}) do
        if group.label and group.label:match('%S') then
            local row = control.list and control.list[index]
            local label = type(row) == 'table' and row.label or row
            if type(label) == 'string' then scope[label] = true end
        end
    end
    return scope
end

local function protectDropdown(class)
    if not class or rawget(class, '_pobCnGroupDrop') or not class.Draw then return end
    class._pobCnGroupDrop = true
    for _, method in ipairs({ 'Draw', 'CheckDroppedWidth' }) do
        local original = class[method]
        if original then
            class[method] = function(self, ...)
                if not self._pobCnSocketGroups or not enabled() then return original(self, ...) end
                local list = self.list
                local display = {}
                for index, row in ipairs(list) do
                    if type(row) == 'table' and self._pobCnSocketGroups[index] then
                        local copy = {}; for k, v in pairs(row) do copy[k] = v end
                        copy.label = A.groupDisplayLabel(self._pobCnSocketGroups[index]) or row.label
                        display[index] = copy
                    else display[index] = row end
                end
                self.list = display
                local results = pack(pcall(original, self, ...))
                self.list = list
                return returned(results)
            end
        end
    end
end

function A.protectBuild(module)
    if not module or rawget(module, '_pobCnSkillRefresh') or not module.RefreshSkillSelectControls then return end
    module._pobCnSkillRefresh = true
    local refresh = module.RefreshSkillSelectControls
    module.RefreshSkillSelectControls = function(self, controls, ...)
        if controls and controls.mainSocketGroup and self.skillsTab then
            controls.mainSocketGroup._pobCnSocketGroups = self.skillsTab.socketGroupList
        end
        return refresh(self, controls, ...)
    end
end

function A.protectClasses(classes)
    if not classes then return end
    protectGem(classes.GemSelectControl)
    protectSkillList(classes.SkillListControl)
    protectDropdown(classes.DropDownControl)
    A.protectBuild(classes.CompareEntry)
end
return A

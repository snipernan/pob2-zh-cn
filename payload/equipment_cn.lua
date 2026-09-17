-- Equipment aliases are scoped to parsed item identities and native selectors.
-- Never replace Item fields, itemBases, database rows, raw text or callback values.
local P, game = ...
local E = {}
local unpackValues = unpack or table.unpack
local function pack(...) return { n = select('#', ...), ... } end
local function returned(result)
    if not result[1] then error(result[2], 0) end
    return unpackValues(result, 2, result.n)
end
local function plain(s) return s:gsub('%^x%x%x%x%x%x%x', ''):gsub('%^%d', '') end
local function unicode(s) return type(s) == 'string' and s:find('[\128-\255]') ~= nil end
local function shortBase(s) return s and s:gsub(' %(.+%)', '') end
local function scopeCall(scope, fn, ...)
    if P.withLiteralText then return P.withLiteralText(scope, fn, ...) end
    return fn(...)
end
local controls, tabs, databases = setmetatable({}, { __mode = 'k' }),
    setmetatable({}, { __mode = 'k' }), setmetatable({}, { __mode = 'k' })

function E.baseName(name, base)
    local record = name and game.equipmentBases and game.equipmentBases[name]
    if not record or record.en ~= name then return nil end
    if base and data and data.itemBases and data.itemBases[name] ~= base then return nil end
    return record.zh
end
function E.uniqueEntry(item)
    if not item or (item.rarity ~= 'UNIQUE' and item.rarity ~= 'RELIC') then return nil end
    local record = game.equipmentUniques and game.equipmentUniques[item.name]
    if not record or record.en ~= item.title or record.base ~= item.baseName then return nil end
    if not item.base or item.name ~= item.title .. ', ' .. shortBase(item.baseName) then return nil end
    return record
end
function E.uniqueTitle(item)
    local record = E.uniqueEntry(item)
    return record and record.zh
end
function E.name(item)
    if not item then return nil end
    if not P.enabled then return item.name end
    if not item.base or not item.baseName then return item.name end
    local base = E.baseName(item.baseName, item.base)
    if not base and not E.uniqueTitle(item) then return item.name end
    base = base or shortBase(item.baseName)
    if item.title then
        if item.name ~= item.title .. ', ' .. shortBase(item.baseName) then return item.name end
        return (E.uniqueTitle(item) or item.title) .. ', ' .. base
    end
    local prefix, suffix = item.namePrefix or '', item.nameSuffix or ''
    if item.name ~= prefix .. item.baseName .. suffix
        and item.name ~= prefix .. shortBase(item.baseName) .. suffix then return item.name end
    return prefix .. base .. suffix
end
local function replacePrefix(text, expected, replacement)
    if type(text) ~= 'string' or not expected or not replacement then return text end
    local prefix = text:match('^(%^x%x%x%x%x%x%x)') or text:match('^(%^%d)') or ''
    local start = #prefix + 1
    if text:sub(start, start + #expected - 1) == expected then
        return prefix .. replacement .. text:sub(start + #expected)
    end
    return text
end
local function exactText(text, english, chinese)
    if plain(text) ~= english then return nil end
    local prefix = text:match('^(%^x%x%x%x%x%x%x)') or text:match('^(%^%d)') or ''
    return prefix .. chinese
end
local function splitWarning(text)
    -- itemLib appends this exact native suffix after an unsupported modifier.
    -- It is UI metadata, not part of the verified equipment stat sentence.
    local warning = main and main.notSupportedTooltipText
    if type(warning) == 'string' and warning ~= '' and text:sub(-#warning) == warning then
        return text:sub(1, #text - #warning), warning
    end
    return text, ''
end
local function equipmentText(text)
    if not P.enabled or type(text) ~= 'string' then return text end
    local body, suffix = splitWarning(text)
    local prefix = body:match('^(%^x%x%x%x%x%x%x)') or body:match('^(%^%d)') or ''
    local canonical = P.importCompat and P.importCompat.canonical(body:sub(#prefix + 1))
    if canonical then body = prefix .. canonical end
    local translated = game.translateEquipmentText and game.translateEquipmentText(body)
    if translated and translated ~= body then return translated .. suffix end
    translated = P.translate(text)
    if translated ~= text then return translated end
    local record = game.equipmentTypes and game.equipmentTypes[plain(text)]
    if record and record.en == plain(text) then return exactText(text, record.en, record.zh) end
    return text
end
local function equipmentAffix(text)
    local translate = game.translateEquipmentAffix or game.translateAffix
    return translate and translate(text)
end
function E.flavourText(item, text)
    local record = E.uniqueEntry(item)
    local flavour = record and record.flavour
    if not P.enabled or not flavour or not flavour.en or not flavour.zh then return nil end
    return exactText(text, table.concat(flavour.en, '\n'), table.concat(flavour.zh, '\n'))
end
function E.effectBlockTexts(item, dbMode)
    local record = P.enabled and E.uniqueEntry(item)
    local blocks = record and record.effectBlocks
    local results = {}
    if not blocks or not item.GetModLineVariantCount or not itemLib or not itemLib.formatModLine
        or not game.matchEquipmentBlockLine or not game.translateEquipmentBlock then return results end
    -- The database tooltip uses dbMode=true (displaying its ranges). Other
    -- callers can explicitly request the native rolled-value presentation.
    if dbMode == nil then dbMode = true end
    for _, field in ipairs({ 'buffModLines', 'enchantModLines', 'runeModLines', 'implicitModLines', 'explicitModLines' }) do
        local lines = {}
        for _, line in ipairs(item[field] or {}) do
            local count = item:GetModLineVariantCount(line)
            if count > 0 then
                local displayed = itemLib.formatModLine(line, dbMode)
                for _ = 1, count do
                    lines[#lines + 1] = type(displayed) == 'string' and splitWarning(displayed) or false
                end
            end
        end
        for start = 1, #lines do
            for _, block in ipairs(blocks) do
                local texts = {}
                for index = 1, #block.lines do
                    local text = lines[start + index - 1]
                    if not text or not game.matchEquipmentBlockLine(block, index, text) then break end
                    texts[#texts + 1] = text
                end
                if #texts == #block.lines then
                    local translated = game.translateEquipmentBlock(block, texts)
                    if translated then results[#results + 1] = translated end
                end
            end
        end
    end
    return results
end
local function protectTooltip(class)
    if not class or not class.AddItemTooltip or rawget(class, '_pobCnEquipmentTooltip') then return end
    class._pobCnEquipmentTooltip = true
    local original = class.AddItemTooltip
    class.AddItemTooltip = function(self, tooltip, item, ...)
        tabs[self] = true
        local own, addLine = rawget(tooltip, 'AddLine'), tooltip.AddLine
        local ownSeparator, separator = rawget(tooltip, 'AddSeparator'), tooltip.AddSeparator
        local record = E.uniqueEntry(item)
        local flavour = record and record.flavour
        local blocks = record and record.effectBlocks
        local effectPending, effectCandidates = {}, nil
        local function flushEffects(complete)
            if #effectPending == 0 then return end
            local translated, first = nil, effectPending[1]
            if complete then
                local texts, warning = {}, ''
                for _, args in ipairs(effectPending) do
                    local body, suffix = splitWarning(args[3])
                    texts[#texts + 1] = body
                    if suffix ~= '' then warning = suffix end
                end
                for _, block in ipairs(effectCandidates or {}) do
                    if #block.lines == #texts then
                        local value = game.translateEquipmentBlock(block, texts)
                        if type(value) ~= 'string' then translated = nil; break end
                        if translated and translated ~= value then translated = nil; break end
                        translated = value
                    end
                end
                if translated then translated = translated .. warning end
            end
            -- Keep the original arguments until translation succeeds. If its
            -- validator throws, the outer cleanup can still emit every line.
            local batch = effectPending
            effectPending, effectCandidates = {}, nil
            if translated then
                first[3] = translated
                scopeCall({ [translated] = true }, addLine, unpackValues(first, 1, first.n))
            else
                for _, args in ipairs(batch) do
                    scopeCall({ [args[3]] = true }, addLine, unpackValues(args, 1, args.n))
                end
            end
        end
        local function appendEffect(args)
            local body = splitWarning(args[3])
            local candidates, index = {}, #effectPending + 1
            for _, block in ipairs(effectCandidates or blocks) do
                local checked = pack(pcall(game.matchEquipmentBlockLine, block, index, body))
                if not checked[1] then
                    effectPending[#effectPending + 1] = args
                    error(checked[2], 0)
                end
                if checked[2] then candidates[#candidates + 1] = block end
            end
            if #candidates == 0 then
                if #effectPending > 0 then
                    flushEffects(false)
                    return appendEffect(args)
                end
                return false
            end
            effectPending[#effectPending + 1], effectCandidates = args, candidates
            local complete = true
            for _, block in ipairs(candidates) do if #block.lines ~= #effectPending then complete = false end end
            if complete then flushEffects(true) end
            return true
        end
        local pending = {}
        local function flushFlavour(complete)
            if #pending == 0 then return end
            if complete then
                local first = pending[1]
                first[3] = exactText(first[3], flavour.en[1], table.concat(flavour.zh, '\n'))
                addLine(unpackValues(first, 1, first.n))
            else
                for _, args in ipairs(pending) do addLine(unpackValues(args, 1, args.n)) end
            end
            pending = {}
        end
        local header, position = {}, 0
        local base = item.base and E.baseName(item.baseName, item.base)
        if item.title then
            header[1] = { item.title, E.uniqueTitle(item) or item.title }
            if item.baseName then header[2] = { shortBase(item.baseName), base or shortBase(item.baseName) } end
        elseif item.baseName then
            local prefix, suffix = item.namePrefix or '', item.nameSuffix or ''
            header[1] = { prefix .. shortBase(item.baseName) .. suffix,
                prefix .. (base or shortBase(item.baseName)) .. suffix }
        else header[1] = { item.name or 'Unknown Item', item.name or 'Unknown Item' } end
        local inHeader = true
        tooltip.AddLine = function(tip, height, text, ...)
            if inHeader and type(text) == 'string' then
                position = position + 1
                local expected = header[position]
                if P.enabled and expected then text = exactText(text, expected[1], expected[2]) or text end
                return scopeCall({ [text] = true }, addLine, tip, height, text, ...)
            end
            if P.enabled and blocks and #blocks > 0 and game.matchEquipmentBlockLine
                and game.translateEquipmentBlock and type(text) == 'string' and select(1, ...) == 'FONTIN SC' then
                flushFlavour(false)
                if appendEffect(pack(tip, height, text, ...)) then return end
            else flushEffects(false) end
            if P.enabled and flavour and flavour.en and #flavour.en > 0 and flavour.zh
                and select(1, ...) == 'FONTIN SC ITALIC' and type(text) == 'string'
                and plain(text) == flavour.en[#pending + 1] then
                pending[#pending + 1] = pack(tip, height, text, ...)
                if #pending == #flavour.en then flushFlavour(true) end
                return
            end
            flushFlavour(false)
            return addLine(tip, height, equipmentText(text), ...)
        end
        if separator then
            tooltip.AddSeparator = function(tip, ...)
                inHeader = false
                flushEffects(false)
                flushFlavour(false)
                return separator(tip, ...)
            end
        end
        local result = pack(pcall(original, self, tooltip, item, ...))
        local flushed = pack(pcall(function() flushEffects(false); flushFlavour(false) end))
        tooltip.AddLine, tooltip.AddSeparator = own, ownSeparator
        if result[1] and not flushed[1] then error(flushed[2], 0) end
        return returned(result)
    end
end
local function protectRows(class, ownItems)
    if not class or not class.GetRowValue or rawget(class, '_pobCnEquipmentRows') then return end
    class._pobCnEquipmentRows = true
    local original = class.GetRowValue
    class.GetRowValue = function(self, column, index, value, ...)
        local result = pack(original(self, column, index, value, ...))
        local item = ownItems and self.itemsTab.items[value] or value
        if P.enabled and column == 1 and item then result[1] = replacePrefix(result[1], item.name, E.name(item)) end
        return unpackValues(result, 1, result.n)
    end
end
local function augment(value)
    if type(value) ~= 'table' or not value.name or not value.lines or not value.slot then return nil end
    if not data or not data.itemMods or not data.itemMods.Runes[value.name] then return nil end
    local record = game.equipmentAugments and game.equipmentAugments[value.name]
    return record and record.en == value.name and record.zh or nil
end
local function emotion(value)
    if type(value) ~= 'table' or not value.emotion then return nil end
    local emotion = value.emotion
    local record = game.equipmentEmotions and game.equipmentEmotions[emotion.name]
    if not record or record.en ~= emotion.name then return nil end
    for _, candidate in pairs(data and data.emotions or {}) do
        if candidate == emotion then return record.zh end
    end
end
local function modifierLabel(control, value)
    local mod = value.mod
    local item = control._pobCnEquipmentItem
    if not mod and item and value.modList and #value.modList == 1 then mod = (item.affixes or {})[value.modList[1]] end
    if not mod or not mod[1] then return equipmentText(value.label) end
    local source, translated = {}, {}
    for _, line in ipairs(mod) do
        if type(line) ~= 'string' then return equipmentText(value.label) end
        source[#source + 1], translated[#translated + 1] = line, equipmentAffix(line) or line
    end
    local english = table.concat(source, '/')
    local start = value.label:find(english, 1, true)
    if not start then return equipmentText(value.label) end
    return value.label:sub(1, start - 1) .. table.concat(translated, '/') .. value.label:sub(start + #english)
end
function E.dropdownLabel(control, index, value)
    if control.itemsTab and control.slotName and control.items then
        local item = control.itemsTab.items[control.items[index]]
        if item then return replacePrefix(value, item.name, E.name(item)) end
        return type(value) == 'string' and (P.enabled and P.translate(value) or value) or nil
    end
    if type(value) == 'table' then
        if value.name == 'None' and value.slot == 'None' and value.lines and value.lines[1] == 'None' then
            return P.enabled and P.translate(value.label) or value.label
        end
        if value.name and value.base and data and data.itemBases
            and data.itemBases[value.name] == value.base then
            return P.enabled and (E.baseName(value.name, value.base) or value.label) or value.label
        end
        local name = augment(value)
        if name then
            return P.enabled and (name .. '  ' .. equipmentText(value.label or '')) or value.label
        end
        name = emotion(value)
        if name then return P.enabled and replacePrefix(value.label, value.emotion.name, name) or value.label end
        if control._pobCnEquipmentAffix then return P.enabled and modifierLabel(control, value) or value.label end
    end
end
local function isEquipmentDropdown(control)
    if control.itemsTab and control.slotName and control.items then return true end
    for i, value in ipairs(control.list or {}) do
        if E.dropdownLabel(control, i, value) then return true end
    end
    return false
end
local function labelsFor(control, index, value)
    local display = E.dropdownLabel(control, index, value)
    local original = type(value) == 'table' and (value.searchFilter or value.label) or value
    if not display then return original or '' end
    local extra = type(value) == 'table' and (value.name or (value.emotion and value.emotion.name)) or ''
    return plain(original or '') .. '\n' .. plain(display) .. '\n' .. (extra or '')
end
local function matchesWords(text, term)
    text = text:lower()
    for word in term:lower():gmatch('%S+') do
        if not text:find(word, 1, true) then return false end
    end
    return true
end
local function lastGlyphStart(text)
    local index = #text
    while index > 1 and text:byte(index) >= 128 and text:byte(index) < 192 do index = index - 1 end
    return index
end
local function protectDropdown(class)
    if not class or not class.Draw or rawget(class, '_pobCnEquipmentDrop') then return end
    class._pobCnEquipmentDrop = true
    local update, draw, highlights, keyDown = class.UpdateSearch, class.Draw, class.DrawSearchHighlights, class.OnSearchKeyDown
    class.UpdateSearch = function(self, ...)
        if not isEquipmentDropdown(self) then return update(self, ...) end
        controls[self] = true
        local result = pack(update(self, ...))
        if self.searchTerm and self.searchTerm ~= '' then
            for index, value in ipairs(self.list) do
                if matchesWords(labelsFor(self, index, value), self.searchTerm) then
                    self.searchInfos[index] = { matches = true, ranges = {} }
                end
            end
            self:UpdateMatchCount()
        end
        return unpackValues(result, 1, result.n)
    end
    class.OnSearchKeyDown = function(self, key, ...)
        if isEquipmentDropdown(self) then
            if key == 'BACK' and unicode(self.searchTerm) then
                self.searchTerm = self.searchTerm:sub(1, lastGlyphStart(self.searchTerm) - 1)
                self:UpdateSearch()
                return self
            elseif key == 'v' and IsKeyDown('CTRL') then
                local pasted = Paste()
                if unicode(pasted) then
                    self.searchTerm = (self.searchTerm or '') .. pasted:gsub('%c', ' ')
                    self:UpdateSearch()
                    return self
                end
            end
        end
        return keyDown(self, key, ...)
    end
    class.Draw = function(self, ...)
        if not isEquipmentDropdown(self) then return draw(self, ...) end
        controls[self] = true
        local list, ownTooltip, tooltip = self.list, rawget(self, 'tooltipFunc'), self.tooltipFunc
        local display, literal = {}, {}
        for index, value in ipairs(list) do
            local label = E.dropdownLabel(self, index, value)
            if type(value) == 'table' then
                local row = setmetatable({}, getmetatable(value))
                for key, field in pairs(value) do row[key] = field end
                row.label = label or value.label
                display[index] = row
            else display[index] = label or value end
            local actual = type(display[index]) == 'table' and display[index].label or display[index]
            if type(actual) == 'string' then literal[actual] = true end
        end
        -- Only drawing sees detached display labels. Click/Enter callbacks and
        -- tooltip builders receive original list values and original indices.
        self.list = display
        if tooltip then
            self.tooltipFunc = function(tip, mode, index)
                local value = list[index]
                local addOwn, addLine = rawget(tip, 'AddLine'), tip.AddLine
                local name = augment(value)
                tip.AddLine = function(t, height, text, ...)
                    if P.enabled and name and type(text) == 'string' then
                        text = exactText(text, value.name, name) or text
                    end
                    return addLine(t, height, equipmentText(text), ...)
                end
                local result = pack(pcall(tooltip, tip, mode, index, value))
                tip.AddLine = addOwn
                return returned(result)
            end
        end
        local result = pack(pcall(scopeCall, literal, draw, self, ...))
        self.list, self.tooltipFunc = list, ownTooltip
        return returned(result)
    end
    if highlights then
        class.DrawSearchHighlights = function(self, ...)
            -- Byte offsets for English aliases cannot highlight Chinese glyphs.
            if P.enabled and isEquipmentDropdown(self) then return end
            return highlights(self, ...)
        end
    end
end
local function prepareEdit(control)
    if not control or rawget(control, '_pobCnEquipmentSearch') then return end
    control._pobCnEquipmentSearch = true
    local keyDown = control.OnKeyDown
    control.OnKeyDown = function(self, key, ...)
        if self:IsShown() and self:IsEnabled() then
            local paste = key == 'v' and IsKeyDown('CTRL')
                or key == 'RIGHTBUTTON' and self.Object:IsMouseOver() and not self.disableRightClickPaste
            if paste then
                local text = Paste()
                if unicode(text) then
                    if self.pasteFilter then text = self.pasteFilter(text) end
                    if self.sel and self.sel ~= self.caret then self:ReplaceSel(text) else self:Insert(text) end
                    return self
                end
            end
            if unicode(self.buf) and (not self.sel or self.sel == self.caret) then
                if key == 'BACK' and self.caret > 1 then
                    local start = lastGlyphStart(self.buf:sub(1, self.caret - 1))
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
local function protectDatabase(class)
    if not class or not class.DoesItemMatchFilters or rawget(class, '_pobCnEquipmentDB') then return end
    class._pobCnEquipmentDB = true
    local filters, draw = class.DoesItemMatchFilters, class.Draw
    class.DoesItemMatchFilters = function(self, item, ...)
        local control = self.controls.search
        prepareEdit(control)
        databases[self] = true
        if not P.enabled or not unicode(control.buf) then return filters(self, item, ...) end
        local original = filters(self, item, ...)
        if original then return original end
        local mode, candidates = self.controls.searchMode.selIndex, {}
        if mode == 1 or mode == 2 then candidates[#candidates + 1] = E.name(item) or '' end
        if mode == 1 or mode == 3 then
            for _, field in ipairs({ 'buffModLines', 'enchantModLines', 'runeModLines', 'implicitModLines', 'explicitModLines' }) do
                for _, line in pairs(item[field] or {}) do
                    if item.GetModLineVariantCount and item:GetModLineVariantCount(line) > 0 then
                        local translated = equipmentAffix(line.line)
                        if translated then candidates[#candidates + 1] = translated end
                    end
                end
            end
            for _, translated in ipairs(E.effectBlockTexts(item)) do candidates[#candidates + 1] = plain(translated) end
        end
        local query = control.buf:lower():gsub('[%-%.%+%[%]%$%^%%%?%*]', '%%%0')
        local matched = false
        for _, candidate in ipairs(candidates) do
            -- A pasted displayed range such as (30-50) is literal text, not
            -- a Lua capture. Keep the native pattern fallback for queries.
            if candidate:lower():find(control.buf:lower(), 1, true) then matched = true; break end
            local ok, match = pcall(function() return candidate:lower():matchOrPattern(query) end)
            if ok and match then matched = true; break end
        end
        if not matched then return false end
        -- Native filters still decide slot/type/league/requirements/obtainability.
        -- This temporary UI query never invokes an editing callback.
        local saved = control.buf
        control.buf = ''
        local result = pack(pcall(filters, self, item, ...))
        control.buf = saved
        return returned(result)
    end
    class.Draw = function(self, ...)
        prepareEdit(self.controls.search)
        databases[self] = true
        if self._pobCnEquipmentRevision ~= P.revision then
            self._pobCnEquipmentRevision = P.revision
            self.listBuildFlag = true
        end
        return draw(self, ...)
    end
end
function E.protectBuild(build)
    local tab = build and build.itemsTab
    if not tab then return end
    tabs[tab] = true
    for _, control in pairs(tab.controls or {}) do
        if control.db and control.controls and control.controls.search then
            prepareEdit(control.controls.search)
            databases[control] = true
        end
    end
end
function E.onLanguageChanged()
    for control in pairs(controls) do control:UpdateSearch() end
    for control in pairs(databases) do control.listBuildFlag = true end
    for tab in pairs(tabs) do
        if tab.displayItem and tab.UpdateDisplayItemTooltip then tab:UpdateDisplayItemTooltip() end
    end
end
function E.protectClasses(classes)
    if not classes then return end
    protectTooltip(classes.ItemsTab)
    protectRows(classes.ItemListControl, true)
    protectRows(classes.SharedItemListControl, false)
    protectRows(classes.ItemDBControl, false)
    protectDatabase(classes.ItemDBControl)
    protectDropdown(classes.DropDownControl)
    local items = classes.ItemsTab
    if items and items.UpdateAffixControl and not rawget(items, '_pobCnEquipmentCraft') then
        items._pobCnEquipmentCraft = true
        local update = items.UpdateAffixControl
        items.UpdateAffixControl = function(self, control, ...)
            control._pobCnEquipmentAffix = true
            control._pobCnEquipmentItem = select(1, ...)
            return update(self, control, ...)
        end
    end
    if items and items.AddCustomModifierToDisplayItem and not rawget(items, '_pobCnEquipmentCustomMods') then
        items._pobCnEquipmentCustomMods = true
        local open = items.AddCustomModifierToDisplayItem
        items.AddCustomModifierToDisplayItem = function(self, ...)
            local previous = main.popups[1]
            local result = pack(open(self, ...))
            local popup = main.popups[1]
            if popup and popup ~= previous and popup.controls and popup.controls.modSelect then
                popup.controls.modSelect._pobCnEquipmentAffix = true
                popup.controls.modSelect._pobCnEquipmentItem = self.displayItem
                popup.controls.modSelect:UpdateSearch()
            end
            return unpackValues(result, 1, result.n)
        end
    end
end
return E

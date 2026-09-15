-- PoB2 Mac zh-CN display plugin. English data/IDs/calculations remain intact.
local root = ...
if _G.PoB2Chinese then return _G.PoB2Chinese end
local dictionary = dofile(root .. '/dictionary.lua')
local game = assert(loadfile(root .. '/game_text.lua'))(root)
local folded = {}
for en, zh in pairs(dictionary) do folded[en:lower()] = zh end
local function lookup(s)
    local direct = game.translateSkill(s) or dictionary[s] or folded[s:lower()]
    if direct then return direct end
    local hand, label = s:match('^(MH) (.+)$')
    if not hand then hand, label = s:match('^(OH) (.+)$') end
    if hand then
        local translated = dictionary[label] or folded[label:lower()]
        if translated then return (hand == 'MH' and '主手' or '副手') .. translated end
    end
end
local atlas = dofile(root .. '/font.lua')
local original = { draw = DrawString, width = DrawStringWidth, cursor = DrawStringCursorIndex }
local P = { enabled = true, version = '0.6.3', suppressed = 0, game = game, revision = 0 }
P.input = dofile(root .. '/mac_input.lua')
P.updates = assert(loadfile(root .. '/update_guard.lua'))(root)
local skillAdapter = assert(loadfile(root .. '/skills_cn.lua'))(P, game)
P.skills = skillAdapter
local treeAdapter = assert(loadfile(root .. '/tree_cn.lua'))(P, game)
P.tree = treeAdapter
local equipmentAdapter = assert(loadfile(root .. '/equipment_cn.lua'))(P, game)
P.equipment = equipmentAdapter
P.statCompare = assert(loadfile(root .. '/stat_compare_cn.lua'))(P, dictionary)
local wrapTooltipText = dofile(root .. '/tooltip_cn.lua')
local prefs = io.open(root .. '/disabled', 'r')
if prefs then P.enabled = false; prefs:close() end
local cache, count, textures = {}, 0, {}
local literalScopes, buttonContext, headerTextContext = {}, nil, nil
local function isLiteral(text)
    for i = #literalScopes, 1, -1 do if literalScopes[i][text] then return true end end
    return false
end
local function escapeAt(s, i)
    local rest = s:sub(i)
    return rest:match('^(%^x%x%x%x%x%x%x)') or rest:match('^(%^[0-9])')
end
local function phrase(s)
    if lookup(s) then return lookup(s) end
    local leading, middle, trailing = s:match('^(%s*)(.-)(%s*)$')
    if lookup(middle) then return leading .. lookup(middle) .. trailing end
    local word, colon = middle:match('^(.-)(:)$')
    if word and lookup(word) then return leading .. lookup(word) .. '：' .. trailing end
    local label, value = middle:match('^(.-):%s*(.+)$')
    if label and lookup(label) then
        local dynamicValue = label:lower() == 'current build' or label:lower() == 'search'
        return leading .. lookup(label) .. '：' .. (dynamicValue and value or lookup(value) or value) .. trailing
    end
    local number, name = middle:match('^(%d+)%s+(.+)$')
    if number and lookup(name) then return leading .. number .. ' ' .. lookup(name) .. trailing end
    return s
end
-- Prefer a complete dictionary sentence when color escapes split its words.
-- Preserve its initial color and final renderer state; interior emphasis becomes
-- the line's initial color, since English word positions do not map to Chinese.
local function translateLine(line)
    local plain, prefix, finalColor, internalColor = {}, {}, nil, false
    local visible, i = false, 1
    while i <= #line do
        local esc = escapeAt(line, i)
        if esc then
            finalColor = esc
            if visible then internalColor = true else prefix[#prefix + 1] = esc end
            i = i + #esc
        else
            local char = line:sub(i, i)
            plain[#plain + 1] = char
            if not visible and char:match('%s') then prefix[#prefix + 1] = char
            else visible = true end
            i = i + 1
        end
    end
    if internalColor then
        local clean = table.concat(plain)
        local _, middle, trailing = clean:match('^(%s*)(.-)(%s*)$')
        local translated = dictionary[middle] or folded[middle:lower()]
        if translated then
            return table.concat(prefix) .. translated .. trailing .. finalColor
        end
    end
    -- Unmatched sentences retain the existing per-color phrase behavior.
    local out, start = {}, 1
    i = 1
    while i <= #line do
        local esc = escapeAt(line, i)
        if esc then
            out[#out + 1] = phrase(line:sub(start, i - 1))
            out[#out + 1] = esc
            i = i + #esc; start = i
        else i = i + 1 end
    end
    out[#out + 1] = phrase(line:sub(start))
    return table.concat(out)
end
function P.translate(text)
    if not P.enabled or P.suppressed > 0 or type(text) ~= 'string' or text == '' then return text end
    if isLiteral(text) then return text end
    if cache[text] then return cache[text] end
    local official = game.translateText(text)
    if official then
        if count >= 4096 then cache, count = {}, 0 end
        cache[text], count = official, count + 1
        return official
    end
    local lines = {}
    for line in (text .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = translateLine(line) end
    local result = table.concat(lines, '\n')
    if count >= 4096 then cache, count = {}, 0 end
    cache[text], count = result, count + 1
    return result
end
local function hasGlyph(s)
    for ch in s:gmatch('[\194-\244][\128-\191]+') do if atlas.glyphs[ch] then return true end end
    return false
end
-- Tokenize UTF-8 without changing the engine's string or UTF-8 libraries.
local function tokens(s)
    local result, i = {}, 1
    while i <= #s do
        local esc = escapeAt(s, i)
        if esc then result[#result + 1] = { color = esc }; i = i + #esc
        else
            local b = s:byte(i)
            local n = b < 128 and 1 or b < 224 and 2 or b < 240 and 3 or 4
            local ch = s:sub(i, i + n - 1)
            result[#result + 1] = { text = ch, glyph = atlas.glyphs[ch] }
            i = i + n
        end
    end
    return result
end
local function tokenWidth(t, h, font)
    if t.color or t.text == '\n' then return 0 end
    if t.glyph then return t.glyph[4] / atlas.cell * h end
    return original.width(h, font, t.text)
end
local function measure(h, font, text)
    local widest, line = 0, 0
    for _, t in ipairs(tokens(text)) do
        if t.text == '\n' then widest = math.max(widest, line); line = 0
        else line = line + tokenWidth(t, h, font) end
    end
    return math.max(widest, line)
end
function DrawStringWidth(h, font, text)
    local translated = P.translate(text)
    if type(translated) ~= 'string' or not hasGlyph(translated) then return original.width(h, font, translated) end
    return measure(h, font, translated)
end
function DrawStringCursorIndex(h, font, text, cursorX, cursorY)
    -- Return indices into the ORIGINAL UTF-8 string, never the translation.
    if type(text) ~= 'string' or not hasGlyph(text) then
        local index = original.cursor(h, font, text, cursorX, cursorY)
        if type(text) == 'string' and isLiteral(text) and #literalScopes > 0 then
            literalScopes[#literalScopes][text:sub(1, index - 1) .. '...'] = true
        end
        return index
    end
    local x, lineY, index = 0, h, 1
    for _, t in ipairs(tokens(text)) do
        if t.text == '\n' then
            if cursorY <= lineY then return index end
            x, lineY = 0, lineY + h
        elseif not t.color then
            x = x + tokenWidth(t, h, font)
            if cursorY <= lineY and cursorX <= x then return index end
        end
        index = index + #(t.color or t.text)
    end
    return #text + 1
end
local function imageFor(page)
    if not textures[page] then
        local image = NewImageHandle()
        image:Load(root .. '/font-' .. page .. '.png', 'CLAMP')
        assert(image:IsValid(), 'Unable to load Chinese font atlas ' .. page)
        textures[page] = image
    end
    return textures[page]
end
function DrawString(x, y, align, h, font, text)
    -- The build header reserves a fixed English-label column for its name box.
    if headerTextContext and align == 'LEFT' and text == 'Current build:  ' .. headerTextContext then
        local name = headerTextContext
        headerTextContext = nil
        local ok, err = pcall(function()
            DrawString(x, y, align, h, font, 'Current build:')
            DrawString(x + original.width(h, font, 'Current build:  '), y, align, h, font, name)
        end)
        headerTextContext = name
        if not ok then error(err, 0) end
        return
    end
    local translated = P.translate(text)
    if type(translated) ~= 'string' or not hasGlyph(translated) then
        return original.draw(x, y, align, h, font, translated)
    end
    -- ButtonControl uses fixed bounds, so fit only its own translated caption.
    if buttonContext and text == buttonContext.label and align == 'CENTER_X' then
        local width = measure(h, font, translated)
        if width > buttonContext.width and width > 0 then
            local fitted = math.max(math.min(h, 10), h * buttonContext.width / width)
            y, h = y + (h - fitted) / 2, fitted
            if measure(h, font, translated) > buttonContext.width then
                local lines, ellipsis = {}, '…'
                local available = math.max(0, buttonContext.width - measure(h, font, ellipsis))
                for line in (translated .. '\n'):gmatch('(.-)\n') do
                    if measure(h, font, line) > buttonContext.width then
                        local clipped, used = {}, 0
                        for _, token in ipairs(tokens(line)) do
                            local advance = tokenWidth(token, h, font)
                            if used + advance > available then break end
                            clipped[#clipped + 1] = token.color or token.text
                            used = used + advance
                        end
                        line = table.concat(clipped) .. ellipsis
                    end
                    lines[#lines + 1] = line
                end
                translated = table.concat(lines, '\n')
            end
        end
    end
    local screenW = GetScreenSize()
    screenW = screenW / (GetScreenScale and GetScreenScale() or 1)
    local lineY = y
    for line in (translated .. '\n'):gmatch('(.-)\n') do
        local w = measure(h, font, line)
        local lineX = x
        if align == 'CENTER' then lineX = (screenW - w) / 2 + x
        elseif align == 'RIGHT' then lineX = screenW - w - x
        elseif align == 'CENTER_X' then lineX = x - w / 2
        elseif align == 'RIGHT_X' then lineX = x - w end
        lineX = math.floor(lineX + 0.5)
        local run = ''
        local function flush()
            if run ~= '' then
                original.draw(lineX, lineY, 'LEFT', h, font, run)
                lineX = lineX + original.width(h, font, run)
                run = ''
            end
        end
        for _, t in ipairs(tokens(line)) do
            if t.color then flush(); SetDrawColor(t.color)
            elseif t.glyph then
                flush()
                local glyph = t.glyph
                -- Atlas has four pixels of left padding, excluded from advance.
                DrawImage(imageFor(glyph[1]), lineX - h / 16, lineY, h, h,
                    glyph[2] / atlas.size, glyph[3] / atlas.size,
                    (glyph[2] + atlas.cell) / atlas.size, (glyph[3] + atlas.cell) / atlas.size)
                lineX = lineX + tokenWidth(t, h, font)
            else run = run .. t.text end
        end
        flush(); lineY = lineY + h
    end
end
-- Editing must always measure and display the exact user-entered buffer.
-- Wrap EditControl methods as they are loaded; translate only its placeholder.
local unpackValues = unpack or table.unpack
local function pack(...) return { n = select('#', ...), ... } end
local function protectEdit(class)
    if not class or rawget(class, '_pobZhProtected') or not rawget(class, 'Draw') then return end
    class._pobZhProtected = true
    for name, fn in pairs(class) do
        if type(fn) == 'function' and name:sub(1, 1) ~= '_' then
            class[name] = function(self, ...)
                local prompt, placeholder = self.prompt, self.placeholder
                -- Prompt width is also used by click handling and scroll calculations.
                self.prompt = P.translate(prompt)
                self.placeholder = P.translate(placeholder)
                P.suppressed = P.suppressed + 1
                local results = pack(pcall(fn, self, ...))
                P.suppressed = P.suppressed - 1
                self.prompt, self.placeholder = prompt, placeholder
                if not results[1] then error(results[2], 0) end
                return unpackValues(results, 2, results.n)
            end
        end
    end
end
-- Translate list display values before the original control measures/truncates them.
-- Data rows remain literal, including any clipped prefix produced by ListControl.
local function literalRow(self, column, value)
    local name = self._className
    if column == 1 and (name == 'BuildListControl' or name == 'FolderListControl') then return true end
    if name == 'SkillListControl' then return value and value.label and value.label ~= '' end
    if name == 'ItemListControl' or name == 'SharedItemListControl' or name == 'ItemDBControl' then return true end
    if name == 'ItemSetListControl' then
        local itemSet = self.itemsTab and self.itemsTab.itemSets[value]
        return itemSet and itemSet.title ~= nil
    end
    if name == 'SkillSetListControl' then
        local skillSet = self.skillsTab and self.skillsTab.skillSets[value]
        return skillSet and skillSet.title ~= nil
    end
    if name == 'PassiveSpecListControl' or name == 'BuildSetListControl' then
        return type(value) == 'table' and value.title ~= nil
    end
    return self._pobZhLiteralRows
end
local function scopedCall(scope, fn, self, ...)
    literalScopes[#literalScopes + 1] = scope
    local results = pack(pcall(fn, self, ...))
    literalScopes[#literalScopes] = nil
    if not results[1] then error(results[2], 0) end
    return unpackValues(results, 2, results.n)
end
P.withLiteralText = scopedCall
local function protectList(class)
    if not class or rawget(class, '_pobZhListProtected') or not class.Draw then return end
    class._pobZhListProtected = true
    local draw = class.Draw
    class.Draw = function(self, ...)
        local saved, getRow = rawget(self, 'GetRowValue'), self.GetRowValue
        if not getRow then return draw(self, ...) end
        local scope = {}
        self.GetRowValue = function(control, column, index, value, ...)
            local values = pack(getRow(control, column, index, value, ...))
            local result = values[1]
            if type(result) == 'string' then
                if literalRow(control, column, value) then scope[result] = true
                else result = P.translate(result) end
            end
            values[1] = result
            return unpackValues(values, 1, values.n)
        end
        local results = pack(pcall(scopedCall, scope, draw, self, ...))
        self.GetRowValue = saved
        if not results[1] then error(results[2], 0) end
        return unpackValues(results, 2, results.n)
    end
end
local function protectButton(class)
    if not class or rawget(class, '_pobZhButtonProtected') or not class.Draw then return end
    class._pobZhButtonProtected = true
    local draw = class.Draw
    class.Draw = function(self, ...)
        local previous = buttonContext
        local width = self:GetSize()
        buttonContext = { label = self:GetProperty('label'), width = math.max(1, width - 6) }
        local results = pack(pcall(draw, self, ...))
        buttonContext = previous
        if not results[1] then error(results[2], 0) end
        return unpackValues(results, 2, results.n)
    end
end
local function setTitleScope(control)
    local scope = skillAdapter.dropdownLiteralScope(control) or {}
    local build = main and main.modes and main.modes.BUILD
    if not build then return scope end
    for _, spec in ipairs({
        { 'itemsTab', 'setSelect', 'itemSets', 'itemSetOrderList' },
        { 'skillsTab', 'setSelect', 'skillSets', 'skillSetOrderList' },
        { 'treeTab', 'specSelect', 'specList' },
        { 'treeTab', 'compareSelect', 'specList' },
    }) do
        local tab = build[spec[1]]
        if tab and tab.controls and control == tab.controls[spec[2]] then
            local sets = tab[spec[3]] or {}
            for index, key in ipairs(spec[4] and tab[spec[4]] or sets) do
                local value = spec[4] and sets[key] or key
                if value and value.title ~= nil then
                    local label = control.list and control.list[index]
                    if type(label) == 'table' then label = label.label end
                    if type(label) == 'string' then scope[label] = true end
                end
            end
        end
    end
    return scope
end
local function protectDropDown(class)
    if not class or rawget(class, '_pobZhDropDownProtected') or not class.Draw then return end
    class._pobZhDropDownProtected = true
    local draw = class.Draw
    class.Draw = function(self, ...) return scopedCall(setTitleScope(self), draw, self, ...) end
end
local function protectBuild(build)
    if not build or build._pobZhBuildProtected or not build.Init then return end
    build._pobZhBuildProtected = true
    local init = build.Init
    build.Init = function(self, ...)
        local results = pack(init(self, ...))
        local control = self.controls and self.controls.buildName
        if control then
            for _, name in ipairs({ 'width', 'Draw' }) do
                local fn = control[name]
                if type(fn) == 'function' then
                    control[name] = function(control, ...)
                        local scope = {}; if self.buildName then scope[self.buildName] = true end
                        local previous = headerTextContext
                        if name == 'Draw' then headerTextContext = self.buildName end
                        local returned = pack(pcall(scopedCall, scope, fn, control, ...))
                        headerTextContext = previous
                        if not returned[1] then error(returned[2], 0) end
                        return unpackValues(returned, 2, returned.n)
                    end
                end
            end
        end
        return unpackValues(results, 1, results.n)
    end
end
local function protectClasses()
    if not common or not common.classes then return end
    protectEdit(common.classes.EditControl)
    protectList(common.classes.ListControl)
    protectButton(common.classes.ButtonControl)
    protectDropDown(common.classes.DropDownControl)
    skillAdapter.protectClasses(common.classes)
    treeAdapter.protectClasses(common.classes)
    local tooltip = common.classes.Tooltip
    if tooltip and tooltip.AddLine and not rawget(tooltip, '_pobZhGameText') then
        tooltip._pobZhGameText = true
        local addLine, check, clear = tooltip.AddLine, tooltip.CheckForUpdate, tooltip.Clear
        tooltip.Clear = function(self, ...)
            self._pobZhLiteralLines = nil
            return clear(self, ...)
        end
        tooltip.AddLine = function(self, size, text, ...)
            -- Translate complete modifiers before PoB wraps them to the tooltip width.
            local literal, first = type(text) == 'string' and isLiteral(text), #self.lines + 1
            local font = select(1, ...)
            local translated = wrapTooltipText(P.translate(text), size,
                self.maxWidth and self.maxWidth - 12,
                (main.showFlavourText and font) or 'VAR', measure)
            local results = pack(addLine(self, size, translated, ...))
            if literal then
                self._pobZhLiteralLines = self._pobZhLiteralLines or {}
                for i = first, #self.lines do
                    local line = self.lines[i].text
                    if line then self._pobZhLiteralLines[line] = true end
                end
            end
            return unpackValues(results, 1, results.n)
        end
        for _, method in ipairs({'Draw', 'GetSize'}) do
            local originalMethod = tooltip[method]
            tooltip[method] = function(self, ...)
                return scopedCall(self._pobZhLiteralLines or {}, originalMethod, self, ...)
            end
        end
        tooltip.CheckForUpdate = function(self, ...)
            local changed = check(self, ...)
            if self._pobZhRevision ~= P.revision then
                self._pobZhRevision = P.revision
                self:Clear()
                return true
            end
            return changed
        end
    end
    local items = common.classes.ItemsTab
    if items and items.AddItemTooltip and not rawget(items, '_pobZhItemNames') then
        items._pobZhItemNames = true
        local addTooltip = items.AddItemTooltip
        items.AddItemTooltip = function(self, tooltip, item, ...)
            local scope, color = {}, colorCodes and colorCodes[item.rarity] or ''
            for _, name in pairs({ item.title, item.name, item.baseName,
                item.baseName and (item.namePrefix or '') .. item.baseName .. (item.nameSuffix or '') }) do
                if type(name) == 'string' then scope[name], scope[color .. name] = true, true end
            end
            return scopedCall(scope, addTooltip, self, tooltip, item, ...)
        end
    end
    equipmentAdapter.protectClasses(common.classes)
    P.statCompare.protectClasses(common.classes)
end
local loadModule = LoadModule
LoadModule = function(name, ...)
    local updateSnapshot = name == 'UpdateApply' and P.updates.capture()
    local results = pack(loadModule(name, ...))
    if name == 'UpdateApply' then P.updates.restore(updateSnapshot) end
    protectClasses()
    if name == 'Modules/Build' then
        protectBuild(results[1])
        skillAdapter.protectBuild(results[1])
        treeAdapter.protectBuild(results[1])
        equipmentAdapter.protectBuild(results[1])
        P.statCompare.protectBuild(results[1])
    end
    return unpackValues(results, 1, results.n)
end
protectClasses()
function P.toggle()
    if skillAdapter.beforeLanguageToggle then skillAdapter.beforeLanguageToggle() end
    P.enabled = not P.enabled
    P.revision = P.revision + 1
    cache, count = {}, 0
    if equipmentAdapter.onLanguageChanged then equipmentAdapter.onLanguageChanged() end
    if P.enabled then os.remove(root .. '/disabled')
    else local f = io.open(root .. '/disabled', 'w'); if f then f:write('disabled\n'); f:close() end end
    return P.enabled
end
P.installCallbacks = function()
    if P.callbackLaunch == launch then return end
    P.callbackLaunch = launch
    P.input.install(launch)
    local old = launch.OnKeyDown
    launch.OnKeyDown = function(self, key, ...)
        if key == 'F10' then P.toggle(); return end
        if old then return old(self, key, ...) end
    end
end
P.measure = measure
_G.PoB2Chinese = P
return P

-- Insert presentation-only line breaks before the native tooltip lays out lines.
-- PoB's word wrapper cannot split a Chinese sentence that contains no spaces.
local function colorAt(text, index)
    local rest = text:sub(index)
    return rest:match('^(%^x%x%x%x%x%x%x)') or rest:match('^(%^[0-9])')
end

local function characterAt(text, index)
    local first = text:byte(index)
    local length = first < 128 and 1 or first < 224 and 2 or first < 240 and 3 or 4
    local value = first < 128 and first or first % (2 ^ (7 - length))
    for offset = 1, length - 1 do
        local byte = text:byte(index + offset)
        if not byte or byte < 128 or byte > 191 then return text:sub(index, index), first end
        value = value * 64 + byte - 128
    end
    return text:sub(index, index + length - 1), value
end

local function cjk(codepoint)
    return codepoint >= 0x2E80 and codepoint <= 0x9FFF
        or codepoint >= 0xF900 and codepoint <= 0xFAFF
        or codepoint >= 0x20000 and codepoint <= 0x323AF
end

local function tokenize(text)
    local units, ascii, hasChinese, index = {}, {}, false, 1
    local function flush()
        if #ascii > 0 then units[#units + 1] = table.concat(ascii); ascii = {} end
    end
    while index <= #text do
        local color = colorAt(text, index)
        if color then
            -- Keep an internal colour escape with its ASCII word/number.
            if #ascii > 0 then ascii[#ascii + 1] = color else units[#units + 1] = color end
            index = index + #color
        else
            local character, codepoint = characterAt(text, index)
            hasChinese = hasChinese or cjk(codepoint)
            if codepoint > 32 and codepoint < 127 then
                ascii[#ascii + 1] = character
            else
                flush()
                units[#units + 1] = character
            end
            index = index + #character
        end
    end
    flush()
    return units, hasChinese
end

return function(text, height, width, font, measure)
    if type(text) ~= 'string' or type(width) ~= 'number' or width <= 0 then return text end
    local output = {}
    for line in (text .. '\n'):gmatch('(.-)\n') do
        local units, hasChinese = tokenize(line)
        if not hasChinese or measure(height, font, line) <= width then
            output[#output + 1] = line
        else
            local parts, used = {}, 0
            local function append(unit)
                local advance = measure(height, font, unit)
                if advance > 0 and used > 0 and used + advance > width then
                    parts[#parts + 1] = '\n'; used = 0
                end
                parts[#parts + 1] = unit
                used = used + advance
            end
            for _, unit in ipairs(units) do
                if measure(height, font, unit) <= width then
                    -- ASCII words, signed decimals, ranges and percentages stay
                    -- whole whenever they can fit on an otherwise empty line.
                    append(unit)
                else
                    -- A very long ASCII token can be wider than the whole box.
                    -- Split it only as a last resort, never inside UTF-8/colour.
                    local index = 1
                    while index <= #unit do
                        local token = colorAt(unit, index) or characterAt(unit, index)
                        append(token)
                        index = index + #token
                    end
                end
            end
            output[#output + 1] = table.concat(parts)
        end
    end
    return table.concat(output, '\n')
end

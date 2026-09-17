-- Narrow compatibility for explicit-plus resistance lines emitted by the
-- PoE2DB WeGame converter. Keep original item text and native parser precedence.
local C = {}
local elements = { Fire = true, Cold = true, Lightning = true, Chaos = true }
function C.canonical(line)
    if type(line) ~= 'string' then return nil end
    -- Minus-only and unsigned "is" forms are native OVERRIDE mechanics.
    local element, value = line:match('^(%a+) Resistance is (%+%d+)%%$')
    if elements[element] then return value .. '% to ' .. element .. ' Resistance' end
end
function C.wrap(parse)
    return function(line, ...)
        local mods, extra = parse(line, ...)
        if mods and not extra then return mods, extra end
        local canonical = C.canonical(line)
        if canonical then
            local compatible, remaining = parse(canonical, ...)
            if compatible and not remaining then return compatible, remaining end
        end
        return mods, extra
    end
end
return C

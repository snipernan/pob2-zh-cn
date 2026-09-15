-- Translate presentation labels before the native comparison formatter joins
-- them with signed numbers. The original code still selects/computes/colors
-- every difference; neither the source stat list nor the outputs are modified.
local P, dictionary = ...
local M, folded = {}, {}
for en, zh in pairs(dictionary) do folded[en:lower()] = zh end
function M.label(text)
    return type(text)=='string' and (dictionary[text] or folded[text:lower()] or text) or text
end
local function itemName(owner, text)
    for _, item in pairs(owner.itemsTab and owner.itemsTab.items or {}) do
        local color = colorCodes and colorCodes[item.rarity] or ''
        if item.name and text == color .. item.name .. '^7' then
            return color .. (P.equipment.name(item) or item.name) .. '^7'
        end
    end
    return text -- Unknown/custom text is never passed through word substitution.
end
function M.header(owner, text)
    if type(text)~='string' then return text end
    local lines={}
    for line in (text..'\n'):gmatch('(.-)\n') do
        local color=line:match('^(%^x%x%x%x%x%x%x)') or line:match('^(%^%d)') or ''
        local body=line:sub(#color+1)
        local translated=M.label(body)
        if translated==body then
            local slot=body:match('^Equipping this item in (.-) will give you:$')
            if slot then translated=M.label('Equipping this item in')..' '..M.label(slot)..' '..M.label('will give you:') end
            slot=body:match('^Removing this item from (.-) will give you:$')
            if slot then translated=M.label('Removing this item from')..' '..M.label(slot)..' '..M.label('will give you:') end
            local replaced=body:match('^%(replacing (.*)%)$')
            if replaced then translated='（'..M.label('replacing')..' '..itemName(owner,replaced)..'）' end
        end
        lines[#lines+1]=color..translated
    end
    return table.concat(lines,'\n')
end
local function pack(...) return {n=select('#',...),...} end
function M.protectBuild(owner)
    if not owner or not owner.CompareStatList or rawget(owner,'_pobCnStatCompare') then return end
    owner._pobCnStatCompare=true
    local compare=owner.CompareStatList
    owner.CompareStatList=function(self, tooltip, statList, actor, baseOutput, compareOutput, header, nodeCount, ...)
        if not P.enabled then return compare(self,tooltip,statList,actor,baseOutput,compareOutput,header,nodeCount,...) end
        local display={}
        for index, entry in ipairs(statList) do
            local copy=setmetatable({},getmetatable(entry))
            for key,value in pairs(entry) do copy[key]=value end
            copy.label=M.label(entry.label)
            display[index]=copy
        end
        local own, add=rawget(tooltip,'AddLine'),tooltip.AddLine
        tooltip.AddLine=function(tip,height,text,...)
            if text==header then text=M.header(self,text)
            elseif nodeCount and type(text)=='string' then
                text=text:gsub(' per point%]$',function() return ' '..M.label('per point')..']' end)
            end
            if type(text)=='string' and P.withLiteralText then
                return P.withLiteralText({[text]=true},add,tip,height,text,...)
            end
            return add(tip,height,text,...)
        end
        local result=pack(pcall(compare,self,tooltip,display,actor,baseOutput,compareOutput,header,nodeCount,...))
        tooltip.AddLine=own
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
end
function M.protectClasses(classes)
    if classes then M.protectBuild(classes.CompareEntry) end
end
return M

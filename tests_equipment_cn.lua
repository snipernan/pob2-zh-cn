-- Run after integration.lua, before the skill tests replace the test build.
local P, tab = assert(PoB2Chinese), build.itemsTab
assert(P.enabled)
local item = assert(tab.items[1], 'The integration fixture must contain a ring')
local before = assert(build:SaveDB('test'))
local tooltip = new('Tooltip')
local function show()
    if tooltip:CheckForUpdate(item) then tab:AddItemTooltip(tooltip, item, nil, false, 500) end
    local lines = {}
    for _, line in ipairs(tooltip.lines) do if line.text then lines[#lines+1]=StripEscapes(line.text) end end
    return table.concat(lines, '\n')
end
local chinese = show()
assert(chinese:find('+50 生命上限', 1, true), 'Real item tooltip must use the official maximum-life wording')
assert(chinese:find('火焰抗性 +25%', 1, true), 'Real item tooltip keeps the signed resistance roll')
P.toggle()
local english = show()
assert(english:find('+50 to maximum Life',1,true), 'Cached tooltip must rebuild when switching to English')
assert(not english:find('生命上限',1,true))
P.toggle()
assert(show():find('+50 生命上限',1,true))
assert(build:SaveDB('test') == before, 'Tooltip translation and language changes must not change exported equipment/build data')
local title = item.title
item.title = 'Fireball'
tooltip:Clear(true)
tab:AddItemTooltip(tooltip,item,nil,false,500)
assert(StripEscapes(tooltip.lines[1].text)=='Fireball', 'An item title is not a skill name')
local oldDraw, displayedTitle = DrawString, false
DrawString = function(x,y,a,h,f,text)
    if text == tooltip.lines[1].text then
        assert(P.translate(text) == text, 'The cached title must remain literal during drawing')
        displayedTitle = true
    end
    return oldDraw(x,y,a,h,f,text)
end
tooltip:Draw(20,20,20,20,{x=0,y=0,width=1920,height=1080})
DrawString = oldDraw
assert(displayedTitle, 'Exercise the actual cached tooltip draw path')
item.title = title
print('PASS real equipment: official signed affixes before wrapping; cached F10 refresh; literal item titles; unchanged English export')

-- Integration regression checks using the actual 0.23.1 controls, without a GUI.
local root = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
assert(build and main and PoB2Chinese, 'Run this script after integration.lua in the same Lua state')
local view = {x=0,y=0,width=1920,height=1080}
local oldCursor, oldViewport, oldIndex = GetCursorPos, SetViewport, DrawStringCursorIndex
local edit = new('EditControl', nil, {0,0,180,20}, 'Save', 'Search')
local promptWidth = DrawStringWidth(16, 'VAR', '搜索')
local originX = 2 + promptWidth + 8
GetCursorPos = function() return originX + 5, 5 end
local drawnOrigin, hitX
SetViewport = function(x,y,w,h) if x then drawnOrigin=x end end
DrawStringCursorIndex = function(h,font,text,x,y) hitX=x; return 1 end
edit:Draw(view, true)
assert(drawnOrigin == originX, 'Real EditControl draws with the translated prompt width')
edit:OnKeyDown('LEFTBUTTON')
assert(hitX == 5, 'Real EditControl click uses the SAME translated text origin')
assert(edit.buf=='Save' and edit.prompt=='Search', 'Real edit retains exact data and prompt')
GetCursorPos, SetViewport, DrawStringCursorIndex = oldCursor, oldViewport, oldIndex
print('PASS real EditControl: translated draw/click origin; literal input')

-- A vertical list reserves 20 pixels for its scrollbar: 92 gives a 72-pixel column.
local list = new('ListControl', nil, {0,0,92,100}, 16, 'VERTICAL', false, {'Average Hit'})
function list:GetRowValue(column,index,value) return value end
local getRow, oldDraw = list.GetRowValue, DrawString
local rows = {}
DrawString = function(x,y,align,h,font,text)
    if type(text)=='string' and text:find('平均',1,true) then rows[#rows+1]={text=text,h=h,font=font} end
    return oldDraw(x,y,align,h,font,text)
end
list:Draw(view,true)
DrawString = oldDraw
assert(#rows==1 and rows[1].text:find('...',1,true), 'Real ListControl clips translated text')
assert(DrawStringWidth(rows[1].h,rows[1].font,rows[1].text)<=list.colList[1]._width-2, 'Clipped translated row stays within its column')
assert(list.list[1]=='Average Hit' and list.GetRowValue==getRow, 'List data and row method are restored')
print('PASS real ListControl: UTF-8 clipping; column fit; unchanged source row')

local name = build.buildName
build.buildName='Save'
local width=build.controls.buildName:GetSize()
assert(build.strWidth==32, 'Build header measures the original custom name, not its translation')
build.buildName=name
print('PASS real build header: exact custom name width')

local root = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
local calls, color, images = {}, {1, 1, 1, 1}, 0
function DrawString(x, y, align, h, font, s) calls[#calls+1] = {x=x,y=y,height=h,text=s} end
function DrawStringWidth(h, font, s) return #s * h / 2 end
function DrawStringCursorIndex(h, font, s, x, y) return math.floor(x / (h / 2)) + 1 end
function GetDrawColor() return unpack(color) end
function SetDrawColor(...) color = {...} end
function GetScreenSize() return 2000, 1600 end
function GetScreenScale() return 2 end
function NewImageHandle()
    return { Load=function(self,p) self.path=p end, IsValid=function() return true end }
end
function DrawImage(image,x,y,w,h,...) images=images+1; calls[#calls+1]={x=x,y=y,height=h,image=image.path} end
common = { classes = { EditControl = {
    Draw=function(self) DrawString(0,0,'LEFT',16,'VAR',self.buf); DrawString(0,20,'LEFT',16,'VAR',self.prompt) end,
    Width=function(self) return DrawStringWidth(16,'VAR',self.buf) end,
    PromptWidth=function(self) return DrawStringWidth(16,'VAR',self.prompt) end,
    DrawPromptWidth=function(self) self.drawPromptWidth = self:PromptWidth(); self.clickPromptWidth = self:OnKeyDown() end,
    OnKeyDown=function(self) return DrawStringWidth(16,'VAR',self.prompt) end,
    Fail=function() error('expected failure') end
}}}
common.classes.ListControl = {
    Draw=function(self)
        local text = self:GetRowValue(1,1,self.value)
        if DrawStringWidth(16,'VAR',text) > self.width then
            local index = DrawStringCursorIndex(16,'VAR',text,self.width-DrawStringWidth(16,'VAR','...'),0)
            text = text:sub(1,index-1)..'...'
        end
        self.displayed = text
        DrawString(0,0,'LEFT',16,'VAR',text)
        if self.fail then error('list failure') end
    end
}
common.classes.ButtonControl = {
    Draw=function(self) DrawString(50,20,'CENTER_X',16,'VAR',self:GetProperty('label')) end
}
common.classes.DropDownControl = {
    Draw=function(self)
        self.displayed = PoB2Chinese.translate(self.list[1])
        DrawString(0,0,'LEFT',16,'VAR',self.list[1])
    end
}
function LoadModule() return nil, 'second', nil end
launch = { OnKeyDown=function() return 'original' end }
local P = assert(loadfile(root .. '/payload/init.lua'))(root .. '/payload')
assert(P.translate('Save') == '保存')
assert(P.translate('^xABCDEFSave\n^7Life: 1234') == '^xABCDEF保存\n^7生命：1234')
assert(P.translate('  Configuration  ') == '  配置  ')
assert(P.translate('https://example.org/Save') == 'https://example.org/Save')
assert(P.translate('Fireball has 25% increased damage') == 'Fireball has 25% increased damage')
assert(DrawStringWidth(16,'VAR','Save') == DrawStringWidth(16,'VAR','保存'))
assert(DrawStringWidth(16,'VAR','保存\n生命：1234') == DrawStringWidth(16,'VAR','生命：1234'))
assert(DrawStringCursorIndex(16,'VAR','保存',0,0)==1)
assert(DrawStringCursorIndex(16,'VAR','保存',15,0)==4, 'UTF-8 byte cursor index')
assert(DrawStringCursorIndex(16,'VAR','保存',100,0)==7)
assert(P.translate('^7MH Average Hit:')=='^7主手平均击中伤害：')
DrawString(0,10,'CENTER',16,'VAR','Save')
local width = DrawStringWidth(16,'VAR','Save')
assert(math.abs(calls[1].x - (math.floor((1000-width)/2+0.5)-1)) < 0.001, 'Retina center alignment')
assert(images == 2, 'Chinese glyph rendering')
calls = {}
DrawString(100,20,'RIGHT_X',16,'VAR','^1Save')
assert(color[1] == '^1', 'Color escape state preserved like native DrawString')
local edit = setmetatable({buf='Save',prompt='Search'}, {__index=common.classes.EditControl})
assert(edit:Width() == 32, 'Editing width must use literal buffer')
calls = {}; edit:Draw()
assert(calls[1].text == 'Save', 'Do not translate editable data')
assert(edit.buf == 'Save' and edit.prompt == 'Search', 'Restore placeholder after draw')
assert(not pcall(edit.Fail, edit))
assert(P.suppressed == 0, 'Error restores suppression state')
assert(select('#', LoadModule('Other')) == 3, 'Preserve nil return values')
P.installCallbacks()
assert(launch:OnKeyDown('A') == 'original')
launch:OnKeyDown('F10'); assert(not P.enabled and P.translate('Save') == 'Save')
launch:OnKeyDown('F10'); assert(P.enabled and P.translate('Save') == '保存')
-- Prompt measurements must match during mouse handling and nested draw calls.
assert(edit:PromptWidth() == DrawStringWidth(16,'VAR','搜索'))
assert(edit:OnKeyDown() == edit:PromptWidth())
edit:DrawPromptWidth()
assert(edit.drawPromptWidth == edit.clickPromptWidth)
assert(edit.prompt == 'Search' and edit.buf == 'Save')
assert(P.translate('Current build: Save') == '当前配装：Save')
assert(P.translate('Search: Save') == '搜索：Save')
-- Fixed-width lists receive the translated UTF-8 string BEFORE byte-safe clipping.
local row = setmetatable({width=65,value={}}, {__index=common.classes.ListControl})
function row:GetRowValue() return 'Average Hit' end
local getRow = row.GetRowValue
row:Draw()
assert(row.displayed:find('平均',1,true) and not row.displayed:find('Average',1,true))
assert(DrawStringWidth(16,'VAR',row.displayed) <= row.width)
assert(row.GetRowValue == getRow)
row.fail=true; assert(not pcall(row.Draw,row)); row.fail=nil
assert(row.GetRowValue == getRow and P.translate('Save') == '保存', 'Error restores row hook and literal scope')
-- User-defined names must remain literal even when they match dictionary labels.
local named = setmetatable({_className='BuildListControl',width=100,value={buildName='Save'}}, {__index=common.classes.ListControl})
function named:GetRowValue() return self.value.buildName end
calls={}; named:Draw()
assert(named.displayed == 'Save' and calls[1].text == 'Save')
local customSet={title='Save'}
local dropdown=setmetatable({list={'Save'}},{__index=common.classes.DropDownControl})
main={modes={BUILD={itemsTab={controls={setSelect=dropdown},itemSets={[1]=customSet},itemSetOrderList={1}}}}}
dropdown:Draw(); assert(dropdown.displayed=='Save' and dropdown.list[1]=='Save')
customSet.title=nil; dropdown.list[1]='Default'
dropdown:Draw(); assert(dropdown.displayed=='默认', 'Untitled default set label remains translatable')
-- Fit translated button captions within their fixed bounds and restore context.
local button=setmetatable({label='Average Hit'}, {__index=common.classes.ButtonControl})
function button:GetProperty(name) return self[name] end
function button:GetSize() return 60,20 end
calls={}; button:Draw()
assert(calls[1].height >= 10 and calls[1].height < 16 and calls[1].y > 20, 'Long button caption shrinks and stays centered')
local last=calls[#calls]; assert(last.x+last.height <= 82, 'Translated button caption stays inside button')
calls={}; DrawString(0,0,'LEFT',16,'VAR','Average Hit'); assert(calls[1].height==16)
P.installCallbacks(); launch:OnKeyDown('F10'); assert(not P.enabled)
launch:OnKeyDown('F10'); assert(P.enabled, 'Callback installation is idempotent')
-- Color codes inside a complete sentence must not prevent dictionary lookup.
local coloredSentence = 'Are you on Full ^xE05030Life?'
local coloredTranslation = '是否满血？^xE05030'
assert(P.translate(coloredSentence) == coloredTranslation)
assert(P.translate('Are you always on Full ^xE05030Life?') == '是否始终满血？^xE05030')
assert(P.translate('^7' .. coloredSentence) == '^7' .. coloredTranslation)
assert(P.translate('^2Are you ^1on Full ^xE05030Life?') == '^2' .. coloredTranslation)
assert(P.translate('  ^7' .. coloredSentence .. '  ') == '  ^7是否满血？  ^xE05030')
assert(P.translate('^7' .. coloredSentence .. '\nLife\n') == '^7' .. coloredTranslation .. '\n生命\n')
assert(P.translate('Unknown ^xE05030sentence?') == 'Unknown ^xE05030sentence?', 'Unmatched colored sentence remains intact')
assert(P.translate('10 ^1Life') == '10 ^1生命', 'Numeric prefix keeps existing color semantics')
assert(P.translate('^7Life: ^11234') == '^7生命： ^11234', 'Colored label/value keeps existing phrase behavior')
assert(P.translate(coloredSentence) == coloredTranslation, 'Cached colored sentence')
P.suppressed = 1
assert(P.translate(coloredSentence) == coloredSentence, 'Edit suppression bypasses cached translation')
P.suppressed = 0
assert(P.translate(coloredSentence) == coloredTranslation)
P.enabled = false; assert(P.translate(coloredSentence) == coloredSentence); P.enabled = true
calls={}; DrawString(0,0,'LEFT',16,'VAR','^7' .. coloredSentence .. '\nLife')
assert(color[1] == '^xE05030', 'Translated sentence preserves final draw color across lines')
local dict = dofile(root .. '/payload/dictionary.lua')
local atlas = dofile(root .. '/payload/font.lua')
local n=0
for en, zh in pairs(dict) do
    n=n+1
    assert(P.translate(en)==zh, en)
    for ch in zh:gmatch('[\194-\244][\128-\191]+') do assert(atlas.glyphs[ch], 'Missing glyph: '..ch) end
end
print('PASS: '..n..' translations; complete glyph coverage; colored full sentences, color, Retina alignment, multiline width, edit/prompt protection, list clipping, custom names, button fit, toggle, module returns')

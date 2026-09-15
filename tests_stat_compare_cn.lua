-- Run with the real installed core after integration.lua; all fixtures isolated.
local root=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*)/'))
local P,M,json=assert(PoB2Chinese),assert(PoB2Chinese.statCompare),require('dkjson')
local before=build:SaveDB('stat-comparison')
local viewBefore=build.viewMode
if not common.classes.CompareEntry then LoadModule('Classes/CompareEntry') end
local originalLabels={}
local function labels()
 local rows={}
 for _,list in ipairs({build.displayStats,build.minionDisplayStats}) do
  for _,entry in ipairs(list) do rows[#rows+1]=(entry.stat or '')..'|'..(entry.label or '') end
 end
 return table.concat(rows,'\n')
end
local labelSnapshot=labels()
local atlas=dofile(root..'/payload/font.lua')
local unique,count={},0
for _,list in ipairs({build.displayStats,build.minionDisplayStats}) do
 for _,entry in ipairs(list) do
  if entry.label then
   assert(M.label(entry.label):find('[\128-\255]'),'Missing comparison label: '..entry.label)
   for ch in M.label(entry.label):gmatch('[\194-\244][\128-\191]+') do assert(atlas.glyphs[ch],'Missing comparison glyph: '..ch) end
   if not unique[entry.label] then unique[entry.label]=true;count=count+1 end
  end
 end
end
local actor={mainSkill={activeEffect={statSet={skillFlags=setmetatable({},{__index=function()return true end})}}}}
local function capture(owner,list,base,other,header,points,enabled)
 local oldEnabled=P.enabled;P.enabled=enabled
 local tip={lines={}}
 function tip:AddLine(height,text) self.lines[#self.lines+1]={height=height,text=text} end
 local add=tip.AddLine
 local n=owner:CompareStatList(tip,list,actor,base,other,header,points)
 P.enabled=oldEnabled
 assert(tip.AddLine==add,'Restore tooltip method after comparison')
 return tip.lines,n
end
local function values(text)
 local result={}
 for number in StripEscapes(text):gmatch('[%+%-]?%d[%d,%.]*%%?') do result[#result+1]=number end
 return table.concat(result,'|')
end
-- Compare every native numeric stat format in both directions. Conditions are
-- separately exercised below; this corpus fixture forces each label to render.
local rendered=0
for _,owner in ipairs({build,assert(common.classes.CompareEntry)}) do
 for _,list in ipairs({build.displayStats,build.minionDisplayStats}) do
  for _,entry in ipairs(list) do
   if entry.stat and not entry.childStat and entry.stat~='SkillDPS' then
    local row={};for k,v in pairs(entry) do row[k]=v end;row.condFunc=nil
    for _,diff in ipairs({12.345,-12.345}) do
     local a,b={[row.stat]=100},{[row.stat]=100+diff}
     local snap=json.encode({a,b})
     local en,n1=capture(owner,{row},a,b,'^7Player:',3,false)
     local cn,n2=capture(owner,{row},a,b,'^7Player:',3,true)
     assert(n1==1 and n2==1 and #en==#cn)
     assert(cn[1].text=='^7玩家：')
     assert(cn[2].text:find(M.label(entry.label),1,true),'Native comparison omitted translated metric')
     assert(values(en[2].text)==values(cn[2].text),'Changed signed delta, precision or percentages: '..entry.label)
     assert(en[2].text:match('^(%^x%x%x%x%x%x%x)')==cn[2].text:match('^(%^x%x%x%x%x%x%x)'),'Changed improvement/degradation color')
     if en[2].text:find(' per point]',1,true) then assert(cn[2].text:find(' 每点]',1,true)) end
     assert(json.encode({a,b})==snap,'Changed calculation output tables')
     rendered=rendered+1
    end
   end
  end
 end
end
-- Existing zero/threshold, child, skill/condition and lower-is-better semantics.
local probe={{stat='A',label='Cast Time',fmt='.2fs',lowerIsBetter=true,compPercent=true},
 {stat='B',label='Life',fmt='d',childStat=true},
 {stat='C',label='Mana',fmt='d',condFunc=function()return false end},
 {stat='D',label='Fire Max Hit',fmt='d',flag='blocked'},
 {stat='SkillDPS',label='Total DPS',fmt='d'}}
actor.mainSkill.activeEffect.statSet.skillFlags.blocked=false
local en,n1=capture(build,probe,{A=2,B=0,C=0,D=0,SkillDPS=0},{A=1,B=10,C=10,D=10,SkillDPS=10},'^7Player:',nil,false)
local cn,n2=capture(build,probe,{A=2,B=0,C=0,D=0,SkillDPS=0},{A=1,B=10,C=10,D=10,SkillDPS=10},'^7Player:',nil,true)
assert(n1==1 and n2==1 and cn[2].text==colorCodes.POSITIVE..'-1.00s 施法时间 (-50.0%)')
local empty,n=capture(build,probe,{A=1},{A=1.0001},'^7Player:',nil,true)
assert(n==0 and #empty==0)
local unknown={{stat='A',label='Future Metric',fmt='d'}}
local unknownLines=capture(build,unknown,{A=0},{A=3},'^7Player:',nil,true)
assert(unknownLines[2].text:find('Future Metric',1,true),'Unknown labels must remain literal')
-- Failure during construction must restore the borrowed method and original rows.
local failure={lines={},AddLine=function()error('comparison fixture error')end}
local method=failure.AddLine
assert(not pcall(build.CompareStatList,build,failure,probe,actor,{A=2},{A=1},'^7Player:'))
assert(failure.AddLine==method and labels()==labelSnapshot)
-- Real item replacement/removal tooltip reaches the comparison adapter.
build.viewMode='ITEMS'
local tab=build.itemsTab
local ring=assert(tab.items[1])
local tip=new('Tooltip')
tab:AddItemTooltip(tip,ring,nil,false,650)
local text={}
for _,line in ipairs(tip.lines) do if line.text then text[#text+1]=StripEscapes(line.text) end end
text=table.concat(text,'\n')
local observed=assert(io.open(root..'/test-output/stat-comparison/item-tooltip.txt','w'));observed:write(text);observed:close()
assert(text:find('属性变化：',1,true),'Actual comparison headings translated')
local englishTip=new('Tooltip')
P.enabled=false;tab:AddItemTooltip(englishTip,ring,nil,false,650);P.enabled=true
local englishRows={}
for _,line in ipairs(englishTip.lines) do if line.text then englishRows[#englishRows+1]=StripEscapes(line.text) end end
local englishText=table.concat(englishRows,'\n')
local lifeDelta=assert(englishText:match('(%-%d+) Total Life'),'Native fixture must produce a life removal delta')
assert(text:find(lifeDelta..' '..M.label('Total Life'),1,true),'Actual removal delta must match native calculation and use the Chinese metric')
assert(not text:find('will give you:',1,true) and not text:find('Life Recoverable',1,true))
assert(M.header(build,'^7Equipping this item in Ring 1 will give you:')=='^7将此装备放入 戒指 1 后的属性变化：')
assert(M.header(build,'(replacing ^xabcdefFuture Custom Name^7)')=='（替换 ^xabcdefFuture Custom Name^7）')
build.viewMode=viewBefore
assert(labels()==labelSnapshot and build:SaveDB('stat-comparison')==before,'Comparisons changed labels or exported build')
local file=assert(io.open(root..'/test-output/stat-comparison/coverage.json','w'))
file:write(json.encode({labels=count,numericComparisons=rendered,untranslatedLabels=0,sourceLabelsUnchanged=true,outputAndExportUnchanged=true},{indent=true}));file:close()
print('PASS stat comparison: '..count..' labels; '..rendered..' native player/minion/CompareEntry comparisons; signed deltas, percentages, per-point values, colors, conditions, errors and actual item tooltip/export')

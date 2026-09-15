-- Run actual installed PoB Lua views with its headless drawing adapter.
-- File writes are redirected to an isolated scratch directory.
local root = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
arg = {}
local mac = assert(os.getenv('POB2_MAC_LIB'), 'Set POB2_MAC_APP when running integration tests') .. '/'
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path
package.cpath = mac .. '?.dylib;' .. package.cpath
local file = assert(io.open('HeadlessWrapper.lua'))
local source = file:read('*a'); file:close()
source = source:gsub('^#[^\n]*\n', '')
local pre = [[
function GetScriptPath() return ROOT .. '/test-user' end
function GetRuntimePath() return ROOT .. '/test-user' end
function GetUserPath() return ROOT .. '/test-user' end
local nativeOpen = io.open
io.open = function(path, mode)
    if mode and mode:find('[wa+]') then
        assert(path:sub(1, #ROOT) == ROOT, 'Unexpected test write: '..path)
    end
    return nativeOpen(path, mode)
end
io.read = function() error('PoB startup failed: ' .. tostring(launch.promptMsg)) end
local function countChars(s) local _, n = s:gsub('[^\128-\191]', ''); return n end
function DrawStringWidth(h, font, s) return countChars(s:gsub('%^x%x%x%x%x%x%x',''):gsub('%^%d',''))*h/2 end
function GetDrawLayer() return 0, 0 end
function NewArtHandle() return { Size=function() return 1,1 end } end
local imageDraws = 0
local drawImage = DrawImage
DrawImage = function(...) imageDraws = imageDraws + 1; return drawImage(...) end
_G.getImageDraws = function() return imageDraws end
-- Do not load the live installation's bootstrap/preferences during a test.
local launchFile = assert(nativeOpen('Launch.lua', 'r'))
local launchSource = launchFile:read('*a'); launchFile:close()
launchSource = launchSource:gsub('\r\n', '\n')
launchSource = launchSource:gsub('\n%-%- BEGIN POB2 ZH%-CN BOOTSTRAP\n.-%-%- END POB2 ZH%-CN\n', '')
assert(not launchSource:find('BEGIN POB2 ZH-CN', 1, true), 'Unrecognized installed bootstrap')
launchSource = launchSource:gsub('^#[^\n]*\n', '')
assert(loadstring(launchSource, '@Launch.lua'))()
-- Match the installed bootstrap: load after Launch defines callbacks,
-- before the engine calls OnInit and loads the actual controls.
local plugin = assert(loadfile(ROOT .. '/payload/init.lua'))(ROOT .. '/payload')
plugin.installCallbacks()
]]
pre = pre:gsub('ROOT', function() return string.format('%q', root) end)
source = source:gsub('dofile%("Launch.lua"%)', function() return pre end, 1)
assert(loadstring(source, '@headless-integration'))()
assert(not launch.promptMsg, tostring(launch.promptMsg))
loadBuildFromXML([[<PathOfBuilding2>
<Build targetVersion="0_1" level="65" className="Sorceress" ascendClassName="None" mainSocketGroup="1" viewMode="SKILLS"/>
<Skills activeSkillSet="1"><SkillSet id="1"><Skill enabled="true" label="Save" mainActiveSkill="1">
<Gem nameSpec="Fireball" level="10" quality="0" enabled="true"/>
</Skill></SkillSet></Skills>
<Items><Item id="1">Rarity: NORMAL
Gold Ring
Implicits: 0
+50 to maximum Life
+25% to Fire Resistance
</Item><ItemSet id="1"><Slot name="Ring 1" itemId="1"/></ItemSet></Items>
</PathOfBuilding2>]], 'Save')
assert(not launch.promptMsg, tostring(launch.promptMsg))
local seen = {}
local draw = DrawString
DrawString = function(x,y,align,h,font,s)
    if PoB2Chinese.enabled and PoB2Chinese.suppressed==0 and type(s)=='string' and PoB2Chinese.translate(s) == s and s:find('%a%a%a') then seen[s] = true end
    return draw(x,y,align,h,font,s)
end
local baseline
local function snapshot()
    local result = {}
    for k,v in pairs(build.calcsTab.mainOutput or {}) do
        if type(v) == 'number' then result[#result+1] = k..'='..tostring(v) end
    end
    table.sort(result)
    return table.concat(result,'\n')
end
for _, mode in ipairs({'IMPORT','NOTES','CONFIG','TREE','SKILLS','ITEMS','CALCS','PARTY'}) do
    build.viewMode = mode
    runCallback('OnFrame')
    assert(not launch.promptMsg, tostring(launch.promptMsg))
    print('PASS view: '..mode)
end
baseline = snapshot()
assert(#baseline > 0, 'Calculation snapshot must not be empty')
assert((build.calcsTab.mainOutput.CombinedDPS or 0) > 0, 'Fixture must have real skill damage')
assert(build.skillsTab.socketGroupList[1].gemList[1].nameSpec == 'Fireball', 'Fixture must load Fireball')
assert(build.buildName == 'Save', 'Do not translate the build model')
assert(build.skillsTab.socketGroupList[1].label == 'Save', 'Do not translate custom skill labels')
PoB2Chinese.toggle(); runCallback('OnFrame')
assert(snapshot()==baseline, 'Changing language changed calculations')
PoB2Chinese.toggle(); runCallback('OnFrame')
assert(snapshot()==baseline)
local out = assert(io.open(root .. '/untranslated-observed.txt', 'w'))
local list = {}; for s in pairs(seen) do list[#list+1] = s end; table.sort(list)
out:write(table.concat(list,'\n')); out:close()
print('PASS: all eight real views; drawing calls='..getImageDraws()..'; Fireball DPS='..tostring(build.calcsTab.mainOutput.CombinedDPS)..'; identical calculation output with language toggled')
dofile(root .. '/runtime_controls.lua')

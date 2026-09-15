-- Full local equipment identity/tooltip audit. Run after integration.lua.
local root = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*)/'))
local P, json = assert(PoB2Chinese), require('dkjson')
local E, tab = assert(P.equipment), build.itemsTab
assert(P.enabled)
local before = build:SaveDB('equipment-coverage')
local baseSnapshot, uniqueSnapshot = json.encode(data.itemBases), json.encode(data.uniques)
local flavourSetting = main.showFlavourText
main.showFlavourText = false
local report = { bases = {total=0, translated=0}, uniques={total=0, translated=0},
    uniqueFlavour={total=0, translated=0}, augments={total=0, translated=0}, emotions={total=0, translated=0}, gaps={} }
local function compact(text) return StripEscapes(text):gsub('%s+', '') end
local function tooltip(item)
    local tip = new('Tooltip')
    tab:AddItemTooltip(tip, item, nil, false, 600)
    local lines = {}
    for _, line in ipairs(tip.lines) do if line.text then lines[#lines+1]=line.text end end
    return compact(table.concat(lines, '\n'))
end
for name, base in pairs(data.itemBases) do
    report.bases.total = report.bases.total + 1
    local zh = E.baseName(name, base)
    local item = new('Item', name, 'NORMAL')
    if not zh then report.gaps[#report.gaps+1] = {kind='base-source',en=name}
    elseif not item.base or item.baseName ~= name then
        -- Certain synthetic bases are selected through skills instead of the raw parser.
        local display = E.dropdownLabel({}, 1, {name=name,base=base,label=name})
        if display == zh then report.bases.translated = report.bases.translated + 1
        else report.gaps[#report.gaps+1] = {kind='synthetic-base-display',en=name} end
    elseif tooltip(item):find(compact(zh),1,true) then
        report.bases.translated = report.bases.translated + 1
    else report.gaps[#report.gaps+1] = {kind='base-tooltip',en=name} end
end
for category, list in pairs(data.uniques) do
    for _, raw in ipairs(list) do
        local item = new('Item',raw,'UNIQUE')
        report.uniques.total = report.uniques.total + 1
        local zh = E.uniqueTitle(item)
        if zh and tooltip(item):find(compact(zh),1,true) then
            report.uniques.translated = report.uniques.translated + 1
        else report.gaps[#report.gaps+1] = {kind='unique-tooltip',en=item.title,base=item.baseName,category=category} end
        local entry = E.uniqueEntry(item)
        if item.title ~= 'Tabula Rasa' then
            report.uniqueFlavour.total=report.uniqueFlavour.total+1
            main.showFlavourText=true
            if entry and entry.flavour and tooltip(item):find(compact(table.concat(entry.flavour.zh,'\n')),1,true) then
                report.uniqueFlavour.translated=report.uniqueFlavour.translated+1
            else report.gaps[#report.gaps+1]={kind='unique-flavour-tooltip',en=item.title,base=item.baseName} end
            main.showFlavourText=false
        end
    end
end
for name in pairs(data.itemMods.Runes) do
    report.augments.total = report.augments.total + 1
    local entry = P.game.equipmentAugments[name]
    if entry and entry.en==name and entry.zh then report.augments.translated=report.augments.translated+1
    else report.gaps[#report.gaps+1]={kind='augment',en=name} end
end
for _, emotion in pairs(data.emotions) do
    report.emotions.total = report.emotions.total + 1
    local entry = P.game.equipmentEmotions[emotion.name]
    if entry and entry.en==emotion.name and entry.zh then report.emotions.translated=report.emotions.translated+1
    else report.gaps[#report.gaps+1]={kind='emotion',en=emotion.name} end
end
main.showFlavourText = flavourSetting
table.sort(report.gaps,function(a,b) return a.kind..(a.en or '') < b.kind..(b.en or '') end)
local file=assert(io.open(root..'/equipment-runtime-coverage.json','w'))
file:write(json.encode(report,{indent=true}));file:close()
assert(json.encode(data.itemBases)==baseSnapshot,'Equipment audit changed base database')
assert(json.encode(data.uniques)==uniqueSnapshot,'Equipment audit changed unique database')
assert(build:SaveDB('equipment-coverage')==before,'Equipment display changed build export')
assert(#report.gaps==0,'Equipment coverage gaps: '..json.encode(report.gaps))
print('PASS equipment coverage: '..json.encode(report))

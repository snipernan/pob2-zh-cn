"""Compile source-backed equipment labels into scoped presentation tables."""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent


def lua(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return '{' + ','.join(lua(v) for v in value) + '}'
    if isinstance(value, dict):
        return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in sorted(value.items())) + '}'
    raise ValueError('Unsupported equipment value: ' + repr(value))


def compile_equipment(chars, official_affixes):
    inputs = {}
    for kind, filename in (('bases', 'equipment-bases-cn.json'), ('uniques', 'equipment-uniques-cn.json'),
                           ('affixes', 'equipment-affixes-cn.json'), ('affixLines', 'equipment-affix-lines-reviewed.json'),
                           ('composed', 'equipment-composed-cn.json'), ('grantedSkills', 'equipment-granted-skills-cn.json'),
                           ('baseImplicits', 'equipment-base-implicits-cn.json')):
        path = ROOT / 'data' / filename
        inputs[kind] = json.loads(path.read_text())
    tables = {key: {} for key in ('equipmentBases', 'equipmentUniques', 'equipmentAugments', 'equipmentEmotions', 'equipmentTypes')}
    kinds = {'base': 'equipmentBases', 'augment': 'equipmentAugments', 'liquid_emotion': 'equipmentEmotions', 'category': 'equipmentTypes'}

    def insert(table, key, record):
        if not key or not record.get('en') or not record.get('zh'):
            raise ValueError('Missing equipment label or identity')
        if key in tables[table] and tables[table][key] != record:
            raise ValueError('Ambiguous equipment identity: ' + key)
        tables[table][key] = record
        chars.update(record['zh'])

    for entry in inputs['bases']['entries'] + inputs['bases'].get('categories', []):
        if not entry.get('sourceIds') or not entry.get('verification'):
            raise ValueError('Equipment label has no source: ' + entry.get('en', '?'))
        insert(kinds[entry['kind']], entry['en'], {'en': entry['en'], 'zh': entry['zh']})
    for entry in inputs['uniques']['entries']:
        if not entry.get('zh'):
            continue
        if not (entry.get('sourceIds') or entry.get('sourceSnapshots')) or not entry.get('verification'):
            raise ValueError('Unique label has no source: ' + entry.get('en', '?'))
        base = entry['baseEn']
        key = entry['en'] + ', ' + re.sub(r' \(.+\)', '', base)
        record = {'en': entry['en'], 'base': base, 'zh': entry['zh']}
        flavour = entry.get('flavour')
        if flavour and flavour.get('en') and flavour.get('zh'):
            if not flavour.get('verification'):
                raise ValueError('Unique flavour has no verification')
            block = {lang: flavour[lang].splitlines() if isinstance(flavour[lang], str) else flavour[lang]
                     for lang in ('en', 'zh')}
            if any(not isinstance(value, list) or not value for value in block.values()):
                raise ValueError('Unique flavour must contain complete text arrays')
            record['flavour'] = block
            for line in block['zh']:
                chars.update(line)
        insert('equipmentUniques', key, record)
    for block in inputs['uniques'].get('blocks', []):
        key = block['en'] + ', ' + re.sub(r' \(.+\)', '', block['baseEn'])
        entry = tables['equipmentUniques'].get(key)
        if not entry or entry['base'] != block['baseEn'] or not block.get('sourceIds') or not block.get('verification'):
            raise ValueError('Unverified equipment block identity: ' + key)
        order=block['capture_map']
        if sum(line.count('#') for line in block['lines'])!=len(order) or block['zh'].count('#')!=len(order) or sorted(order)!=list(range(1,len(order)+1)):
            raise ValueError('Invalid equipment block slots: '+key)
        entry.setdefault('effectBlocks',[]).append({'lines':block['lines'],'zh':block['zh'],'order':order})
        chars.update(block['zh'])
    official = {re.sub(r'\s+', ' ', e['en']).strip().lower() for e in official_affixes}
    supplemental, conflicts = {}, set()
    for entry in inputs['affixes']['entries'] + inputs['uniques'].get('affixes', []) + inputs['affixLines']['entries'] + inputs['composed']['entries'] + inputs['grantedSkills']['entries'] + inputs['baseImplicits']['entries']:
        if not entry.get('verification') or not entry.get('sourceIds'):
            raise ValueError('Supplemental modifier has no source')
        en, zh, order = entry['en'], entry['zh'], entry['capture_map']
        if en.count('#') != len(order) or zh.count('#') != len(order) or sorted(order) != list(range(1, len(order) + 1)):
            raise ValueError('Invalid equipment modifier slots: ' + en)
        en = re.sub(r'\s+', ' ', en).strip()
        if en.lower() in official:
            continue
        record = {'en': en, 'zh': zh, 'order': order}
        if en in supplemental and supplemental[en] != record:
            # Explicitly reviewed stylistic difference; mechanics and the sole
            # numeric slot agree. Prefer wording consistent with the official corpus.
            if en=='#% increased Armour, Evasion and Energy Shield' and order==[1] and supplemental[en]['order']==[1] and {zh,supplemental[en]['zh']} <= {'护甲，闪避与能量护盾提高 #%','护甲、闪避和能量护盾提高 #%'}:
                record['zh']='护甲，闪避与能量护盾提高 #%'
            else:
                conflicts.add(en)
        supplemental[en] = record
    for en in conflicts:
        supplemental.pop(en)
    tables['equipmentAffixes'] = [supplemental[en] for en in sorted(supplemental)]
    for record in tables['equipmentAffixes']:
        chars.update(record['zh'])
    summary = {'counts': {k: len(v) for k, v in tables.items()}, 'excludedAffixConflicts': sorted(conflicts),
               'reviewedAffixPreference': {'#% increased Armour, Evasion and Energy Shield': '护甲，闪避与能量护盾提高 #%'},
               'inputSha256': {kind: hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True).encode()).hexdigest()
                               for kind, value in inputs.items()}}
    (ROOT / 'equipment-compiled-coverage.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    print('Compiled scoped equipment:', summary['counts'])
    return [key + '=' + lua(value) + ',' for key, value in tables.items()]

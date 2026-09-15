"""Compile verified Tencent texts without changing the PoB game database."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def quote(value):
    return json.dumps(value, ensure_ascii=False)


def compile_tree_data(chars):
    from build_tree_overlay import build_overlay
    tree = build_overlay()
    name_methods = {
        'official-trade2-node-id-and-exact-english-name',
        'official-trade2-exact-standalone-keystone-name',
        'poe2db-cn-node-id-internal-id-english-name',
        'poe2db-cn-ascendancy-stable-id-name',
        'poe2db-cn-reviewed-local-spelling-alias-identical-id-and-stats',
        'poe2db-cn-parent-node-id-class-scope-exact-stats',
        'poe2db-cn-option-page-hash-and-english-name',
        'poe2db-cn-us-passive-hash-english-name-internal-id',
        'poe2db-cn-us-exact-english-name-and-full-stat-block-generic-equivalent',
        'poe2db-cn-us-exact-english-name-and-stat-template-generic-equivalent',
        'poe2db-cn-us-generic-equivalent-with-official-terminology-preference',
    }
    stat_methods = {'official-trade2-exact-numeric-stat-template',
                    'poe2db-cn-exact-line-proved-by-single-line-node'}
    rows, ids = [], set()
    counts = {'names': 0, 'variants': 0, 'blocks': 0}

    def strings(values, empty=False):
        if not isinstance(values, list) or (not empty and not values) or any(not isinstance(v, str) or not v for v in values):
            raise ValueError('Invalid passive text array')
        return '{' + ','.join(quote(v) for v in values) + '}'

    def versions(values):
        if not values or not isinstance(values, list) or len(values) != len(set(values)):
            raise ValueError('Missing or duplicate passive tree versions')
        if any(value not in {'0_1', '0_2', '0_3', '0_4', '0_5'} for value in values):
            raise ValueError('Unverified passive tree version')
        return strings(values)

    def record(entry, key, variant=False):
        if not entry.get('en'):
            raise ValueError(f'Missing passive English identity: {key}')
        fields = [f'en={quote(entry["en"])}', f'versions={versions(entry["versions"])}']
        if variant:
            fields.append('currentStats=' + strings(entry['currentStats'], empty=True))
            counts['variants'] += 1
        if entry.get('zh'):
            if entry.get('verification') not in name_methods or not entry.get('sourceIds'):
                raise ValueError(f'Unverified passive name: {key}: {entry.get("verification")}')
            fields.append(f'zh={quote(entry["zh"])}')
            chars.update(entry['zh'])
            counts['names'] += not variant
        stats, seen = [], set()
        for stat in entry.get('stats', []):
            stat_method = stat.get('verification')
            valid_stat = stat_method in stat_methods
            valid_stat = valid_stat or (stat_method == 'manual-reviewed-local-english-with-poe2db-cn-glossary'
                                        and key in {'46070', '58894'})
            valid_stat = valid_stat or (stat_method == 'poe2db-cn-unique-residual-line-after-independent-official-pairs'
                                        and key == '58894')
            if (not valid_stat or not stat.get('sourceIds')
                    or not stat.get('en') or not stat.get('zh') or stat['en'] in seen):
                raise ValueError(f'Missing source or duplicate passive stat: {key}')
            if not set(stat['versions']).issubset(entry['versions']):
                raise ValueError(f'Passive stat version not present in node: {key}')
            seen.add(stat['en'])
            stats.append('{en=' + quote(stat['en']) + ',zh=' + quote(stat['zh']) +
                         ',versions=' + versions(stat['versions']) +
                         ',verification=' + quote(stat['verification']) + '}')
            chars.update(stat['zh'])
        fields.append('stats={' + ','.join(stats) + '}')
        blocks = []
        for block in entry.get('statBlocks', []):
            block_method = block.get('verification')
            valid_block = block_method == 'poe2db-cn-complete-node-stats-multiset'
            valid_block = valid_block or (block_method == 'poe2db-cn-complete-node-stats-with-explicit-reviewed-differences'
                                          and key in {'1502', '4367', '37778', '29762'})
            valid_block = valid_block or (block_method == 'manual-reviewed-local-english-with-poe2db-cn-glossary'
                                          and key in {'46070', '58894'})
            if (not valid_block
                    or not block.get('sourceIds') or not set(block['versions']).issubset(entry['versions'])):
                raise ValueError(f'Unverified passive description block: {key}')
            blocks.append('{en=' + strings(block['en']) + ',zh=' + strings(block['zh']) +
                          ',versions=' + versions(block['versions']) + '}')
            for line in block['zh']:
                chars.update(line)
            counts['blocks'] += 1
        fields.append('statBlocks={' + ','.join(blocks) + '}')
        if entry.get('variants'):
            fields.append('variants={' + ','.join(record(v, key, True) for v in entry['variants']) + '}')
        return '{' + ','.join(fields) + '}'

    for entry in tree['entries']:
        key = str(entry['id'])
        if not key.isdecimal() or key in ids:
            raise ValueError(f'Invalid or duplicate passive ID: {key}')
        ids.add(key)
        rows.append(f'[{quote(key)}]=' + record(entry, key) + ',')
    print(f'Compiled {len(ids)} passive records: {counts}')
    return rows


def compile_game_data():
    skills = json.loads((ROOT / 'data/skills-cn.json').read_text())
    affixes = json.loads((ROOT / 'data/affixes-cn.json').read_text())
    by_id, by_name, ambiguous, phrases, chars = {}, {}, set(), {}, set()
    for entry in skills['entries']:
        key, en, zh = entry['pobId'], entry['english'], entry['chinese']
        if entry['verification'] != 'tencent-trade-exact-name' or key in by_id:
            raise ValueError(f'Unverified or duplicate skill: {key}')
        by_id[key] = (en, zh)
        if en in by_name and by_name[en] != zh:
            ambiguous.add(en)
        by_name[en] = zh
        chars.update(zh)
    for en in ambiguous:
        del by_name[en]
    for entry in affixes['entries']:
        en, zh, order = entry['en'], entry['zh'], entry['capture_map']
        if en.count('#') != len(order) or zh.count('#') != len(order):
            raise ValueError(f'Placeholder count mismatch: {entry["id"]}')
        if sorted(order) != list(range(1, len(order) + 1)):
            raise ValueError(f'Invalid capture order: {entry["id"]}')
        if en in phrases and phrases[en] != (zh, order):
            raise ValueError(f'Ambiguous equipment text: {en}')
        phrases[en] = (zh, order)
        chars.update(zh)
    lines = ['-- Generated from the verified snapshots in data/. See docs/DATA_SOURCES.md for sources.', 'return {']
    from build_equipment_assets import compile_equipment
    # LuaJIT limits each function to 65536 constants. Keep the growing equipment
    # catalogue in a separate chunk from the skill/affix/passive dictionary.
    equipment_lines = lines + compile_equipment(chars, affixes['entries']) + ['}\n']
    (ROOT / 'payload/equipment_dictionary.lua').write_text('\n'.join(equipment_lines))
    lines.append('skillsById = {')
    for key, (en, zh) in sorted(by_id.items()):
        lines.append(f'[{quote(key)}]={{en={quote(en)},zh={quote(zh)}}},')
    lines.append('}, skillNames = {')
    for en, zh in sorted(by_name.items()):
        lines.append(f'[{quote(en)}]={quote(zh)},')
    lines.append('}, affixes = {')
    for en, (zh, order) in sorted(phrases.items()):
        slots = ','.join(map(str, order))
        lines.append(f'{{en={quote(en)},zh={quote(zh)},order={{{slots}}}}},')
    lines.append('}, treeById = {')
    lines.extend(compile_tree_data(chars))
    lines.append('}}\n')
    (ROOT / 'payload/game_dictionary.lua').write_text('\n'.join(lines))
    print(f'Compiled {len(by_id)} verified skill IDs / {len(by_name)} names; {len(phrases)} official affix templates')
    return chars


if __name__ == '__main__':
    compile_game_data()

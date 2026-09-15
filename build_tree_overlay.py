"""Merge the requested PoE2DB supplement while keeping Tencent text first."""
from collections import Counter
from copy import deepcopy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def flatten(lines):
    return [part for line in lines for part in line.splitlines() if part.strip()]


def build_overlay():
    official_path = ROOT / 'data/tree-cn.json'
    supplement_path = ROOT / 'data/tree-poe2db-cn.json'
    official = json.loads(official_path.read_text())
    supplement = json.loads(supplement_path.read_text())
    records = {entry['id']: deepcopy(entry) for entry in official['entries']}
    conflicts, normalized, seen = [], [], set()
    canonical = {}
    for entry in official['entries']:
        for stat in entry['stats']:
            if stat['en'] in canonical and canonical[stat['en']] != stat['zh']:
                raise ValueError('Ambiguous official English modifier')
            canonical[stat['en']] = stat['zh']
    correspondence = {line['en']: line['zh'] for line in supplement.get('lineCorrespondences', [])}

    def prefer_official_blocks(entry):
        for block in entry.get('statBlocks', []):
            before = block['zh'][:]
            if all(text in canonical for text in block['en']):
                block['zh'] = [canonical[text] for text in block['en']]
            else:
                for text in block['en']:
                    prior = correspondence.get(text)
                    if text in canonical and prior:
                        block['zh'] = [canonical[text] if line == prior else line for line in block['zh']]
            if before != block['zh']:
                proof = {'en': block['en'], 'poe2db': before, 'preferred': block['zh']}
                block['officialPreference'] = proof
                normalized.append(proof)
        for variant in entry.get('variants', []):
            prefer_official_blocks(variant)

    for extra in supplement['entries']:
        key = str(extra['id'])
        if key in seen:
            raise ValueError(f'Duplicate supplemental node ID: {key}')
        seen.add(key)
        current = records.setdefault(key, {'id': key, 'en': extra['en'],
                                          'versions': [], 'stats': []})
        if current['en'] != extra['en']:
            raise ValueError(f'Conflicting local English node identity: {key}')
        current['versions'] = sorted(set(current['versions']) | set(extra['versions']))
        if extra.get('zh'):
            if current.get('zh'):
                if current['zh'] != extra['zh']:
                    conflicts.append({'id': key, 'en': current['en'], 'kept': current['zh'],
                                      'poe2db': extra['zh'], 'reason': 'Tencent name has priority'})
            else:
                for field in ('zh', 'verification', 'sourceIds'):
                    current[field] = deepcopy(extra[field])
        known_stats = {stat['en'] for stat in current['stats']}
        for stat in extra.get('stats', []):
            if stat['en'] not in known_stats:
                current['stats'].append(deepcopy(stat))
                known_stats.add(stat['en'])
        if extra.get('statBlocks'):
            current['statBlocks'] = deepcopy(extra['statBlocks'])
        if extra.get('variants'):
            current['variants'] = deepcopy(extra['variants'])
        prefer_official_blocks(current)
    entries = sorted(records.values(), key=lambda entry: int(entry['id']))
    result = {
        'schema': 1,
        'source': {
            'priority': ['Tencent official trade2', 'User-requested PoE2DB /cn/ supplement'],
            'official': {'path': 'data/tree-cn.json', 'sha256': digest(official_path)},
            'poe2db': {'path': 'data/tree-poe2db-cn.json', 'sha256': digest(supplement_path)},
        },
        'summary': {
            'entries': len(entries),
            'named_entries': sum(bool(entry.get('zh')) for entry in entries),
            'official_named_entries': official['summary']['named_entries'],
            'variant_records': sum(len(entry.get('variants', [])) for entry in entries),
            'stat_blocks': sum(len(entry.get('statBlocks', [])) for entry in entries),
            'preserved_official_name_conflicts': conflicts,
            'blocks_with_official_wording_preferred': len(normalized),
        },
        'entries': entries,
    }
    nodes = json.loads((ROOT / 'data/inputs/tree-0_5.json').read_text())['nodes']
    visible = {key: node for key, node in nodes.items()
               if not node.get('isOnlyImage') and not node.get('classesStart')}
    missing_names, missing_stats = [], []
    for key, node in visible.items():
        entry = records.get(key, {})
        if not entry.get('zh'):
            missing_names.append({'id': key, 'en': node['name']})
        lines = flatten(node.get('stats', []))
        full_block = any('0_5' in block['versions'] and Counter(block['en']) == Counter(lines)
                         for block in entry.get('statBlocks', []))
        if not full_block:
            known = {s['en'] for s in entry.get('stats', []) if '0_5' in s['versions']}
            absent = [line for line in lines if line not in known]
            if absent:
                missing_stats.append({'id': key, 'en': node['name'], 'stats': absent})
    result['summary']['latest'] = {
        'visible_nodes': len(visible), 'translated_names': len(visible) - len(missing_names),
        'nodes_with_all_descriptions_translated': len(visible) - len(missing_stats),
        'missing_names': missing_names, 'missing_descriptions': missing_stats,
    }
    (ROOT / 'data/tree-combined-cn.json').write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return result


if __name__ == '__main__':
    print(json.dumps(build_overlay()['summary'], ensure_ascii=False, indent=2))

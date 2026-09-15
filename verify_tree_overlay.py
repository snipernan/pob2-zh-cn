"""Verify the compiled merge without weakening either source's own verifier."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path

from build_tree_overlay import build_overlay

ROOT = Path(__file__).resolve().parent
combined = json.loads((ROOT / 'data/tree-combined-cn.json').read_text())
official = json.loads((ROOT / 'data/tree-cn.json').read_text())
for name in ('official', 'poe2db'):
    source = combined['source'][name]
    assert hashlib.sha256((ROOT / source['path']).read_bytes()).hexdigest() == source['sha256']
by_id = {entry['id']: entry for entry in combined['entries']}
assert len(by_id) == len(combined['entries'])
for entry in official['entries']:
    merged = by_id[entry['id']]
    assert merged['en'] == entry['en']
    if entry.get('zh'):
        assert merged['zh'] == entry['zh'], 'Never replace an official title with a third-party alternative'
        assert merged['verification'] == entry['verification']
        assert merged['sourceIds'] == entry['sourceIds']
    merged_stats = {stat['en']: stat for stat in merged['stats']}
    for stat in entry['stats']:
        assert merged_stats[stat['en']] == stat, 'Preserve every official modifier and its provenance'


def check_record(entry, variant=False):
    assert entry['en'] and entry['versions']
    if entry.get('zh'):
        assert entry['verification'] and entry['sourceIds']
    if variant:
        assert isinstance(entry['currentStats'], list)
    for field in ('stats', 'statBlocks'):
        for part in entry.get(field, []):
            assert part['en'] and part['zh'] and part['sourceIds'] and part['verification']
            assert part['versions'] and set(part['versions']) <= set(entry['versions'])
    for choice in entry.get('variants', []):
        check_record(choice, True)


for entry in combined['entries']:
    check_record(entry)
assert build_overlay() == combined, 'Overlay must rebuild deterministically from the two source corpora'
summary = combined['summary']
print(f"PASS tree overlay: {summary['named_entries']} base names; "
      f"{summary['variant_records']} variant records; "
      f"all {official['summary']['named_entries']} official titles and every official stat unchanged; "
      "source hashes, provenance, version guards and deterministic rebuild")

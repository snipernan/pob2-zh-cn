"""Compile the editable TSV dictionary. No downloads or third-party packages."""
import json
from pathlib import Path
from build_game_assets import compile_game_data

ROOT = Path(__file__).resolve().parent

def common_han():
    """GB2312's 6,763 Han characters cover common user-entered Chinese names."""
    chars = set()
    for lead in range(0xB0, 0xF8):
        for trail in range(0xA1, 0xFF):
            try:
                chars.add(bytes((lead, trail)).decode('gb2312'))
            except UnicodeDecodeError:
                pass
    assert len(chars) == 6763
    return chars

def compile_dictionary():
    mapping, folded = {}, {}
    for i, line in enumerate((ROOT / 'translations.tsv').read_text().splitlines(), 1):
        if not line or (line.startswith('#') and '\t' not in line):
            continue
        if line.count('\t') != 1:
            raise ValueError(f'Expected one tab at line {i}')
        en, zh = line.split('\t', 1)
        if not en.strip() or not zh.strip():
            raise ValueError(f'Empty text at line {i}')
        if en in mapping:
            raise ValueError(f'Duplicate key at line {i}: {en}')
        if en.lower() in folded and folded[en.lower()] != zh:
            raise ValueError(f'Ambiguous case-insensitive translation at line {i}: {en}')
        mapping[en] = zh
        folded[en.lower()] = zh
    out = ROOT / 'payload'
    out.mkdir(exist_ok=True)
    quote = lambda s: json.dumps(s, ensure_ascii=False)
    (out / 'dictionary.lua').write_text('return {\n' + ''.join(
        f'  [{quote(k)}] = {quote(v)},\n' for k, v in sorted(mapping.items())
    ) + '}\n')
    game_chars = compile_game_data()
    chars = sorted(set(''.join(mapping.values()) + '简体中文汉化已启用按切换界面语言：，。…？（）【】；“”') | game_chars | common_han())
    (ROOT / 'charset.txt').write_text(''.join(c for c in chars if ord(c) > 127))
    print(f'Compiled {len(mapping)} translations')

if __name__ == '__main__':
    compile_dictionary()

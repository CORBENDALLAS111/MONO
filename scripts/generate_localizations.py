import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
entries = [line.split('\t') for line in (root / 'scripts/localizations.tsv').read_text(encoding='utf-8').splitlines() if line.strip()]
assert all(len(row) == 3 for row in entries)
assert len(set(row[0] for row in entries)) == len(entries)
for index, lang in enumerate(('ru','en'), 1):
    folder = root / 'Shared/Localization' / (lang + '.lproj')
    folder.mkdir(parents=True, exist_ok=True)
    text = '\n'.join(json.dumps(row[0]) + ' = ' + json.dumps(row[index].replace('\\n', '\n'), ensure_ascii=False) + ';' for row in entries) + '\n'
    (folder / 'Localizable.strings').write_text(text, encoding='utf-8')
print(f'{len(entries)} keys x 2 languages')

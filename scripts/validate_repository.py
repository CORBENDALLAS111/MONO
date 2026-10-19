"""Bounded local integrity checks. This is NOT xcodebuild or Swift type checking."""
import json
import pathlib
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
import yaml
from tree_sitter import Language, Parser
import tree_sitter_swift

root=pathlib.Path(__file__).resolve().parents[1]
errors=[]
def check(condition,message):
    if not condition: errors.append(message)

spec=yaml.load((root/'project.yml').read_text(),Loader=yaml.BaseLoader)
check(set(spec['targets']) == {'MONO','MONOShareExtension','MONOTests','MONOUITests'},'Missing targets')
for path in (root/'.github/workflows').glob('*.yml'):
    workflow=yaml.load(path.read_text(),Loader=yaml.BaseLoader)
    check('on' in workflow and 'jobs' in workflow,'Invalid workflow '+str(path))
for path in root.rglob('*.xcprivacy'):
    check(plistlib.loads(path.read_bytes())['NSPrivacyTracking'] is False,'Tracking declaration')

rows=[line.split('\t') for line in (root/'scripts/localizations.tsv').read_text(encoding='utf-8').splitlines() if line]
keys={row[0] for row in rows}
check(len(rows)==len(keys),'Duplicate localization keys')
for index,lang in enumerate(('ru','en'),1):
    text=(root/f'Shared/Localization/{lang}.lproj/Localizable.strings').read_text(encoding='utf-8')
    found={json.loads(m[0]):json.loads(m[1]) for m in re.findall(r'("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*");',text)}
    check(set(found)==keys,'Localization parity: '+lang)
    check(all(found.get(row[0])==row[index].replace('\\n','\n') for row in rows),'Generated localization mismatch: '+lang)

parser=Parser(Language(tree_sitter_swift.language()))
files=list(root.rglob('*.swift'))
for file in files:
    data=file.read_bytes()
    check(not parser.parse(data).root_node.has_error,'Swift syntax: '+str(file.relative_to(root)))
    text=data.decode('utf-8')
    check('try!' not in text,'Force try: '+str(file))
    # All literal localizable UI text keys must be present. Dynamic user/media text is not treated as a key.
    pattern=r'(?:String\(localized:|Text\(|Button\(|Section\(|accessibilityLabel\(|accessibilityHint\()\s*"([a-z][a-z.]+)"'
    for key in re.findall(pattern,text):
        check(key in keys,'Missing localization: '+key)
check(not any('systemName:' in file.read_text(encoding='utf-8') for file in files),'Unreviewed SF Symbol')
source=json.loads((root/'Vendor/Lucide/source.json').read_text())
for name in source['icons']:
    ET.parse(root/'Vendor/Lucide'/f'{name}.svg')
generated=(root/'MONOApp/DesignSystem/Lucide.generated.swift').read_text()
check(len(re.findall(r'^    case ',generated,re.M))==len(source['icons']),'Icon enum parity')
print(f'Checked {len(files)} Swift syntax trees, {len(keys)} localization keys per language, {len(source["icons"])} SVGs, project/workflow/plist structure.')
print('Swift type checking, Xcode build and device behavior are NOT validated by this script.')
for error in errors: print('FAIL:',error)
if errors: sys.exit(1)
print('PASS: repository integrity checks')

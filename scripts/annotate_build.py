from pathlib import Path
for file in sorted(Path('build').glob('*.log'), key=lambda p:p.stat().st_mtime, reverse=True):
    for line in file.read_text(errors='replace').splitlines():
        if ' error:' in line or 'error: ' in line or 'TEST FAILED' in line:
            print('::error::' + line.replace('%','%25').replace('\r','%0D').replace('\n','%0A'))
            raise SystemExit()
print('::error::Build or tests failed. Inspect uploaded logs for the first failure.')

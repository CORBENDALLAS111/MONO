"""Read/dispatch this repository's Actions using existing Git Credential Manager auth.
Never prints or persists credentials. Not used by the iOS app or CI.
Usage: python scripts/github_actions.py runs|jobs RUN_ID|logs RUN_ID|artifacts RUN_ID
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import io

root=pathlib.Path(__file__).resolve().parents[1]
remote=subprocess.check_output(['git','remote','get-url','origin'],cwd=root,text=True).strip()
match=re.fullmatch(r'https://github.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?',remote)
if not match: raise SystemExit('Expected a GitHub HTTPS origin')
repo=match[1]
settings=os.environ.copy(); settings['GIT_TERMINAL_PROMPT']='0'; settings['GCM_INTERACTIVE']='Never'
result=subprocess.run(['git','credential','fill'],input='protocol=https\nhost=github.com\n\n',text=True,capture_output=True,env=settings,timeout=25)
if result.returncode: raise SystemExit('Stored Git authorization unavailable')
credential=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
token=credential.get('password')
if not token: raise SystemExit('No authorization token')

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args): return None

def api(path, payload=None):
    request=urllib.request.Request('https://api.github.com/repos/'+repo+path,
        data=None if payload is None else json.dumps(payload).encode(),
        headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','Content-Type':'application/json','X-GitHub-Api-Version':'2022-11-28'})
    try:
        with urllib.request.build_opener(NoRedirect).open(request,timeout=45) as response:
            data=response.read()
            return json.loads(data) if 'json' in response.headers.get('Content-Type','') else data
    except urllib.error.HTTPError as error:
        if error.code in (301,302,303,307,308):
            location=error.headers['Location']; parsed=urllib.parse.urlsplit(location)
            if parsed.scheme != 'https' or parsed.username or parsed.password: raise SystemExit('Unsafe artifact redirect')
            # New request intentionally has NO GitHub Authorization header.
            try:
                with urllib.request.urlopen(location,timeout=60) as response: return response.read()
            except urllib.error.HTTPError as temporary:
                print('GitHub log/artifact storage HTTP status:',temporary.code); raise SystemExit(1)
        print('GitHub HTTP status:',error.code); raise SystemExit(1)

command=sys.argv[1]
if command == 'runs':
    data=api('/actions/runs?per_page=5')
    print(json.dumps([{'id':r['id'],'workflow':r['name'],'status':r['status'],'result':r['conclusion'],'sha':r['head_sha'],'url':r['html_url']} for r in data['workflow_runs']],indent=2))
elif command == 'jobs':
    data=api('/actions/runs/'+str(int(sys.argv[2]))+'/jobs')
    print(json.dumps([{'id':j['id'],'name':j['name'],'status':j['status'],'result':j['conclusion'],'steps':[{'name':s['name'],'status':s['status'],'result':s['conclusion']} for s in j.get('steps',[])]} for j in data['jobs']],indent=2))
elif command == 'artifacts':
    data=api('/actions/runs/'+str(int(sys.argv[2]))+'/artifacts')
    print(json.dumps([{'id':a['id'],'name':a['name'],'bytes':a['size_in_bytes'],'expired':a['expired']} for a in data['artifacts']],indent=2))
elif command == 'job-log':
    data=api('/actions/jobs/'+str(int(sys.argv[2]))+'/logs')
    text=data.decode(errors='replace') if isinstance(data,bytes) else str(data)
    print('\n'.join(text.splitlines()[-70:]))
elif command == 'logs':
    data=api('/actions/runs/'+str(int(sys.argv[2]))+'/logs')
    directory=root/'build'/'logs'/str(int(sys.argv[2])); directory.mkdir(parents=True,exist_ok=True)
    archive=zipfile.ZipFile(io.BytesIO(data))
    for item in archive.infolist():
        if item.is_dir(): continue
        destination=directory/pathlib.Path(item.filename).name
        text=archive.read(item).decode(errors='replace')
        destination.write_text(text,encoding='utf-8')
        errors=[line for line in text.splitlines() if any(p in line for p in ('error:','##[error]','TEST FAILED','Executed ','Xcode 26','FAILED'))]
        if errors: print(destination.name+'\n'+'\n'.join(errors[:45]))
elif command == 'download-artifact':
    identifier=str(int(sys.argv[2]))
    data=api('/actions/artifacts/'+identifier+'/zip')
    directory=root/'build'/'artifacts'/identifier
    directory.mkdir(parents=True,exist_ok=True)
    (directory/'artifact.zip').write_bytes(data)
    archive=zipfile.ZipFile(io.BytesIO(data))
    # Extract only preview PNGs and their manifest for local inspection, using flat safe names.
    previews=[]
    for item in archive.infolist():
        name=pathlib.Path(item.filename).name
        if name.lower().endswith('.png') or (name == 'manifest.json' and 'screenshots' in item.filename):
            (directory/name).write_bytes(archive.read(item))
            previews.append(name)
    print(json.dumps({'file':str(directory/'artifact.zip'),'previews':previews},indent=2))
elif command == 'dispatch':
    api('/actions/workflows/ios-ci.yml/dispatches',{'ref':'main','inputs':{'live_network':'true' if '--live' in sys.argv else 'false'}})
    print('Workflow dispatch accepted')
else: raise SystemExit('Unknown command')

import datetime
import hashlib
import json
import os
import pathlib
import plistlib
import re
import shutil
import subprocess

folder=pathlib.Path(os.environ['RUNNER_TEMP'])/'mono-signing'
team=os.environ['APPLE_TEAM_ID']
group=os.environ['APP_GROUP']
method=os.environ['EXPORT_METHOD']
assert re.fullmatch(r'[A-Z0-9]{10}',team), 'Invalid team ID'
identity_text=subprocess.check_output(['security','find-identity','-v','-p','codesigning',str(folder/'mono.keychain-db')],text=True)
identities={m.upper() for m in re.findall(r'\b[0-9A-Fa-f]{40}\b',identity_text)}
assert identities, 'No usable signing identity with private key was imported'
names={}
overrides={}
installed=[]
certificate_candidates=set(identities)
for component, target, bundle_var in [('app','MONO','APP_BUNDLE_ID'),('share','MONOShareExtension','EXTENSION_BUNDLE_ID')]:
    profile=plistlib.loads((folder/(component+'.plist')).read_bytes())
    bundle=os.environ[bundle_var]
    assert re.fullmatch(r'[A-Za-z0-9.-]+',bundle), 'Invalid bundle ID'
    ent=profile['Entitlements']
    assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Provisioning profile expired'
    assert team in profile['TeamIdentifier'], 'Profile team does not match APPLE_TEAM_ID'
    assert ent['application-identifier'] == team+'.'+bundle, 'Profile must match exact bundle ID'
    assert group in ent.get('com.apple.security.application-groups',[]), 'Missing matching App Group entitlement'
    if method in ('ad-hoc','development'):
        assert profile.get('ProvisionedDevices'), 'Device installation requires registered devices in BOTH profiles'
        assert bool(ent.get('get-task-allow')) == (method == 'development'), 'Profile type does not match export method'
    else:
        assert not profile.get('ProvisionedDevices') and not ent.get('get-task-allow') and not profile.get('ProvisionsAllDevices'), 'Expected App Store distribution profile'
    certificate_candidates &= {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}
    names[bundle]=profile['UUID']
    overrides[target]={'settings':{'base':{
        'PRODUCT_BUNDLE_IDENTIFIER':bundle,'DEVELOPMENT_TEAM':team,'CODE_SIGN_STYLE':'Manual',
        'PROVISIONING_PROFILE_SPECIFIER':profile['UUID'],'APP_GROUP':group,
    }}}
    # Xcode 16+ location, plus legacy location for tools that still search there.
    for parent in [pathlib.Path.home()/'Library/Developer/Xcode/UserData/Provisioning Profiles', pathlib.Path.home()/'Library/MobileDevice/Provisioning Profiles']:
        parent.mkdir(parents=True,exist_ok=True)
        destination=parent/(profile['UUID']+'.mobileprovision')
        assert not destination.exists(), 'Refusing to overwrite an existing provisioning profile'
        shutil.copyfile(folder/(component+'.mobileprovision'),destination)
        installed.append(str(destination))
        (folder/'installed.json').write_text(json.dumps(installed))
assert certificate_candidates, 'Imported certificate must occur in BOTH provisioning profiles'
identity=sorted(certificate_candidates)[0]
for target in overrides.values():
    target['settings']['base']['CODE_SIGN_IDENTITY']=identity
options={'method':{'ad-hoc':'release-testing','development':'debugging','app-store-connect':'app-store-connect'}[method],
         'destination':'export','teamID':team,'signingStyle':'manual','signingCertificate':identity,
         'provisioningProfiles':names,'manageAppVersionAndBuildNumber':False}
pathlib.Path('build/ExportOptions.plist').write_bytes(plistlib.dumps(options))
pathlib.Path('signing-project.json').write_text(json.dumps({'include':['project.yml'],'targets':overrides}))
print('Both provisioning profiles, App Group, team, certificate membership and export method validated.')

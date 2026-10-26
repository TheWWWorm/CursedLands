from pathlib import Path
import hashlib,json,shutil,subprocess,tarfile,zipfile

W=Path(__file__).resolve().parent
R=W.parent/'repo'
V='1.31.0'
ASSETS=W/'assets';ASSETS.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads(p.read_text())
validation=R/'docs/validation/release-1.31.0-2026-10-26.json'
report=read(validation)
assert report['acceptance_passed'] is True
assert read(W/'android-audit.json')['all_five_platforms_identical']
verified_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip()
assert not subprocess.check_output(['git','status','--porcelain'],cwd=R,text=True).strip()
assert subprocess.check_output(['git','rev-parse','HEAD:game'],cwd=R,text=True).strip()==report['game_tree']
manifest=[]

def archive(folder,destination,mac=False):
    expected={}
    if destination.name.endswith('.tar.gz'):
        expected={folder.name+'/'+str(p.relative_to(folder)):sha(p) for p in folder.rglob('*') if p.is_file()}
        with tarfile.open(destination,'w:gz',compresslevel=6) as z:z.add(folder,arcname=folder.name)
        with tarfile.open(destination) as z:
            members=[m for m in z.getmembers() if m.isfile()]
            assert {m.name for m in members}==expected.keys()
            for m in members:assert hashlib.sha256(z.extractfile(m).read()).hexdigest()==expected[m.name]
            assert any(m.name.endswith('/Play.sh') and m.mode&0o111 for m in members)
    else:
        with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
            if mac:
                with zipfile.ZipFile(folder/'CursedLands.zip') as old:
                    for info in old.infolist():
                        data=old.read(info.filename);z.writestr(info,data);expected[info.filename]=hashlib.sha256(data).hexdigest()
            for p in sorted(folder.rglob('*')):
                if not p.is_file() or (mac and p.name=='CursedLands.zip'):continue
                name=('' if mac else folder.name+'/')+str(p.relative_to(folder))
                z.write(p,name);expected[name]=sha(p)
        with zipfile.ZipFile(destination) as z:
            assert z.testzip() is None and set(z.namelist())==expected.keys()
            for name,digest in expected.items():assert hashlib.sha256(z.read(name)).hexdigest()==digest,name
    manifest.append({'name':destination.name,'bytes':destination.stat().st_size,'sha256':sha(destination),'members_read_back':True})
    print('Verified',destination.name,flush=True)

build=read(W/'build.json')
for platform,row in build['platforms'].items():
    folder=Path(row['folder']);info=read(folder/'BUILD-INFO.json')
    for name,digest in info['files'].items():assert sha(folder/name)==digest,name
    shutil.copy2(R/'docs/regression-checks.md',folder/'docs/regression-checks.md')
    shutil.copy2(R/'docs/releases/1.31.0.md',folder/'docs/releases/1.31.0.md')
    shutil.copy2(R/'CHANGELOG.md',folder/'CHANGELOG.md')
    (folder/'RELEASE-NOTES.md').write_text((W/'release-body.md').read_text())
    info.update(source_tag='v'+V,release_type='stable',production_scripts_identical_across_five_platforms=True,
                verified_release_commit=verified_commit,
                runtime_validation=report['platform_runtime'][platform],
                target_os_runtime_tested=report['platform_runtime'][platform]['target_os_tested'])
    (folder/'docs/validation').mkdir(exist_ok=True)
    shutil.copy2(validation,folder/'docs/validation'/validation.name)
    info['files']={str(p.relative_to(folder)):sha(p) for p in sorted(folder.rglob('*')) if p.is_file() and p.name not in ['BUILD-INFO.json','SHA256SUMS.txt']}
    (folder/'BUILD-INFO.json').write_text(json.dumps(info,indent=2)+'\n')
    (folder/'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.relative_to(folder)}\n' for p in sorted(folder.rglob('*')) if p.is_file() and p.name!='SHA256SUMS.txt'))
    archive(folder,ASSETS/(folder.name+('.tar.gz' if platform=='linux-x86_64' else '.zip')),platform=='macos-universal')

apk=W/'CursedLands-1.31.0-android/CursedLands.apk'
dest=ASSETS/f'CursedLands-{V}-android.apk';shutil.copy2(apk,dest)
manifest.append({'name':dest.name,'bytes':dest.stat().st_size,'sha256':sha(dest)})
web=W/f'CursedLands-{V}-web';shutil.copytree(W/'web/unsplit',web)
(web/'README.md').write_text(f'# Cursed Lands {V} — browser\n\nServe this directory over HTTPS with cross-origin isolation headers. Original game data is required to play.\n\nHosted at https://cursedlands.wwworm.com/.\n')
(web/'RELEASE-NOTES.md').write_text((W/'release-body.md').read_text())
shutil.copy2(validation,web/'VALIDATION.json')
archive(web,ASSETS/(web.name+'.zip'))
(W/'assets.json').write_text(json.dumps(manifest,indent=2)+'\n')
subprocess.run(['python3',str(W/'tools_bundle.py')],check=True)
assets=sorted(p for p in ASSETS.iterdir() if p.is_file() and p.name!='SHA256SUMS.txt')
(ASSETS/'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in assets))
subprocess.run(['python3',str(R/'tools/check_release_assets.py'),*[str(p) for p in sorted(ASSETS.iterdir())]],check=True)
print('All assets and checksums passed the release policy',flush=True)

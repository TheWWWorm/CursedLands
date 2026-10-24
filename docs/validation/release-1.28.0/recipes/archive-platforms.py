from pathlib import Path
import json,hashlib,tarfile,zipfile,shutil
W=Path(__file__).resolve().parent;R=W.parent/'repo';V='1.28.0'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads(p.read_text())
build=read(W/'build.json');cross=read(W/'android-audit.json');assert cross['all_five_platforms_identical']
body=(W/'release-body.md').read_text();validation=R/'docs/validation/release-1.28.0-2026-10-24.json'
hosted=read(W/'hosted-files.json')
assets=W/'assets';assets.mkdir(exist_ok=True);manifest=[]
def archive(folder,dest,mac=False):
    expected={}
    if dest.name.endswith('.tar.gz'):
        expected={folder.name+'/'+str(p.relative_to(folder)):sha(p) for p in folder.rglob('*') if p.is_file()}
        with tarfile.open(dest,'w:gz',compresslevel=6) as z:z.add(folder,arcname=folder.name)
        with tarfile.open(dest) as z:
            files=[m for m in z.getmembers() if m.isfile()];assert {m.name for m in files}==expected.keys()
            for m in files:assert hashlib.sha256(z.extractfile(m).read()).hexdigest()==expected[m.name]
            assert any(m.name.endswith('/Play.sh') and m.mode&0o111 for m in files)
    else:
        with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
            if mac:
                with zipfile.ZipFile(folder/'CursedLands.zip') as source:
                    for info in source.infolist():
                        data=source.read(info.filename);z.writestr(info,data);expected[info.filename]=hashlib.sha256(data).hexdigest()
            for p in sorted(folder.rglob('*')):
                if not p.is_file() or (mac and p.name=='CursedLands.zip'):continue
                name=('' if mac else folder.name+'/')+str(p.relative_to(folder));z.write(p,name);expected[name]=sha(p)
        with zipfile.ZipFile(dest) as z:
            assert z.testzip() is None and set(z.namelist())==expected.keys()
            for name,h in expected.items():assert hashlib.sha256(z.read(name)).hexdigest()==h,name
    row={'name':dest.name,'bytes':dest.stat().st_size,'sha256':sha(dest),'all_members_verified':True};manifest.append(row);print('Archived',dest.name,flush=True)
for platform,row in build['platforms'].items():
    folder=Path(row['folder']);info=read(folder/'BUILD-INFO.json')
    for name,h in info['files'].items():assert sha(folder/name)==h,name
    runtime=read(validation)['platform_runtime'].get(platform,{'tested':False,'scope':'not recorded'})
    info.update(source_tag='v'+V,release_type='stable',production_scripts_identical_across_five_platforms=cross['all_five_platforms_identical'],runtime_validation=runtime,target_os_runtime_tested=bool(runtime.get('target_os_tested',False)))
    (folder/'BUILD-INFO.json').write_text(json.dumps(info,indent=2)+'\n');(folder/'docs/validation').mkdir(exist_ok=True)
    shutil.copy2(validation,folder/'docs/validation'/validation.name)
    shutil.copytree(R/'docs/validation/release-1.28.0',folder/'docs/validation/release-1.28.0',dirs_exist_ok=True)
    shutil.copy2(R/'docs/integrations/dlssg-sm86-player.txt',folder/'docs/integrations/dlssg-sm86-player.txt')
    info['files']={str(p.relative_to(folder)):sha(p) for p in sorted(folder.rglob('*')) if p.is_file() and p.name not in ['BUILD-INFO.json','SHA256SUMS.txt']}
    (folder/'BUILD-INFO.json').write_text(json.dumps(info,indent=2)+'\n')
    (folder/'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.relative_to(folder)}\n' for p in sorted(folder.rglob('*')) if p.is_file() and p.name not in ['SHA256SUMS.txt','CursedLands.zip']))
    archive(folder,assets/(folder.name+('.tar.gz' if platform.startswith('linux') else '.zip')),platform.startswith('macos'))
apk=Path(read(W/'android-build.json')['folder'])/'CursedLands.apk';dest=assets/f'CursedLands-{V}-android.apk';shutil.copy2(apk,dest);manifest.append({'name':dest.name,'bytes':dest.stat().st_size,'sha256':sha(dest)})
folder=W/f'CursedLands-{V}-web';shutil.copytree(W/'web/unsplit',folder,dirs_exist_ok=True)
(folder/'README.md').write_text(f'# Cursed Lands {V} — browser\n\nServe this directory over HTTPS with the supplied isolation headers. Playing requires your own original game data. The wiki needs no game data or account.\n\nHosted at https://cursedlands.wwworm.com/.\n')
(folder/'RELEASE-NOTES.md').write_text(body);shutil.copy2(validation,folder/'VALIDATION.json');archive(folder,assets/(folder.name+'.zip'))
(W/'assets.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Prepared',len(manifest),'platform archives and',len(hosted),'hosted files',flush=True)

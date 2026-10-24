from pathlib import Path
import hashlib,json,shutil,zipfile
w=Path(__file__).resolve().parent;r=w.parent/'repo';v='1.28.0'
folder=w/'rtx30'/f'CursedLands-{v}-windows-x86_64'
stock=w/f'CursedLands-{v}-windows-x86_64'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
info=json.loads((folder/'BUILD-INFO.json').read_text())
for name,h in info['files'].items():assert sha(folder/name)==h,name
assert sha(folder/'CursedLands.exe')==sha(stock/'CursedLands.exe')
assert sha(folder/'CursedLands.pck')==sha(stock/'CursedLands.pck')
info['base_package_build_info_sha256']=sha(stock/'BUILD-INFO.json')
info.update(source_tag='v'+v,release_type='stable',build_type='optional experimental DLSS-G SM86 package',native_windows_qualified=False)
info['runtime_validation']=json.loads((r/'docs/validation/release-1.28.0-2026-10-24.json').read_text())['platform_runtime']['windows-x86_64']
validation=folder/'docs/validation'
validation.mkdir(exist_ok=True)
shutil.copy2(r/'docs/validation/release-1.28.0-2026-10-24.json',validation/'release-1.28.0-2026-10-24.json')
shutil.copytree(r/'docs/validation/release-1.28.0',validation/'release-1.28.0',dirs_exist_ok=True)
shutil.copy2(r/'docs/integrations/dlssg-sm86-player.txt', folder/'README-RTX30.txt')
shutil.copy2(r/'docs/integrations/dlssg-sm86-player.txt', folder/'docs/integrations/dlssg-sm86-player.txt')
info['files']={str(p.relative_to(folder)):sha(p) for p in sorted(folder.rglob('*')) if p.is_file() and p.name not in ['BUILD-INFO.json','SHA256SUMS.txt']}
(folder/'BUILD-INFO.json').write_text(json.dumps(info,indent=2)+'\n')
(folder/'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.relative_to(folder)}\n' for p in sorted(folder.rglob('*')) if p.is_file() and p.name!='SHA256SUMS.txt'))
dest=w/'assets'/f'CursedLands-{v}-windows-x86_64-rtx30.zip'
expected={}
with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(folder.rglob('*')):
  if p.is_file():
   name=folder.name+'/'+str(p.relative_to(folder));z.write(p,name);expected[name]=sha(p)
with zipfile.ZipFile(dest) as z:
 assert z.testzip() is None and set(z.namelist())==expected.keys()
 for name,h in expected.items():assert hashlib.sha256(z.read(name)).hexdigest()==h,name
row={'name':dest.name,'bytes':dest.stat().st_size,'sha256':sha(dest),'all_members_verified':True}
manifest=json.loads((w/'assets.json').read_text())
manifest=[x for x in manifest if x['name']!=dest.name]+[row]
(w/'assets.json').write_text(json.dumps(manifest,indent=2)+'\n')
(w/'assets/SHA256SUMS.txt').write_text(''.join(f'{x["sha256"]}  {x["name"]}\n' for x in manifest))
print('Archived optional RTX 30 package:',dest.name,flush=True)

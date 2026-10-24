from pathlib import Path
import hashlib,io,json,os,re,shutil,subprocess,tarfile
W=Path(__file__).resolve().parent
R=W.parent/'pt-quality-20261024/repo'
V='1.28.0-experimental.2'
SOURCE=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip()
TREE=subprocess.check_output(['git','rev-parse','HEAD:game'],cwd=R,text=True).strip()
DEST=W/'preview2';DEST.mkdir(exist_ok=False)
STAGE=DEST/'source';STAGE.mkdir()
with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['git','archive',SOURCE+':game'],cwd=R))) as f:f.extractall(STAGE,filter='data')
BASE=W.parent/'release-1.27.0-20261024/release'
PROFILE=DEST/'export-profile'
U=PROFILE/'data/godot/app_userdata/Cursed Lands';U.mkdir(parents=True)
(U/'settings.cfg').write_text('[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\n')
(PROFILE/'data/godot/export_templates').symlink_to(Path.home()/'.local/share/godot/export_templates',target_is_directory=True)
ENV=dict(os.environ,**{f'XDG_{k}_HOME':str(PROFILE/k.lower()) for k in ['DATA','CONFIG','CACHE']})
EDITOR='/home/llm2x/.local/bin/godot-4'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(label,args):
 for attempt in range(2):
  log=DEST/(label+('-retry' if attempt else '')+'.log')
  with log.open('w') as f:code=subprocess.run([EDITOR,'--headless','--path',str(STAGE)]+args,env=ENV,stdout=f,stderr=subprocess.STDOUT,timeout=600).returncode
  errors=re.findall(r'(?m)^(?:ERROR:|SCRIPT ERROR:).*$',log.read_text())
  if not code and not errors:print(label,'passed',flush=True);return
  if attempt==0 and '--import' in args and any('no resource loaders' in e for e in errors):continue
  raise RuntimeError((label,code,errors[:10]))
run('import',['--editor','--import','--quit'])
presets=(STAGE/'export_presets.cfg').read_text()
project=(STAGE/'project.godot').read_text()
for platform,preset,exe,ext in [('linux-x86_64','Linux','CursedLands.x86_64','so'),('windows-x86_64','Windows','CursedLands.exe','dll')]:
 base=BASE/('CursedLands-1.27.0-'+platform)
 old=json.loads((base/'BUILD-INFO.json').read_text())
 assert sha(base/exe)==old['files'][exe]
 out=DEST/('CursedLands-'+V+'-'+platform);shutil.copytree(base,out)
 parts=re.split(r'(?=\[preset\.\d+\]\n)',presets)
 for i,part in enumerate(parts):
  if f'name="{preset}"' in part:parts[i]=part.replace('custom_template/release=""','custom_template/release='+json.dumps(str(base/exe)))
 (STAGE/'export_presets.cfg').write_text(''.join(parts))
 (STAGE/'project.godot').write_text(project.replace('boot_splash/image="res://assets/branding/splash.png"','boot_splash/image="res://assets/branding/splash-fsr.png"\ngraphics_sdk/amd=true') if ext=='dll' else project)
 run(platform,['--export-release',preset,str(out/exe)])
 if ext=='so':subprocess.run(['strip','--strip-unneeded',str(out/exe)],check=True)
 native=out/'src/native/bin';native.mkdir(parents=True,exist_ok=True)
 shutil.copy2(R/f'game/src/native/bin/libpath_nrd.{ext}',native)
 for p in (R/'game/src/native').glob('*NOTICES.txt'):shutil.copy2(p,out/p.name)
 for name in ['THIRD_PARTY_NOTICES.md','CHANGELOG.md']:shutil.copy2(R/name,out/name)
 for name in ['docs/integrations/path-tracing-nrd.md',f'docs/releases/{V}.md']:
  (out/name).parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/name,out/name)
 (out/'RELEASE-NOTES.md').write_text((R/f'docs/releases/{V}.md').read_text().replace('../validation/','docs/validation/').replace('../../THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.md'))
 shutil.copy2(out/'RELEASE-NOTES.md',out/'README-preview.md')
 (out/'SHA256SUMS.txt').unlink()
 info={'version':V,'build_type':'local unpublished NRD preview','source_commit':SOURCE,'game_tree':TREE,
  'platform':platform,'protocol':23,'formula_api':1,'package_api':3,'base_version':'1.27.0',
  'engine_source':old['engine_source'],'engine_patch_count':old['engine_patch_count'],
  'qualified_template_sha256':sha(base/exe),'engine_code_unchanged':True,
  'native_nrd_sha256':sha(native/f'libpath_nrd.{ext}'),
  'original_game_data_bundled':False,
  'files':{str(p.relative_to(out)):sha(p) for p in sorted(out.rglob('*')) if p.is_file() and p.name!='BUILD-INFO.json'}}
 (out/'BUILD-INFO.json').write_text(json.dumps(info,indent=2)+'\n')
print('Built local previews from',SOURCE,flush=True)

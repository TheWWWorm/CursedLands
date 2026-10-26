from pathlib import Path
import io,tarfile,zipfile,json,hashlib,subprocess,os,re,time,shutil
from release_config import WORK as root, REPO as repo, ANDROID_TEMPLATE, ANDROID_TEMPLATE_SHA256, ANDROID_VERSION_CODE, ANDROID_APP_ID, ANDROID_CERT_SHA256, PROTOCOL, assert_source
assert_source()
assert hashlib.sha256(ANDROID_TEMPLATE.read_bytes()).hexdigest()==ANDROID_TEMPLATE_SHA256
old=Path('/home/llm2x/Documents/EI/local/scratchpad/portal-60-20261007')
build=json.loads((root/'build.json').read_text());version=build['version'];source=build['source_commit']
stage=root/'android-stage';stage.mkdir()
with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['git','archive',source+':game'],cwd=repo))) as t:t.extractall(stage,filter='data')
assert f'config/version="{version}"' in (stage/'project.godot').read_text()
sha=lambda b:hashlib.sha256(b).hexdigest()
original={str(p.relative_to(stage)):sha(p.read_bytes()) for p in stage.rglob('*') if p.is_file()}
notices=stage/'src/release_licenses';notices.mkdir()
for name in ['LICENSE.md','THIRD_PARTY_NOTICES.md','licenses/LGPL-2.1.txt']:
 dest=notices/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(repo/name,dest)
for name,path in {'FONT_LICENSE.txt':repo/'game/fonts/LICENSE.txt','NATIVE_NAVIGATION_NOTICES.txt':repo/'game/src/native/NATIVE_NAVIGATION_NOTICES.txt','GODOT_LICENSES.txt':Path(build['platforms']['linux-x86_64']['folder'])/'GODOT_LICENSES.txt','NATIVE_ARCHIVE_NOTICES.txt':repo/'game/src/native/NATIVE_ARCHIVE_NOTICES.txt'}.items():shutil.copyfile(path,notices/name)
p=notices/'THIRD_PARTY_NOTICES.md';p.write_text(p.read_text().replace('game/fonts/LICENSE.txt','FONT_LICENSE.txt').replace('game/src/native/NATIVE_ARCHIVE_NOTICES.txt','NATIVE_ARCHIVE_NOTICES.txt').replace('game/src/native/NATIVE_NAVIGATION_NOTICES.txt','NATIVE_NAVIGATION_NOTICES.txt'))
preset=(old/'experimental6-android-stage/export_presets.cfg').read_text()
preset=preset.replace('version/code=16','version/code='+str(ANDROID_VERSION_CODE)).replace('version/name="1.0.3-experimental.6"','version/name="'+version+'"')
preset=re.sub(r'^custom_template/release=.*$', 'custom_template/release='+json.dumps(str(ANDROID_TEMPLATE)),preset,flags=re.M)
preset=re.sub(r'^exclude_filter=.*$', 'exclude_filter="src/native/source/*,src/native/archive/*,src/native/nrd/*,src/native/path_nrd.cfg,src/native/bin/libpath_nrd.so,src/native/bin/libpath_nrd.dll,src/game/fx/shaders/nrd/*,src/native/mod_lua/*,src/native/mod_lua.cfg,src/native/bin/libmod_lua.so,src/native/bin/libmod_lua.dll,src/native/bin/libterrain_search.so,src/native/bin/libterrain_search.dll,src/native/bin/libmod_archive.so,src/native/bin/libmod_archive.dll"', preset, flags=re.M)
assert 'package/unique_name="org.cursedlands.engine"' in preset and ('version/code='+str(ANDROID_VERSION_CODE)) in preset
(stage/'export_presets.cfg').write_text(preset)
(stage/'.godot').mkdir();creds=stage/'.godot/export_credentials.cfg';shutil.copyfile(old/'experimental6-android-stage/.godot/export_credentials.cfg',creds);creds.chmod(0o600)
sdk=Path('/home/llm2x/Documents/GoF3DRemake/local/toolchains/android-sdk');java=Path('/home/llm2x/opt/temurin-21.0.12.1')
profile=root/'android-profile';config=profile/'config/godot';config.mkdir(parents=True)
user=profile/'data/godot/app_userdata/Cursed Lands';user.mkdir(parents=True);(user/'settings.cfg').write_text('[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\n')
(config/'editor_settings-4.7.tres').write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/android/android_sdk_path = '+json.dumps(str(sdk))+'\nexport/android/java_sdk_path = '+json.dumps(str(java))+'\n')
env=dict(os.environ,XDG_CONFIG_HOME=str(profile/'config'),XDG_DATA_HOME=str(profile/'data'),XDG_CACHE_HOME=str(profile/'cache'),JAVA_HOME=str(java),ANDROID_HOME=str(sdk))
out=root/('CursedLands-'+version+'-android');out.mkdir();apk=out/'CursedLands.apk'
report={'source_commit':source,'version':version,'version_code':ANDROID_VERSION_CODE,'protocol':PROTOCOL,'steps':[],'template':json.loads((root/'release-container.json').read_text()),'folder':str(out)}
for label,args in [('android-import',['--editor','--import','--quit']),('android-export',['--export-release','Android',str(apk)])]:
 start=time.monotonic();log=root/(label+'.log');cmd=['/home/llm2x/.local/bin/godot-4','--headless','--path',str(stage),*args]
 with log.open('w') as f:r=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,env=env,timeout=240)
 errors=[s for s in log.read_text().splitlines() if re.search('ERROR:|Parse Error|Compile Error',s)]
 if r.returncode==0 and errors and label=='android-import' and any('no resource loaders' in e for e in errors):
  log.rename(root/'android-import-bootstrap.log')
  with log.open('w') as f:r=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,env=env,timeout=240)
  errors=[s for s in log.read_text().splitlines() if re.search('ERROR:|Parse Error|Compile Error',s)]
 report['steps'].append({'command':cmd,'exit':r.returncode,'seconds':time.monotonic()-start,'errors':errors});assert r.returncode==0 and not errors,(label,errors)
for f,h in original.items():
 if f!='export_presets.cfg' and sha((stage/f).read_bytes())!=h:
  # Godot rewrites hand-written .import files into canonical form; accept only when every committed setting survives.
  committed={l.replace(' ','') for l in subprocess.check_output(['git','show',source+':game/'+f],cwd=repo,text=True).splitlines() if '=' in l}
  regenerated=(stage/f).read_text().replace('\n"','"').replace('{\n','{').replace('\n}','}').replace(' ','')
  assert f.endswith('.import') and all(l in regenerated for l in committed),f
  report.setdefault('canonicalized_imports',[]).append(f)
with zipfile.ZipFile(apk) as z:
 assert z.testzip() is None
 assert sha(z.read('classes.dex')) == report['template']['classes_dex_sha256']
 assert all(s.encode() not in z.read('classes.dex') for s in ['qa_startup_hold','qa_boot_ready'])
 report['libraries']={n:sha(z.read(n)) for n in z.namelist() if n.startswith('lib/') and not n.endswith('/')}
 assert report['libraries']['lib/arm64-v8a/libgodot_android.so']==report['template']['engine_sha256']
 assert report['libraries']['lib/arm64-v8a/libc++_shared.so']==report['template']['libcxx_sha256']
 assert report['libraries']['lib/arm64-v8a/libterrain_search_android.so']==sha((repo/'game/src/native/bin/libterrain_search_android.so').read_bytes())
assert report['libraries']['lib/arm64-v8a/libmod_archive_android.so']==sha((repo/'game/src/native/bin/libmod_archive_android.so').read_bytes())
signer=sdk/'build-tools/36.0.0/apksigner';aapt=sdk/'build-tools/36.0.0/aapt'
cert=subprocess.check_output([str(signer),'verify','--print-certs',str(apk)],text=True,env=env);assert ANDROID_CERT_SHA256 in cert
manifest=subprocess.check_output([str(aapt),'dump','xmltree',str(apk),'AndroidManifest.xml'],text=True);badging=subprocess.check_output([str(aapt),'dump','badging',str(apk)],text=True)
assert 'debuggable' not in manifest and f"package: name='{ANDROID_APP_ID}' versionCode='{ANDROID_VERSION_CODE}' versionName='{version}'" in badging
assert all(n in manifest for n in ['org.godotengine.godot.service.GodotService',':simulation','org.godotengine.plugin.v2.EISimulation','android.intent.category.LAUNCHER','org.cursedlands.simulation.StartupApplication'])
(root/'android-manifest.txt').write_text(manifest);(root/'android-badging.txt').write_text(badging)
report.update(apk_sha256=sha(apk.read_bytes()),bytes=apk.stat().st_size,debuggable=False,matching_public_certificate=True,source_exact_except_export_preset_and_canonicalized_imports=True)
(root/'android-build.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))

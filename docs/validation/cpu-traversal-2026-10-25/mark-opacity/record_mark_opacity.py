from pathlib import Path
import gzip, hashlib, json, shutil, subprocess, re
s=Path(__file__).resolve().parent;r=s/'repo'
out=r/'docs/validation/cpu-traversal-2026-10-25/mark-opacity';out.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(name,value):(out/name).write_text(json.dumps(value,indent=2)+'\n')
def zipped(p,name):(out/(name+'.gz')).write_bytes(gzip.compress(p.read_bytes(),mtime=0))
visual=json.loads((s/'mark-opacity-rendered-checks.json').read_text())
assert len(visual)==6 and all(row['returncode']==0 for row in visual)
checks={}
names=['mark-opacity-probe','mark-opacity-before','mark-opacity-blood-pool-save','dar-mark-opacity-micro']
names+=['mark-opacity-'+row['test']+'-'+row['renderer'] for row in visual]
for name in names:
 folder=s/'runs'/name;log=folder/'run.log'
 zipped(log,name+'.log');shutil.copy2(folder/'command.json',out/(name+'-command.json'))
 checks[name]=[line for line in log.read_text().splitlines() if re.search(r'(checks=| checks |^FAIL |MARK_OPACITY_)',line)]
 for p in (folder/'data/godot/app_userdata/Cursed Lands').glob('*.json'):
  if p.name in ['ground-mark-animation.json','blood-pool-save.json']:shutil.copy2(p,out/(name+'-'+p.name))
registered=json.loads((s/'mark-opacity-registered/results.json').read_text());assert registered['passed'] and len(registered['cases'])==2
shutil.copy2(s/'mark-opacity-registered/results.json',out/'registered.json')
for row in registered['cases']:
 zipped(s/'mark-opacity-registered'/row['log'],'registered-'+row['id']+'.log');checks[row['id']]=row['result']
for p in s.glob('mark-opacity-windows-*.log'):zipped(p,p.name)
for name in ['mark-opacity-windows-checks.json','mark-opacity-rendered-checks.json','export_mark_opacity.py','mark_opacity_visual_checks.py','mark_opacity_windows_checks.py','dar_mark_opacity_micro.gd','legacy_mark_update.gd','mark_opacity_probe.gd','mark_opacity_candidate.gd','record_mark_opacity.py']:
 shutil.copy2(s/name,out/name)
for name in ['legacy_mark_update.gd','mark_opacity_candidate.gd']:
 p=out/name;p.write_text(p.read_text().rstrip()+'\n')
for name,filename in [('footprint_running_scene-forward_plus','running-footprints-2x.png'),('ground_mark_animation-forward_plus','blood-animated.png'),('ground_mark_receivers-gl_compatibility','projected-bridge.png')]:
 shutil.copy2(s/'runs'/('mark-opacity-'+name)/'data/godot/app_userdata/Cursed Lands'/filename,out/filename)
route=s/'runs/dar-mark-opacity-micro/data/godot/app_userdata/Cursed Lands/zone-traversal'
rows=json.loads((route/'mark-opacity-micro.json').read_text())
old=sum(row['usec'] for row in rows if not row['candidate'])/sum(row['queries'] for row in rows if not row['candidate'])
new=sum(row['usec'] for row in rows if row['candidate'])/sum(row['queries'] for row in rows if row['candidate'])
summary=json.loads((route/'zone-traversal.json').read_text());assert summary['failures']==0
zipped(route/'zone-traversal.json','dar-route.json')
write('dar-micro.json',{'gpu_job':'4e4a1ced4622471e','checks':summary['checks'],'failures':0,'before_us':old,'after_us':new,'saving_percent':100*(1-new/old),'saving_us':old-new,'rows':rows,
 'method':'ABBA of the unchanged old _update and production update on the same 32 live Dar footprint objects and ordinary ShaderMaterials. Restore identical lifetime/colour/uniform inputs outside each timed batch; compare exact mark fields, Color and float32 shader opacity afterward. No own CPU builds or checks ran during this heavy GPU job.',
 'limits':'Per-mark update microbenchmark, not a whole-frame or FPS claim. The earlier screening probe used a counting material; only these ordinary live materials supply the accepted performance figure.'})
baseline=subprocess.check_output(['git','show','1bc39a05:game/src/game/fx/ground_marks.gd'],cwd=r,text=True)
body=baseline[baseline.index('func _update('):baseline.index('\n\n# ------------------------------------------------------------------ creation')].rstrip()
fixture=(r/'tools/tests/ground_mark_opacity.gd').read_text();a=fixture.index('\tfunc _update(');b=fixture.index('\nfunc check(',a)
oracle='\n'.join(line[1:] for line in fixture[a:b].rstrip().splitlines());assert oracle==body
assert (s/'legacy_mark_update.gd').read_text().split('extends GroundMarks\n',1)[1].rstrip()==body
snapshot=s/'mark-opacity-game'
runtime=[p for p in (r/'game').rglob('*') if p.is_file() and '.godot' not in p.relative_to(r/'game').parts and (p.suffix in {'.gd','.gdshader','.tscn','.tres','.gdextension'} or 'src/native/bin/' in str(p))]
differences=[str(p.relative_to(r/'game')) for p in runtime if not (snapshot/p.relative_to(r/'game')).exists() or sha(p)!=sha(snapshot/p.relative_to(r/'game'))];assert not differences
packs={}
for name in ['mark-opacity-linux','mark-opacity-windows']:
 packs[name]={str(p.relative_to(s/name)):sha(p) for p in list((s/name).glob('runtime.*'))+list((s/name/'src/native/bin').glob('libterrain_search*'))}
original=Path('/home/llm2x/Documents/EI/inspection/ghidra/decompiled/functions/002cf/6cf9e0_FUN_006cf9e0.c')
write('provenance.json',{'base_commit':'1bc39a05','runtime_files_compared':len(runtime),'differences':differences,'snapshot':str(snapshot),'packs':packs,
 'source_sha256':{name:sha(r/name) for name in ['game/src/game/fx/ground_marks.gd','tools/tests/ground_mark_opacity.gd','tools/regressions.json']},'legacy_method_exact':True,'legacy_method_sha256':hashlib.sha256(body.encode()).hexdigest(),
 'original_source':{'path':str(original),'sha256':sha(original),'address':'0x6cf9e0'},
 'original_comparison':'The original updates growth, spin, lifetime and fade in float fields. Those computations and their order are unchanged. Only the Godot Color-versus-script-double comparison before renderer writes changes. An identical original Wine comparison of Godot calls is inapplicable; existing original blood captures remain referenced in the parent report. Windows/Wine checks here execute the remake. No original FPS claim.',
 'native_libraries':'Unchanged; this fix is GDScript only.'})
write('checks.json',checks)
print(json.dumps({'before_us':old,'after_us':new,'saving_percent':100*(1-new/old),'files':len(list(out.iterdir()))}))

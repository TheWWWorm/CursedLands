from pathlib import Path
import gzip,hashlib,json,shutil,re,subprocess
s=Path(__file__).resolve().parent;r=s/'repo'
out=r/'docs/validation/cpu-traversal-2026-10-25/mark-projection';out.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(name,obj):(out/name).write_text(json.dumps(obj,indent=2)+'\n')
def zipped(p,name):(out/(name+'.gz')).write_bytes(gzip.compress(p.read_bytes(),mtime=0))
checks={}
visual=[('footprint_running_scene','forward_plus'),('footprint_running_scene','gl_compatibility'),('footprint_surface_scene','forward_plus'),('ground_mark_receivers','forward_plus'),('ground_mark_animation','forward_plus')]
names=['mark-projection-before','mark-projection-first','mark-projection-snapshot','dar-mark-projection-legacy-micro']+['mark-projection-'+test+'-'+renderer for test,renderer in visual]
for name in names:
 folder=s/'runs'/name;log=folder/'run.log'
 zipped(log,name+'.log');shutil.copy2(folder/'command.json',out/(name+'-command.json'))
 checks[name]=[line for line in log.read_text().splitlines() if any(token in line for token in ['checks=', ' checks ', 'FAIL ', 'MARK_PROJECTION_NATIVE_TIMING','MARK_PROJECTION_LIVE_MICRO'])]
 for path in (folder/'data/godot/app_userdata/Cursed Lands').glob('*.json'):
  shutil.copy2(path,out/(name+'-'+path.name))
for name in ['mark-projection-registered','mark-projection-final-registered','mark-projection-rendered-registered']:
 receipt=json.loads((s/name/'results.json').read_text());assert receipt['passed']
 shutil.copy2(s/name/'results.json',out/(name+'.json'))
 for case in receipt['cases']:
  zipped(s/name/case['log'],name+'-'+case['id']+'.log');checks[name+'-'+case['id']]=case['result']
for p in s.glob('mark-projection-windows-*.log'):
 zipped(p,p.name);checks[p.stem]=[line for line in p.read_text().splitlines() if 'checks=' in line]
write('checks.json',checks)
for name in ['mark-projection-windows-checks.json','mark-projection-windows-final-checks.json','mark-projection-rendered-checks.json','dar-mark-projection-comparison-runs.json','dar-mark-projection-live-receipt.json']:
 shutil.copy2(s/name,out/name)
for name in ['dar_mark_projection_legacy_micro.gd','legacy_mark_projection.gd','run_mark_projection_dar.py','dar_mark_projection_comparison.py','prepare_mark_projection_profile.py','build_mark_projection.py','export_mark_projection_final.py','mark_projection_visual_checks.py','mark_projection_windows_checks.py']:
 shutil.copy2(s/name,out/name)
for name,image in [('mark-projection-footprint_running_scene-forward_plus','running-footprints-2x.png'),('mark-projection-ground_mark_receivers-forward_plus','projected-bridge.png'),('mark-projection-ground_mark_animation-forward_plus','blood-animated.png')]:
 shutil.copy2(s/'runs'/name/'data/godot/app_userdata/Cursed Lands'/image,out/image)
scopes_wanted=['game/fx/ground_mark_projection.gd:place','game/fx/ground_mark_projection.gd:sync','game/fx/ground_marks.gd:_process','game/fx/ground_marks.gd:_update','game/fx/ground_marks.gd:_tick','game/fx/ground_marks.gd:_drain_units']
profiles={}
for tag in ['script','native']:
 name='dar-mark-projection-profile-'+tag;folder=s/'runs'/name;zipped(folder/'run.log',name+'.log')
 route=folder/'data/godot/app_userdata/Cursed Lands/zone-traversal'
 for p in route.glob('*.json'):zipped(p,name+'-'+p.name)
 summary=json.loads((route/'zone-traversal.json').read_text());assert summary['failures']==0
 rows=[]
 for leg in range(4):
  scopes=json.loads((route/f'walk-{leg}-cpu-scopes.json').read_text());frames=scopes['game/fx/ground_marks.gd:_process']['calls']
  row={'leg':leg,'frames':frames,'scopes':{}}
  for key in scopes_wanted:
   scope=scopes.get(key,{'calls':0,'inclusive_us':0,'max_us':0})
   row['scopes'][key]=scope|{'ms_per_frame':scope['inclusive_us']/frames/1000,'us_per_call':scope['inclusive_us']/scope['calls'] if scope['calls'] else 0}
  rows.append(row)
 profiles[tag]={'checks':summary['checks'],'failures':summary['failures'],'legs':rows,'weighted_ms_per_frame':{key:sum(row['scopes'][key]['inclusive_us'] for row in rows)/sum(row['frames'] for row in rows)/1000 for key in scopes_wanted},'weighted_us_per_call':{key:sum(row['scopes'][key]['inclusive_us'] for row in rows)/max(1,sum(row['scopes'][key]['calls'] for row in rows)) for key in scopes_wanted}}
write('dar-profile-comparison.json',{'gpu_job':'d4145b84f5574445','profiles':profiles,'limits':'Inclusive scope comparison; do not sum nested scopes or infer whole-game FPS. Both modes use one instrumented export. Live actor counts/mark generation can vary. No own CPU builds or tests during measurement.'})
route=s/'runs/dar-mark-projection-legacy-micro/data/godot/app_userdata/Cursed Lands/zone-traversal'
rows=json.loads((route/'mark-projection-micro.json').read_text())
old_time=sum(row['usec'] for row in rows if not row['native'])/sum(row['queries'] for row in rows if not row['native'])
new_time=sum(row['usec'] for row in rows if row['native'])/sum(row['queries'] for row in rows if row['native'])
log=(s/'runs/dar-mark-projection-legacy-micro/run.log').read_text();summary=re.search(r'STANDARD_ZONE_TRAVERSAL (\d+) checks (\d+) failures',log);assert summary and int(summary[2])==0
baseline=subprocess.check_output(['git','show','3c0e375d:game/src/game/fx/ground_mark_projection.gd'],cwd=r,text=True)
body=baseline[baseline.index('func place('):baseline.index('\nfunc triangle(')]
assert (s/'legacy_mark_projection.gd').read_text().split('func place(',1)[1].rstrip()==body.split('func place(',1)[1].rstrip()
triangle=baseline[baseline.index('func triangle('):].strip().replace('GroundMarks.DEPTH','_thickness')
assert (r/'tools/tests/ground_mark_projection_native.gd').read_text().rsplit('func triangle(',1)[1].strip()==triangle.split('func triangle(',1)[1].strip()
write('dar-legacy-micro.json',{'gpu_job':'d4145b84f5574445','baseline_commit':'3c0e375d070593d52b0b112f54d2946114130687','baseline_method_exact':True,'baseline_method_sha256':hashlib.sha256(body.encode()).hexdigest(),'method':'Untouched previous place() in a separate projector over the same live world and marks; legacy/native/native/legacy synchronous blocks after the route. All five geometry channels verified before and after each block.','checks':int(summary[1]),'failures':0,'legacy_us_per_query':old_time,'native_us_per_query':new_time,'saving_us_per_query':old_time-new_time,'saving_percent':(1-new_time/old_time)*100,'raw':rows,'limits':'Forced geometry rebuilds only. Ordinary animated blood reuses its patch. This is not whole-game FPS.'})
zipped(route/'zone-traversal.json','dar-legacy-route.json')
snapshot=s/'mark-projection-final-game'
runtime=[p for p in (r/'game').rglob('*') if p.is_file() and '.godot' not in p.relative_to(r/'game').parts and (p.suffix in {'.gd','.gdshader','.tscn','.tres','.gdextension'} or 'src/native/bin/' in str(p))]
differences=[str(p.relative_to(r/'game')) for p in runtime if not (snapshot/p.relative_to(r/'game')).exists() or sha(p)!=sha(snapshot/p.relative_to(r/'game'))];assert not differences,differences
packs={}
for name in ['mark-projection-final-linux','mark-projection-final-windows','mark-projection-profile']:
 paths=list((s/name).glob('runtime.*'))+list((s/name/'src/native/bin').glob('libterrain_search*'))
 packs[name]={str(p.relative_to(s/name)):sha(p) for p in paths}
for platform,filename in [('linux','libterrain_search.so'),('windows','libterrain_search.dll'),('android','libterrain_search_android.so')]:
 p=s/('mark-projection-'+platform+'-build.json');receipt=json.loads(p.read_text());assert sha(r/'game/src/native/bin'/filename)==receipt['sha256']
 for name,value in receipt['source_sha256'].items():assert sha(r/'game/src/native/source'/name)==value,name
 shutil.copy2(p,out/p.name);zipped(s/('mark-projection-'+platform+'-build.log'),'mark-projection-'+platform+'-build.log')
source=['game/src/game/fx/ground_mark_projection.gd','game/src/native/source/ground_mark_projection.h','game/src/native/source/nav_kernel.cpp','tools/tests/ground_mark_projection_native.gd','tools/regressions.json']
original=Path('/home/llm2x/Documents/EI/inspection/ghidra/decompiled/functions/002cf')
write('provenance.json',{'base_commit':'3c0e375d070593d52b0b112f54d2946114130687','source_sha256':{name:sha(r/name) for name in source},'packs':packs,'runtime_files_compared':len(runtime),'runtime_snapshot':str(snapshot),'differences':differences,'android':'ARM64 rebuilt, not executed on device.','original_sources':[{'path':str(p),'sha256':sha(p)} for p in [original/'6cfb60_FUN_006cfb60.c',original/'6cf620_FUN_006cf620.c',original/'6cf9e0_FUN_006cf9e0.c']],'original_comparison':'0x6cfb60 constructs authored footprint atlas/orientation fields; 0x6cf620 selects blood atlas, growth and rotation; 0x6cf9e0 advances growth, rotation and fade. Those paths remain in script and are unchanged. Existing original GOG 1.06 Wine blood captures are referenced in the report. The exact modern terrain/floor mesh and soft-ground clipping API is remake-specific, so no identical original Wine geometry or FPS comparison is claimed. Windows/Wine checks execute the remake.','initial_failure':'The first test retained shared packed output arrays, then place() cleared those references. Its 145 live comparison failures were corrected by duplicating all five expected channels. Native output did not change; the first failed log is retained.'})
print(json.dumps({'legacy_us':old_time,'native_us':new_time,'saving_percent':(1-new_time/old_time)*100,'profiles':{key:value['weighted_ms_per_frame'] for key,value in profiles.items()},'runtime_files':len(runtime),'files':len(list(out.iterdir()))},indent=2))

from pathlib import Path
import gzip,hashlib,json,shutil,subprocess
s=Path(__file__).resolve().parent;r=s/'repo';out=r/'docs/validation/cpu-traversal-2026-10-25';recipes=out/'recipes'
def dump(name,obj):(out/name).write_text(json.dumps(obj,indent=2)+'\n')
def gz(p,name):(out/name).write_bytes(gzip.compress(p.read_bytes(),mtime=0))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
logs={}
for run in ['direct-pose-linux','direct-pose-typed-linux','direct-pose-cache-linux','direct-pose-cache-expanded','direct-pose-cache-expanded-fixed','direct-pose-final-before','direct-pose-gait-linux','direct-pose-first_person_shadows','direct-pose-first_person_running_down','direct-pose-ingos_direct_feedback']:
 logs[run]=s/'runs'/run/'run.log'
for test in ['direct_pose_native','direct_gait_continuity','picking_figures','star_particles']:
 logs['direct-pose-windows-'+test]=s/('direct-pose-windows-'+test+'.log')
for test in ['direct_pose_native','picking_figures','star_particles']:
 logs['direct-pose-registered-'+test]=s/'direct-pose-registered'/test/'run.log'
checks={}
for name,p in logs.items():
 if not p.exists():
  p=p.with_name('output.log')
 assert p.exists(),p
 gz(p,name+'.log.gz')
 checks[name]=[x for x in p.read_text(errors='replace').splitlines() if 'checks' in x or x.startswith(('FAIL ','ERROR:','SCRIPT ERROR:','DIRECT_POSE_NATIVE_TIMING'))]
dump('direct-pose-checks.json',checks)
runs=[]
for entry in json.loads((s/'dar-pose-comparison-runs.json').read_text()):
 name=entry['name'];p=s/'runs'/name/'data/godot/app_userdata/Cursed Lands/zone-traversal'
 j=json.loads((p/'zone-traversal.json').read_text());walking=[x for x in j['rows'] if x['phase'].startswith('walk-')]
 row={**entry,'checks':j['checks'],'failures':j['failures'],'adapter':j['adapter'],'actor_count':j['actor_count'],'window':j['window'],'options_sha256':hashlib.sha256(json.dumps(j['options'],sort_keys=True).encode()).hexdigest(),'walking_seconds':sum(x['seconds'] for x in walking),'walking_frames':sum(x['frames'] for x in walking),'legs':[{k:x[k] for k in ['phase','seconds','frames','frame_ms','from','to','reroutes','blocked']} for x in walking]}
 for phase in j['rows']:
  f=p/(phase['phase']+'-cpu-scopes.json')
  if f.exists():
   sc=json.loads(f.read_text());frames=sc['game/game.gd:_process']['calls']
   row.setdefault('scopes',{})[phase['phase']]={k:dict(v,ms_per_frame=v['inclusive_us']/frames/1000,frame_count=frames) for k,v in sc.items() if k.startswith(('game/direct_pose.gd:','game/fx/vegetation_interaction.gd:')) or k in ['game/unit.gd:anim_flush','game/fx/ground_marks.gd:_process','game/fx/terrain_details.gd:_update_motion']}
 for f in p.glob('*.json'):gz(f,name+'-'+f.name+'.gz')
 gz(s/'runs'/name/'run.log',name+'.log.gz');runs.append(row)
assert len(runs)==2 and all(x['returncode']==0 and x['failures']==0 for x in runs)
for key in ['adapter','actor_count','window','options_sha256','fixture_sha256']:
 assert len({str(x[key]) for x in runs})==1,key
assert all(len(x['legs'])==4 and all(not leg['blocked'] and not leg['reroutes'] for leg in x['legs']) for x in runs)
dump('dar-pose-comparison.json',{'job':'3912cd1d4dea40ff','method':'Matched instrumented script/native pair in one GPU Lab heavy job. Same pack, native library, fixed save, route and graphics settings; only --ei-script-direct-pose changes. No CPU builds/checks, per-phase image encoding or recording during measurements. Inclusive scopes must not be added. This pair establishes callback savings; it is not an uninstrumented whole-game FPS claim.','runs':runs})
for f in ['direct-pose-linux-build.json','direct-pose-windows-build.json','direct-pose-android-build.json','direct-pose-original-code.json','direct-pose-windows-checks.json','direct-pose-rendered-checks.json','dar-pose-comparison-runs.json']:
 shutil.copy2(s/f,out/f)
shutil.copy2(s/'direct-pose-registered/results.json',out/'direct-pose-registered.json')
for f in ['build_pose_native.py','export_pose_final.py','prepare_actor_detail_profile.py','prepare_pose_detail_profile.py','prepare_round4_profile.py','direct-pose-detail-profile-methods.json','dar_pose_comparison.py','pose_windows_checks.py','pose_rendered_checks.py','run_pose_visual.py','collect_pose_evidence.py']:
 shutil.copy2(s/f,recipes/f)
paths=['game/src/game/direct_pose.gd','game/src/native/source/direct_pose.h','game/src/native/source/build_profile.json','tools/tests/direct_pose_native.gd']
packs={}
for name in ['direct-pose-final-linux','direct-pose-final-windows','direct-pose-detail-profile']:
 folder=s/name;packs[name]={str(p.relative_to(folder)):sha(p) for p in folder.rglob('*') if p.is_file() and p.suffix in ['.pck','.so','.dll','.x86_64','.exe']}
dump('direct-pose-provenance.json',{'base_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip(),'source_sha256':{p:sha(r/p) for p in paths},'packs':packs,'rendered_job':'ac40ffb326914e81','android':'ARM64 library rebuilt; not executed on an Android device','original':'Original authored-key interpolation and parent composition inspected at 0x50acd0/0x50c230. Remake first-person DirectPose composition has no original Wine fixture; no original runtime/FPS equivalence claim.','fixture_correction':'The first expanded fixture used Animation.track_move_down(0), which attempts index -1 in this engine. Corrected the fixture to move index 3; its same-frame comparison is unchanged. The failed setup log remains included.','experiments':'Initial dynamic engine-call batch was slightly slower; typed calls improved modestly. Bounded, synchronously invalidated path/type metadata supplies the measured saving. Only the cached typed implementation is shipped.'})
print(json.dumps([{'name':x['name'],'checks':x['checks'],'scopes':{k:v for k,v in x['scopes'].items() if k.startswith('walk-')}} for x in runs],indent=2))

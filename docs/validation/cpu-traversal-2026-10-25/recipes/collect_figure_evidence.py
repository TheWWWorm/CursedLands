from pathlib import Path
import gzip,hashlib,json,shutil,subprocess,statistics
s=Path(__file__).resolve().parent;r=s/'repo';out=r/'docs/validation/cpu-traversal-2026-10-25';recipes=out/'recipes'
def dump(name,obj): (out/name).write_text(json.dumps(obj,indent=2)+'\n')
def gz(p,name): (out/name).write_bytes(gzip.compress(p.read_bytes(),mtime=0))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
checks={}
logs={'figure-contract-linux':s/'runs/figure-contract-linux-fixed/run.log','figure-contract-before':s/'runs/figure-contract-before/run.log','figure-contract-windows':s/'figure-windows-fixed-picking_figures.log'}
logs['figure-contract-linux-astral']=s/'runs/figure-contract-linux-astral/run.log'
for platform in ['linux','windows']:
 for test in ['picking_retained','picking_mechanisms','picking_bounds','picking_deformation','touch_unit_picking','arena_picking']:
  logs['figure-related-'+platform+'-'+test]=s/('runs/figure-related-'+test+'/run.log' if platform=='linux' else 'figure-windows-fixed-'+test+'.log')
for name,p in logs.items():
 gz(p,name+'.log.gz');checks[name]=[x for x in p.read_text(errors='replace').splitlines() if 'checks' in x or x.startswith('FAIL ') or x.startswith('PICKING_FIGURES_TIMING')]
dump('figure-checks.json',checks)
runs=[]
for entry in json.loads((s/'dar-figures-comparison-runs.json').read_text()):
 name=entry['name'];p=s/'runs'/name/'data/godot/app_userdata/Cursed Lands/zone-traversal'
 j=json.loads((p/'zone-traversal.json').read_text());walking=[x for x in j['rows'] if x['phase'].startswith('walk-')]
 row={**entry,'checks':j['checks'],'failures':j['failures'],'adapter':j['adapter'],'actor_count':j['actor_count'],'window':j['window'],'options_sha256':hashlib.sha256(json.dumps(j['options'],sort_keys=True).encode()).hexdigest(),'walking_fps':sum(x['frames'] for x in walking)/sum(x['seconds'] for x in walking),'walking_seconds':sum(x['seconds'] for x in walking),'walking_frames':sum(x['frames'] for x in walking),'legs':[{k:x[k] for k in ['phase','seconds','frames','frame_ms','from','to','reroutes','blocked']} for x in walking]}
 for phase in j['rows']:
  f=p/(phase['phase']+'-cpu-scopes.json')
  if f.exists():
   sc=json.loads(f.read_text());frames=sc['game/game.gd:_process']['calls']
   row.setdefault('scopes',{})[phase['phase']]={k:dict(v,ms_per_frame=v['inclusive_us']/frames/1000) for k,v in sc.items() if k in ['game/unit.gd:screen_rects','game/game.gd:pick_unit','game/game.gd:_pick_unit','ui/mesh_screen_rect.gd:of_context','game/unit.gd:anim_flush','game/fx/ground_marks.gd:_process']}
 for f in p.glob('*.json'):gz(f,name+'-'+f.name+'.gz')
 gz(s/'runs'/name/'run.log',name+'.log.gz');runs.append(row)
accepted=[x for x in runs if 'profile' not in x['name']]
assert len(accepted)==4 and all(x['returncode']==0 and x['failures']==0 for x in accepted)
for key in ['adapter','actor_count','window','options_sha256','fixture_sha256']:
 assert len({str(x[key]) for x in accepted})==1,key
assert all(len(x['legs'])==4 and all(not leg['blocked'] and not leg['reroutes'] for leg in x['legs']) for x in accepted)
means={}
for script in [True,False]:
 rows=[x for x in accepted if x['script_control']==script]
 means['before' if script else 'after']={'fps':sum(x['walking_frames'] for x in rows)/sum(x['walking_seconds'] for x in rows),'legs':{str(i):{'fps':sum(x['legs'][i]['frames'] for x in rows)/sum(x['legs'][i]['seconds'] for x in rows),'p95_ms_mean':statistics.mean(x['legs'][i]['frame_ms']['p95'] for x in rows)} for i in range(4)}}
dump('dar-figure-comparison.json',{'job':'73c7b3d8b6a643e4','method':'Profile script/native pair followed by uninstrumented script/native/native/script in one GPU Lab heavy job. Same exported production pack, helper library, route fixture and graphics options for the acceptance runs; only --ei-script-figure-picking changes. Metrics reading stays enabled in both modes. No per-phase image capture or recording.','aggregate':means,'runs':runs})
for f in ['native-build.json','figure-linux-checks.json','figure-windows-fixed-checks.json','dar-figures-comparison-runs.json']:
 shutil.copy2(s/f,out/('figure-native-build.json' if f=='native-build.json' else f))
for f in ['prepare_dar_standard.py','prepare_dar_tactical.py','prepare_dar_figure_profile.py','dar_standard_base.gd','dar_standard_route.gd','dar_standard_metrics.gd','dar_tactical_base.gd','dar_tactical_route.gd','dar_tactical_metrics.gd','dar_figure_comparison.py','dar-figure-profile-methods.json','export_figures.py','figure_windows_checks.py','figure_linux_checks.py','collect_figure_evidence.py']:shutil.copy2(s/f,recipes/f)
paths=['game/src/game/unit.gd','game/src/ui/mesh_screen_rect.gd','game/src/native/source/screen_rect.h','tools/tests/picking_figures.gd']
packs={}
for name in ['figure-picking-linux','figure-picking-windows','dar-figure-profile']:
 folder=s/name;packs[name]={str(p.relative_to(folder)):sha(p) for p in folder.rglob('*') if p.is_file() and p.suffix in ['.pck','.so','.dll','.x86_64','.exe']}
dump('figure-provenance.json',{'base_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip(),'source_sha256':{p:sha(r/p) for p in paths},'packs':packs,'android':'ARM64 library rebuilt, not executed on a device','original':'Same exact projected-vertex contract verified in original-picking-sources.json; no original Dar route/FPS equivalence claimed.'})
for run in ['dar-standard-profile-astral','dar-tactical-profile']:
 p=s/'runs'/run/'data/godot/app_userdata/Cursed Lands/zone-traversal'
 for f in p.glob('*.json'):gz(f,run+'-'+f.name+'.gz')
 gz(s/'runs'/run/'run.log',run+'.log.gz')
print(json.dumps(means,indent=2))

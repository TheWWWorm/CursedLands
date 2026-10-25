from pathlib import Path
import os,subprocess,json
s=Path(__file__).resolve().parent;rows=[]
for zone in ['gz1h','gz16g','gz21k']:
 cfg=json.loads((s/(zone+'.json')).read_text());cfg['seconds']=35;cfg['profile']=True
 path=s/('round2-'+zone+'.json');path.write_text(json.dumps(cfg))
 name='round2-profile-'+zone
 command=['python3',str(s/'run.py'),name,str(s/'traversal-scopes.gd'),'rendered','--gameplay-config='+str(path)]
 env=os.environ|{'BENCH_ENGINE':str(s/'round2-profile/runtime.x86_64')}
 with (s/'round2-profiles.log').open('a') as log:res=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT)
 raw=s/'runs'/name/'data/godot/app_userdata/Cursed Lands/traversal.json';scopes=raw.with_name('cpu-scopes.json')
 row={'name':name,'zone':zone,'returncode':res.returncode,'scopes':str(scopes)}
 if raw.exists():
  d=json.loads(raw.read_text());row.update({k:d[k] for k in ['fps','frame_ms','sim_seconds','wall_seconds','viewport_size','adapter','controlled','units']})
 rows.append(row);(s/'round2-profiles.json').write_text(json.dumps(rows,indent=2));print(json.dumps(row),flush=True)
 if res.returncode or not scopes.exists():raise SystemExit(1)

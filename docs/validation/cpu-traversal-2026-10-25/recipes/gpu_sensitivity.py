from pathlib import Path
import subprocess,os,json
s=Path(__file__).resolve().parent
rows=[]
for index,scale in enumerate([7,4]):
 name=f'resolution-{index}-scale{scale}'
 cfg=json.loads((s/'gz1h.json').read_text());cfg.update(seconds=45,name='traversal');cfg['options']['render_scale']=scale
 cp=s/(name+'.json');cp.write_text(json.dumps(cfg))
 env=os.environ|{'BENCH_ENGINE':str(s/'candidate/runtime.x86_64')}
 command=['python3',str(s/'run.py'),name,str(s/'traversal.gd'),'rendered','--gameplay-config='+str(cp)]
 with (s/'resolution-series.log').open('a') as f:r=subprocess.run(command,env=env,stdout=f,stderr=subprocess.STDOUT)
 p=s/'runs'/name/'data/godot/app_userdata/Cursed Lands/traversal.json'
 row={'name':name,'returncode':r.returncode}
 if p.exists():
  d=json.loads(p.read_text());row.update({k:d[k] for k in ['fps','frame_ms','sim_seconds','wall_seconds','render_scale','viewport_size','controlled']})
  frames=sorted(x[1]/1000 for x in d['timeline'] if x[0]>=5000000)
  row['after_5s']={'fps':1000*len(frames)/sum(frames),'p50_ms':frames[len(frames)//2],'p95_ms':frames[int(len(frames)*.95)]}
 rows.append(row);(s/'resolution-series.json').write_text(json.dumps(rows,indent=2));print(row,flush=True)
 if r.returncode:raise SystemExit(r.returncode)

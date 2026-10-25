from pathlib import Path
import subprocess,os,json,hashlib,time
s=Path(__file__).resolve().parent
rows=[]
for zone,modes in [('gz1h',['script','batch','batch','script']),('gz16g',['batch','script']),('gz21k',['script','batch'])]:
 for index,mode in enumerate(modes):
  name=f'mechanisms-render-{zone}-{index}-{mode}'
  cfg=json.loads((s/(zone+'.json')).read_text());cfg['seconds']=45;cfg['name']='traversal'
  cp=s/(name+'-cfg.json');cp.write_text(json.dumps(cfg))
  runtime=s/'mechanisms-linux/runtime.x86_64'
  env=os.environ|{'BENCH_ENGINE':str(runtime)}
  command=['python3',str(s/'run.py'),name,str(s/'traversal-mechanisms.gd'),'rendered','--gameplay-config='+str(cp)]
  if mode=='script': command.append('--bench-script-mechanisms')
  with (s/'mechanisms-render-series.log').open('a') as f:r=subprocess.run(command,env=env,stdout=f,stderr=subprocess.STDOUT)
  result=s/'runs'/name/'data/godot/app_userdata/Cursed Lands/traversal.json'
  row={'name':name,'zone':zone,'mode':mode,'returncode':r.returncode,'pack_sha256':hashlib.sha256(runtime.with_suffix('.pck').read_bytes()).hexdigest()}
  if result.exists():
   d=json.loads(result.read_text())
   row.update({k:d[k] for k in ['fps','frame_ms','sim_seconds','wall_seconds','viewport_size','adapter','controlled','units']})
   stable=[r[1]/1000 for r in d['timeline'] if r[0]>=5000000]
   stable.sort();row['after_5s']={'fps':1000*len(stable)/sum(stable),'p50_ms':stable[len(stable)//2],'p95_ms':stable[int(len(stable)*.95)],'p99_ms':stable[int(len(stable)*.99)]}
   row['valid']=d['viewport_size']==[1920,1080] and all(not u['dead'] for u in d['controlled']) and d['sim_seconds']>=d['wall_seconds']*.95 and len(d['commands'])>=10
  rows.append(row);(s/'mechanisms-render-series.json').write_text(json.dumps(rows,indent=2));print(json.dumps(row),flush=True)
  if r.returncode or not row.get('valid'):raise SystemExit(1)

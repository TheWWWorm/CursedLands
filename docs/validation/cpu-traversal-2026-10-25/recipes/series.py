from pathlib import Path
import subprocess,os,json,time,hashlib
s=Path(__file__).resolve().parent
zones={'gz1h':415,'gz2h':323,'gz16g':294,'gz7g':262,'gz21k':207}
rows=[]
for zone,pop in zones.items():
 for index,mode in enumerate(['script','native','native','script'] if zone!='gz1h' else ['script','native','native','script','script','native']):
  name=f'logic-{zone}-{index}-{mode}';out=s/'runs'/(name+'.json');cfg=json.loads((s/(zone+'.json')).read_text())
  cfg.update(name=name,out=str(out),ticks=600,profile=False,zone=zone,units=pop)
  cp=s/(name+'-cfg.json');cp.write_text(json.dumps(cfg))
  cmd=['python3',str(s/'run.py'),name,str(s/'repo/tools/benchmarks/campaign_cpu.gd'),'headless','--throughput-config='+str(cp)]
  if mode=='script':cmd+=['--ei-script-expressions']
  env=os.environ|{'BENCH_ENGINE':str(s/'candidate/runtime.x86_64')}
  with (s/'series.log').open('a') as f:r=subprocess.run(cmd,env=env,stdout=f,stderr=subprocess.STDOUT)
  row={'name':name,'zone':zone,'mode':mode,'returncode':r.returncode}
  if out.exists():
   d=json.loads(out.read_text());row.update({k:d[k] for k in ['wall_seconds','tick_seconds','tick_ms','sim_seconds','events','party','expression_native','rng_next']})
   row['state_sha256']=hashlib.sha256(json.dumps(d['state'],sort_keys=True).encode()).hexdigest()
  rows.append(row);(s/'logic-series.json').write_text(json.dumps(rows,indent=2));print(json.dumps(row),flush=True)
  if r.returncode:raise SystemExit(r.returncode)

from pathlib import Path
import json,os,subprocess
s=Path(__file__).resolve().parent
rows=[]
for name,pack in [('before','mechanisms-final-linux'),('after','vegetation-final-linux')]:
 run='vegetation-pair-'+name
 cmd=['python3',str(s/'run.py'),run,str(s/'traversal-admission.gd'),'rendered','--gameplay-config='+str(s/'phase-gz1h.json')]
 p=subprocess.run(cmd,env=os.environ|{'BENCH_ENGINE':str(s/pack/'runtime.x86_64')},stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 print(run,p.returncode,p.stdout[-1800:],flush=True)
 rows.append({'run':run,'pack':pack,'returncode':p.returncode,'command':cmd})
 (s/'vegetation-pair.json').write_text(json.dumps(rows,indent=2))
 if p.returncode:raise SystemExit(p.returncode)

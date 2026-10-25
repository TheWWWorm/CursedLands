from pathlib import Path
import subprocess,os,json
s=Path(__file__).resolve().parent;rows=[]
for mode in ['script','native']:
 name='ambient-profile-'+mode
 cmd=['python3',str(s/'run.py'),name,str(s/'traversal-ambient-scopes.gd'),'rendered','--gameplay-config='+str(s/'ambient-profile-gz21k.json')]
 if mode=='script':cmd+=['--bench-script-ambient-ground']
 p=subprocess.run(cmd,env=os.environ|{'BENCH_ENGINE':str(s/'ambient-profile/runtime.x86_64')},stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 print(name,p.returncode,p.stdout[-1800:],flush=True)
 rows.append({'name':name,'returncode':p.returncode,'command':cmd});(s/'ambient-profile-pair.json').write_text(json.dumps(rows,indent=2))
 if p.returncode:raise SystemExit(p.returncode)

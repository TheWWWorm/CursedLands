from pathlib import Path
import os, subprocess, json
s=Path(__file__).resolve().parent;r=s/'repo'
rows=[]
for test,renderer in [('footprint_running_scene','forward_plus'),('footprint_running_scene','gl_compatibility'),('ingos_direct_feedback','forward_plus'),('arena_ground_ink','gl_compatibility')]:
 name='ground-contact-'+test+'-'+renderer
 cmd=['python3',str(s/'run_ground_contact_visual.py'),name,str(r/'tools/tests'/str(test+'.gd')),'rendered']
 result=subprocess.run(cmd,cwd=s,env=os.environ|{'BENCH_ENGINE':str(s/'ground-contact-final-linux/runtime.x86_64'),'BENCH_DATA':'/home/llm2x/Documents/EI/inspection/extracted/app','BENCH_RENDERER':renderer,'BENCH_SIZE':'1280x720'},capture_output=True,text=True)
 print(name,result.returncode,result.stdout[-2500:],flush=True)
 rows.append({'test':test,'renderer':renderer,'command':cmd,'returncode':result.returncode})
 (s/'ground-contact-rendered-checks.json').write_text(json.dumps(rows,indent=2)+'\n')
 if result.returncode:raise SystemExit(result.returncode)

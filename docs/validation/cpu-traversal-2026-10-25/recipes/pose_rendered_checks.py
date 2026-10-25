from pathlib import Path
import subprocess,os,json
s=Path(__file__).resolve().parent;r=s/'repo';rows=[]
for test in ['first_person_shadows','first_person_running_down','ingos_direct_feedback']:
 command=['python3',str(s/'run_pose_visual.py'),'direct-pose-'+test,str(r/'tools/tests'/str(test+'.gd')),'rendered']
 result=subprocess.run(command,env=os.environ|{'BENCH_ENGINE':str(s/'direct-pose-final-linux/runtime.x86_64'),'BENCH_DATA':'/home/llm2x/Documents/EI/inspection/extracted/app','BENCH_SIZE':'1280x720'},capture_output=True,text=True)
 print(test,result.returncode,result.stdout[-4000:],flush=True)
 rows.append({'test':test,'command':command,'returncode':result.returncode})
 (s/'direct-pose-rendered-checks.json').write_text(json.dumps(rows,indent=2))
 if result.returncode:raise SystemExit(result.returncode)

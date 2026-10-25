from pathlib import Path
import os,subprocess,json,re
s=Path(__file__).resolve().parent;r=s/'repo';rows=[]
for test,data in [('picking_mechanisms','base'),('picking_retained','base'),('picking_bounds','base'),('picking_deformation','base'),('ingos_interactions','base'),('exhausted_interactions','base'),('exhausted_interactions','astral'),('astral_torch','astral'),('astral_chest_permission','astral')]:
 env=os.environ|{'BENCH_ENGINE':str(s/'mechanisms-linux/runtime.x86_64'),'BENCH_DATA':'/home/llm2x/Documents/EI/inspection/'+('extracted/app' if data=='base' else 'lost-in-astral/game')}
 name='mechanisms-check-'+test+'-'+data
 command=['python3',str(s/'run.py'),name,str(r/'tools/parity/gameplay_bootstrap.gd'),'headless','--suite-script='+str(r/'tools/tests'/str(test+'.gd')),'--suite-script-root='+str(r/'tools/tests'),'--suite-campaign='+('cursed_lands' if data=='base' else 'lost_in_astral'),'--suite-display=headless']
 result=subprocess.run(command,env=env,capture_output=True,text=True)
 log=(s/'runs'/name/'run.log').read_text();bad=[line for line in log.splitlines() if any(k in line for k in ['SCRIPT ERROR:','ERROR:','FAIL ','WARNING: ObjectDB'])]
 row={'test':test,'campaign':data,'returncode':result.returncode,'errors':bad,'summary':[line for line in log.splitlines() if 'checks' in line or 'TIMING' in line]}
 rows.append(row);(s/'mechanisms-checks.json').write_text(json.dumps(rows,indent=2));print(json.dumps(row),flush=True)

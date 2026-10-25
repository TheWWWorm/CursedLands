from pathlib import Path
import subprocess,os,json
s=Path(__file__).resolve().parent;r=s/'repo';p=s/os.environ.get('MECHANISMS_PACK','ambient-ground-windows')
env=os.environ|{'WINEPREFIX':str(s/'original-wine-prefix'),'WINEDEBUG':'-all'}
wine='/home/llm2x/Documents/EI/local/scratchpad/outstanding-issues-20261023/wine-runtime/wine-11.20-amd64-wow64/bin/wine'
rows=[]
for test in ['ambient_ground_native','vegetation_warmup']:
 command=[wine,str(p/'runtime.exe'),'--headless','--render-thread','safe','--audio-driver','Dummy','--','--no-movies','--ei-path=Z:/home/llm2x/Documents/EI/inspection/extracted/app','--tool=Z:'+str(r/'tools/tests'/str(test+'.gd'))]
 with (s/(p.name+'-'+test+'-safe.log')).open('w') as log: result=subprocess.run(command,cwd=p,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 text=(s/(p.name+'-'+test+'-safe.log')).read_text(errors='replace')
 row={'test':test,'returncode':result.returncode,'command':command,'summary':[line for line in text.splitlines() if 'checks' in line or 'SCRIPT ERROR' in line or 'ERROR:' in line]};rows.append(row);print(json.dumps(row),flush=True)
(s/(p.name+'-safe-checks.json')).write_text(json.dumps(rows,indent=2))

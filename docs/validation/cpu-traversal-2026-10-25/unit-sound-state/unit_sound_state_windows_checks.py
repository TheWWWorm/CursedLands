from pathlib import Path
import subprocess,os,json
s=Path(__file__).resolve().parent;r=s/'repo';p=s/'unit-sound-state-windows'
env=os.environ|{'WINEPREFIX':str(s/'original-wine-prefix'),'WINEDEBUG':'-all'}
wine='/home/llm2x/Documents/EI/local/scratchpad/outstanding-issues-20261023/wine-runtime/wine-11.20-amd64-wow64/bin/wine'
rows=[]
for test in ['unit_sound_state','hidden_presentation','combat_inputs','audio_bus_routes']:
 data='/home/llm2x/Documents/EI/inspection/lost-in-astral/game' if test=='touch_unit_picking' else '/home/llm2x/Documents/EI/inspection/extracted/app'
 command=[wine,str(p/'runtime.exe'),'--headless','--render-thread','safe','--audio-driver','Dummy','--','--no-movies','--ei-path=Z:'+data,'--tool=Z:'+str(r/'tools/tests'/str(test+'.gd'))]
 logpath=s/('unit-sound-state-windows-'+test+'.log')
 with logpath.open('w') as log:result=subprocess.run(command,cwd=p,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180)
 text=logpath.read_text(errors='replace');row={'test':test,'returncode':result.returncode,'command':command,'summary':[line for line in text.splitlines() if 'checks' in line or 'SCRIPT ERROR' in line or line.startswith('ERROR:') or line.startswith('FAIL ')]};rows.append(row);print(json.dumps(row),flush=True)
 (s/'unit-sound-state-windows-checks.json').write_text(json.dumps(rows,indent=2))
 if result.returncode:raise SystemExit(result.returncode)

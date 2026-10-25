from pathlib import Path
import subprocess,os,json
s=Path(__file__).resolve().parent;r=s/'repo';rows=[]
for test in ['picking_retained','picking_mechanisms','picking_bounds','picking_deformation','touch_unit_picking','arena_picking']:
 data='/home/llm2x/Documents/EI/inspection/lost-in-astral/game' if test=='touch_unit_picking' else '/home/llm2x/Documents/EI/inspection/extracted/app'
 p=subprocess.run(['python3',str(s/'run.py'),'figure-related-'+test,str(r/'tools/tests'/str(test+'.gd')),'headless'],env=os.environ|{'BENCH_ENGINE':str(s/'figure-picking-linux/runtime.x86_64'),'BENCH_DATA':data},capture_output=True,text=True)
 print(test,p.returncode,p.stdout[-1400:],flush=True);rows.append({'test':test,'returncode':p.returncode,'summary':p.stdout[-1400:]});(s/'figure-linux-checks.json').write_text(json.dumps(rows,indent=2))
 if p.returncode:raise SystemExit(p.returncode)

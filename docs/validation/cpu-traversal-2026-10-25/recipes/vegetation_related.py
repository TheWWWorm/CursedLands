from pathlib import Path
import json,os,subprocess
s=Path(__file__).resolve().parent;r=s/'repo';rows=[]
for test,mode in [('vegetation_warmup','headless'),('biome_cover_contact','headless'),('shader_compilation_live','rendered'),('shader_compilation_arena','rendered')]:
 cmd=['python3',str(s/'run.py'),'vegetation-related-'+test,str(r/'tools/tests'/str(test+'.gd')),mode]
 p=subprocess.run(cmd,env=os.environ|{'BENCH_ENGINE':str(s/'vegetation-final-linux/runtime.x86_64'),'BENCH_DATA':'/home/llm2x/Documents/EI/inspection/extracted/app'},stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 print(test,p.returncode,p.stdout[-2500:],flush=True)
 rows.append({'test':test,'returncode':p.returncode,'command':cmd})
 (s/'vegetation-related.json').write_text(json.dumps(rows,indent=2))

from pathlib import Path
import subprocess,sys,json,time,shutil
b=Path(__file__).resolve().parent
rows=[]
for tag,candidate in [('accepted-before-1',False),('accepted-after-1',True),('accepted-after-2',True),('accepted-before-2',False)]:
 cmd=[sys.executable,str(b/'run_windows.py'),tag,'dar_fixed_benchmark.gd','--dar-benchmark','--fg-relay','--zone-route-fg','--zone-route-zone=gz31j','--zone-route-peaceful','--warm-from=baseline-cpu']
 if candidate:cmd.append('--combined')
 started=time.time();r=subprocess.run(cmd,cwd=b)
 rows.append(dict(tag=tag,exit=r.returncode,start=started,finish=time.time()))
 (b/'accepted-paired-runs.json').write_text(json.dumps(rows,indent=2))
 if (b/tag/'result.json').exists():shutil.rmtree(b/tag/'prefix')
 if r.returncode:sys.exit(r.returncode)

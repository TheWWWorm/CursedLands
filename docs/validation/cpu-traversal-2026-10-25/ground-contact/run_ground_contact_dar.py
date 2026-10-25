from pathlib import Path
import os, subprocess, json, time
s=Path(__file__).resolve().parent
save=s/'runs/dar-standard-profile-astral/data/godot/app_userdata/Cursed Lands/saves/lost_in_astral/zone-route.sav'
cmd=['python3',str(s/'run.py'),'dar-ground-contact-live-micro',str(s/'dar_ground_contact_micro.gd'),'rendered','--dar-benchmark','--zone-route-zone=gz31j','--zone-route-save='+str(save),'--zone-route-peaceful','--zone-route-recording']
started=time.time()
result=subprocess.run(cmd,cwd=s,env=os.environ|{'BENCH_ENGINE':str(s/'ground-contact-final-linux/runtime.x86_64')},capture_output=True,text=True)
(s/'dar-ground-contact-live-receipt.json').write_text(json.dumps({'command':cmd,'start':started,'finish':time.time(),'returncode':result.returncode},indent=2)+'\n')
print(result.stdout,flush=True)
if result.returncode:raise SystemExit(result.returncode)
subprocess.run(['python3',str(s/'dar_ground_contact_comparison.py')],cwd=s,check=True)

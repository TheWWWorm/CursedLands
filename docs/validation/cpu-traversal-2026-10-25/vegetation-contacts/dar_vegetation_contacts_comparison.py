from pathlib import Path
import subprocess,os,json,time,shutil,hashlib
s=Path(__file__).resolve().parent;rows=[]
fixture=s/'runs/dar-standard-profile-astral/data/godot/app_userdata/Cursed Lands/saves/lost_in_astral/zone-route.sav'
assert fixture.exists()
sequence=[('profile-script','vegetation-contact-profile',True),('profile-native','vegetation-contact-profile',False)]
for tag,pack,script in sequence:
 name='dar-vegetation-contacts-'+tag
 cmd=['python3',str(s/'run.py'),name,str(s/'dar_standard_metrics.gd'),'rendered','--dar-benchmark','--zone-route-zone=gz31j','--zone-route-save='+str(fixture),'--zone-route-peaceful','--zone-route-recording']
 if script:cmd.append('--ei-script-vegetation-contacts')
 started=time.time();print('BEGIN',name,flush=True)
 result=subprocess.run(cmd,cwd=s,env=os.environ|{'BENCH_ENGINE':str(s/pack/'runtime.x86_64')},capture_output=True,text=True)
 print(name,result.returncode,result.stdout[-700:],flush=True)
 rows.append({'name':name,'pack':pack,'script_control':script,'returncode':result.returncode,'command':cmd,'start':started,'finish':time.time(),'fixture_sha256':hashlib.sha256(fixture.read_bytes()).hexdigest()})
 (s/'dar-vegetation-contacts-comparison-runs.json').write_text(json.dumps(rows,indent=2))
 if result.returncode:raise SystemExit(result.returncode)

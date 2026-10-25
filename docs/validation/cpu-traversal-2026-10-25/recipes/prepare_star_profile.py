from pathlib import Path
import re
s=Path(__file__).resolve().parent
text=(s/'prepare_round4_profile.py').read_text()
text=text[:text.index('# Eligible mechanism census')]+'''\n(s/'star-profile-methods.json').write_text(json.dumps(wrapped,indent=2))
shutil.copy2(s/'runtime.x86_64',out/'runtime.x86_64');shutil.copytree(r/'game/src/native/bin',out/'src/native/bin',dirs_exist_ok=True)
with (s/'star-profile-export.log').open('w') as log:
 result=subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(dest),'--export-pack','Linux',str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT)
print('Star profile export',result.returncode,flush=True);raise SystemExit(result.returncode)
'''
text=text.replace("dest=s/'round4-profile-game';out=s/'round4-profile'","dest=s/'star-profile-game';out=s/'star-profile'")
text=re.sub(r'extra=\{.*?\n\}',"extra={'game/fx/particle_system.gd':['_process','_tick']}",text,count=1,flags=re.S)
exec(compile(text,str(s/'prepare_star_profile.py'),'exec'))

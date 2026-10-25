from pathlib import Path
import subprocess,shutil,os,json
s=Path(__file__).resolve().parent;r=s/'repo';game=s/'mark-opacity-game'
assert not game.exists();subprocess.run(['cp','-a','--reflink=auto',str(r/'game'),str(game)],check=True)
rows=[]
for platform,preset,ext,base in [('linux','Linux','x86_64','combined-main-linux'),('windows','Windows','exe','star-particles-final-windows')]:
 out=s/('mark-opacity-'+platform);out.mkdir();shutil.copy2(s/base/('runtime.'+ext),out/('runtime.'+ext));shutil.copytree(r/'game/src/native/bin',out/'src/native/bin')
 with (s/('mark-opacity-'+platform+'-export.log')).open('w') as log:p=subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(game),'--export-pack',preset,str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT)
 print(platform,p.returncode,flush=True)
 if p.returncode:raise SystemExit(p.returncode)

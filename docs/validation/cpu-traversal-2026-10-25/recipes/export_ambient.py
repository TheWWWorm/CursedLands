from pathlib import Path
import subprocess,shutil,os,hashlib
s=Path(__file__).resolve().parent;r=s/'repo';game=s/'ambient-ground-game'
subprocess.run(['cp','-a','--reflink=auto',str(r/'game'),str(game)],check=True)
(game/'src/ei/figure.gd').write_bytes(subprocess.check_output(['git','show','18b58726:game/src/ei/figure.gd'],cwd=r))
out=s/'ambient-ground-linux';out.mkdir()
shutil.copy2(s/'vegetation-final-linux/runtime.x86_64',out/'runtime.x86_64')
shutil.copytree(r/'game/src/native/bin',out/'src/native/bin')
with (s/'ambient-ground-linux-export.log').open('w') as log:
 subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(game),'--export-pack','Linux',str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT,check=True)
print(hashlib.sha256((out/'runtime.pck').read_bytes()).hexdigest(),flush=True)
shutil.copy2(s/'native-build.json',s/'ambient-ground-native-linux-build.json')

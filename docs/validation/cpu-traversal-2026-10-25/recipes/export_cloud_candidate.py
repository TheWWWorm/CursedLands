from pathlib import Path
import subprocess,shutil,os
s=Path(__file__).resolve().parent;r=s/'repo';game=s/'cloud-preparation-game';out=s/'cloud-preparation-linux'
assert not game.exists();subprocess.run(['cp','-a','--reflink=auto',str(r/'game'),str(game)],check=True)
(game/'src/ei/figure.gd').write_bytes(subprocess.check_output(['git','show','18b58726:game/src/ei/figure.gd'],cwd=r))
out.mkdir();shutil.copy2(s/'runtime.x86_64',out/'runtime.x86_64');shutil.copytree(game/'src/native/bin',out/'src/native/bin')
with (s/'cloud-preparation-export.log').open('w') as log:p=subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(game),'--export-pack','Linux',str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT)
print('Cloud export',p.returncode);raise SystemExit(p.returncode)

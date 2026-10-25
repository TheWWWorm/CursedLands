from pathlib import Path
import subprocess,shutil,os,json,hashlib
s=Path(__file__).resolve().parent;r=s/'repo';game=s/'star-particles-game'
shutil.copytree(r/'game/src/native/bin',game/'src/native/bin',dirs_exist_ok=True)
rows=[]
for platform,preset,ext,base in [('linux','Linux','x86_64','ambient-ground-linux'),('windows','Windows','exe','ambient-ground-windows')]:
 out=s/('star-particles-final-'+platform);out.mkdir()
 shutil.copy2(s/base/('runtime.'+ext),out/('runtime.'+ext));shutil.copytree(game/'src/native/bin',out/'src/native/bin')
 with (s/('star-particles-final-'+platform+'-export.log')).open('w') as log:
  p=subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(game),'--export-pack',preset,str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT)
 rows.append({'platform':platform,'returncode':p.returncode,'pck_sha256':hashlib.sha256((out/'runtime.pck').read_bytes()).hexdigest() if (out/'runtime.pck').exists() else ''})
 print(rows[-1],flush=True)
 if p.returncode:raise SystemExit(p.returncode)
(s/'star-particles-exports.json').write_text(json.dumps(rows,indent=2))

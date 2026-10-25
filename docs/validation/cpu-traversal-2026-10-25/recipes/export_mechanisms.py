from pathlib import Path
import subprocess,shutil,os,json,hashlib,sys
s=Path(__file__).resolve().parent;r=s/'repo';prefix=sys.argv[1] if len(sys.argv)>1 else 'mechanisms';game=s/(prefix+'-game')
subprocess.run(['cp','-a','--reflink=auto',str(r/'game'),str(game)],check=True)
(game/'src/ei/figure.gd').write_bytes(subprocess.check_output(['git','show','18b58726:game/src/ei/figure.gd'],cwd=r))
for platform,preset,template in [('linux','Linux','picking-candidate/runtime.x86_64'),('windows','Windows','picking-windows/runtime.exe')]:
 out=s/(prefix+'-'+platform);out.mkdir()
 shutil.copy2(s/template,out/Path(template).name)
 shutil.copytree(r/'game/src/native/bin',out/'src/native/bin')
 with (s/(prefix+'-'+platform+'-export.log')).open('w') as log:
  p=subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(game),'--export-pack',preset,str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT)
  if p.returncode:raise SystemExit(p.returncode)
 print('Exported',platform,hashlib.sha256((out/'runtime.pck').read_bytes()).hexdigest(),flush=True)
shutil.copy2(s/'native-build.json',s/'mechanisms-native-build.json')

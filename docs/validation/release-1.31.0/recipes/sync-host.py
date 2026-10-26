from pathlib import Path
import json,shutil,hashlib
w=Path(__file__).resolve().parent;r=w.parent/'repo';src=w/'web/host/public';dest=r/'public'
files={p.relative_to(src):p for p in src.rglob('*') if p.is_file()}
for rel,p in files.items():
 target=dest/rel
 if not target.exists() or p.read_bytes()!=target.read_bytes():target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
removed=[]
for p in dest.rglob('*'):
 if p.is_file() and p.relative_to(dest) not in files:removed.append(str(p.relative_to(dest)));p.unlink()
shutil.copy2(w/'web/host/parts.json',r/'parts.json')
m={str(rel):hashlib.sha256(p.read_bytes()).hexdigest() for rel,p in files.items()};(w/'hosted-files.json').write_text(json.dumps(m,indent=2,sort_keys=True)+'\n');print('Synced',len(files),'files; removed',removed)

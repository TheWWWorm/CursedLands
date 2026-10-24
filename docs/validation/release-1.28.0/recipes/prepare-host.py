from pathlib import Path
import json,shutil,sys,hashlib,re,subprocess
w=Path(__file__).resolve().parent;r=w.parent/'repo';web=w/'web/unsplit'
shutil.copytree(r/'public/wiki',web/'wiki',dirs_exist_ok=True)
subprocess.run([sys.executable,str(r/'tools/prepare_public_wiki.py'),'--refresh-ui','--output',str(web/'wiki')],check=True)
subprocess.run([sys.executable,str(r/'tools/prepare_public_wiki.py'),'--check','--output',str(web/'wiki')],check=True)
counts={}
for p in (web/'wiki/data').rglob('index.json'):
 j=json.loads(p.read_text());counts[str(p.relative_to(web))]={'entries':len(j['entries']),'article_version':j['version']}
assert len(counts)==6,counts
# Keep the article-export version; the frontend version is recorded separately.
manifest={str(p.relative_to(web)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (web/'wiki').rglob('*') if p.is_file()}
(w/'wiki-package.json').write_text(json.dumps({'frontend_version':'1.28.0','indexes':counts,'files':len(manifest),'manifest_sha256':hashlib.sha256(json.dumps(manifest,sort_keys=True).encode()).hexdigest(),'content':'Current public wiki retained with an unchanged Cut content interface; original article-export version preserved.'},indent=2)+'\n')
sys.path.insert(0,str(w))
import prepare_web_host
print(prepare_web_host.prepare(web,w/'web/host/public'))

"""Read-only Cloudflare verification of committed current assets and split files."""
import concurrent.futures,hashlib,json,re,subprocess,time,urllib.request,urllib.error
from release_config import WORK as w, REPO as r, VERSION, PREVIOUS_VERSION
base='https://cursedlands.wwworm.com/'
headers={'User-Agent':'Mozilla/5.0 CursedLandsReleaseVerification','Cache-Control':'no-cache'}
assert not subprocess.check_output(['git','status','--porcelain','--','public','parts.json'],cwd=r,text=True).strip(), 'Commit public/ and parts.json before deployment verification'
expected=(r/'public/BUILD-INFO.json').read_bytes()
assert json.loads(expected)['version']==VERSION
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip()
assert subprocess.check_output(['git','show',head+':public/BUILD-INFO.json'],cwd=r)==expected

def read(name):
    with urllib.request.urlopen(urllib.request.Request(base+name,headers=headers),timeout=30) as response:
        data=response.read();assert response.status==200
        return data,{k.lower():v for k,v in response.headers.items()}
for attempt in range(60):
    try:
        if read('BUILD-INFO.json')[0]==expected:break
        print(f'Waiting for Cloudflare to serve {VERSION}',flush=True)
    except (urllib.error.URLError,TimeoutError) as e:print('Waiting for deployment:',str(e),flush=True)
    time.sleep(10)
else:raise SystemExit('New committed build did not reach the live site')
manifest=json.loads(re.search(r'const HASHES = (\{.*?\});',(r/'public/service-worker.js').read_text(),re.S)[1])
manifest.update({'service-worker.js':hashlib.sha256((r/'public/service-worker.js').read_bytes()).hexdigest(),'BUILD-INFO.json':hashlib.sha256(expected).hexdigest()})
changed=subprocess.check_output(['git','diff','--name-only','v'+PREVIOUS_VERSION,head,'--','public'],cwd=r,text=True).splitlines()
for name in changed:
    path=r/name
    if path.is_file() and path.name!='_headers':manifest[str(path.relative_to(r/'public'))]=hashlib.sha256(path.read_bytes()).hexdigest()
splits=json.loads((r/'parts.json').read_text())
for name,split in splits.items():
    name=name.lstrip('/')
    for index in range(split['count']):
        part=f'{name}.part{index}';manifest[part]=hashlib.sha256((r/'public'/part).read_bytes()).hexdigest()
    raw=b''.join((r/'public'/f'{name}.part{i}').read_bytes() for i in range(split['count']))
    assert len(raw)==split['size'],name
    manifest[name]=hashlib.sha256(raw).hexdigest()

def check(row):
    name,digest=row
    for attempt in range(10):
        try:
            data,h=read(name);actual=hashlib.sha256(data).hexdigest()
            if actual==digest:break
            if attempt==9:raise AssertionError((name,actual,digest))
        except (urllib.error.URLError,TimeoutError):
            if attempt==9:raise
        time.sleep(2)
    for key,value in [('cross-origin-opener-policy','same-origin'),('cross-origin-embedder-policy','require-corp'),('cross-origin-resource-policy','same-origin')]:assert h.get(key)==value,(name,key,h.get(key))
    if name.endswith('.wasm'):assert h.get('content-type','').split(';')[0]=='application/wasm',name
    if 'content-length' in h:assert int(h['content-length'])==len(data),name
    return name,{'bytes':len(data),'sha256':actual,'isolation_headers':True}
files={}
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    for name,info in pool.map(check,manifest.items()):
        files[name]=info
        if len(files)%2000==0:print('Verified',len(files),'live assets',flush=True)
report={'site':base,'commit':head,'version':VERSION,'previous_stable':'v'+PREVIOUS_VERSION,'verified_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'live_files':files,'all_live_hashes_match':True,'scope':'Every changed hosted asset since 1.31.0, complete service-worker engine cache, build metadata, all split parts and reassembled files'}
(w/'deployment.json').write_text(json.dumps(report,indent=2)+'\n')
print('LIVE VERIFIED:',len(files),'files; committed hashes and isolation headers match',flush=True)

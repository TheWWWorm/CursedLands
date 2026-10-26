from pathlib import Path
import hashlib,json,subprocess,time
W=Path(__file__).resolve().parent
R=W.parent/'repo'
REPO='TheWWWorm/CursedLands'
data=json.loads(subprocess.check_output(['gh','api',f'repos/{REPO}/releases/tags/v1.31.0'],text=True))
assert not data['draft'] and not data['prerelease'] and data['tag_name']=='v1.31.0'
files={p.name:p for p in (W/'assets').iterdir() if p.is_file()}
assert set(files)=={a['name'] for a in data['assets']}
for a in data['assets']:
    p=files[a['name']]
    assert a['state']=='uploaded' and a['size']==p.stat().st_size
    assert a['digest']=='sha256:'+hashlib.sha256(p.read_bytes()).hexdigest(),a['name']
assert data['body'].replace('\r\n','\n').strip()==(W/'release-body.md').read_text().strip()
ref=json.loads(subprocess.check_output(['gh','api',f'repos/{REPO}/git/ref/tags/v1.31.0'],text=True))['object']
if ref['type']=='tag':ref=json.loads(subprocess.check_output(['gh','api',f'repos/{REPO}/git/tags/'+ref['sha']],text=True))['object']
expected=subprocess.check_output(['git','rev-parse','v1.31.0^{}'],cwd=R,text=True).strip()
assert ref['type']=='commit' and ref['sha']==expected
download=W/'published-downloads';download.mkdir(exist_ok=True)
subprocess.run(['gh','release','download','v1.31.0','--repo',REPO,'--pattern','SHA256SUMS.txt','--dir',str(download)],check=True)
assert (download/'SHA256SUMS.txt').read_bytes()==(W/'assets/SHA256SUMS.txt').read_bytes()
record={
    'release_url':data['html_url'],'tag':'v1.31.0','tag_commit':expected,
    'isDraft':data['draft'],'isPrerelease':data['prerelease'],'published_at':data['published_at'],
    'verified_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
    'all_asset_names_sizes_and_server_sha256_match':True,'checksum_download_matches':True,
    'asset_policy_check':'passed before upload for every asset',
    'assets':[{k:a[k] for k in ['name','size','digest','browser_download_url']} for a in data['assets']],
}
(W/'publication.json').write_text(json.dumps(record,indent=2)+'\n')
print(data['html_url'])
print('Verified public stable release, immutable tag, all seven upload digests and downloaded checksums')

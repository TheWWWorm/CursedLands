"""Extract the verified published 1.25.0 web asset for the upgrade check."""
from pathlib import Path
import hashlib,json,zipfile
from release_config import WORK, PREVIOUS_WEB_ARCHIVE, PREVIOUS_WEB_SHA256, PREVIOUS_VERSION
assert hashlib.sha256(PREVIOUS_WEB_ARCHIVE.read_bytes()).hexdigest()==PREVIOUS_WEB_SHA256
out=WORK/f'prev-{PREVIOUS_VERSION}'
assert not out.exists(), f'Input already prepared: {out}; keep its existing bytes'
with zipfile.ZipFile(PREVIOUS_WEB_ARCHIVE) as archive:
    assert archive.testzip() is None
    for name in archive.namelist():
        target=out/name
        assert target.resolve().is_relative_to(out.resolve()),name
    archive.extractall(out)
    for name in archive.namelist():
        if not name.endswith('/'): assert (out/name).read_bytes()==archive.read(name),name
folder=out/f'CursedLands-{PREVIOUS_VERSION}-web'
info=json.loads((folder/'BUILD-INFO.json').read_text())
assert info['version']==PREVIOUS_VERSION
assert hashlib.sha256((folder/'index.pck').read_bytes()).hexdigest()==info['pck_sha256']
assert hashlib.sha256((folder/'index.wasm').read_bytes()).hexdigest()==info['wasm_sha256']
(WORK/'previous-browser-input.json').write_text(json.dumps({'version':PREVIOUS_VERSION,'archive':str(PREVIOUS_WEB_ARCHIVE),'archive_sha256':PREVIOUS_WEB_SHA256,'folder':str(folder),'build_info':info,'service_worker_sha256':hashlib.sha256((folder/'service-worker.js').read_bytes()).hexdigest()},indent=2)+'\n')
print('Verified original published browser input:',folder)

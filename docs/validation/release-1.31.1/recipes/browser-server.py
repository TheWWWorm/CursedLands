"""Loopback-only old/new origins. Run before the GPU Lab browser checks."""
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
import hashlib,json,mimetypes,os,re,threading
from release_config import WORK as W, VERSION, PREVIOUS_VERSION
OLD=W/f'prev-{PREVIOUS_VERSION}/CursedLands-{PREVIOUS_VERSION}-web'
NEW=W/'web/unsplit'
PORT=int(os.environ.get('CL_RELEASE_PORT','30990'))
def metadata(folder):
    info=json.loads((folder/'BUILD-INFO.json').read_text())
    return {'version':info['version'],'cache':re.search("const ENGINE_CACHE = '([^']+)'",(folder/'service-worker.js').read_text())[1], 'pck':hashlib.sha256((folder/'index.pck').read_bytes()).hexdigest()}
assert metadata(OLD)['version']==PREVIOUS_VERSION
assert metadata(NEW)['version']==VERSION
class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        phase=(W/'browser-phase.txt').read_text().strip() if self.server.server_port==PORT else 'new'
        name=self.path.split('?')[0].lstrip('/') or 'index.html'
        if name.endswith('/'):name+='index.html'
        if '..' in name.split('/'):self.send_error(400);return
        if name=='release-check.html':data=(W/'browser-check.html').read_bytes();mime='text/html'
        elif name in ['__expected','__previous']:data=json.dumps(metadata(NEW if name=='__expected' else OLD)).encode();mime='application/json'
        else:
            path=(OLD if phase=='old' else NEW)/('index.icon.png' if name=='favicon.ico' else name)
            if not path.is_file():self.send_error(404);return
            data=path.read_bytes();mime=mimetypes.guess_type(str(path))[0] or 'application/octet-stream'
        with (W/'browser-requests.jsonl').open('a') as log:log.write(json.dumps({'phase':phase,'port':self.server.server_port,'name':name})+'\n')
        self.send_response(200)
        for k,v in {'Content-Type':mime,'Content-Length':str(len(data)),'Cache-Control':'no-cache','Cross-Origin-Opener-Policy':'same-origin','Cross-Origin-Embedder-Policy':'require-corp','Cross-Origin-Resource-Policy':'same-origin'}.items():self.send_header(k,v)
        self.end_headers();self.wfile.write(data)
    def do_POST(self):
        if self.path!='/__result':self.send_error(404);return
        data=self.rfile.read(int(self.headers['Content-Length']));report=json.loads(data)
        assert report['version']==VERSION and report['cache_upgrade']['passed']
        (W/'browser-validation.json').write_bytes(data);self.send_response(200);self.end_headers()
    def log_message(self,*args):pass
(W/'browser-phase.txt').write_text('old\n')
threading.Thread(target=ThreadingHTTPServer(('127.0.0.1',PORT+1),Handler).serve_forever,daemon=True).start()
print(f'Upgrade origin http://127.0.0.1:{PORT}; fresh origin http://127.0.0.1:{PORT+1}',flush=True)
ThreadingHTTPServer(('127.0.0.1',PORT),Handler).serve_forever()

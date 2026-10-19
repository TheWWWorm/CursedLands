"""Real local IPC framing test, without Discord account/application credentials."""
import json, os, pathlib, socket, struct, subprocess, tempfile, time
repo = pathlib.Path(__file__).resolve().parents[2]
godot = os.environ.get('GODOT', '/home/llm2x/opt/godot/Godot_v4.7-stable_linux.x86_64')
with tempfile.TemporaryDirectory(prefix='ei-discord-') as tmp:
    sock = socket.socket(socket.AF_UNIX); sock.bind(tmp + '/discord-ipc-0'); sock.listen(); sock.settimeout(30)
    env = dict(os.environ, XDG_RUNTIME_DIR=tmp, XDG_DATA_HOME=tmp)
    env.pop("EI_DISCORD_APP_ID", None)
    proc = subprocess.Popen([godot, '--headless', '--render-thread', 'safe', '--path', str(repo/'game'), '--', '--ei-path='+os.environ['EI_PATH'], '--tool=../tools/tests/discord_presence.gd'], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        conn, _ = sock.accept(); conn.settimeout(10)
        def exact(n):
            out=b''
            while len(out)<n:
                data=conn.recv(n-len(out))
                if not data: raise AssertionError('unexpected IPC close')
                out+=data
            return out
        def read():
            op,n=struct.unpack('<II',exact(8)); return op,json.loads(exact(n))
        def frame(op,data):
            data=json.dumps(data).encode(); return struct.pack('<II',op,len(data))+data
        op,hello=read(); assert op==0 and hello=={'v':1,'client_id':'1561645781533069393'},(op,hello)
        ready=frame(1,{'cmd':'DISPATCH','evt':'READY','data':{}})
        conn.sendall(ready[:5]); time.sleep(.03); conn.sendall(ready[5:])
        op,activity=read(); assert op==1 and activity['cmd']=='SET_ACTIVITY'
        assert activity['args']['activity']['state']=='Suslanger' and activity['args']['pid']==proc.pid
        conn.sendall(frame(3,{'ping':'nonce'}))
        seen_pong=False; seen_clear=False
        for _ in range(3):
            op,data=read()
            if op==4: assert data=={'ping':'nonce'}; seen_pong=True
            if op==1: assert data['args']['activity'] is None; seen_clear=True
            if seen_pong and seen_clear: break
        assert seen_pong and seen_clear
        output=proc.communicate(timeout=15)[0]; print(output); assert proc.returncode==0
        print('PASS real IPC: handshake, fragmented READY, activity, ping/pong, option clearing and clean exit')
    finally:
        if proc.poll() is None: proc.kill(); proc.wait()

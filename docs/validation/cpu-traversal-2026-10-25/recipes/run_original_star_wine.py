from pathlib import Path
import subprocess,os,hashlib,json
s=Path(__file__).resolve().parent;base=Path('/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005/native-deps/mingw/root/usr');b=base/'bin'
env=os.environ|{'LD_LIBRARY_PATH':str(base/'lib/x86_64-linux-gnu')}
for lib in ['kernel32','msvcrt']:
 subprocess.run([str(b/'x86_64-w64-mingw32-dlltool'),'-m','i386','-f','--32','-k','-d','replay_'+lib+'.def','-l','replay_'+lib+'.a'],cwd=s,env=env,check=True)
cmd=[str(b/'x86_64-w64-mingw32-gcc'),'-m32','-O1','-fno-builtin','-fno-stack-protector','-nostdlib','-Wl,-mi386pe','-Wl,-T,/usr/lib/x86_64-linux-gnu/ldscripts/i386pe.x','-Wl,--entry,__start','-Wl,--image-base,0x400000','-Wl,--stack,0x10000','-Wl,--heap,0x10000','replay_star_updates_wine.c','replay_kernel32.a','replay_msvcrt.a','-o','replay_star_updates_wine.exe']
subprocess.run(cmd,cwd=s,env=env,check=True)
original=Path('/home/llm2x/Documents/EI/inspection/extracted/app/game.exe');sha=hashlib.sha256(original.read_bytes()).hexdigest();assert sha=='d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8'
wine='/home/llm2x/Documents/EI/local/scratchpad/outstanding-issues-20261023/wine-runtime/wine-11.20-amd64-wow64/bin/wine'
with (s/'star-original-wine.json').open('w') as out,(s/'star-original-wine.log').open('w') as log:p=subprocess.run([wine,str(s/'replay_star_updates_wine.exe')],cwd=s,env=os.environ|{'WINEPREFIX':str(s/'original-wine-prefix'),'WINEDEBUG':'-all'},stdout=out,stderr=log,timeout=45)
(s/'star-original-wine-command.json').write_text(json.dumps({'original_sha256':sha,'build':cmd,'wine':wine,'returncode':p.returncode},indent=2))
print('Original callback Wine exit',p.returncode,'bytes',(s/'star-original-wine.json').stat().st_size)
if p.returncode:print((s/'star-original-wine.log').read_text()[-1200:]);raise SystemExit(p.returncode)
print('Rows',len(json.loads((s/'star-original-wine.json').read_text())['rows']))

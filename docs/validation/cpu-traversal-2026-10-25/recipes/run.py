from pathlib import Path
import os,sys,subprocess,json
s=Path(__file__).resolve().parent
name,tool,mode=sys.argv[1:4]
p=s/'runs'/name
p.mkdir(parents=True,exist_ok=False)
u=p/'data/godot/app_userdata/Cursed Lands';u.mkdir(parents=True)
(u/'settings.cfg').write_text('[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\nauto_graphics=0\ndisplay_mode=0\nfps_limit=0\nnet_directory=0\nnet_upnp=0\nnet_lan=0\n')
env=os.environ|{'XDG_DATA_HOME':str(p/'data'),'XDG_CONFIG_HOME':str(p/'config'),'XDG_CACHE_HOME':str(s/'cache')}
engine=os.environ.get('BENCH_ENGINE',str(s/'runtime.x86_64'))
cmd=[engine,'--render-thread','safe','--audio-driver','Dummy']
if os.environ.get('BENCH_GAME'):cmd+=['--path',os.environ['BENCH_GAME']]
cmd+=['--headless'] if mode=='headless' else ['--display-driver','x11','--rendering-method','forward_plus','--rendering-driver','vulkan','--windowed','--resolution',os.environ.get('BENCH_SIZE','1920x1080')]
cmd+=['--','--no-movies','--ei-path='+os.environ.get('BENCH_DATA','/home/llm2x/Documents/EI/inspection/lost-in-astral/game'),'--tool='+tool]+sys.argv[4:]
if os.environ.get('BENCH_GDB'):cmd=['gdb','-q','-batch','-ex','run','-ex','thread apply all bt 8','--args']+cmd
(p/'command.json').write_text(json.dumps(cmd,indent=2))
with (p/'run.log').open('w') as log:
 result=subprocess.run(cmd,env=env,cwd=s,stdout=log,stderr=subprocess.STDOUT,timeout=420)
print((p/'run.log').read_text()[-4500:]);sys.exit(result.returncode)

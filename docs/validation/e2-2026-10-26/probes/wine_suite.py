from pathlib import Path
import os,sys,subprocess,shutil,fcntl,json,time
w=Path(__file__).resolve().parent;base=Path('/home/llm2x/Documents/EI');rt=base/'local/runtime';kind=sys.argv[1];tag=sys.argv[2] if len(sys.argv)>2 else kind
out=w/tag;out.mkdir(exist_ok=True)
lock=(rt/'locks'/('e2-'+kind+'.lock')).open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
prefix=rt/'sessions'/('e2-'+kind)
seed=rt/'templates'/('original-base' if kind=='original' else 'remake-proton')
if not prefix.exists():
 shutil.copytree(seed.resolve(),prefix,symlinks=True,ignore=shutil.ignore_patterns('*.dmp','*.dxvk-cache','shadercache','mesa_shader_cache','GLCache','D3DSCache'))
if (prefix/'RETIRED-BY-CLEANUP.md').exists():raise RuntimeError('Retired prefix is not a template')
proton=rt/'toolchains/proton-ge-11-11/files';runtime=rt/'toolchains/wine-11.20' if kind=='original' else proton
wine=runtime/'bin/wine';server=runtime/'bin/wineserver'
env=os.environ|{'WINEPREFIX':str(prefix),'WINEDEBUG':'-all'}
if kind=='original':
 game=w/'original-game'
 if not game.exists():shutil.copytree(base/'local/scratchpad/outstanding-issues-20261023/original-game',game,symlinks=True)
 alsa=w/'alsa-null.conf';alsa.write_text('pcm.!default { type null }\nctl.!default { type hw card 0 }\n')
 env.update(WINEDLLOVERRIDES='mscoree,mshtml=',ALSA_CONFIG_PATH=str(alsa))
 reg=w/'original-test.reg';shutil.copy2(base/'local/scratchpad/outstanding-issues-20261023/original-test.reg',reg)
 cmd=[str(wine),'explorer','/desktop=E2original,1024x768','game.exe']
else:
 game=Path(os.environ.get('E2_WINDOWS_GAME',str(base/'local/scratchpad/release-1.30.0-20261025/release/CursedLands-1.30.0-windows-x86_64')))
 system=prefix/'drive_c/windows/system32';support=rt/'toolchains/wine-dx12-support'
 shutil.copy2(support/'x86_64-w64-mingw32/lib/zlib1.dll',system/'zlib1.dll')
 shutil.copy2(proton/'lib/wine/nvapi/x86_64-windows/nvapi64.dll',system/'nvapi64.dll')
 shutil.copy2(proton/'lib/wine/nvidia-libs/nvcuda/x86_64-windows/nvcuda.dll.so',system/'nvcuda.dll')
 env.update(WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree,mshtml=;dinput8=d;winedbg.exe=d;d3d12,d3d12core,dxgi,d3d11,nvapi64,nvngx,_nvngx=n;nvcuda=n,b',LD_LIBRARY_PATH=str(proton/'lib')+':'+str(proton/'lib/x86_64-linux-gnu'),DXVK_ENABLE_NVAPI='1',DXVK_LOG_LEVEL='warn',DXVK_NVAPI_LOG_LEVEL='warn',DXVK_LOG_PATH=str(out),VKD3D_DEBUG='warn',VKD3D_SHADER_CACHE_PATH=str(out))
 profile=prefix/'drive_c/users/steamuser/AppData/Roaming/Godot/app_userdata/Cursed Lands';profile.mkdir(parents=True,exist_ok=True)
 (profile/'settings.cfg').write_text('[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\nauto_graphics=0\ndisplay_mode=0\nnet_lan=0\nnet_upnp=0\nnet_directory=0\ncontrol_mode=3\nrtx_upscaling=4\nrtx_frame_generation=0\n')
 fixtures=w/'windows-fixtures';fixtures.mkdir(exist_ok=True)
 for p in (w/'fixtures').glob('*.gd'):(fixtures/p.name).write_text(p.read_text().replace(str(w/'fixtures'),'Z:'+str(fixtures)))
 cmd=[str(wine),str(game/'CursedLands.exe'),'--render-thread','safe','--audio-driver','Dummy','--max-fps','30','--rendering-method','forward_plus','--rendering-driver','d3d12','--windowed','--resolution','1920x1080','--','--no-movies','--ei-path=Z:'+str(base/('inspection/extracted/app' if os.environ.get('E2_SUITE') and os.environ.get('E2_CAMPAIGN')!='lia' else 'inspection/lost-in-astral/game')),'--tool=Z:'+str(base/'source/tools/parity/gameplay_bootstrap.gd'),'--suite-script=Z:'+str(fixtures/os.environ.get('E2_SUITE','e2_lia_load_probe.gd')),'--suite-script-root=Z:'+str(fixtures),'--suite-campaign='+('cursed_lands' if os.environ.get('E2_SUITE') and os.environ.get('E2_CAMPAIGN')!='lia' else 'lost_in_astral'),'--suite-display=rendered','--lia-pt']
started=time.monotonic()
try:
 with (out/'run.log').open('w') as log:
  if kind=='original':subprocess.run([str(wine),'regedit','/S',str(reg)],cwd=game,env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=60)
  else:
   harness=base/'local/scratchpad/release-1.30.0-20261025/release'
   ident=subprocess.check_output([str(harness/'gpu_identity')],text=True).strip().splitlines()
   if len(ident)!=1:raise RuntimeError('GPU Lab did not isolate one adapter')
   (out/'adapter.txt').write_text(ident[0]+'\n')
   subprocess.run([str(wine),str(harness/'wine_gpu_map.exe'),ident[0].split('|')[-1]],cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=60)
  result=subprocess.run(cmd,cwd=game,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=420 if kind!='original' else 900)
finally:
 subprocess.run([str(server),'-k'],env=env,timeout=20)
 subprocess.run([str(server),'-w'],env=env,timeout=20)
 if kind!='original':
  for p in profile.glob('*.json'):shutil.copy2(p,out/p.name)
  for p in profile.glob('*.png'):shutil.copy2(p,out/p.name)
  for p in profile.rglob('recenter-programs.json'):shutil.copy2(p,out/p.name)
  if (profile/'lia-cliffs-dlss').exists():shutil.copytree(profile/'lia-cliffs-dlss',out/'lia-cliffs-dlss',dirs_exist_ok=True)
 (out/'invocation.json').write_text(json.dumps({'argv':cmd,'runtime':str(runtime.resolve()),'prefix':str(prefix),'elapsed':time.monotonic()-started},indent=2))

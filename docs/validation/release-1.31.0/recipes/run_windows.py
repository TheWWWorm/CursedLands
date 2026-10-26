from pathlib import Path
import os,subprocess,json,re,time,hashlib,sys,shutil,fcntl
W=Path(__file__).resolve().parent;R=W.parent/'repo';B=Path(os.environ.get('PT_WINDOWS_BUNDLE',str(W/'CursedLands-1.31.0-windows-x86_64')));runtime=Path('/home/llm2x/Documents/EI/local/runtime')
for requested_suite in sys.argv[1:]:assert (R/'tools/tests'/(requested_suite+'.gd')).is_file(),requested_suite
proton=(runtime/'toolchains/proton-ge-11-11').resolve()/'files'
support=(runtime/'toolchains/wine-dx12-support').resolve()
prefix=runtime/'sessions/release-1.31.0-dx12';lock=runtime/'locks/release-1.31.0-dx12.lock'
release=Path('/home/llm2x/Documents/EI/local/scratchpad/release-1.30.0-20261025/release')
seed=(runtime/'templates/remake-proton').resolve()
assert not (seed/'RETIRED-BY-CLEANUP.md').exists()
lock.parent.mkdir(parents=True,exist_ok=True)
with lock.open('w') as locked:
 fcntl.flock(locked,fcntl.LOCK_EX|fcntl.LOCK_NB)
 if not prefix.exists():
  shutil.copytree(seed,prefix,symlinks=True,ignore=shutil.ignore_patterns('*.dxvk-cache','*.bin.cache','*.dmp','.cache','shadercache'))
  (prefix/'RELEASE-OWNER.json').write_text(json.dumps({'owner':str(W),'purpose':'One exclusively locked writable prefix for serial final 1.31.0 package verification; seed unchanged. Remove after preserving final results.','seed':str(seed),'runtime':str(proton)},indent=2)+'\n')
 assert not (prefix/'RETIRED-BY-CLEANUP.md').exists()
 system=prefix/'drive_c/windows/system32'
 for source,dest in [(support/'x86_64-w64-mingw32/lib/zlib1.dll','zlib1.dll'),(proton/'lib/wine/nvapi/x86_64-windows/nvapi64.dll','nvapi64.dll'),(proton/'lib/wine/nvidia-libs/nvcuda/x86_64-windows/nvcuda.dll.so','nvcuda.dll')]:shutil.copy2(source,system/dest)
 env=os.environ|{'WINEPREFIX':str(prefix),'WINEARCH':'win64','WINEDEBUG':'-all','WINESERVER':str(proton/'bin/wineserver'),'LD_LIBRARY_PATH':str(proton/'lib')+':'+str(proton/'lib/x86_64-linux-gnu'),'WINEDLLOVERRIDES':'winemenubuilder.exe=d;mscoree,mshtml=;dinput8=d;winedbg.exe=d;d3d12,d3d12core,dxgi,d3d11,nvapi64,nvngx,_nvngx=n;nvcuda=n,b','DXVK_ENABLE_NVAPI':'1','DXVK_LOG_LEVEL':'warn','DXVK_NVAPI_LOG_LEVEL':'warn','VKD3D_DEBUG':'warn'}
 try:
  identity=subprocess.check_output([str(release/'gpu_identity')],text=True).strip().splitlines();assert len(identity)==1,identity
  name,vendor,device,uuid=identity[0].split('|')
  with (W/'windows-adapter.log').open('w') as log:subprocess.run([str(proton/'bin/wine'),str(release/'wine_gpu_map.exe'),uuid],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=60,check=True)
  subprocess.run([str(proton/'bin/wine'),'reg','add',r'HKLM\SOFTWARE\NVIDIA Corporation\Global\NGXCore','/v','ShowDlssIndicator','/t','REG_DWORD','/d','0','/f'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30,check=True)
  for suite in sys.argv[1:]:
   tag=os.environ.get('PT_TAG','windows-')+suite;P=W/'evidence'/tag;P.mkdir(parents=True,exist_ok=False)
   F=P/'fixtures';F.mkdir()
   for src in (R/'tools/tests').glob('*.gd'):(F/src.name).write_text(src.read_text().replace('res://tools/tests/','Z:'+str(F)+'/'))
   U=prefix/'drive_c/users/steamuser/AppData/Roaming/Godot/app_userdata/Cursed Lands';U.mkdir(parents=True,exist_ok=True)
   (U/'settings.cfg').write_text('[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\nauto_graphics=0\ndisplay_mode=0\nfps_limit=1\nnet_directory=0\nnet_lan=0\nnet_upnp=0\nrtx_upscaling=0\nrtx_frame_generation=0\n')
   if os.environ.get('PT_DLSS')=='1':
    config=U/'settings.cfg';config.write_text(config.read_text().replace('rtx_upscaling=0','rtx_upscaling=1'))
   env.update(DXVK_LOG_PATH=str(P),VKD3D_SHADER_CACHE_PATH=str(prefix/'shader-cache'))
   (prefix/'shader-cache').mkdir(exist_ok=True)
   cmd=[str(proton/'bin/wine'),str(B/'CursedLands.exe'),'--render-thread','safe','--audio-driver','Dummy','--max-fps','30','--rendering-method','forward_plus','--rendering-driver','d3d12','--windowed','--resolution','1280x720','--','--no-movies','--ei-path=Z:/home/llm2x/Documents/EI/local/runtime/reference/base','--tool=Z:'+str(F/(suite+'.gd')),'--audit-out=Z:'+str(P)]+json.loads(os.environ.get('PT_EXTRA_ARGS','[]'))
   start=time.monotonic()
   with (P/'run.log').open('w') as log:res=subprocess.run(cmd,env=env,cwd=P,stdout=log,stderr=subprocess.STDOUT,timeout=600)
   lines=(P/'run.log').read_text(errors='replace').splitlines();errors=[x for x in lines if re.search(r'SCRIPT ERROR|^ERROR:|Parse Error|Unhandled exception|^FAIL ',x)]
   summary=[x for x in lines if re.search(r'\d+ checks \d+ failures',x)]
   if not summary and suite=='rtx_super_resolution':
    reports=[json.loads(x.removeprefix('SR_RENDER ')) for x in lines if x.startswith('SR_RENDER ')]
    if reports:
     sr=reports[-1]
     if not sr.get('blocked',True) and sr.get('checks',0)>=50 and not sr.get('failures',['missing']):summary=['SR_RENDER '+str(sr['checks'])+' checks 0 failures']
   if not summary and suite=='fsr_attribution':
    reports=[json.loads(x.removeprefix('ATTRIBUTION ')) for x in lines if x.startswith('ATTRIBUTION ')]
    if reports and reports[-1].get('checks',0)>=100 and not reports[-1].get('failures',['missing']):summary=['ATTRIBUTION '+str(reports[-1]['checks'])+' checks 0 failures']
   if len(summary)!=1 or not summary[0].endswith(' 0 failures'):errors.append('No passing summary: '+str(summary))
   report={'exit':res.returncode,'errors':errors,'summary':summary,'seconds':round(time.monotonic()-start,2),'argv':cmd,'adapter':{'name':name,'vendor':vendor,'device':device,'uuid':uuid,'capabilities_overridden':False},'runtime':json.loads((B/'BUILD-INFO.json').read_text()),'fixture_sha256':hashlib.sha256((F/(suite+'.gd')).read_bytes()).hexdigest()}
   (P/'result.json').write_text(json.dumps(report,indent=2)+'\n');print(tag,res.returncode,errors,summary,flush=True)
   if errors or res.returncode:raise SystemExit(1)
 finally:
  subprocess.run([str(proton/'bin/wineserver'),'-k'],env=env,timeout=30)
  subprocess.run([str(proton/'bin/wineserver'),'-w'],env=env,timeout=30)

from pathlib import Path
import json, os, shlex, shutil, subprocess, time

w = Path(__file__).resolve().parent
build = w / 'native-rt-build'
private = w / 'native-rt-sanitizers'
private.mkdir(exist_ok=True)
commands = subprocess.check_output(['ninja', '-C', str(build), '-t', 'commands', 'CMakeFiles/terrain_search.dir/nav_kernel.cpp.o'], text=True)
original = shlex.split(commands.strip().splitlines()[-1])
compile_args = original[:original.index('-MD')]
compile_args = [x for x in compile_args if x != '-O3']
compile_args += ['-O1', '-g1', '-DASAN_ENABLED', '-DUBSAN_ENABLED', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-c', str(w/'repo/game/src/native/source/nav_kernel.cpp'), '-o', str(private/'nav_kernel.o')]
link_args = ['/usr/bin/c++', '-shared', '-fsanitize=address,undefined', '-o', str(private/'libterrain_search.so'), str(private/'nav_kernel.o'), str(build/'bin/libgodot-cpp.linux.template_release.x86_64.a')]
(private/'build-commands.json').write_text(json.dumps([compile_args,link_args],indent=2)+'\n')
if os.environ.get('SAN_REUSE') != '1':
    with (private/'build.log').open('w') as log:
        subprocess.run(compile_args, stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(link_args, stdout=log, stderr=subprocess.STDOUT, check=True)
subprocess.run(['/usr/bin/cc','-shared','-fPIC',str(private/'dlopen_adapter.c'),'-o',str(private/'dlopen_adapter.so'),'-ldl'],check=True)
for name in ['godot-water-rt.x86_64','godot-water-rt.pck']:
    dest=private/name
    if dest.exists(): dest.unlink()
    os.link(w/'engine'/name,dest)
shutil.copytree(w/'engine/src/native/bin',private/'src/native/bin',dirs_exist_ok=True)
shutil.copy2(private/'libterrain_search.so',private/'src/native/bin/libterrain_search.so')
out=private/'run'; out.mkdir(exist_ok=True)
profile=out/'profile/godot/app_userdata/Cursed Lands'; profile.mkdir(parents=True,exist_ok=True)
(profile/'settings.cfg').write_text('[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\nauto_graphics=0\ndisplay_mode=0\nnet_directory=0\nnet_upnp=0\nnet_lan=0\nvsync=0\n')
cmd=json.loads((w/'rt-optimized-native-final/command.json').read_text())
cmd[0]=str(private/'godot-water-rt.x86_64')
cmd[cmd.index('--rendering-method')+1]='gl_compatibility'
cmd[1:1]=['--rendering-driver','opengl3']
cmd=[('--audit-out='+str(out)) if x.startswith('--audit-out=') else x for x in cmd]
asan=subprocess.check_output(['/usr/bin/c++','-print-file-name=libasan.so'],text=True).strip()
env=dict(os.environ,DISPLAY=':98',XDG_DATA_HOME=str(out/'profile'),XDG_CACHE_HOME=str(w/'cache'),LD_PRELOAD=str(private/'dlopen_adapter.so')+':'+asan,ASAN_OPTIONS='detect_leaks=0:halt_on_error=1:verify_asan_link_order=0',UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1',LIBGL_ALWAYS_SOFTWARE='1',__GLX_VENDOR_LIBRARY_NAME='mesa')
(out/'command.json').write_text(json.dumps(cmd,indent=2)+'\n')
start=time.monotonic()
with (out/'run.log').open('w') as log:
    result=subprocess.run(cmd,env=env,cwd=private,stdout=log,stderr=subprocess.STDOUT,timeout=240)
report={'exit':result.returncode,'seconds':time.monotonic()-start,'output':str(out),'instrumented':'complete terrain_search GDExtension translation unit; Godot and godot-cpp archive are uninstrumented','leak_detection':False,'renderer':'Compatibility / OpenGL / llvmpipe; native CPU parity only. The NVIDIA Vulkan driver did not initialize with ASan preloaded.','loader_adapter':'Private extension dlopen calls omit RTLD_DEEPBIND so ASan can interpose; production runtime unchanged.'}
(out/'run.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report),flush=True)
raise SystemExit(result.returncode)

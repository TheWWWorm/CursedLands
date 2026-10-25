from pathlib import Path
import subprocess, os, sys, hashlib, json, shutil
s=Path(__file__).resolve().parent;r=s/'repo'
platform=sys.argv[1]
build=s/('native-pose-'+platform)
deps=Path('/home/llm2x/Documents/EI/local/scratchpad/coop-performance-20261005')
configure=['cmake','-S',str(r/'game/src/native/source'),'-B',str(build),'-DCMAKE_BUILD_TYPE=Release','-DGODOTCPP_DIR='+str(deps/'native-deps/godot-cpp')]
env=dict(os.environ)
if platform=='windows':
 configure+=['-DCMAKE_TOOLCHAIN_FILE='+str(deps/'native-mingw-toolchain.cmake')]
 env['LD_LIBRARY_PATH']=str(deps/'native-deps/mingw/root/usr/lib/x86_64-linux-gnu')
elif platform=='android':
 configure+=['-DCMAKE_TOOLCHAIN_FILE=/home/llm2x/Documents/GoF3DRemake/local/toolchains/android-sdk/ndk/29.0.14206865/build/cmake/android.toolchain.cmake','-DANDROID_ABI=arm64-v8a','-DANDROID_PLATFORM=android-24','-DANDROID_STL=c++_static']
commands=[configure,['cmake','--build',str(build),'--parallel','6']]
with (s/('unit-sound-scan-'+platform+'-build.log')).open('w') as log:
 for command in commands:
  subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
target=build/('libterrain_search.dll' if platform=='windows' else 'libterrain_search.so')
destination=r/'game/src/native/bin'/('libterrain_search_android.so' if platform=='android' else target.name)
shutil.copy2(target,destination)
row={'platform':platform,'commands':commands,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (r/'game/src/native/source').glob('*') if p.is_file()}}
(s/('unit-sound-scan-'+platform+'-build.json')).write_text(json.dumps(row,indent=2)+'\n')
print('Built',platform,row['sha256'],flush=True)

import os,sys
from run import run,W
rows=[]
for version,directory,tag in [('1.28.0-experimental.1','preview','recording-final-before'),('1.28.0-experimental.2','preview2','recording-final-after')]:
    os.environ['PT_BUNDLE_ROOT']=str(W/directory)
    os.environ['PT_PACKAGE_VERSION']=version
    rows.append(run('path_trace_recording_route',tag,'windows','d3d12',['--ei-profile-rt']))
sys.exit(int(any(r['exit'] or r['errors'] for r in rows)))

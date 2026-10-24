import os,json,sys
from pathlib import Path
from run import run
w=Path(__file__).resolve().parent
rows=[]
for label,folder,version in [('stable-1.27',w.parent/'release-1.27.0-20261024/release','1.27.0'),('nrd-preview',w/'preview','1.28.0-experimental.1')]:
 os.environ['PT_BUNDLE_ROOT']=str(folder);os.environ['PT_PACKAGE_VERSION']=version
 rows.append(run('path_trace_walk_performance','wide-'+label,'windows','d3d12',['--ei-profile-rt','--pt-wide','--pt-storm-fast']))
(w/'benchmark-wide.json').write_text(json.dumps(rows,indent=2)+'\n')
sys.exit(int(any(r['exit'] or r['errors'] for r in rows)))

from pathlib import Path
import os,json,sys
from run import run
w=Path(__file__).resolve().parent
rows=[]
for label,folder in [('stable-1.27',w.parent/'release-1.27.0-20261024/release'),('nrd-final',w/'final'),('nrd-final-repeat',w/'final')]:
 os.environ['PT_BUNDLE_ROOT']=str(folder)
 rows.append(run('path_trace_walk_performance','walk-'+label,'windows','d3d12',['--ei-profile-rt']))
(w/'benchmark-final.json').write_text(json.dumps(rows,indent=2))
sys.exit(int(any(r['exit'] or r['errors'] for r in rows)))

import os,json,sys
from pathlib import Path
from run import run
w=Path(__file__).resolve().parent
rows=[]
for suite,extra in [('path_trace_nrd_device',[]),('path_trace_glossy',[]),
 ('path_trace_walk_performance',['--ei-profile-rt','--pt-soak','--pt-storm-fast'])]:
 rows.append(run(suite,'preview-dx12-'+suite,'windows','d3d12',extra))
(w/'preview-dx12.json').write_text(json.dumps(rows,indent=2)+'\n')
sys.exit(int(any(r['exit'] or r['errors'] for r in rows)))

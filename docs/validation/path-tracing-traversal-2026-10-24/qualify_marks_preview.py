from run import run
import sys
rows=[]
for suite,tag,platform,renderer in [('ground_mark_receivers','preview2-receivers-dx12','windows','d3d12'),('ground_mark_receivers','preview2-receivers-gl','linux','opengl3'),('path_trace_nrd_device','preview2-nrd-dx12','windows','d3d12'),('path_trace_nrd_device','preview2-nrd-vulkan','linux','vulkan')]:
    rows.append(run(suite,tag,platform,renderer,['--enhanced'] if 'receivers' in suite else []))
sys.exit(int(any(r['exit'] or r['errors'] for r in rows)))

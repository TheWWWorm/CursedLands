from pathlib import Path
import os,sys
import pt_harness as h
W=Path(__file__).resolve().parent
h.W=W;h.R=W.parent/'repo'
h.PREFIX=Path('/home/llm2x/Documents/EI/local/scratchpad/dlss-restore-20261024/wine-template')
proton=W/'proton/GE-Proton11-11-x86_64/files'
os.environ.update(PT_PACKAGE_VERSION='1.28.0',FG_WINE=str(proton/'bin/wine'),FG_WINE_LIB=str(proton/'lib')+':'+str(proton/'lib/x86_64-linux-gnu'),FG_REAL_CUDA='1',FG_PROTON_NVAPI='1')
group=sys.argv[1]
os.environ['PT_BUNDLE_ROOT']=str(W/'rtx30' if group in ['route','framegen'] else W)
h.SETTINGS+='fps_limit=2\nrtx_upscaling='+('2' if group in ['route','framegen','dlss'] else '0')+'\nrtx_frame_generation=0\n'
spec={
 'route':[('path_trace_traversal_stalls',['--route-dlss','--route-dlss-fg','--route-fit-output','--route-adaptive=3','--ei-profile-rt'])],
 'framegen':[('rtx_frame_generation',[])],
 'dlss':[('rtx_super_resolution',[]),('fsr_screen',[])],
 'fsr':[('fsr_render',[]),('path_trace_upload_staging',[]),('path_trace_history_handoff',[])],
}
rows=[]
for suite,extra in spec[group]:rows.append(h.run(suite,('windows-route-waypoint-' if group=='route' else 'windows-'+group+'-')+suite,'windows','d3d12',extra))
sys.exit(int(any(r['exit'] or r['errors'] for r in rows)))

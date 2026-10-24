from pathlib import Path
import os,sys,importlib.util,argparse
w=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('nrd_harness',w/'harness.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);m.W=w;m.PREFIX=Path('/home/llm2x/Documents/EI/local/scratchpad/dlss-restore-20261024/wine-template')
p=argparse.ArgumentParser();p.add_argument('--suite',required=True);p.add_argument('--tag',required=True);p.add_argument('--platform',default='windows');p.add_argument('--renderer',default='d3d12');p.add_argument('--dlss',action='store_true');p.add_argument('--bundle',default='candidate1');p.add_argument('--version',default='1.28.0-experimental.3');args,extra=p.parse_known_args()
os.environ['PT_BUNDLE_ROOT']=str(w/args.bundle);os.environ['PT_PACKAGE_VERSION']=args.version
m.SETTINGS+='fps_limit=2\n'
m.SETTINGS+='rtx_upscaling='+('2' if args.dlss else '0')+'\nrtx_frame_generation=0\n'
row=m.run(args.suite,args.tag,args.platform,args.renderer,[x for x in extra if x!='--'])
raise SystemExit(int(bool(row['exit'] or row['errors'])))

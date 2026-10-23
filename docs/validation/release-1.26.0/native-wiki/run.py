"""One packaged native wiki capture; invoke through GPU Lab auto."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
parser=argparse.ArgumentParser();parser.add_argument('campaign',choices=['base','lia']);parser.add_argument('language',choices=['en','ru','de']);args=parser.parse_args()
base=Path(__file__).resolve().parent;release=base.parent;repo=release.parent/'repo'
folder=release/'CursedLands-1.26.0-linux-x86_64';exe=folder/'CursedLands.x86_64'
roots={'base':{'en':'/home/llm2x/Documents/EI/inspection/extracted/app','ru':'/home/llm2x/Documents/EI/local/scratchpad/in-game-wiki-20261015/data/ru','de':'/home/llm2x/Documents/EI/local/scratchpad/visuals-aim-localization-20261013/german/app'},'lia':{lang:'/home/llm2x/Documents/EI/inspection/lost-in-astral/game' for lang in ['en','ru','de']}}
root=Path(roots[args.campaign][args.language]);assert (root/'res/texts.res').exists()
out=base/(args.campaign+'-'+args.language);out.mkdir()
profile=out/'profile';user=profile/'data/godot/app_userdata/Cursed Lands';user.mkdir(parents=True)
(user/'settings.cfg').write_text('[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\nauto_graphics=0\ndisplay_mode=0\nshow_tutorial=0\nnet_upnp=0\nnet_lan=0\nnet_directory=0\npad_enabled=0\n[display]\nresolution="1280x720"\n')
index_path=repo/'public/wiki/data'/('lost_in_astral' if args.campaign=='lia' else '')/args.language/'index.json'
index=json.loads(index_path.read_text());keys=[r['key'] for r in index['entries'] if r['key'].startswith('cut/')]
illustrated=next((key for key in keys if key.startswith('cut/figure/')),None) or next(key for key in keys if key!='cut/overview')
pages=['cut/overview',illustrated]
env=dict(os.environ,**{f'XDG_{key}_HOME':str(profile/key.lower()) for key in ['DATA','CONFIG','CACHE']})
cmd=[str(exe),'--display-driver','x11','--rendering-method','gl_compatibility','--rendering-driver','opengl3','--audio-driver','Dummy','--max-fps','30','--windowed','--resolution','1280x720','--','--ei-path='+str(root),'--no-movies','--tool='+str(base/'visual.gd'),'--capture='+str(out),'--pages='+','.join(pages),'--ui-lang='+args.language]
start=time.monotonic()
with (out/'run.log').open('w') as log:proc=subprocess.run(cmd,cwd=folder,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180)
lines=(out/'run.log').read_text().splitlines()
allowed=[];errors=[]
for i,line in enumerate(lines):
 if line=='ERROR: Parameter "monitors" is null.' and i+1<len(lines) and 'screen_get_refresh_rate (platform/linuxbsd/x11/' in lines[i+1]:allowed.append(line);continue
 if re.search(r'SCRIPT ERROR:|^ERROR:|Parse Error|Assertion.*failed|^FAIL ',line):errors.append(line)
meta=[json.loads(line.removeprefix('NATIVE_WIKI ')) for line in lines if line.startswith('NATIVE_WIKI ')]
expected_campaign='cursed_lands' if args.campaign=='base' else 'lost_in_astral'
images=sorted(out.glob('*.png'));passed=proc.returncode==0 and not errors and len(images)==len(pages)+1 and len(meta)==1 and meta[0]['campaign']==expected_campaign and meta[0]['language']==args.language and meta[0]['version']=='1.26.0'
report={'version':'1.26.0','campaign':expected_campaign,'language':args.language,'passed':passed,'exit':proc.returncode,'seconds':round(time.monotonic()-start,2),'errors':errors,'allowed_diagnostics':allowed,'pages':pages,'screenshots':[str(p) for p in images],'command':cmd,'meta':meta,'binary_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'pck_sha256':hashlib.sha256((folder/'CursedLands.pck').read_bytes()).hexdigest(),'profile':{'isolated':True,'confine_mouse':0,'show_fps':1,'volume_sfx':0,'volume_stream':0,'volume_voice':0},'language_setup':'Original installed localized base edition' if args.campaign=='base' else 'Original Russian LiA data; UI language override exercises production fingerprint-checked WikiReferenceText translations'}
(out/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2));raise SystemExit(0 if passed else 1)

from pathlib import Path
import concurrent.futures,hashlib,json,os,re,subprocess,sys
from release_config import REPO as R, WORK as W, VERSION
data={
 'en':'/home/llm2x/Documents/EI/inspection/extracted/app',
 'ru':'/home/llm2x/Documents/EI/local/scratchpad/in-game-wiki-20261015/data/ru',
 'de':'/home/llm2x/Documents/EI/local/scratchpad/visuals-aim-localization-20261013/german/app',
}
fixture=W/'guide_export.gd'
fixture.write_text((R/'tools/tests/tutorial_wiki_export.gd').read_text().replace('for language in ["en", "ru", "de"]:', 'for language in [RemakeText.lang]:'))
def run(language):
 p=W/'wiki-guides'/language;p.mkdir(parents=True,exist_ok=False)
 user=p/'data/godot/app_userdata/Cursed Lands';user.mkdir(parents=True)
 (user/'settings.cfg').write_text('[options]\nconfine_mouse=0\nshow_fps=1\nvolume_sfx=0\nvolume_stream=0\nvolume_voice=0\n')
 output=p/'guides.json';env=dict(os.environ,**{f'XDG_{k}_HOME':str(p/k.lower()) for k in ['DATA','CONFIG','CACHE']})
 cmd=[str(W/f'CursedLands-{VERSION}-linux-x86_64/CursedLands.x86_64'),'--headless','--audio-driver','Dummy','--','--ei-path='+data[language],'--no-movies','--tool='+str(fixture),'--guide-output='+str(output)]
 with (p/'run.log').open('w') as log:result=subprocess.run(cmd,cwd=p,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180)
 assert result.returncode==0 and not re.search(r'(?m)^(?:SCRIPT )?ERROR:|^FAIL ',(p/'run.log').read_text())
 result=json.loads(output.read_text());assert set(result)=={language}
 return language,result[language]
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:guides=dict(pool.map(run,data))
for campaign in ['', 'lost_in_astral']:
 for language,guide in guides.items():
  folder=R/'public/wiki/data'/campaign/language
  index=json.loads((folder/'index.json').read_text())
  index['entries']=[e for e in index['entries'] if e.get('kind') not in ('guide','guide_recent')]
  index['entries']+=guide['entries'];index['categories']['Getting started']=guide['category']
  index.setdefault('supplemental_exports',{})['guide']={'version':VERSION,'source':'Current game guide and matching localized original edition'}
  (folder/'index.json').write_text(json.dumps(index,ensure_ascii=False,separators=(',',':'))+'\n')
  for filename,page in guide['pages'].items():
   text=json.dumps(page,ensure_ascii=False,separators=(',',':'))+'\n'
   assert language=='ru' or not re.search('[А-Яа-яЁё]',text),(language,filename)
   (folder/'pages'/filename).write_text(text)
(W/'guide-fixtures.json').write_text(json.dumps(guides,ensure_ascii=False)+'\n')
report=json.loads((R/'public/wiki/BUILD-INFO.json').read_text())
report['supplemental_exports']={'guide':{'version':VERSION,'languages':['en','ru','de'],'campaigns':['cursed_lands','lost_in_astral'],'topics_per_language':{k:len(v['entries']) for k,v in guides.items()}}}
(R/'public/wiki/BUILD-INFO.json').write_text(json.dumps(report,indent=2)+'\n')
subprocess.run([sys.executable,str(R/'tools/prepare_public_wiki.py'),'--refresh-ui','--output',str(R/'public/wiki')],check=True)
print('Published-data preparation: localized guide articles added to both campaigns',flush=True)

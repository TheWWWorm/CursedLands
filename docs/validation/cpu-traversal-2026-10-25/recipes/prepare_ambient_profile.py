from pathlib import Path
import shutil,re,subprocess,json,os
s=Path(__file__).resolve().parent;r=s/'repo';dest=s/'ambient-profile-game';out=s/'ambient-profile';out.mkdir(exist_ok=True)
assert not dest.exists()
subprocess.run(['cp','-a','--reflink=auto',str(r/'game'),str(dest)],check=True)
(dest/'src/ei/figure.gd').write_bytes(subprocess.check_output(['git','show','18b58726:game/src/ei/figure.gd'],cwd=r))
shutil.copy2(s/'front-profile-game/cpu_scope.gd',dest/'cpu_scope.gd')
extra={'game/fx/ambient_life.gd':['_process'],'game/fx/ambient_habitats.gd':['ground'],'game/fx/ambient_ground.gd':['elevation']}
wrapped=[]
for index,p in enumerate(sorted((dest/'src').rglob('*.gd'))):
 rel=p.relative_to(dest/'src').as_posix();t=p.read_text();original=t;cname='CpuScopeRound4'+str(index)
 for m in reversed(list(re.finditer(r'^(?:static )?func (\w+)\(([^\n]*)\)([^\n]*):\n',t,re.M))):
  name,args,ret=m.groups()
  if name not in extra.get(rel,[]):continue
  end=re.search(r'^\S',t[m.end():],re.M);body=t[m.end():m.end()+end.start()] if end else t[m.end():]
  if 'await ' in body:continue
  params=[];start=0;depth=0
  for i,c in enumerate(args):
   if c in '([{':depth+=1
   elif c in ')]}':depth-=1
   elif c==',' and depth==0:params.append(args[start:i].split(':')[0].split('=')[0].strip());start=i+1
  if args:params.append(args[start:].split(':')[0].split('=')[0].strip())
  renamed='_cpu_round4_'+str(index)+'_'+name;call=renamed+'('+', '.join(params)+')';void='-> void' in ret or name in ['_process','_physics_process']
  modifier='static ' if m[0].startswith('static ') else ''
  wrapper=modifier+'func '+name+'('+args+')'+ret+':\n'
  wrapper+='\tif not '+cname+'.enabled:\n\t\t'+('' if void else 'return ')+call+'\n'
  if void:wrapper+='\t\treturn\n'
  wrapper+='\tvar cpu_started := Time.get_ticks_usec()\n\t'+('' if void else 'var cpu_result = ')+call+'\n'
  wrapper+='\t'+cname+'.record("'+rel+':'+name+'",Time.get_ticks_usec()-cpu_started)\n'
  if not void:wrapper+='\treturn cpu_result\n'
  wrapper+='\n'+modifier+'func '+renamed+'('+args+')'+ret+':\n'
  t=t[:m.start()]+wrapper+t[m.end():];wrapped.append(rel+':'+name)
 if t!=original:
  t=re.sub(r'^(extends[^\n]*\n)',lambda m:m[0]+'const '+cname+' = preload("res://cpu_scope.gd")\n',t,count=1,flags=re.M);p.write_text(t)

(s/'ambient-profile-methods.json').write_text(json.dumps(wrapped,indent=2))
shutil.copy2(s/'runtime.x86_64',out/'runtime.x86_64');shutil.copytree(r/'game/src/native/bin',out/'src/native/bin',dirs_exist_ok=True)
with (s/'ambient-profile-export.log').open('w') as log:
 result=subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(dest),'--export-pack','Linux',str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT)
print('Wrapped',len(wrapped),'export exit',result.returncode,flush=True);raise SystemExit(result.returncode)

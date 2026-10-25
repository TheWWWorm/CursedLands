from pathlib import Path
import shutil,re,subprocess,json,os
s=Path(__file__).resolve().parent;r=s/'repo';dest=s/'round2-profile-game';out=s/'round2-profile';out.mkdir(exist_ok=True)
assert not dest.exists()
subprocess.run(['cp','-a','--reflink=auto',str(r/'game'),str(dest)],check=True)
(dest/'src/ei/figure.gd').write_bytes(subprocess.check_output(['git','show','18b58726:game/src/ei/figure.gd'],cwd=r))
shutil.copy2(s/'front-profile-game/cpu_scope.gd',dest/'cpu_scope.gd')
extra={
 'game/game.gd':['_update_cursor','pick_lever','_update_daylight','_keep_selection'],
 'game/world.gd':['_step_hidden_presentations','_sample_client_effect_frame','_advance_client_effects'],
 'game/levers.gd':['draw'],
 'game/game_sound.gd':['_world_tick','_update_listener','_screens','_send_combat_flags','_combat_inputs','_player_combat_flag','_bored_tick'],
 'game/unit_sounds.gd':['tick','_frame'],
 'game/spell_sounds.gd':['tick'],
 'game/fx/particle_system.gd':['_advance_effects','_tick','_draw','_apply_material_options','_fill','_fill_apply'],
 'game/fx/ground_marks.gd':['_tick','_drain_units','_step_frames','_deform_feet','_sole_contact','_step'],
 'game/fx/ground_mark_projection.gd':['sync','place','bind','refresh_receivers'],
 'ei/terrain.gd':['_update_wave_parameters','_update_wind_parameters','_update_cloud_parameters','wind_frame'],
 'game/fx/terrain_details.gd':[],
}
wrapped=[]
for index,p in enumerate(sorted((dest/'src').rglob('*.gd'))):
 rel=p.relative_to(dest/'src').as_posix();t=p.read_text();original=t;cname='CpuScopeRound2'+str(index)
 for m in reversed(list(re.finditer(r'^func (\w+)\(([^\n]*)\)([^\n]*):\n',t,re.M))):
  name,args,ret=m.groups()
  if name not in ['_process','_physics_process']+extra.get(rel,[]):continue
  end=re.search(r'^\S',t[m.end():],re.M);body=t[m.end():m.end()+end.start()] if end else t[m.end():]
  if 'await ' in body:continue
  params=[];start=0;depth=0
  for i,c in enumerate(args):
   if c in '([{':depth+=1
   elif c in ')]}':depth-=1
   elif c==',' and depth==0:params.append(args[start:i].split(':')[0].split('=')[0].strip());start=i+1
  if args:params.append(args[start:].split(':')[0].split('=')[0].strip())
  renamed='_cpu_round2_'+str(index)+'_'+name;call=renamed+'('+', '.join(params)+')';void='-> void' in ret or name in ['_process','_physics_process']
  wrapper='func '+name+'('+args+')'+ret+':\n'
  wrapper+='\tif not '+cname+'.enabled:\n\t\t'+('' if void else 'return ')+call+'\n'
  if void:wrapper+='\t\treturn\n'
  wrapper+='\tvar cpu_started := Time.get_ticks_usec()\n\t'+('' if void else 'var cpu_result = ')+call+'\n'
  wrapper+='\t'+cname+'.record("'+rel+':'+name+'",Time.get_ticks_usec()-cpu_started)\n'
  if not void:wrapper+='\treturn cpu_result\n'
  wrapper+='\nfunc '+renamed+'('+args+')'+ret+':\n'
  t=t[:m.start()]+wrapper+t[m.end():];wrapped.append(rel+':'+name)
 if t!=original:
  t=re.sub(r'^(extends[^\n]*\n)',lambda m:m[0]+'const '+cname+' = preload("res://cpu_scope.gd")\n',t,count=1,flags=re.M);p.write_text(t)
(s/'round2-profile-methods.json').write_text(json.dumps(wrapped,indent=2))
shutil.copy2(s/'runtime.x86_64',out/'runtime.x86_64');shutil.copytree(r/'game/src/native/bin',out/'src/native/bin',dirs_exist_ok=True)
with (s/'round2-profile-export.log').open('w') as log:
 result=subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(dest),'--export-pack','Linux',str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT)
print('Wrapped',len(wrapped),'export exit',result.returncode,flush=True);raise SystemExit(result.returncode)

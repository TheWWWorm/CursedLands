from pathlib import Path
import shutil,re,subprocess,json,os
s=Path(__file__).resolve().parent;r=s/'repo';dest=s/'dar-current-profile-game';out=s/'dar-current-profile';out.mkdir(exist_ok=True)
assert not dest.exists()
subprocess.run(['cp','-a','--reflink=auto',str(r/'game'),str(dest)],check=True)
# Current integrated source; no gameplay substitutions.
shutil.copy2(s/'front-profile-game/cpu_scope.gd',dest/'cpu_scope.gd')
extra={
 'game/game.gd':['_update_cursor','pick_lever','_update_daylight','_keep_selection','_update_hero_lights'],
 'game/world.gd':['_step_hidden_presentations','_sample_client_effect_frame','_advance_client_effects'],
 'game/levers.gd':['draw','usable'],
 'game/game_sound.gd':['_world_tick','_update_listener','_screens','_send_combat_flags','_combat_inputs','_player_combat_flag','_bored_tick'],
 'game/unit_sounds.gd':['tick','_frame'],
 'game/spell_sounds.gd':['tick'],
 'game/fx/particle_system.gd':['_advance_effects','_tick','_draw','_apply_material_options','_fill','_fill_apply'],
 'game/fx/ground_marks.gd':['_tick','_drain_units','_step_frames','_deform_feet','_sole_contact','_step'],
 'game/fx/ground_mark_projection.gd':['sync','place','bind','refresh_receivers'],
 'ei/terrain.gd':['_update_wave_parameters','_update_wind_parameters','_update_cloud_parameters','wind_frame'],
 'game/fx/terrain_details.gd':[],
 'ui/mesh_screen_rect.gd':['of_retained_context','of_context','camera_context'],
 'game/unit.gd':['_step_sleeping_presentation','_advance_sleeping_presentation','_present_frame','_can_sleep_presentation','_sleep_model','_present_native_frame','_update_pose','anim_flush','_pre_cast','_held','_anim_rate','_draw_step'],
 'game/fx/ambient_life.gd':['step','_threats','_update_residents','_move'],
 'game/fx/ambient_particles.gd':['step'],
 'game/fx/ambient_habitats.gd':['ground','liquid','habitat','clear_at','refresh'],
 'game/fx/ambient_ground.gd':['elevation','surface','displaced','texel'],
 'game/fx/fx_ground.gd':['of'],
 'ui/gfx.gd':[],
}
extra['game/fx/vegetation_interaction.gd']=['update','contacts','advance','posed_bounds']
extra['game/direct_pose.gd']=['sample','restore_pose','_compose_pose','apply_pose']
extra['game/fx/ground_marks.gd']+=['_update','_place','_sole_vertices','_sole_geometry']
extra['game/fx/terrain_details.gd']=['surface_sample','grass_allowed','vegetation_allowed','_camera_focus','_update_motion','_stream','_finish_grass_jobs','_install_chunk','_update_submissions']
wrapped=[]
for index,p in enumerate(sorted((dest/'src').rglob('*.gd'))):
 rel=p.relative_to(dest/'src').as_posix();t=p.read_text();original=t;cname='CpuScopeRound4'+str(index)
 for m in reversed(list(re.finditer(r'^(?:static )?func (\w+)\(([^\n]*)\)([^\n]*):\n',t,re.M))):
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

# Thread-local diagnostic timing: each worker owns one emitter, and only the
# main thread merges records after the complete group has joined.
p=dest/'src/game/fx/fx_emitter.gd';t=p.read_text()
t=t.replace('func update_sim() -> bool:', '''var _cpu_sim_elapsed := -1
var _cpu_sim_parts := 0
func update_sim() -> bool:
	_cpu_sim_parts = parts.size()
	var started := Time.get_ticks_usec()
	var result := _cpu_sim_unprofiled()
	_cpu_sim_elapsed = Time.get_ticks_usec() - started
	return result

func _cpu_sim_unprofiled() -> bool:''')
p.write_text(t)
p=dest/'src/game/fx/particle_system.gd';t=p.read_text()
t=t.replace('\t_in_tick = false\n', '\t_in_tick = false\n') if False else t
needle='\t_in_tick = false\n'
addition='''	if CpuRound4Detail.enabled:
		for measured in effects:
			if measured.e._cpu_sim_elapsed >= 0:
				var label := "particle_type_%04x" % measured.e.type
				CpuRound4Detail.record(label, measured.e._cpu_sim_elapsed)
				CpuRound4Detail.count(label+"_parts", measured.e._cpu_sim_parts)
				measured.e._cpu_sim_elapsed = -1
'''
t=t.replace(needle,needle+addition)
t=t.replace('extends Node3D\n','extends Node3D\nconst CpuRound4Detail = preload("res://cpu_scope.gd")\n',1)
p.write_text(t)
p=dest/'cpu_scope.gd';t=p.read_text()
t += '\nstatic var counts := {}\nstatic func count(label: String, n: int)->void:\n\tcounts[label]=int(counts.get(label,0))+n\n'
t=t.replace('rows.clear();enabled=true','rows.clear();counts.clear();enabled=true')
t=t.replace('\tenabled=false','\tenabled=false\n\tFileAccess.open("user://cpu-census.json",FileAccess.WRITE).store_string(JSON.stringify(counts,"\\t"))')
p.write_text(t)
(s/'dar-current-profile-methods.json').write_text(json.dumps(wrapped,indent=2))
shutil.copy2(s/'mark-opacity-linux/runtime.x86_64',out/'runtime.x86_64');shutil.copytree(r/'game/src/native/bin',out/'src/native/bin',dirs_exist_ok=True)
with (s/'dar-current-profile-export.log').open('w') as log:
 result=subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(dest),'--export-pack','Linux',str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT)
print('Wrapped',len(wrapped),'export exit',result.returncode,flush=True);raise SystemExit(result.returncode)

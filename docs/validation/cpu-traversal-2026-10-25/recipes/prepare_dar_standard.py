from pathlib import Path
import re
s=Path(__file__).resolve().parent;r=s/'repo'
t=(r/'tools/tests/path_trace_zone_traversal.gd').read_text()
t=t.replace('extends "local_host_campaign.gd"',f'extends "{r}/tools/tests/local_host_campaign.gd"')
t=t.replace('GfxPresets.ULTRA','GfxPresets.VERY_HIGH').replace('"gfx_water_reflections":3','"gfx_water_reflections":1').replace('"pt_mode":1','"pt_mode":0,"rt_shadows":0,"rt_gi":0')
t=t.replace('check(active==frames and nrd==frames,label+" keeps PT/native NRD active")','check(active==0 and nrd==0,label+" stays in standard rendering")')
t=t.replace('rt.stats.get("active",false) and rt.device!=null and rt.device.nrd_active and g.direct.usable()','not rt.stats.get("active",false) and g.direct.usable()').replace('"PT and first-person controls are ready"','"standard rendering and first-person controls are ready"')
t=t.replace('g.direct.usable() and rt.stats.get("active",false) and not rt.stats.get("rebuilding",false)','g.direct.usable() and not rt.stats.get("active",false) and not rt.stats.get("rebuilding",false)')
t=t.replace('PT_ZONE_TRAVERSAL','STANDARD_ZONE_TRAVERSAL')
t=t.replace('var rows := []','var rows := []\nvar scope_active := false\nvar profile_path := "res://cpu_scope.gd"')
t=t.replace('\tvar start := Time.get_ticks_usec()','\tEngine.max_fps=0\n\tif ResourceLoader.exists(profile_path):load(profile_path).begin()\n\tvar start := Time.get_ticks_usec()',1)
t=t.replace('\tkey(KEY_W,false)\n\tvar sdk_after', '\tif ResourceLoader.exists(profile_path):\n\t\tload(profile_path).end()\n\t\tfor name in ["cpu-scopes.json","cpu-census.json"]:\n\t\t\tDirAccess.copy_absolute(ProjectSettings.globalize_path("user://"+name),out.path_join(label+"-"+name))\n\tkey(KEY_W,false)\n\tvar sdk_after',1)
t=t.replace('"frame_limit":Engine.max_fps,','"frame_limit":Engine.max_fps,"actor_count":s.world.units.size(),"options":GameData.options.duplicate(),"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),')
(s/'dar_standard_base.gd').write_text(t)
t=(r/'tools/tests/dar_leanos_route.gd').read_text().replace('extends "path_trace_zone_traversal.gd"','extends "dar_standard_base.gd"')
(s/'dar_standard_route.gd').write_text(t)
# Same private wrapper machinery as the earlier CPU profiles, now on merged main.
t=(s/'prepare_round4_profile.py').read_text();t=t[:t.index('# Eligible mechanism census')]+'''\n(s/'dar-standard-profile-methods.json').write_text(json.dumps(wrapped,indent=2))
shutil.copy2(s/'runtime.x86_64',out/'runtime.x86_64');shutil.copytree(r/'game/src/native/bin',out/'src/native/bin',dirs_exist_ok=True)
with (s/'dar-standard-profile-export.log').open('w') as log:
 result=subprocess.run(['/home/llm2x/.local/bin/godot-4','--headless','--path',str(dest),'--export-pack','Linux',str(out/'runtime.pck')],env=os.environ|{'XDG_DATA_HOME':str(s/'import-profile')},stdout=log,stderr=subprocess.STDOUT)
print('Dar standard profile export',result.returncode,flush=True);raise SystemExit(result.returncode)
'''
t=t.replace("dest=s/'round4-profile-game';out=s/'round4-profile'","dest=s/'dar-standard-profile-game';out=s/'dar-standard-profile'")
t=t.replace("(dest/'src/ei/figure.gd').write_bytes(subprocess.check_output(['git','show','18b58726:game/src/ei/figure.gd'],cwd=r))",'# No private gameplay fixes: this is merged main.')
exec(compile(t,str(s/'prepare_dar_standard.py'),'exec'))

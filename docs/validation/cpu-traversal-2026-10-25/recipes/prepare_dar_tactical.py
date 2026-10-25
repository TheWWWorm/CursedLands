from pathlib import Path
s=Path(__file__).resolve().parent
p=s/'dar_standard_base.gd';t=p.read_text()
a=t.index('func _process(');b=t.index('\nfunc key(',a)
t=t[:a]+'''func _process(_dt: float) -> void:
	if g and g.rig and hero:
		g.rig._window_focused = true
		g.rig.yaw = heading
		g.rig.focus(hero.global_position)

func _tactical_ready() -> bool:
	return s.world!=null and not s._remote_loading and not s._zone_holding and not ShaderCompilationScreen.active() and not g.hud.blocks_camera()
''' +t[b:]
t=t.replace('"control_mode":3','"control_mode":0').replace('g.direct.usable()','_tactical_ready()')
t=t.replace('if goal.is_finite(): key(KEY_W,true)','if goal.is_finite():g.issue({"t":"move","units":[hero.uid],"x":goal.x,"y":goal.y,"run":true})')
t=t.replace('check(body==frames,label+" uses the production first-person body")','check(body==0,label+" retains the tactical camera and complete actor model")')
t=t.replace('keyboard input moves the authority-controlled hero','move command moves the authority-controlled hero').replace('first-person controls','tactical controls')
t=t.replace('g.rig.release();g.rig._window_focused=true','g.rig.release();g.rig._window_focused=true;g.rig.distance=CameraRig.M_DEFAULT_DISTANCE')
t=t.replace('Real solo worker, normal keyboard steering, live AI and authored geometry; camera turns are scripted.','Real solo worker, normal move commands, live AI and authored geometry; tactical camera follows the hero with scripted turns.')
t=t.replace('STANDARD_ZONE_TRAVERSAL','TACTICAL_ZONE_TRAVERSAL')
(s/'dar_tactical_base.gd').write_text(t)
t=(s/'dar_standard_route.gd').read_text().replace('extends "dar_standard_base.gd"','extends "dar_tactical_base.gd"')
(s/'dar_tactical_route.gd').write_text(t)
for view in ['standard','tactical']:
 t='''extends "dar_VIEW_route.gd"
var measuring := false
var render_rows := []
var render_phases := []
func _process(dt: float) -> void:
	super._process(dt)
	if not measuring:return
	var vp:=get_viewport().get_viewport_rid()
	render_rows.append({"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(vp),"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(vp),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
func phase(label: String,seconds: float,goal:=Vector2.INF,pan:=false)->void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	render_rows=[];measuring=true
	await super.phase(label,seconds,goal,pan)
	measuring=false;render_phases.append({"phase":label,"rows":render_rows})
	write_file("render-metrics.json",JSON.stringify(render_phases))
'''.replace('VIEW',view)
 (s/('dar_'+view+'_metrics.gd')).write_text(t)

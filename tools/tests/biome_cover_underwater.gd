extends Node
## Compare immutable cover depths and GPU attenuation with the independent
## visual-water query over the actual authored mesh, plus lifecycle controls.
const Sea = preload("res://src/game/fx/biome_cover_water.gd")
const Cover = preload("res://src/game/fx/biome_cover.gd")
const Geometry = preload("res://src/game/fx/biome_cover_mesh.gd")
const Surface = preload("res://src/game/fx/water_surface.gd")
const N := 32
var checks := 0
var failures := 0
var rows := []

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count := 12) -> void:
	for i in count:
		if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
		await get_tree().process_frame

func oracle(points: PackedVector3Array,p: Vector2) -> float:
	var best := -INF
	for y in 2:
		for x in 2:
			var at := y*3+x
			for ids: Array in [[at+3,at+1,at],[at+1,at+3,at+4]]:
				var a := points[ids[0]]; var b := points[ids[1]]; var c := points[ids[2]]
				var ab := Vector2(b.x-a.x,-b.z+a.z); var ac := Vector2(c.x-a.x,-c.z+a.z)
				var ap := p-Vector2(a.x,-a.z); var det := ab.cross(ac)
				if absf(det)<0.000001: continue
				var u := ap.cross(ac)/det; var v := ab.cross(ap)/det
				if u>= -0.000001 and v>= -0.000001 and u+v<=1.000001: best=maxf(best,a.y+u*(b.y-a.y)+v*(c.y-a.y))
	return best

func rules() -> void:
	var points := PackedVector3Array()
	for y in 3:
		for x in 3: points.append(Vector3(x,1.0+x*0.2-y*0.1+sin(x+y)*0.2,-y))
	var material := {"color":Color(0.2,0.3,0.4,0.6),"wave":1.0,"type":3}
	for jitter in [false,true]:
		material.wave = 1.0
		var p := points.duplicate()
		if jitter:
			p[4].x += 0.28; p[4].z -= 0.19
		var f := Sea.new(); f.add_tile(Vector2i.ZERO,p,2,material,0.0)
		for y in 16:
			for x in 16:
				var at := Vector2((x+0.31)/8.0,(y+0.67)/8.0)
				var plane := f.sample(at); var expected := oracle(p,at)
				check(plane.w>0 and absf(plane.x*at.x-plane.y*at.y+plane.z-expected)<0.00001,"exact mean-water triangle "+str(jitter))
		check(is_equal_approx(f.sample(Vector2.ONE).w,1.0/6.0),"original material alpha sets the depth coefficient")
		check(f.sample(Vector2(-1,-1))==Vector4.ZERO,"missing water stays absent")
		check(not is_finite(f.ceiling(Vector2.ONE,0.3)),"an incomplete wave envelope is rejected")
		var old := f.sample(Vector2(0.8,0.9)); p.fill(Vector3(100,100,100)); material.wave = 0.0
		check(f.sample(Vector2(0.8,0.9))==old,"published sea data does not retain mutable source arrays")
	var f := Sea.new()
	for y in range(-1,2):
		for x in range(-1,2):
			var p := points.duplicate()
			for i in 9: p[i]=Vector3(p[i].x+x*2,3,-(-p[i].z+y*2))
			f.add_tile(Vector2i(x,y),p,2,{"color":material.color,"wave":1.0,"type":3},0)
	check(absf(f.ceiling(Vector2.ONE,0.3)-2.925)<0.00001,"complete patch includes the vertical wave trough")
	f.tiles[Vector2i(1,0)].owner=0
	check(not is_finite(f.ceiling(Vector2.ONE,0.3)),"another material cannot complete the sea envelope")
	# In particular, tilting the rigid shell must fit the height reservation.
	for kind in [11,12,13]:
		for angle in range(8):
			var r: Array[Dictionary] = [{"kind":kind,"p":Vector2.ONE,"height":0.0,"seed":0.6,
				"normal":Vector3(sqrt(1.0-0.9*0.9),0.9,0),"angle":angle*TAU/8,
				"scale":1.15,"colour":Color.GREEN}]
			var arr := Geometry.new().build(r,Vector2i.ZERO)
			for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
				check(v.y<=float([0.70,1.40,0.13][kind-11])*1.15+0.008,"tilted plant stays inside reserved height")
				check(Vector2(v.x-1,v.z+1).length()<=Cover.RADII[kind]*1.15,"plant stays inside admitted horizontal footprint")

func gpu(points: Array[Dictionary],label: String,wrong := false) -> void:
	var vertices := PackedVector3Array(); var planes := PackedFloat32Array(); var expected := PackedFloat32Array(); var ids := PackedInt32Array()
	for i in mini(N*N,points.size()):
		# Spread the GPU probes across the complete scan, rather than taking
		# only the first patch of flat sea at one edge of the map.
		var p: Dictionary = points[int(float(i)*points.size()/mini(N*N,points.size()))]
		var first := vertices.size(); var x := i%N; var y := i/N
		for corner: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
			var clip := (Vector2(x,y)+corner)/N*2-Vector2.ONE
			vertices.append(p.vertex); planes.append_array([p.plane.x,p.plane.y,p.plane.z,p.plane.w])
			expected.append_array([clip.x,clip.y,p.expected+(0.02 if wrong else 0.0),p.lift])
		ids.append_array([first,first+1,first+2,first,first+2,first+3])
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_INDEX]=ids; arrays[Mesh.ARRAY_CUSTOM1]=planes; arrays[Mesh.ARRAY_CUSTOM2]=expected
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT))
	var shader := Shader.new(); shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
varying float failed;
void vertex() {
	float ei_k=0.0; float cover_leaf=0.25;
	VERTEX.y+=CUSTOM2.w;
"""+Geometry.UNDERWATER+"""
	failed=abs(ei_k-CUSTOM2.z)>0.0001 || abs(cover_leaf-0.25*max(1.0-CUSTOM2.z,0.0))>0.0001 ? 1.0 : 0.0;
	POSITION=vec4(CUSTOM2.xy,0.5,1.0);
}
void fragment() { ALBEDO=vec3(failed,1.0-failed,0.0); }
"""
	var material := ShaderMaterial.new(); material.shader=shader
	var node := MeshInstance3D.new(); node.mesh=mesh; node.material_override=material
	var view := SubViewport.new(); view.size=Vector2i(N,N); view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(view); view.add_child(node)
	var camera := Camera3D.new(); view.add_child(camera); camera.position=Vector3(100,30,-100); camera.look_at(Vector3(100,0,-100),Vector3.FORWARD); camera.current=true
	node.extra_cull_margin=1000.0
	await frames(24); var image := view.get_texture().get_image(); image.save_png("user://underwater-"+label+".png")
	var good := 0; var bad := 0
	for y in N:
		for x in N:
			var c := image.get_pixel(x,y); good+=int(c.g>0.8); bad+=int(c.r>0.8)
	var count := mini(N*N,points.size())
	check(bad==count and good==0 if wrong else good==count and bad==0,"GPU depth and transmission agree with real water mesh "+label)
	rows.append({"case":"gpu-depth","label":label,"points":count,"good":good,"bad":bad,"wrong_control":wrong})
	view.free(); await frames()

func authored() -> void:
	var name := "zone1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--underwater-map="): name=arg.trim_prefix("--underwater-map=")
	var owner: int = {"zone1":2,"zone7":0,"zone8":4}[name]
	# Zone8 has few eligible shallow patches; scan all chunks to retain the
	# same minimum probe coverage as the larger starting/island seas.
	var step := 1 if name=="zone8" else 2
	var t := EITerrain.load_map(name); add_child(t); t.set_process(false); t.details.set_process(false)
	t._water_mat.set_shader_parameter("waves",0.0)
	var surface := Surface.new(t); var baseline := {}; var retained: RefCounted
	for offset in [0.0,0.65,-0.35,0.0]:
		t.set_water_offset(owner,offset); t.details.prepare_grass(); surface.begin_frame()
		var f := t.details._cover_field; var captures: Array[Dictionary] = []; var counts := {}; var timings := []; var visited := 0
		var dry := []; var point_count := 0; var nonflat := 0; var wind_plane_error := 0.0; var custom_bytes := 0
		for y in range(0,int(t.size_ei().y/8),step):
			for x in range(0,int(t.size_ei().x/8),step):
				var key := Vector2i(x,y); var started := Time.get_ticks_usec(); var data := f.build(key,[],[]); timings.append(Time.get_ticks_usec()-started)
				for r: Dictionary in data.records:
					if not r.get("underwater",false): dry.append(r); continue
					counts[r.kind]=int(counts.get(r.kind,0))+1
					check(not f.sea_surface(r.p).is_empty(),"drawn seabed owns underwater roots")
					var ceiling: float = f.sea.ceiling(r.p,f.RADII[r.kind]*r.scale+0.04)
					check(is_finite(ceiling),"complete sea wave footprint")
				var verts: PackedVector3Array = data.arrays[Mesh.ARRAY_VERTEX]
				var planes: PackedFloat32Array = data.arrays[Mesh.ARRAY_CUSTOM1] if data.arrays[Mesh.ARRAY_CUSTOM1]!=null else PackedFloat32Array()
				custom_bytes+=planes.size()*4
				var submerged := PackedInt32Array()
				for i in range(0,verts.size(),3):
					if not planes.is_empty() and planes[i*4+3]>0: submerged.append(i)
				for pick in mini(64,submerged.size()):
					var i := submerged[int(float(pick)*submerged.size()/mini(64,submerged.size()))]
					var vertex := verts[i]; var p := Vector2(vertex.x+x*8,vertex.z-y*8)
					var actual := surface.sample(p)
					check(not actual.is_empty() and actual.material==owner,"actual water triangles cover emitted sea vertices")
					if actual.is_empty(): continue
					var level: float = actual.height; var plane := Vector4(planes[i*4],planes[i*4+1],planes[i*4+2],planes[i*4+3])
					nonflat+=int(absf(plane.x)+absf(plane.y)>0.000001)
					check(absf(plane.x*vertex.x+plane.y*vertex.z+plane.z-level)<0.00002,"baked mean-water plane matches independent query")
					check(vertex.y<level-0.01,"complete plant is underwater")
					# Motion can cross a non-coplanar water triangle: measure the
					# static plane extrapolation error, without calling it wave lighting.
					for direction: float in [-1.0,1.0]:
						var move := Vector2(0.035,0.035*0.35)*direction
						var moved := surface.sample(p+move)
						check(not moved.is_empty(),"maximum cover sway retains authored water coverage")
						if not moved.is_empty(): wind_plane_error=maxf(wind_plane_error,absf(plane.x*(vertex.x+move.x)+plane.y*(vertex.z+move.y)+plane.z-moved.height))
					var lift := 0.10 if point_count%2==0 else 0.0
					var expected := minf(pow(maxf(level-vertex.y-lift,0),2)/(15.0*(1.0-(t.materials[owner].color as Color).a)),4.0)
					captures.append({"vertex":vertex,"plane":plane,"expected":expected,"lift":lift}); point_count+=1
				visited+=1
		check(counts.has(11) and counts.has(12) and counts.has(13),"authored sea emits short/tall vegetation and shells")
		check(point_count>=1024,"enough actual underwater vertex probes across the map")
		var stamp := str(offset)+"-"+str(rows.size())
		if baseline.is_empty(): baseline={"dry":dry,"counts":counts}; retained=f.sea
		elif offset==0.0: check(dry==baseline.dry and counts==baseline.counts,"flood/drain/restore preserves deterministic distribution")
		timings.sort(); rows.append({"case":"authored","map":name,"owner":owner,"offset":offset,"counts":counts,"points":point_count,"nonflat_points":nonflat,"wind_plane_error_m":wind_plane_error,"custom1_bytes":custom_bytes,"chunks":visited,"build_us_median":timings[timings.size()/2],"build_us_max":timings[-1],"sea_tiles":f.sea.tiles.size()})
		if DisplayServer.get_name()!="headless": await gpu(captures,stamp)
		if offset==0.65 and DisplayServer.get_name()!="headless": await gpu(captures,"wrong",true)
	var probe := Vector2(retained.tiles.keys()[0])*2+Vector2.ONE
	var saved: Vector4 = retained.sample(probe); t.free()
	check(saved.w>0 and retained.sample(probe)==saved,"retained immutable sea data survives terrain destruction")
	surface=null; retained=null

func _ready() -> void:
	for option in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[option]=0
	GameData.options["gfx_biome_cover"]=1; Gfx.ensure_globals(); Engine.time_scale=0; Engine.max_fps=120
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; RenderingServer.set_render_loop_enabled(true)
	rules(); await authored()
	TexUpscale.shutdown(); await frames()
	FileAccess.open("user://biome-cover-underwater.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("BIOME_UNDERWATER checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)

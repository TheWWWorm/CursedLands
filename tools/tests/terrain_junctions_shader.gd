extends Node
## GPU invariants for the production junction field and shader. Constant donor
## art isolates field behavior; a separate patterned-art pass checks relief
## tap identity. Original-map visual acceptance is separate.
## No CPU copy of the transition/warp/score formula is evaluated here.
const Field = preload("res://src/game/fx/terrain_transition.gd")
const GRID := 16
const COLUMNS := 64
const PIXELS := 2
const EPSILON := 0.00001
const RELIEF_STEP := 0.03125 # 1/512 * 8 * 1.5 / (1 - 2 * 8/512*8)
const ORIGINAL := Vector3(0.21, 0.33, 0.47)
const HEADER := """shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform sampler2D probe_data : filter_nearest, repeat_disable;
uniform int probe_count;
uniform int probe_columns;
uniform int probe_rows;
uniform ivec4 donor_codes;
uniform int fifth_donor;
uniform bool probe_patterned=false;
vec3 probe_donor(int slot) {
	if (slot==donor_codes.x) { return vec3(0.8,0.2,0.1); }
	if (slot==donor_codes.y) { return vec3(0.1,0.8,0.2); }
	if (slot==donor_codes.z) { return vec3(0.2,0.1,0.8); }
	if (slot==donor_codes.w) { return vec3(0.8,0.8,0.8); }
	if (slot==fifth_donor) { return vec3(0.6,0.2,0.7); }
	return vec3(1.0,0.0,1.0);
}
vec3 probe_gradient(vec2 dx,vec2 dy) {
	return vec3(dx.x+dy.y,dx.y+dy.x,dx.x-dy.x+dx.y-dy.y)*0.25;
}
vec3 tile_sample(float code, vec2 p, vec2 dx, vec2 dy) {
	vec3 color=probe_donor(int(code));
	if (probe_patterned) { color=color*0.4+vec3(p.x*0.2,p.y*0.3,0.1)+probe_gradient(dx,dy); }
	return color;
}
vec4 tile_traits(float type) {
	if (int(type)==2) { return vec4(0.0,1.0,0.0,0.0); }
	if (int(type)==9) { return vec4(0.0,0.0,1.0,0.0); }
	if (int(type)==15) { return vec4(0.0,0.0,0.0,1.0); }
	return vec4(1.0,0.0,0.0,0.0);
}
vec3 ground_sample(ivec2 cell, vec2 p, vec2 dx, vec2 dy, out vec4 traits) {
	traits=vec4(1.0,0.0,0.0,0.0);
	if (probe_patterned) { return vec3(0.1+(float(cell.x)+p.x)*0.015,0.1+(float(cell.y)+p.y)*0.02,0.31)+probe_gradient(dx,dy); }
	return vec3(0.21,0.33,0.47);
}
// END_GROUND_TILE_SAMPLER
"""
const FOOTER := """
float probe_max(vec4 value) {
	return max(max(abs(value.x),abs(value.y)),max(abs(value.z),abs(value.w)));
}
bool probe_finite(vec4 value) { return !any(isnan(value)) && !any(isinf(value)); }
vec3 probe_sample(vec4 point, bool core, out vec4 traits) {
	ivec2 cell=ivec2(point.xy); vec2 p=point.zw;
	if (core) {
		return transition_junction_sample(cell,p,vec2(0.001,0.0),vec2(0.0,0.001),
			transition_row(cell),transition_junction_row(cell),vec3(0.21,0.33,0.47),
			vec4(1.0,0.0,0.0,0.0),traits);
	}
	return ground_sample(cell,p,vec2(0.001,0.0),vec2(0.0,0.001),traits);
}
void fragment() {
	ivec2 block=ivec2(floor(UV*vec2(float(probe_columns),float(probe_rows))));
	int id=block.y*probe_columns+block.x;
	if (id>=probe_count) { ALBEDO=vec3(0.0,0.0,1.0); }
	else {
		vec4 a=texelFetch(probe_data,ivec2(0,id),0);
		vec4 b=texelFetch(probe_data,ivec2(1,id),0);
		vec4 expected=texelFetch(probe_data,ivec2(2,id),0);
		vec4 control=texelFetch(probe_data,ivec2(3,id),0);
		int operation=int(control.x); float error=0.0; bool valid=true;
		vec4 ta; vec4 tb; vec3 ca; vec3 cb;
		if (operation==0 || operation==1 || operation==7) {
			ca=probe_sample(a,operation==0,ta); cb=probe_sample(b,operation==0,tb);
			error=max(probe_max(vec4(ca-cb,0.0)),probe_max(ta-tb));
			valid=probe_finite(vec4(ca,0.0)) && probe_finite(vec4(cb,0.0)) && probe_finite(ta) && probe_finite(tb);
		} else if (operation==2) {
			vec4 weights=transition_junction_weights(transition_junction_row(ivec2(a.xy)),a.zw);
			error=probe_max(weights-expected);
			valid=probe_finite(weights) && abs(dot(weights,vec4(1.0))-1.0)<0.000001 && all(greaterThanEqual(weights,vec4(0.0)));
		} else if (operation==3) {
			vec4 row=transition_row(ivec2(a.xy)); vec4 metadata=transition_junction_row(ivec2(a.xy));
			int packed=int(metadata.r);
			ivec4 ids=ivec4(packed&63,(packed>>6)&63,(packed>>12)&63,(packed>>18)&63);
			valid=all(equal(ids,ivec4(expected))) && ((int(row.b)>>20)&15)==int(control.z) && (int(row.b)&15)==int(control.w)
				&& (int(metadata.b)&32767)==int(b.x) && (int(metadata.a)&32767)==int(b.y)
				&& ((int(metadata.b)>>15)&15)==int(b.z) && ((int(metadata.a)>>15)&15)==int(b.w);
		} else if (operation==4 || operation==8) {
			ca=probe_sample(a,false,ta);
			error=max(probe_max(vec4(ca-vec3(0.21,0.33,0.47),0.0)),probe_max(ta-vec4(1.0,0.0,0.0,0.0)));
			if (operation==8) {
				for (int k=0;k<4;k++) {
					vec2 offset=vec2(k<2 ? (k==0 ? -control.z:control.z):0.0,k>=2 ? (k==2 ? -control.z:control.z):0.0);
					cb=probe_sample(a+vec4(0.0,0.0,offset),false,tb);
					error=max(error,max(probe_max(vec4(cb-vec3(0.21,0.33,0.47),0.0)),probe_max(tb-vec4(1.0,0.0,0.0,0.0))));
				}
			}
		} else if (operation==5) {
			ca=probe_sample(a,false,ta);
			cb=transition_pair_sample(ivec2(a.xy),a.zw,vec2(0.001,0.0),vec2(0.0,0.001),tb);
			error=max(probe_max(vec4(ca-cb,0.0)),probe_max(ta-tb));
		} else if (operation==6 || operation==9) {
			ca=probe_sample(a,false,ta);
			valid=probe_finite(vec4(ca,0.0)) && probe_finite(ta) && all(greaterThanEqual(ta,vec4(-0.000001)))
				&& all(lessThanEqual(ta,vec4(1.000001))) && all(greaterThanEqual(ca,vec3(0.0))) && all(lessThanEqual(ca,vec3(1.0)));
			error=abs(dot(ta,vec4(1.0))-1.0);
			if (operation==9) { error=max(error,abs(ta.w)); }
		} else if (operation==10) {
			valid=transition_row(ivec2(a.xy))==vec4(0.0) && transition_junction_row(ivec2(a.xy))==vec4(0.0);
		} else if (operation==11) {
			vec2 seed=vec2(expected.x*17.31,expected.x*29.17);
			float left=PROBE_MATERIAL_NOISE((a.xy+a.zw)*2.6+seed);
			float right=PROBE_MATERIAL_NOISE((b.xy+b.zw)*2.6+seed);
			error=abs(left-right); valid=probe_finite(vec4(left,right,0.0,0.0));
		} else if (operation==12) {
			vec3 left; vec3 right; vec3 down; vec3 up;
			transition_relief_samples(ivec2(a.xy),a.zw,vec2(control.w,0.0),expected.xy,expected.zw,left,right,down,up);
			int tap=int(control.z);
			ca=tap==0 ? left:(tap==1 ? right:(tap==2 ? down:up));
			// Each probe supplies one independent old call coordinate. The
			// production relief helper's four outputs are checked individually.
			cb=ground_sample(ivec2(b.xy),b.zw,expected.xy,expected.zw,tb);
			error=probe_max(vec4(ca-cb,0.0));
			valid=probe_finite(vec4(ca,0.0)) && probe_finite(vec4(cb,0.0));
		} else { valid=false; }
		bool passed=valid && error<=control.y;
		// Binary channels are exact on both linear and sRGB backends. Blue is
		// a visual residual only, not an uncalibrated numeric GPU readback.
		ALBEDO=vec3(passed ? 0.0:1.0,passed ? 1.0:0.0,clamp(error*8.0,0.0,1.0));
	}
}
"""

var checks := 0
var failures := 0
var probes: Array[Dictionary] = []
var records := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func point(cell: Vector2i, local: Vector2) -> Color:
	return Color(cell.x,cell.y,local.x,local.y)

func add_probe(group: String, label: String, operation: int, a: Color, b := Color(0,0,0,0), expected := Color(0,0,0,0), tolerance := 0.000001, extra := Vector2.ZERO) -> void:
	probes.append({"group":group,"label":label,"a":a,"b":b,"expected":expected,"control":Color(operation,tolerance,extra.x,extra.y)})

func fixture() -> Dictionary:
	var terrain := EITerrain.new()
	terrain.sectors_x=1;terrain.sectors_y=1;terrain.grid_w=33
	terrain.heights.resize(1089);terrain.land_xy.resize(1089);terrain.land_n.resize(1089);terrain.land_n.fill(Vector3.UP)
	terrain.land_tile.resize(256);terrain.tile_types.resize(16384)
	var vertices := PackedByteArray();vertices.resize(17*17)
	for y in 17:
		for x in 17:
			vertices[y*17+x]=(1 if x<=8 else 2) if y<=8 else (3 if x<=8 else 43)
	# A neighboring full set and a separate three-family junction. Every
	# signature is generated from one shared vertex field, without conflicts.
	vertices[8*17+10]=31;vertices[9*17+10]=3
	vertices[7*17+7]=2;vertices[8*17+7]=3
	for y in range(0,4):
		for x in range(13,17):vertices[y*17+x]=31
	var assigned := {};var rules := {};var next_slot := 0
	var types := {1:0,2:2,3:9,43:15,31:11}
	for y in GRID:
		for x in GRID:
			var corners := PackedByteArray([vertices[y*17+x],vertices[y*17+x+1],vertices[(y+1)*17+x],vertices[(y+1)*17+x+1]])
			var unsupported := Vector2i(x,y)==Vector2i(5,8)
			var key := str(corners)+(":path" if unsupported else "")
			if not assigned.has(key):
				var slot := 16383 if corners==PackedByteArray([43,43,43,43]) else next_slot
				if slot!=16383:next_slot+=1
				assigned[key]=slot
				var atlas := slot>>6
				if not rules.has(atlas):
					var blank:=PackedByteArray();blank.resize(256);rules[atlas]=blank
				var signature := PackedByteArray();signature.resize(4)
				for k in 4:signature[Field.CORNER_ORDER[0][k]]=corners[k]
				for k in 4:rules[atlas][(slot&63)*4+k]=signature[k]
				terrain.tile_types[slot]=1 if unsupported else int(types[corners[0]])
			terrain.land_tile[y*GRID+x]=assigned[key]
	var field := Field.new(terrain,rules)
	return {"terrain":terrain,"field":field,"vertices":vertices}

func edge(label: String, a: Vector2i, b: Vector2i, vertical: bool) -> void:
	for t in [0.0,0.125,0.25,0.5,0.75,0.875,1.0]:
		var left := Vector2(1,t) if vertical else Vector2(t,1)
		var right := Vector2(0,t) if vertical else Vector2(t,0)
		add_probe(label+" core",str(t),0,point(a,left),point(b,right),Color(0,0,0,0),0.00001)
		# Unlike exact public aliases, these calls retain distinct tile rows.
		var delta := Vector2(EPSILON,0) if vertical else Vector2(0,EPSILON)
		add_probe(label+" entry",str(t),1,point(a,left-delta),point(b,right+delta),Color(0,0,0,0),0.002)
		add_probe(label+" alias",str(t),1,point(a,left),point(b,right),Color(0,0,0,0),0.000001)

func build_probes(field: Field) -> void:
	check(field.junctions>0 and field.admitted_families[3]>0 and field.admitted_families[4]>0,"production builder admits coherent three/four-family fixtures")
	check(field.conflicting==0 and field.missing_donor==0,"fixture has shared vertices and exact own-family donors")
	check(field.families_at(8*GRID+8)==PackedByteArray([1,2,3,43]),"known four-family cell uses authored identities")
	check(field.families_at(7*GRID+7)==PackedByteArray([1,2,3]),"known three-family cell uses authored identities")
	check(field.donors[43]==16383,"fourth donor exercises maximum original atlas slot")
	check(field.rows[8*GRID+5].a==0,"authored path neighbor is outside the field")
	for witness in [[7,7,173,0.5,3],[7,7,417,0.5,2],[8,8,732,0.25,2],[8,8,488,0.5,3],[8,8,732,0.5,2],[8,8,960,0.5,43]]:
		var cell:=Vector2i(witness[0],witness[1]);var local:=Vector2(0.25+float(witness[2])/2048.0,witness[3])
		add_probe("material noise lattice continuity",str(witness),11,point(cell,local),point(cell,local+Vector2(1.0/2048.0,0)),Color(witness[4],0,0,0),0.01)
	if OS.get_cmdline_user_args().has("--junction-noise-probe"):return
	edge("pair to four",Vector2i(8,7),Vector2i(8,8),false)
	edge("pair to three",Vector2i(7,6),Vector2i(7,7),false)
	edge("different full sets",Vector2i(8,8),Vector2i(9,8),true)
	edge("halo to legacy",Vector2i(8,5),Vector2i(8,6),false)
	edge("pure to mixed",Vector2i(7,9),Vector2i(8,9),true)
	for cell in [Vector2i(8,8),Vector2i(7,7),Vector2i(9,8)]:
		for local in [Vector2.ZERO,Vector2(1,0),Vector2(0,1),Vector2.ONE]:
			add_probe("pure corner endpoints",str(cell)+str(local),4,point(cell,local))
		for y in 9:
			for x in 9:add_probe("finite normalized receiver",str(cell)+str(Vector2i(x,y)),6,point(cell,Vector2(x,y)/8.0))
	add_probe("equal four weights","center",2,point(Vector2i(8,8),Vector2(0.5,0.5)),Color(0,0,0,0),Color(0.25,0.25,0.25,0.25))
	add_probe("equal three runners","center",2,point(Vector2i(7,7),Vector2(0.5,0.5)),Color(0,0,0,0),Color(0.5,0.25,0.25,0))
	for local in [Vector2(0.3,0.3),Vector2(0.5,0.5),Vector2(0.7,0.7)]:
		add_probe("zero absent family","three "+str(local),9,point(Vector2i(7,7),local))
	add_probe("24 bit GPU packing","odd high family pack and maximum donor",3,point(Vector2i(8,8),Vector2.ZERO),
		Color(field.donors[3]+1,field.donors[43]+1,9,15),Color(1,2,3,43),0.0,Vector2(15,2))
	add_probe("24 bit GPU packing","odd high influence pack preserves corner bit",3,point(Vector2i(7,7),Vector2.ZERO),
		Color(field.donors[3]+1,0,9,0),Color(1,2,3,0),0.0,Vector2(15,1))
	for cell in [Vector2i(8,3),Vector2i(8,4),Vector2i(2,8)]:
		check(((int(field.rows[cell.y*GRID+cell.x].b)>>20)&15)==0,"legacy witness outside junction halo "+str(cell))
		for x in 9:add_probe("legacy pair unchanged",str(cell)+" "+str(x),5,point(cell,Vector2(float(x)/8.0,0.5)),Color(0,0,0,0),Color(0,0,0,0),0.0)
	for x in [0.0,0.05,0.10,0.15]:
		add_probe("unsupported band","mixed x="+str(x),4,point(Vector2i(6,8),Vector2(x,0.5)))
	for x in [0.0,0.05,0.10]:
		add_probe("unsupported relief guard","mixed x="+str(x),8,point(Vector2i(6,8),Vector2(x,0.5)),Color(0,0,0,0),Color(0,0,0,0),0.000001,Vector2(RELIEF_STEP,0))
	add_probe("unsupported relief guard","path tap crosses into mixed receiver",8,point(Vector2i(5,8),Vector2(0.99,0.5)),Color(0,0,0,0),Color(0,0,0,0),0.000001,Vector2(RELIEF_STEP,0))
	for cell in [Vector2i(-1,8),Vector2i(16,8),Vector2i(8,-1),Vector2i(8,16),Vector2i(8,31)]:
		add_probe("logical field bounds",str(cell),10,point(cell,Vector2.ZERO))
	# Dense GPU evaluations cross heterogeneous hard/soft score orderings.
	# This is a sampled continuity bound, not a proof over every world point.
	for cell in [Vector2i(7,7),Vector2i(8,8)]:
		for y in [0.25,0.5,0.75]:
			for k in 1024:
				var a:=Vector2(0.25+float(k)/2048.0,y)
				var b:=a+Vector2(1.0/2048.0,0)
				add_probe("heterogeneous continuity "+str(cell)+" y="+str(y),str(k),7,point(cell,a),point(cell,b),Color(0,0,0,0),0.02)

func build_relief_probes() -> void:
	var sites := [
		["heterogeneous three",Vector2i(7,7),Vector2(0.5,0.5)],
		["four family",Vector2i(8,8),Vector2(0.5,0.5)],
		["full set edge",Vector2i(8,8),Vector2(0.99,0.5)],
		["pair junction edge",Vector2i(8,7),Vector2(0.5,0.99)],
		["pure endpoint",Vector2i(7,9),Vector2(0.99,0.01)],
		["guarded band",Vector2i(6,8),Vector2(0.10,0.5)],
		["path crossing",Vector2i(5,8),Vector2(0.99,0.5)],
		["halo legacy edge",Vector2i(8,6),Vector2(0.5,0.01)],
		["plain original",Vector2i(2,2),Vector2(0.01,0.01)],
		["four tile corner",Vector2i(8,8),Vector2(0.01,0.01)],
	]
	var names := ["left","right","down","up"]
	# Independent coordinates of the four pre-helper calls, in original order.
	var offsets := [Vector2(-RELIEF_STEP,0),Vector2(RELIEF_STEP,0),Vector2(0,-RELIEF_STEP),Vector2(0,RELIEF_STEP)]
	var gradients := [Color(0.013,0.021,-0.017,0.025),Color(-0.033,0.002,0.007,-0.015)]
	for site in sites:
		for g in gradients.size():
			for k in 4:
				add_probe("patterned relief "+site[0],names[k]+" gradients="+str(g),12,
					point(site[1],site[2]),point(site[1],site[2]+offsets[k]),gradients[g],0.000001,Vector2(k,RELIEF_STEP))

func source_controls() -> void:
	var terrain_source: String=EITerrain.TERRAIN_SHADER
	var contact_source: String=GroundContactShader.source(EIFigure.OBJECT_SHADER,true)
	for source: String in [terrain_source,contact_source,terrain_source.replace("shader_type spatial;","shader_type spatial;\n#define EI_BAKED_TERRAIN")]:
		var old: String=Field.TransitionShader.source(source,false)
		var current: String=Field.TransitionShader.source(source,true)
		var original_calls: String=Field.TransitionShader.CONTACT_RELIEF if source==contact_source else Field.TransitionShader.TERRAIN_RELIEF
		check(old.count(original_calls)==1 and not old.contains("transition_relief_samples("),"no-junction source retains original four relief calls")
		check(current.count(Field.TransitionShader.SHARED_RELIEF)==1 and not current.contains(original_calls),"junction land/contact/baked source replaces exactly one relief block")

func frames(count: int) -> void:
	for i in count:await get_tree().process_frame

func evaluate(view: SubViewport, material: ShaderMaterial, mesh: QuadMesh, patterned: bool, label: String) -> int:
	var payload := PackedColorArray()
	for probe: Dictionary in probes:
		for key in ["a","b","expected","control"]:payload.append(probe[key])
	var probe_texture:=ImageTexture.create_from_image(Image.create_from_data(4,probes.size(),false,Image.FORMAT_RGBAF,payload.to_byte_array()))
	var row_count:=ceili(float(probes.size())/COLUMNS)
	view.size=Vector2i(COLUMNS*PIXELS,row_count*PIXELS);mesh.size=Vector2(2.0*view.size.x/view.size.y,2)
	material.set_shader_parameter("probe_data",probe_texture);material.set_shader_parameter("probe_count",probes.size())
	material.set_shader_parameter("probe_columns",COLUMNS);material.set_shader_parameter("probe_rows",row_count)
	material.set_shader_parameter("probe_patterned",patterned)
	await frames(20);await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image();image.convert(Image.FORMAT_RGBA8);image.save_png("user://terrain-junctions-shader-"+label+".png")
	var groups := {}
	for i in probes.size():
		var probe: Dictionary=probes[i]
		if not groups.has(probe.group):groups[probe.group]={"group":probe.group,"patterned":patterned,"probes":0,"failed":[]}
		var group: Dictionary=groups[probe.group];group.probes+=1
		var pixel:=image.get_pixel((i%COLUMNS)*PIXELS+1,int(i/COLUMNS)*PIXELS+1)
		if pixel.r>0.05 or pixel.g<0.95:
			group.failed.append({"index":i,"label":probe.label,"pixel":str(pixel),"a":str(probe.a),"b":str(probe.b),"tolerance":probe.control.g})
	for group: Dictionary in groups.values():
		check(group.failed.is_empty(),"GPU "+group.group+" ("+str(group.probes)+" probes; failures="+str(group.failed.size())+")")
		records.append(group)
	return probes.size()

func run() -> void:
	var data := fixture();var terrain: EITerrain=data.terrain;var field: Field=data.field
	build_probes(field);source_controls()
	var view:=SubViewport.new();view.size=Vector2i(128,128);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2;camera.position=Vector3(0,0,2);view.add_child(camera);camera.current=true
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color.MAGENTA;view.add_child(environment)
	var quad:=MeshInstance3D.new();var mesh:=QuadMesh.new();quad.mesh=mesh
	var shader:=Shader.new();var production_source:=Field.TransitionShader.source(HEADER,true)
	var material_noise:="transition_junction_noise" if production_source.contains("float transition_junction_noise(") else "transition_noise"
	shader.code=production_source+FOOTER.replace("PROBE_MATERIAL_NOISE",material_noise)
	check(shader.code.contains(Field.TransitionShader.JUNCTION_FUNCTIONS),"harness includes exact production junction functions")
	var material:=ShaderMaterial.new();material.shader=shader;field.bind(material)
	material.set_shader_parameter("donor_codes",Vector4i(field.donors[1],field.donors[2],field.donors[3],field.donors[43]))
	material.set_shader_parameter("fifth_donor",field.donors[31]);quad.material_override=material;view.add_child(quad)
	# ShaderMaterial.get_shader_parameter reads explicit overrides only. Check
	# the declared defaults without setting an override that could hide a bug.
	check(RenderingServer.shader_get_parameter_default(shader.get_rid(),"transition_relief_passes")==4,"relief helper receives all four default passes")
	check(RenderingServer.shader_get_parameter_default(shader.get_rid(),"transition_junction_materials")==4,"material helper receives all four default families")
	FileAccess.open("user://terrain-junctions-shader.gdshader",FileAccess.WRITE).store_string(shader.code)
	var base_probes:=await evaluate(view,material,mesh,false,"base")
	probes.clear();build_relief_probes()
	var relief_probes:=await evaluate(view,material,mesh,true,"relief")
	var report: Dictionary={"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"probes":base_probes+relief_probes,
		"base_probes":base_probes,"relief_probes":relief_probes,
		"material_noise":material_noise,
		"epsilon":EPSILON,"relief_step":RELIEF_STEP,"continuity_step":1.0/2048.0,"continuity_tolerance":0.02,
		"field":{"families":field.admitted_families,"junctions":field.junctions,"donors":field.donors,"bytes":field.tiles.get_image().get_data().size()},
		"limits":"Synthetic constant-color invariants plus patterned-art relief tap equivalence; no claim of original-art quality, global continuity proof or performance. Binary pass/fail is evaluated on GPU; blue pixels are uncalibrated residual visualization.","groups":records}
	FileAccess.open("user://terrain-junctions-shader.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	view.free();terrain.free();await frames(3)

func _ready() -> void:
	Engine.max_fps=120;process_mode=Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if DisplayServer.get_name()=="headless":
		printerr("terrain_junctions_shader requires a rendered backend");get_tree().quit(2);return
	await run()
	print("TERRAIN_JUNCTIONS_SHADER ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

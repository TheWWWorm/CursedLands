extends Node
## Sample the production wall projection with deliberately non-seamless art.
## Pixel comparisons catch hard wrap seams and identical 2/4 metre patches.
const Cliff = preload("res://src/game/fx/terrain_cliff_shader.gd")
var checks := 0
var failures := 0
var out := "user://"
var report := {}

func _ready() -> void:
	RenderingServer.set_render_loop_enabled(true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)

func capture(view: SubViewport,label: String) -> Image:
	for i in 6:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image()
	image.save_png(out.path_join(label+".png"))
	return image

func delta(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	Engine.max_fps=30
	var view:=SubViewport.new();view.size=Vector2i(1024,512);view.disable_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var rect:=ColorRect.new();rect.size=Vector2(view.size);view.add_child(rect)
	var shader:=Shader.new()
	shader.code="""shader_type canvas_item;
uniform vec2 origin=vec2(0.0);
uniform int normal_mode=0;
vec4 tile_info(ivec2 cell) { return vec4(0.0); }
// Opposite edges deliberately disagree; a wrapped projection must not
// depend on a specially seamless source texture to pass this fixture.
vec3 tile_sample(float code,vec2 p,vec2 dx,vec2 dy) {
 return vec3(0.1+0.8*p.x,0.1+0.8*p.y,0.5+0.4*sin(p.x*9.0+p.y*7.0));
}
"""+Cliff.FUNCTIONS+"""
void fragment() {
 vec2 p=(UV-0.5)*vec2(16.0,8.0)+origin;
 vec3 c=cliff_tile(0.0,vec3(p,0.0),vec3(0.0,1.0,1.0),vec3(1.0/64.0,0.0,0.0),vec3(0.0,1.0/64.0,0.0));
 if(normal_mode>0) {
  vec3 planes=normal_mode==2?vec3(0.0):vec3(0.0,1.0,1.0);
  c=cliff_relief_normal(vec3(p,0.0),vec3(0,0,1),vec3(0,0,1),vec3(0,0,1),planes,normal_mode==3?100.0:10.0,normal_mode==4?1.0:1.0/64.0)*0.5+0.5;
 }
 COLOR=vec4(c,1.0);
}
"""
	var material:=ShaderMaterial.new();material.shader=shader;rect.material=material
	var image:=await capture(view,"cliff-pattern")
	check(image!=null and image.get_size()==view.size,"wall sampler produces the full diagnostic image")
	var peak_x:=0.0;var peak_y:=0.0;var sum:=0.0;var squares:=0.0
	for y in range(1,511):
		for x in range(1,1023):
			var c:=image.get_pixel(x,y)
			peak_x=maxf(peak_x,delta(c,image.get_pixel(x-1,y)))
			peak_y=maxf(peak_y,delta(c,image.get_pixel(x,y-1)))
			sum+=c.r;squares+=c.r*c.r
	var n:=510.0*1022.0
	var deviation:=sqrt(maxf(squares/n-pow(sum/n,2),0.0))
	check(peak_x<0.1,"no hard horizontal wrap seam: %.6f"%peak_x)
	check(peak_y<0.1,"no hard vertical wrap seam: %.6f"%peak_y)
	check(deviation>0.08,"anti-repeat retains texture contrast instead of flattening the wall: %.6f"%deviation)
	report={"peak_x":peak_x,"peak_y":peak_y,"deviation":deviation,"translations":{}}
	for shift: Vector2i in [Vector2i(128,0),Vector2i(0,128),Vector2i(256,0),Vector2i(0,256),Vector2i(128,128)]:
		var difference:=0.0;var count:=0
		for y in range(0,512-shift.y,3):
			for x in range(0,1024-shift.x,3):
				difference+=delta(image.get_pixel(x,y),image.get_pixel(x+shift.x,y+shift.y));count+=1
		difference/=count;report.translations[str(shift)]=difference
		check(difference>0.04,"wall pattern does not repeat at world shift %s: %.6f"%[Vector2(shift)/64.0,difference])
	material.set_shader_parameter("origin",Vector2(1,0))
	var shifted:=await capture(view,"cliff-pattern-shifted")
	var error:=0.0
	for y in range(0,512,3):
		for x in range(0,960,3):error=maxf(error,delta(image.get_pixel(x+64,y),shifted.get_pixel(x,y)))
	check(error<0.008,"moving the view keeps the pattern fixed in world space: %.6f"%error)
	report["world_lock_error"]=error;report["checks"]=checks;report["failures"]=failures
	material.set_shader_parameter("origin",Vector2.ZERO);material.set_shader_parameter("normal_mode",1)
	var normals:=await capture(view,"cliff-relief")
	var variation:=0.0;var count:=0;var valid:=true;var jump:=0.0
	for y in range(0,480,2):
		for x in range(0,1023,2):
			var c:=normals.get_pixel(x,y);var direction:=Vector3(c.r,c.g,c.b)*2.0-Vector3.ONE
			valid=valid and direction.is_finite() and direction.z>0.8 and absf(direction.length()-1.0)<0.015
			variation+=delta(c,normals.get_pixel(x,y+24));count+=1
			jump=maxf(jump,maxf(delta(c,normals.get_pixel(x+1,y)),delta(c,normals.get_pixel(x,y+1))))
	variation/=count
	check(variation>0.02,"wall normals vary over height instead of forming painted columns: %.6f"%variation)
	check(valid,"rock relief retains bounded outward unit normals")
	check(jump<0.1,"rock relief has no hard noise-cell or ridge seams: %.6f"%jump)
	material.set_shader_parameter("origin",Vector2(1,0))
	var shifted_normals:=await capture(view,"cliff-relief-shifted");error=0.0
	for y in range(0,512,3):
		for x in range(0,960,3):error=maxf(error,delta(normals.get_pixel(x+64,y),shifted_normals.get_pixel(x,y)))
	check(error<0.008,"moving the camera keeps relief fixed to the wall: %.6f"%error)
	for mode in [2,3,4]:
		material.set_shader_parameter("normal_mode",mode)
		var neutral:=await capture(view,"cliff-relief-neutral-%d"%mode);var peak:=0.0
		for y in range(0,512,5):
			for x in range(0,1024,5):peak=maxf(peak,delta(neutral.get_pixel(x,y),Color(0.5,0.5,1.0)))
		check(peak<0.008,"relief preserves flat, distant or unresolved surfaces (%d): %.6f"%[mode,peak])
	report["relief"]={"vertical_variation":variation,"valid":valid,"jump":jump,"world_lock_error":error}
	report["checks"]=checks;report["failures"]=failures
	FileAccess.open(out.path_join("cliff-pattern.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	view.queue_free()
	print("CLIFF_PATTERN ",checks," checks ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)

extends Node
## Draw the production batched sampler against the independent legacy calls.
## Every tap, centre traits, clamping and the no-relief branch are checked on
## the GPU; shader compilation alone cannot catch a driver's changed results.
var failures := 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("TERRAIN_SAMPLING needs a renderer"); get_tree().quit(2); return
	RenderingServer.set_render_loop_enabled(true)
	var view := SubViewport.new(); view.size=Vector2i(192,128); view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2.0; camera.position=Vector3(0,0,2); view.add_child(camera); camera.make_current()
	var draw := MeshInstance3D.new(); var quad := QuadMesh.new(); quad.size=Vector2(3,2)
	draw.mesh=quad; view.add_child(draw)
	view.debug_draw=Viewport.DEBUG_DRAW_DISABLED
	var material := ShaderMaterial.new(); draw.material_override=material
	var header := """shader_type spatial;
render_mode unshaded, fog_disabled;
vec3 ground_sample(ivec2 cell,vec2 p,vec2 dx,vec2 dy,out vec4 traits) {
    traits=vec4(p,dx.x+dy.y,float(cell.x)*0.01);
    return vec3((vec2(cell)+p)*0.03,dx.y+dy.x);
}
"""
	var footer := """
void fragment() {
    int output_id=int(UV.x*6.0);
    int row=int(UV.y*16.0);
    // Include helper-fragment overshoot and both sides of tile joins.
    vec2 p=vec2(-0.00001+float(row%4)*0.33334,-0.02+float(row/4)*0.34667);
    ivec2 tile=ivec2(row%3-1,row%5-1);
    vec2 dx=vec2(0.002,0.0003),dy=vec2(0.0007,0.003),step_uv=vec2(0.03125,0.0);
    bool relief=(row%2)==0;
    vec3 center;vec4 traits;vec3 left;vec3 right;vec3 down;vec3 up;
    terrain_samples(tile,p,dx,dy,step_uv,relief,center,traits,left,right,down,up);
    vec4 expected_traits;
    vec3 expected=ground_sample(tile,clamp(p,vec2(0.0),vec2(0.99999)),dx,dy,expected_traits);
    vec4 actual=vec4(center,0.0),reference=vec4(expected,0.0);
    if(output_id==1) {actual=traits;reference=expected_traits;}
    if(output_id>=2) {
        vec2 point=p-step_uv;
        if(output_id==3) {point=p+step_uv;}
        if(output_id==4) {point=p-step_uv.yx;}
        if(output_id==5) {point=p+step_uv.yx;}
        vec3 color=vec3(0.0);
        if(relief) {color=ground_sample(tile,point,dx,dy,expected_traits);}
        reference=vec4(color,0.0);
        actual=vec4(output_id==2 ? left:(output_id==3 ? right:(output_id==4 ? down:up)),0.0);
    }
    bool ok=all(lessThanEqual(abs(actual-reference),vec4(0.000001)))
        && !any(isnan(actual)) && !any(isinf(actual));
    ALBEDO=ok ? vec3(0.0,1.0,0.0) : vec3(1.0,0.0,0.0);
}
"""
	var shader := Shader.new(); shader.code=header+TerrainSamplingShader.FUNCTIONS+footer
	shader.get_shader_uniform_list(); material.shader=shader
	# The first few submitted frames can precede asynchronous pipeline
	# compilation; wait for presentation before testing the actual pixels.
	await get_tree().create_timer(1.0).timeout
	for i in 4: await RenderingServer.frame_post_draw
	var pixels := view.get_texture().get_image()
	for row in 16:
		for column in 6:
			var pixel := pixels.get_pixel(column*32+16,row*8+4)
			if pixel.g<0.99 or pixel.r>0.01: failures+=1
	pixels.save_png("user://terrain-sampling.png")
	view.free()
	print("TERRAIN_SAMPLING checks=96 failures=",failures)
	get_tree().quit(int(failures>0))

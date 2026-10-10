extends RefCounted
## Shared directional cloud attenuation. A column through the volume depends
## on xz - height * sun.xz / sun.y, so ground, figures and water can sample
## the same field. Keep the original integrator outside its bounded domain.
## This does not change sky density, ray steps or reflected cloud shapes.
const Volume = preload("res://src/game/fx/cloud_volume.gd")
const SIZE := 512
const SPAN := 1024.0
const LOOKUP := """
global uniform sampler2D ei_cv_shadow_field : filter_linear, repeat_disable;
global uniform vec4 ei_cv_shadow_domain; // minimum xz, span, texture size; zero = unavailable
float cv_shadow_field(vec3 p){
 if(ei_cloud_state.w<.5 || ei_cv_storm.z<.5 || ei_cloud_state.y<=0.0 || ei_sun_dir.y<.12 || p.y>=CV_TOP){return 1.0;}
 if(ei_cv_shadow_domain.w>.5 && ei_sun_dir.y>=.18 && p.y<CV_BASE){
  vec3 toward=normalize(ei_sun_dir);
  if(toward.y<.18){return cv_shadow(p,ei_sun_dir);}
  vec2 uv=(p.xz-p.y*toward.xz/toward.y-ei_cv_shadow_domain.xy)/ei_cv_shadow_domain.z;
  float margin=.5/ei_cv_shadow_domain.w;
  if(all(greaterThanEqual(uv,vec2(margin))) && all(lessThanEqual(uv,vec2(1.0-margin)))){
   return textureLod(ei_cv_shadow_field,uv,0.0).r;
  }
 }
 return cv_shadow(p,ei_sun_dir);
}
"""
const SOURCE := """
shader_type canvas_item;
render_mode unshaded;
global uniform sampler2D ei_cloud_noise : filter_linear_mipmap, repeat_enable;
global uniform vec4 ei_cloud_state;
global uniform vec3 ei_sun_dir;
global uniform vec4 ei_cv_shadow_domain;
"""+Volume.COMMON+"""
void fragment(){
 vec2 column=ei_cv_shadow_domain.xy+UV*ei_cv_shadow_domain.z;
 COLOR=vec4(cv_shadow(vec3(column.x,0,column.y),ei_sun_dir),0,0,1);
}
"""
var view: SubViewport
var _parent: WeakRef
var _published := false


func update(owner: Node, map_size: Vector2, enabled: bool) -> void:
	if not owner or not owner.is_inside_tree(): return
	var parent := owner.get_viewport()
	if view and (not is_instance_valid(view) or _parent.get_ref()!=parent):
		release()
	if not view:
		view=SubViewport.new();view.name="CloudShadowField"
		view.size=Vector2i(SIZE,SIZE);view.disable_3d=true;view.use_hdr_2d=true
		view.render_target_update_mode=SubViewport.UPDATE_DISABLED
		var material:=ShaderMaterial.new();material.shader=Shader.new();material.shader.code=SOURCE
		var rect:=ColorRect.new();rect.size=Vector2(SIZE,SIZE);rect.material=material
		view.add_child(rect);_parent=weakref(parent)
		# Map setup can run while a parent is adding its children. Publish the
		# field only on a later call after this attachment has completed.
		parent.add_child.call_deferred(view)
	if not view.is_inside_tree(): return
	var centre:=Vector2(map_size.x,-map_size.y)*.5
	var origin:=(centre-Vector2.ONE*SPAN*.5).snapped(Vector2.ONE*2.0)
	if not _published:
		RenderingServer.global_shader_parameter_set(&"ei_cv_shadow_field",view.get_texture())
		_published=true
	RenderingServer.global_shader_parameter_set(&"ei_cv_shadow_domain",Vector4(origin.x,origin.y,SPAN,float(SIZE) if enabled else 0.0))
	# A child viewport renders before its receiving viewport. Both programs
	# read the same final global sun/weather values, including clock holds.
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED


func release() -> void:
	RenderingServer.global_shader_parameter_set(&"ei_cv_shadow_domain",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_cv_shadow_field",null)
	if is_instance_valid(view):
		# Deferred attachment may still be queued during a rapid option toggle.
		view.queue_free()
	view=null;_parent=null;_published=false

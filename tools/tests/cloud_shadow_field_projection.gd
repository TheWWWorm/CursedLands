extends "clouds.gd"
const SharedField = preload("res://src/game/fx/cloud_shadow_field.gd")

var grid := SharedField.SIZE
var span := SharedField.SPAN
var shadow_view: SubViewport

func _ready() -> void:
 for option: Array in GameData.OPTIONS:
  if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
 GameData.options.merge({"gfx_clouds":3,"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":0},true)
 Gfx.ensure_globals();Gfx.apply_surface_options();Engine.time_scale=0;Engine.max_fps=0;process_mode=Node.PROCESS_MODE_ALWAYS
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
 var field:=Clouds.new();Gfx.set_cloud_frame(get_instance_id(),field.sample(0,"probe-gipat","Gipat",Vector4(.8,.6,.8,1),0,0,12,false))
 var probe:=SubViewport.new();probe.size=Vector2i(383,257);probe.disable_3d=true;probe.use_hdr_2d=true
 probe.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(probe)
 var mat:=ShaderMaterial.new();mat.shader=Shader.new()
 mat.shader.code="shader_type canvas_item;\nrender_mode unshaded;\nglobal uniform vec3 ei_sun_dir;\nuniform float probe_altitude;\n"+Clouds.common_source()+SharedField.LOOKUP+"""
void fragment(){
 vec2 q=ei_cv_shadow_domain.xy+(UV*1.2-.1)*ei_cv_shadow_domain.z;
 vec3 toward=normalize(ei_sun_dir);
 vec2 horizontal=q+probe_altitude*toward.xz/max(toward.y,.18);
 vec3 p=vec3(horizontal.x,probe_altitude,horizontal.y);
 float a=cv_shadow(p,ei_sun_dir),b=cv_shadow_field(p);
 COLOR=vec4(a,b,abs(a-b),1);
}
"""
 var rect:=ColorRect.new();rect.size=Vector2(probe.size);rect.material=mat;probe.add_child(rect)
 Gfx.set_cloud_frame(probe.get_instance_id(),field.frame);await frames(4)
 Gfx.set_cloud_frame(probe.get_instance_id(),field.frame);await frames(4)
 shadow_view=Gfx._cloud_shadow_field.view
 check(shadow_view.size==Vector2i(grid,grid),"actual integrated grid matches declared size")
 await frames(100)
 var deadline:=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:await frames(1)
 var scenarios:=[
  {"id":"gipat","rain":0.0,"allod":"Gipat","sun":SUN},
  {"id":"ingos","rain":.52,"allod":"Ingos","sun":Vector3(-.9,.5,.2).normalized()},
  {"id":"suslanger","rain":0.0,"allod":"Suslanger","sun":Vector3(1,.2,.2).normalized()},
  {"id":"storm","rain":1.0,"allod":"Gipat","sun":SUN},
  {"id":"low-sun","rain":.52,"allod":"Ingos","sun":Vector3(1,.16,0).normalized()},
  {"id":"scaled-sun","rain":.52,"allod":"Ingos","sun":Vector3(2,.3,0)},
  {"id":"night","rain":1.0,"allod":"Ingos","sun":Vector3(1,.1,0).normalized()}]
 for scenario: Dictionary in scenarios:
  RenderingServer.global_shader_parameter_set(&"ei_sun_dir",scenario.sun)
  field=Clouds.new()
  for height: float in [-40.0,0.0,120.0,1500.0,2600.0]:
   mat.set_shader_parameter("probe_altitude",height)
   for seconds: float in [0.0,437.0]:
    var frame: Dictionary=field.sample(seconds,"probe-"+scenario.id,scenario.allod,Vector4(.8,.6,.8,1),scenario.rain,0,12,false)
    Gfx.set_cloud_frame(probe.get_instance_id(),frame)
    await frames(10)
    var im:=probe.get_texture().get_image()
    if height==0.0 and seconds==437.0:im.save_png("user://probe-"+scenario.id+".png")
    var minimum:=1.0;var maximum:=0.0;var peak:=0.0;var total:=0.0;var over:=0
    for y in im.get_height():
     for x in im.get_width():
      var c:=im.get_pixel(x,y);minimum=minf(minimum,c.r);maximum=maxf(maximum,c.r);peak=maxf(peak,c.b);total+=c.b;over+=int(c.b>1.0/1024)
    var row:={"case":"projection","scenario":scenario.id,"seconds":seconds,"height":height,"pixels":im.get_width()*im.get_height(),"reference_range":[minimum,maximum],"max_absolute_error":peak,"mean_absolute_error":total/(im.get_width()*im.get_height()),"pixels_over_1_in_1024":over,"format":im.get_format()}
    rows.append(row);print("SHADOW_PROBE ",JSON.stringify(row))
    check(peak<.004,"projected shadow error below one display level")
  shadow_view.get_texture().get_image().save_exr("user://field-"+scenario.id+".exr")
 mat.set_shader_parameter("probe_altitude",120.0)
 var dynamic_field:=Clouds.new()
 for step in 12:
  var wet:=step%2==1
  var sun_dir:=SUN if step%3==0 else Vector3(-.9,.5,.2).normalized()
  RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun_dir)
  var current: Dictionary=dynamic_field.sample(float(step)*100.0,"jump-"+str(step),"Ingos",Vector4(.8,.6,.8,1),1.0 if wet else 0.0,0,12,false).duplicate(true)
  if step in [4,8]:current.state.w=0.0
  Gfx.set_cloud_frame(probe.get_instance_id(),current)
  await frames(1)
  var im:=probe.get_texture().get_image();var peak:=0.0;var minimum:=1.0;var maximum:=0.0
  for y in im.get_height():
   for x in im.get_width():
    var c:=im.get_pixel(x,y);peak=maxf(peak,c.b);minimum=minf(minimum,c.r);maximum=maxf(maximum,c.r)
  rows.append({"case":"single-frame-jump","step":step,"field_published":Gfx._cloud_shadow_field!=null and Gfx._cloud_shadow_field._published,"clouds_enabled":current.state.w,"max_absolute_error":peak,"reference_range":[minimum,maximum],"pixels":im.get_width()*im.get_height()})
  print("SHADOW_UPDATE ",JSON.stringify(rows.back()))
  check(peak<.004,"same-frame sun/weather/owner/enable jump remains aligned")
 Gfx.clear_clouds();probe.free();TexUpscale.shutdown();await frames(8)
 FileAccess.open("user://shadow-probe.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"grid":grid,"span":span,"rows":rows,"integrated":true,"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method()},"\t"))
 print("SHADOW_PROBE checks=",checks," failures=",failures)
 get_tree().quit(int(failures>0))

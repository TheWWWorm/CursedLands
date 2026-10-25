extends "path_trace_nrd_device.gd"
## One-sample finite area lighting on metal and a soft sun-shadow boundary.
## Compare temporal pixel error against the exact raw AOV from the same rays.
signal readback
var raw_direct:Image
var raw_sun:Image
var lamp_energy:=1.0
func read_raw()->void:
 raw_direct=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,device._rd.texture_get_data(device._raw[5],0))
 raw_sun=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,device._rd.texture_get_data(device._raw[6],0))
 readback.emit.call_deferred()
func frame(history:=true,gi:=true,shadows:=true)->PackedByteArray:
 var bytes:=super.frame(history,gi,shadows)
 bytes.encode_float(77*4,1.0)
 for i in 3:bytes.encode_float((448+i)*4,lamp_energy)
 bytes.encode_float(451*4,0.3)
 bytes.encode_float(71*4,0.12)
 return bytes
func error(a:Image,b:Image)->float:
 var sum:=0.0
 for y in range(size.y/4,size.y*3/4):
  for x in range(size.x/4,size.x*3/4):
   var delta:=a.get_pixel(x,y)-b.get_pixel(x,y)
   sum+=delta.r*delta.r+delta.g*delta.g+delta.b*delta.b
 return sum/(size.x*size.y/4.0)
func energy(value:Image)->float:
 var sum:=0.0
 for y in size.y:
  for x in size.x:sum+=value.get_pixel(x,y).r
 return sum/(size.x*size.y)
func run()->void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
 DirAccess.make_dir_recursive_absolute(out)
 check(PathDevice.supported(),"qualified direct-light regression runtime")
 if not PathDevice.supported():finish();return
 camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 camera.size=3;camera.position=Vector3(0,1,0.001);camera.look_at(Vector3.ZERO);camera.current=true
 quad(mesh_data,[Vector3(-3,0,-3),Vector3(3,0,-3),Vector3(3,0,3),Vector3(-3,0,3)],Vector3.UP,Vector3.ZERO)
 geometries.append({"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(0.25,1,0.5)})
 placements.append({"geometry":0,"transform":Transform3D.IDENTITY,"mask":7})
 device=PathDevice.new()
 var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
 var images:Array[Image]=[white]
 Device.dispatch(device,&"build",[mesh_data.to_byte_array(),images,geometries,placements])
 check(await device.prepared,"build finite-area-light metal receiver")
 sun_energy=0;sky_energy=0;local_light=Vector4(0,1,0,5);lighting_limit=8
 var raw_previous:Image;var filtered_previous:Image
 var raw_error:=0.0;var filtered_error:=0.0
 var raw_energy:=0.0;var filtered_energy:=0.0
 for i in 40:
  Device.dispatch(device,&"render",[size,frame(i>0)])
  await frames(2);await RenderingServer.frame_post_draw
  RenderingServer.call_on_render_thread(read_raw);await readback
  var filtered:=device.shadow0.get_image()
  if i>=16:
   raw_error+=error(raw_direct,raw_previous);filtered_error+=error(filtered,filtered_previous)
   raw_energy+=energy(raw_direct);filtered_energy+=energy(filtered)
  raw_previous=raw_direct;filtered_previous=filtered
 check(device.nrd_active,"test exercises NRD direct-highlight resolve")
 check(raw_error>0.001,"finite lamp produces measurable one-sample glossy noise")
 check(filtered_error<raw_error*0.45,"published metal highlight rejects stochastic shimmer: %.6f / %.6f"%[filtered_error,raw_error])
 check(mean(device.shadow0).r>0.01,"filter retains illuminated metal")
 check(absf(filtered_energy/raw_energy-1.0)<0.1,"reconstruction preserves mean highlight energy within 10%%: %.4f"%(filtered_energy/raw_energy))
 lamp_energy=0
 Device.dispatch(device,&"render",[size,frame(false)])
 await frames(3);await RenderingServer.frame_post_draw
 check(mean(device.shadow0).r<0.001,"lighting reset removes the direct highlight without ghosting")
 # A finite sun and a roof above the camera create a noisy penumbra on a
 # diffuse receiver. This AOV is consumed separately by terrain and grass.
 quad(mesh_data,[Vector3(-0.4,2,-0.4),Vector3(0.4,2,-0.4),Vector3(0.4,2,0.4),Vector3(-0.4,2,0.4)],Vector3.DOWN,Vector3.ZERO)
 geometries.append({"offset":6,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
 placements.append({"geometry":1,"transform":Transform3D.IDENTITY,"mask":7})
 check(await build_fixture(),"build sun-shadow penumbra receiver")
 sun_energy=1.0;sun_direction=Vector3.UP
 var raw_sun_error:=0.0;var sun_error:=0.0
 for i in 40:
  Device.dispatch(device,&"render",[size,frame(i>0)])
  await frames(2);await RenderingServer.frame_post_draw
  RenderingServer.call_on_render_thread(read_raw);await readback
  var filtered:Image=device.direct_sun.get_image()
  if i>=16:
   raw_sun_error+=error(raw_sun,raw_previous);sun_error+=error(filtered,filtered_previous)
  raw_previous=raw_sun;filtered_previous=filtered
 check(raw_sun_error>0.001,"soft sun shadow has measurable raw sample noise")
 check(sun_error<raw_sun_error*0.45,"terrain sunlight rejects stochastic shadow shimmer: %.6f / %.6f"%[sun_error,raw_sun_error])
 check(sample(device.direct_sun,Vector3.ZERO).r<0.01 and sample(device.direct_sun,Vector3(1,0,0)).r>0.5,"filtered sunlight preserves the roof umbra and unoccluded light")
 # The same material remains available after target replacement.
 size=Vector2i(193,109)
 Device.dispatch(device,&"render",[size,frame(false)])
 await frames(3);await RenderingServer.frame_post_draw
 check(device.output_ready() and device.direct_sun.get_size()==Vector2(size),"odd-size target replacement publishes a complete sunlight image")
 Device.dispatch(device,&"dispose");await frames(8)
 check(device.output.get_width()==0 and device.direct_sun.get_width()==0,"direct and indirect outputs retire together")
 FileAccess.open(out.path_join("direct-stability.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"raw_error":raw_error,"filtered_error":filtered_error,"energy_ratio":filtered_energy/raw_energy,"raw_sun_error":raw_sun_error,"sun_error":sun_error},"\t"))
 print("PT_DIRECT_STABILITY ",checks," checks ",failures.size()," failures")
 get_tree().quit(1 if failures else 0)

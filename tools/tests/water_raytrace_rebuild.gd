extends "water_raytrace_live.gd"
## Exercise actual controller recentering with real scene collection and GPU
## builds. A replacement must not retire the sampled output before first draw.
func run() -> void:
 var context := await setup()
 Engine.max_fps=30
 GameData.options.gfx_water_reflections=3
 GameData.options.q_water_rt_quality=0
 t.apply_gfx()
 check(await ready_rt(),"initial water trace presents a complete reflection")
 var reflector:Node=t._reflection
 if not reflector._rt_ready:get_tree().quit(1);return
 # Move only the snapshot centre: retain this known water-facing camera so
 # the test cannot pass by disabling reflections after leaving the river.
 var previous:Object=reflector._rt
 var previous_output:Texture2D=previous.output
 var before:int=previous.completed_renders
 reflector._rt_center=camera.global_position+Vector3(17,0,0)
 reflector._update_raytrace(camera)
 check(reflector._rt==previous and not previous._closed,"recenter keeps the active device alive")
 check(t._water_mat.get_shader_parameter("planar_texture")==previous_output,"recenter keeps the complete RT output bound")
 var pending_seen:=false
 for i in 1800:
  await frames(1)
  if reflector._rt!=previous and reflector._rt_ready:break
  pending_seen=true
  if reflector._rt==null:break
 check(pending_seen and previous.completed_renders>before,"working reflection continues to render during replacement")
 check(reflector._rt!=null and reflector._rt!=previous and reflector._rt.output_ready(),"replacement promotes only after a successful first render")
 if reflector._rt==null:
  await finish_test(context)
  return
 if reflector._rt!=null:
  check(reflector._rt.incremental_build,"replacement builds textures and visible BLAS incrementally")
  check(reflector._rt.programs!=null and reflector._rt.programs==previous.programs,"replacement reuses compiled ray programs")
 check(t._water_mat.get_shader_parameter("planar_texture")==reflector._rt.output,"water samples the promoted output")
 await frames(8)
 check(previous._closed,"old GPU resources retire after replacement")
 var active:Object=reflector._rt
 # A quality-only settings change reuses the scene. Its preparation cover
 # still needs an acknowledgement from this active device, not a candidate.
 reflector._begin_preparation()
 for i in 60:
  await frames(1)
  if not reflector._preparing:break
 check(not reflector._preparing,"quality-only preparation releases its input/loading cover")
 check(reflector._rt==active and active.output_ready(),"quality-only preparation retains the active scene")
 reflector._finish_preparation()
 reflector._raytrace_prepared(false,active.get_instance_id())
 check(not reflector._rt_ready and reflector._rt_failed,"failure after promotion retires the active device")
 check(t._water_mat.get_shader_parameter("planar_texture")==reflector.viewport.get_texture(),"late device failure restores a complete planar fallback")
 await finish_test(context)
func finish_test(context:Array)->void:
 context[1].queue_free();context[0].queue_free();await frames(12)
 print("WATER_RT_REBUILD ",checks," checks ",failures.size()," failures")
 TexUpscale.shutdown();get_tree().quit(1 if failures else 0)

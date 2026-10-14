extends Node
## Real travel map and edition strings at small and desktop layouts.
var checks:=0
var failures:=0
var selected:={}
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func frames(n:=8)->void:
 for i in n:await get_tree().process_frame
func _ready()->void:run.call_deferred()
func run()->void:
 GameData.options.merge({"auto_graphics":0,"display_mode":0,"confine_mouse":0,"net_lan":0,"net_directory":0,"net_upnp":0,"show_tutorial":0},true)
 GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED
 var s:=Session.new();add_child(s);s.zone_id="bz14h"
 for id in ["bz1g","bz8k","bz14h"]:
  s.state.visited[id]=true;s.state.zones[id]={"vm":{"instances":[]}}
 var opts:=s.island_return_options("gz17h_bz14h")
 check(opts.size()==2,"both previously visited islands are offered")
 for shape:Vector2i in [Vector2i(800,600),Vector2i(1280,720)]:
  var surface:=SubViewport.new();surface.size=shape;surface.render_target_update_mode=SubViewport.UPDATE_ALWAYS
  add_child(surface)
  var map:=TravelMap.new();map.setup(s,opts,true,"gz17h_bz14h");surface.add_child(map)
  map.picked.connect(func(o):selected=o)
  await frames()
  var buttons:=map._extra.find_children("*","Button",true,false)
  check(buttons.size()==3,"two island buttons and Stay here are visible")
  for i in 2:
   var b:Button=buttons[i]
   var title:=GameData.text("allod "+str(opts[i].return_allod)).get_slice("\n",0).strip_edges()
   check(not title.is_empty() and b.text==RemakeText.t("Return to %s")%title,"button uses localized island name "+RemakeText.lang)
   check(b.text.find("bz")==-1 and b.text.find("gz")==-1,"no internal destination ID in label")
   check(Rect2(Vector2.ZERO,Vector2(shape)).encloses(b.get_global_rect()) and b.size.x>=b.get_minimum_size().x,"button fits "+str(shape))
   check(map.pad_targets().any(func(t):return t.rect.has_point(b.get_global_rect().get_center())),"island button has a gamepad target")
   b.pressed.emit();check(selected==opts[i],"island button selects the advertised route")
  if DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   check(surface.get_texture().get_image().save_png("user://island-return-%s-%d.png"%[RemakeText.lang,shape.x])==OK,"capture localized island map")
  surface.queue_free();await frames()
 s.queue_free();await frames();TexUpscale.shutdown()
 print("ISLAND_RETURN_UI ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)

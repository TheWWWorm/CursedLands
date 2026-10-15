extends Node
## Real shop and inventory rendering, eight-rune spells, stacked quantities,
## prices, constructor slots and HUD icons at two interface sizes.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func frames(n:=5)->void:
 for i in n:await get_tree().process_frame
func _ready()->void: _run.call_deferred()
func _run()->void:
 GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0},true)
 GameData.options.merge(GfxPresets.values(GfxPresets.LOW),true)
 get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
 var s:=Session.new();add_child(s)
 var g:=Game.new();g.session=s;s.game=g;add_child(g)
 s.state.ensure_hero(0,s._hero_proto(0));await s.enter_zone("bz21k" if GameData.campaign_id==CampaignProfile.ASTRAL else "bz8k",1,false)
 s.set_physics_process(false);s.world.set_physics_process(false);s.world.set_process(false)
 s.world.vm.briefings._check=INF;g.hud._dialog.hide()
 var spells:=["spell:lightning{e1;e1;m1;m1;m1;m1;m1;m1}","spell:inv_lit{m1;m1;m1;m1;m1;m1;m1;m1}","spell:healing{e1;e1;m1;m1;m1}","spell:strength{d1;d1;d1;m1;m1}"]
 s.state.items=[];s.state.money=10000000;s.state.shops[3]={"restock":false,"goods":{},"sold":{}}
 for i in spells.size():
  s.state.shops[3].goods[spells[i]]=[1,2,123,9][i]
  for j in [1,2,12,9][i]:s.state.items.append(spells[i])
 var panel:InventoryPanel=g.hud._inventory;panel.open(true,3)
 var camp:CampView=panel._camp;camp.set_mode("spelltrade")
 var archives:={RemakeText.lang:GameData.texts}
 for arg:String in OS.get_cmdline_user_args():
  for language:String in ["en","ru","de"]:
   if arg.begins_with("--"+language+"-texts="):archives[language]=EIResArchive.open_path(arg.get_slice("=",1))
 for language:String in archives:
  GameData.texts=archives[language];EIText.code_page=EIText.detect_code_page(GameData.texts);RemakeText.lang=RemakeText.detect(GameData.texts);GameData._text_cache.clear()
  check(RemakeText.lang==language,"correct text archive "+language)
  for resolution:Vector2i in [Vector2i(800,600),Vector2i(1600,900)]:
   get_window().content_scale_size=resolution;await frames()
   camp._sig="";camp._process(0.0);await frames()
   for key:String in ["shop0","bag0","buy0","sell0"]:
    for count:int in [1,2,12,123,9999]:
     var rect:=camp._spell_picture_rect(key,count)
     var slot:=camp._slot_rect(key)
     var price:=camp._r(Rect2(slot.position+Vector2(15,65),Vector2(70,20)))
     var width:=Interface800.font().get_string_size(str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,camp._fpx(1)).x
     var quantity:=camp._r(Rect2(slot.position+Vector2(85,15),Vector2(0,20)));quantity.position.x-=width;quantity.size.x=width+2
     check(not rect.intersects(price),"card clears price "+key+" "+str(count))
     check(count==1 or not rect.intersects(quantity),"card clears quantity "+key+" "+str(count))
     var cells:=SpellSlots.rune_rects(rect)
     check(cells.size()==8 and cells.all(func(cell:Rect2):return rect.encloses(cell) and not cell.intersects(price)),"all eight runes stay above price")
     check(not cells.any(func(cell:Rect2):return cell.has_point(rect.get_center())),"spell centre remains visible")
   var hud_cells:=SpellSlots.rune_rects(Rect2(0,0,40,40))
   check(hud_cells.size()==8 and hud_cells.all(func(cell:Rect2):return Rect2(0,0,40,40).encloses(cell)),"HUD rune bounds")
   check(camp._spell_picture_rect("sready",1)==camp._r(camp._slot_rect("sready").grow(-10.0)),"constructor keeps full icon")
   check(camp._content.values().any(func(row):return row[0]==spells[0]),"actual shop shows eight-rune spell")
   if DisplayServer.get_name()!="headless":
    await RenderingServer.frame_post_draw
    check(get_viewport().get_texture().get_image().save_png("user://runes-"+language+"-"+str(resolution.x)+".png")==OK,"capture real shop")
 print("SPELL_RUNE_LAYOUT ",checks," checks ",failures," failures")
 FileAccess.open("user://spell-rune-layout.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"languages":archives.keys()},"  "))
 g.queue_free();s.queue_free();await frames(2);get_tree().quit(1 if failures else 0)

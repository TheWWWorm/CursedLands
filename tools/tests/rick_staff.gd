extends Node
## The Great Mage's authored staff is attached to his animated right hand.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
 var campaign:=CampaignMap.load_from(GameData.texts)
 var z:=campaign.zone("bz14g")
 var mob:=EIMob.load_bytes(GameData.read_file("maps/"+String(z.get("mob",z.mpr))+".mob"))
 var rec:Dictionary={}
 for o:Dictionary in mob.objects:
  if o.get("template","")=="unmori":rec=o;break
 check(not rec.is_empty(),"authored Great Mage record exists")
 if rec.is_empty():get_tree().quit(1);return
 for preview:bool in [false,true]:
  var model:=EIUnitModel.create(rec,preview);add_child(model)
  var staff:=model.find_child("rh3_staff00",true,false) as Node3D
  check(staff!=null,"staff exists in world and preview")
  if staff:
   check(staff.get_parent().name=="rh3","staff retains authored hand parent")
   var meshes:=staff.find_children("*","MeshInstance3D",true,false)
   check(meshes.size()==1 and meshes[0].mesh.get_surface_count()>0,"staff has visible original geometry")
   for clip:String in ["idle","cast","walk"]:
    model.act(clip,1,0.0);model.player.advance(0.2);model.flush_pending_pose()
    check(staff.global_transform.is_finite() and staff.is_visible_in_tree(),"staff follows "+clip)
  model.free()
 var restricted:=rec.duplicate(true);restricted.parts=PackedStringArray(["hp","bd","rh3"])
 var model:=EIUnitModel.create(restricted);add_child(model)
 check(model.find_child("rh3_staff00",true,false)==null,"explicit map part selection still hides staff")
 model.free()
 print("RICK_STAFF ",checks," checks ",failures," failures")
 get_tree().quit(1 if failures else 0)

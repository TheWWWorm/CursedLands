extends Node
var s:Session
var g:Game
var checks:=0
var failures:=0
var cfg:={"save":"","output":""}
func _ready()->void:
 process_mode=Node.PROCESS_MODE_ALWAYS
 run.call_deferred()
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func run()->void:
 for arg:String in OS.get_cmdline_user_args():
  for key:String in cfg:
   if arg.begins_with("--"+key+"="):cfg[key]=arg.trim_prefix("--"+key+"=")
 GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
 if not FileAccess.file_exists(cfg.save) or not FileAccess.file_exists(cfg.save+".expected.json"):
  printerr("FAIL missing input/expected state");get_tree().quit(1);return
 DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
 FileAccess.open(SaveInfo.path("roundtrip"),FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(cfg.save))
 s=Session.new();get_parent().add_child(s);g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
 check(await s.local_host.start(0,Session.MAX_PLAYERS,true)==OK,"local worker started")
 if failures:await s.local_host.stop();get_tree().quit(1);return
 check(await s.load_game_shown("roundtrip"),"supplied state loads through frontend and worker")
 if failures:await s.local_host.stop();get_tree().quit(1);return
 check(s.local_host.frontend,"real simulation worker is running")
 var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(cfg.save+".expected.json"))
 await get_tree().create_timer(3.0,true,false,true).timeout
 for nid:String in expected:
  var u:GameUnit=s.world.units.get(int(nid))
  check(u==null if expected[nid]=="looted" else u!=null and u.dead,"frontend preserves dead/looted actor "+nid)
 if not cfg.output.is_empty():
  var answer:Dictionary=await s.local_host.request("save",{"slot":"worker-result","name":"Persistence regression","camera":s.local_host.view()})
  check(bool(answer.get("ok",false)),"worker acknowledges save")
  var saved:=CampaignState.load_from(SaveInfo.path("worker-result"))
  check(saved!=null,"worker checkpoint can be decoded")
  if saved:
   var zone:Dictionary=saved.zones[saved.current_zone]
   for nid:String in expected:
    check(int(nid) in zone.get("looted",[]) if expected[nid]=="looted" else int(nid) in zone.get("dead",[]),"worker snapshot keeps tombstone "+nid)
   FileAccess.open(cfg.output,FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(SaveInfo.path("worker-result")))
   FileAccess.open(cfg.output+".expected.json",FileAccess.WRITE).store_string(JSON.stringify(expected))
 await s.local_host.stop()
 FileAccess.open("user://worker-persistence.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
 print("WORKER_PERSISTENCE ",checks," checks ",failures," failures")
 get_tree().quit(1 if failures else 0)

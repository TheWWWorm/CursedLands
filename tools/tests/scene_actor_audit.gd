extends Node
## Audit every base/side-quest/AddMob record against the actual figure loader.
const Visibility=preload("res://src/game/script/scene_visibility.gd")
const P=preload("res://src/game/script/script_parser.gd")
var files:={}
var failures:=[]
var templates:={}
var count:=0
var spawn_sites:=0
var visibility:=[]
var cut_maps:=[]
func scan(v:Variant)->void:
 if not v is Array:return
 if v.size()==3 and v[0] is int and v[0]==P.S_CALL and v[1]=="AddMob":
  spawn_sites+=1
  if v[2].size()==1 and v[2][0][0]==P.N_STR:
   var file:=String(v[2][0][1]).to_lower()
   if not files.has(file):files[file]=false
  else:failures.append("Nonliteral AddMob requires review: "+str(v))
 for part in v:scan(part)
func _ready()->void:
 var map:=CampaignMap.load_from(GameData.texts)
 for z:Dictionary in map.zones.values():
  if not z.has("mpr"):continue
  if not GameFiles.exists(GameData.root.path_join("maps/"+str(z.mpr)+".mpr")):
   cut_maps.append(z.id);continue
  files[str(z.get("mob",z.mpr))+".mob"]=false
 for q:Dictionary in SideQuests.all():files[str(q.id)+".mob"]=false
 while files.values().has(false):
  for file:String in files.keys():
   if files[file]:continue
   files[file]=true
   var bytes:=GameData.read_file("maps/"+file)
   if bytes.is_empty():failures.append("Missing authored mob "+file);continue
   var mob:=EIMob.load_bytes(bytes)
   var ast:=ScriptParser.parse(mob.script_text)
   if not ast.errors.is_empty():failures.append({"file":file,"parse":ast.errors})
   for rule:Dictionary in Visibility.rules(ast):visibility.append({"file":file,"root":rule.call[1],"family":rule.names.keys()})
   scan(ast.world)
   for script:Dictionary in ast.scripts.values():
    for block:Dictionary in script.blocks:scan(block.body)
   for raw:Dictionary in mob.objects:
    if raw.kind!="UNIT":continue
    count+=1
    var rec:=CampaignState.map_unit_record(raw)
    var proto:=GameData.db.find("monster_prototypes",rec.get("prototype",rec.get("parent_template","")))
    var race:=GameData.db.find("race_models",proto.get("base_race",""))
    var tmpl:=str(rec.get("template",""))
    if tmpl.is_empty():tmpl=str(race.get("mask","")).to_lower()
    if not templates.has(tmpl):templates[tmpl]=not EIFigure.get_model(tmpl).is_empty()
    if not templates[tmpl]:failures.append({"file":file,"actor":rec.get("name",""),"prototype":rec.get("prototype",""),"template":tmpl})
 var report:={"mob_files":files.size(),"unshipped_maps":cut_maps,"unit_records":count,"figure_templates":templates.size(),"add_mob_sites":spawn_sites,"visibility":visibility,"failures":failures}
 FileAccess.open("user://scene-actor-audit.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("SCENE_ACTOR_AUDIT ",JSON.stringify(report));TexUpscale.shutdown();get_tree().quit(1 if not failures.is_empty() else 0)

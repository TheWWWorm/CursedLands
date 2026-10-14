extends Node
## Recovery recognizes a declarative subset, never rewards or waiting scripts.
const V=preload("res://src/game/script/scene_visibility.gd")
var checks:=0
var failures:=0
const TREE='''GlobalVars(actor:object)
DeclareScript Gate(this:object)
DeclareScript Show(this:object)
DeclareScript Hide(this:object)
Script Gate(
 if(IsEqual(GSGetVar(0,"quest"),2))then(KillScript() Show(actor))
 if()then(KillScript() Hide(actor)))
Script Show(if()then(KillScript() HideObject(this,0)))
Script Hide(if()then(KillScript() HideObject(this,1)))
WorldScript(Gate(NULL))'''
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _ready()->void:
 check(V.rules(ScriptParser.parse(TREE)).size()==1,"recognizes parameterized gate without actor/map names")
 for pair:Array in [
  ['HideObject(this,0)','HideObject(this,0) GiveMoney(0,50)'],
  ['HideObject(this,0)','HideObject(this,0) GSSetVar(0,"reward",2)'],
  ['HideObject(this,0)','AddMob("zone.mob")'],
  ['HideObject(this,0)','RemoveObject(this)'],
  ['HideObject(this,0)','Sleep(2) HideObject(this,0)'],
  ['HideObject(this,0)','Gate(this)'],
  ['HideObject(this,0)','HideObject(this,Random(0,1))'],
  ['if()then(KillScript() Hide(actor))',''],
  ['Gate(NULL)','Gate()'],
  ['GSGetVar(0,"quest")','GiveMoney(0,50)'],
  ['KillScript() Show(actor)','Show(actor)'],
  ['Show(actor)','Show(actor,actor)']]:
  check(V.rules(ScriptParser.parse(TREE.replace(pair[0],pair[1]))).is_empty(),"excludes side effects / incomplete tree: "+pair[1])
 var bad:=ScriptParser.parse(TREE);bad.errors.append("incomplete parse")
 check(V.rules(bad).is_empty(),"rejects a partially parsed script")
 print("SCENE_VISIBILITY_GUARDS ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)

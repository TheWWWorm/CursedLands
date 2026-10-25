extends Node
class Report extends CrashReportBox:
 var actions:=[]
 var closed:=false
 func act(i:int)->void:actions.append(i)
 func _answer(_yes:bool)->void:closed=true
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func motion(box:Report,p:Vector2)->void:
 var e:=InputEventMouseMotion.new();e.position=box.p8(p);box._gui_input(e)
func key(box:Report,k:Key)->void:
 var e:=InputEventKey.new();e.keycode=k;e.pressed=true;box._unhandled_key_input(e)
func _ready()->void:
 get_window().size=Vector2i(1600,900)
 for language in ["en","ru","de"]:
  RemakeText.lang=language
  var box:=Report.new();box.ok_only=true
  box.title=RemakeText.t("The game closed unexpectedly last time.")
  box.message=RemakeText.t("A report with the log of that session helps to find the cause. Save it or copy it, to send it with a bug report.")
  box._status=RemakeText.t("Report saved:")+" C:/Users/player/Downloads/CursedLands-report-20261025-100630.txt"
  add_child(box)
  await get_tree().process_frame
  var r:=box._rects()
  motion(box,r.rows[1].get_center())
  check(box._sel==1,language+" hovered copy row is highlighted")
  motion(box,r.ok.get_center())
  check(box._sel==-1,language+" moving to Accept clears the old row highlight")
  key(box,KEY_ENTER)
  check(box.closed and box.actions.is_empty(),language+" Enter at Accept closes without copying a report")
  box.closed=false
  key(box,KEY_UP)
  check(box._sel==1,language+" keyboard returns from Accept to final report action")
  key(box,KEY_ENTER)
  check(box.actions==[1],language+" keyboard activates the visibly selected action")
  key(box,KEY_DOWN)
  check(box._sel==-1,language+" keyboard can reach Accept after the final action")
  var targets:=box.pad_targets()
  for i in targets.size():
   # PadUI navigates the same hit rectangles using synthetic mouse motion.
   motion(box,box.to800(targets[i].rect.get_center()))
   check(box._sel==(i if i<2 else -1),language+" controller focus follows target "+str(i))
  check(r.top>=0 and r.ok.end.y<=600,language+" translated report and saved path fit vertically")
  for text:String in [box.title,box.message,RemakeText.t("Save report"),RemakeText.t("Copy to clipboard")]:
   for line:String in box.wrap_text(text,370,2):check(box.text_width(line,2)<=371,language+" translated text fits")
  if DisplayServer.get_name()!="headless":
   motion(box,r.ok.get_center())
   await RenderingServer.frame_post_draw
   get_viewport().get_texture().get_image().save_png("user://report-hover-"+language+".png")
  box.free()
 print("CRASH_REPORT_HOVER ",checks," checks ",failures," failures")
 get_tree().quit(1 if failures else 0)

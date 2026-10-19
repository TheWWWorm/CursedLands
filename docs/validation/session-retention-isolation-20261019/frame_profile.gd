extends RefCounted
static var enabled:=false
static var sums:={}
static var counts:={}
class Scope extends RefCounted:
 var key:String
 var start:int
 var finish:Callable
 func _init(k:String,fn:Callable)->void:key=k;start=Time.get_ticks_usec();finish=fn
 func _notification(what:int)->void:
  if what==NOTIFICATION_PREDELETE:
   var elapsed:=Time.get_ticks_usec()-start
   finish.call(key,elapsed)
static func record(key:String,elapsed:int)->void:
 sums[key]=int(sums.get(key,0))+elapsed
 counts[key]=int(counts.get(key,0))+1
static func begin(key:String)->RefCounted:
 return Scope.new(key,record) if enabled else null
static func take()->Dictionary:
 var row:={"us":sums.duplicate(),"calls":counts.duplicate()}
 sums.clear();counts.clear();return row

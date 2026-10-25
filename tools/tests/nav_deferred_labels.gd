extends Node
class Measured extends NavGrid:
	var floods:=0
	func _label(l:Layer)->void:floods+=1;super._label(l)
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
	for scalar in [false,true]:
		var nav:=Measured.new();nav.size=Vector2i(16,16)
		if scalar:nav._build_kernel_checked=true;nav._build_kernel=null
		var layer:=NavGrid.Layer.new();layer.label_owner=weakref(nav);layer.land.resize(256)
		layer.labels_dirty=true
		check(nav.floods==0,"invalidating defers the whole-map label pass")
		var open:=layer.comp
		check(nav.floods==1 and not layer.labels_dirty and open[1]==open[14],"first comparison query labels the connected map")
		var again:=layer.comp
		check(again==open and nav.floods==1,"unchanged comparison query reuses labels")
		for y in 16:layer.land[y*16+8]=1
		layer.labels_dirty=true
		check(nav.floods==1,"map edit does not eagerly flood")
		var closed:=layer.comp
		check(nav.floods==2 and closed[1]!=closed[14] and closed[8]==0,"first query after closing separates components")
		layer.land[8*16+8]=0;layer.labels_dirty=true
		var joined:=layer.comp
		check(nav.floods==3 and joined[1]==joined[14],"opening a gap reconnects components on demand")
	print("NAV_DEFERRED_LABELS ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)

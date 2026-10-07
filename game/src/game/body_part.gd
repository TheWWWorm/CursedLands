class_name UnitBodyPart
extends RefCounted
## Live body records are typed. A shared, owner-free revision token lets the
## unit reuse derived health until an actual part changes. Saves and network
## snapshots still serialize the same numeric fields as before.
class Revision extends RefCounted:
	var value := 0

var revision: Revision
var type := -1:
	set(v):
		if type != v:
			type = v
			if revision: revision.value += 1
var size := 0.0
var sever := 0
var lethal := 0.0:
	set(v):
		if lethal != v:
			lethal = v
			if revision: revision.value += 1
var cur := 0.0:
	set(v):
		if cur != v:
			cur = v
			if revision: revision.value += 1
var max := 0.0:
	set(v):
		if max != v:
			max = v
			if revision: revision.value += 1
var state := 0:
	set(v):
		if state != v:
			state = v
			if revision: revision.value += 1

static func from_record(d: Dictionary, token: Revision) -> UnitBodyPart:
	var p := UnitBodyPart.new()
	p.type = int(d.get("type",-1))
	p.size = float(d.get("size",0.0))
	p.sever = int(d.get("sever",0))
	p.lethal = float(d.get("lethal",0.0))
	p.cur = float(d.get("cur",0.0))
	p.max = float(d.get("max",0.0))
	p.state = int(d.get("state",0))
	p.revision = token
	return p

func record() -> Dictionary:
	return {"type":type,"size":size,"sever":sever,"lethal":lethal,"cur":cur,"max":max,"state":state}

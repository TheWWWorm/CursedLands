extends Node
## Equal 54-gold, six-slot two-star formations. Hand-authored counter checks,
## not a search for optimal teams; all native traits and targeting remain active.
const Duel=preload("arena_roster_matchups.gd").Duel
const TEAMS := {
	"casters":[6,11,13,18,19,20],
	"screened_casters":[0,28,29,18,19,20],
	"mixed":[6,9,11,14,23,27],
	"assault":[6,9,7,14,24,27],
}
var rows := []
func army(run: ArenaRun, name: String) -> void:
	run.army.clear(); run.training=36
	var front:=0; var back:=0
	for family: int in TEAMS[name]:
		var entry:=run._recruit(family,1,ArenaRules.FAMILIES[family].cost*3)
		var ranged:=ArenaRules.recruit_role(family,1)!="Melee"
		var number:=back if ranged else front
		entry.deployed=true; entry.point=[22.0 if ranged else 27.0,32.0+[0.0,-4.0,4.0,-8.0,8.0,12.0][number]]
		if ranged:back+=1
		else:front+=1
func _ready() -> void:
	var native:=hash(GameData.db.tables)
	for name in TEAMS:
		assert(TEAMS[name].reduce(func(total,f):return total+ArenaRules.FAMILIES[f].cost*3,0)==54)
	var names:=TEAMS.keys()
	for ai in names.size():
		for bi in range(ai+1,names.size()):
			var a:String=names[ai]; var b:String=names[bi]
			for seed_value in [8519,10777]:
				for side in 2:
					var run:=Duel.new(); run.auto_save=false; run.begin(seed_value)
					var other:=ArenaRun.new(); other.auto_save=false; other.begin(seed_value)
					army(run,a if side==0 else b); army(other,b if side==0 else a); run.opposing=other.army
					var battle:=ArenaPveMatch.new(); battle.run=run; battle.rendered=false; battle.drives_clock=false
					add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent=self
					battle.prepare(); battle.start()
					for tick in 1700:
						if battle.phase!=ArenaMatch.Phase.FIGHT: break
						battle.simulate_tick()
					assert(battle.phase==ArenaMatch.Phase.FINISHED)
					var row:={"a":a,"b":b,"seed":seed_value,"side":side,"winner":"draw" if battle.winner<0 else a if battle.winner==side else b,"seconds":battle.world.time,"reason":battle.end_reason}
					rows.append(row); print("COMPOSITION ",JSON.stringify(row))
					FileAccess.open("user://arena-composition-balance.json",FileAccess.WRITE).store_string(JSON.stringify({"teams":TEAMS,"rank":1,"purchase_cost":54,"rows":rows},"\t"))
					battle.queue_free(); await get_tree().process_frame
	get_tree().quit(0 if hash(GameData.db.tables)==native and rows.size()==24 else 1)

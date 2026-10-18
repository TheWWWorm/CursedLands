extends Node
## Paired sides on the actual Trials terrain, native spells, armor and AI.
## One-creature duels expose outliers; full-run policies cover the economy.
class Duel extends ArenaRun:
	var opposing: Array[Dictionary] = []
	func enemy_army() -> Array[Dictionary]: return opposing
	func enemy_formation() -> Array[Dictionary]: return ArenaTournamentRun.formation_for(opposing, 1)
	func resolve(_winner: int, _seconds: float, _damage: Array, _survivors: Array = [0,0]) -> void: stage="result"
var rows := []
func _ready() -> void:
	var native := hash(GameData.db.tables)
	var level := 0
	var only := -1
	var first := 12
	var opponent_first := 0
	var opponent_count := 12
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--family="): only=int(arg.get_slice("=",1))
		if arg.begins_with("--from="): first=int(arg.get_slice("=",1))
		if arg.begins_with("--rank="): level=int(arg.get_slice("=",1))
		if arg.begins_with("--opponent-from="): opponent_first=int(arg.get_slice("=",1))
		if arg.begins_with("--opponents="): opponent_count=mini(ArenaRules.FAMILIES.size(),int(arg.get_slice("=",1)))
	for candidate in range(first,ArenaRules.FAMILIES.size()):
		if only>=0 and candidate!=only:continue
		var row := {"family":candidate,"name":ArenaRules.FAMILIES[candidate].name,"rank":level,"opponents":[]}
		for baseline in range(opponent_first,opponent_count):
			var wins:=0; var draws:=0; var seconds:=0.0
			for side in 2:
				var run:=Duel.new();run.auto_save=false;run.begin(8519+baseline)
				var rival:=ArenaRun.new();rival.auto_save=false;rival.begin(8519+baseline)
				run.army.clear();rival.army.clear()
				run._recruit(candidate if side==0 else baseline,level,1)
				rival._recruit(baseline if side==0 else candidate,level,1)
				for company in [run,rival]:
					company.army[0].deployed=true;company.army[0].point=[27.0,32.0]
				run.opposing=rival.army
				var battle:=ArenaPveMatch.new();battle.rendered=false;battle.drives_clock=false;battle.run=run
				add_child(battle);battle.set_process(false);battle.set_physics_process(false);battle._world_parent=self
				battle.prepare();battle.start()
				for tick in 2200:
					if battle.phase!=ArenaMatch.Phase.FIGHT:break
					battle.simulate_tick()
				if only>=0 and baseline==0:
					for u in battle.world.unit_rows():print("DUEL_UNIT ",u.info.prototype," hp=",u.hp," mana=",u.mana," pos=",u.pos," action=",u.action," target=",u.target," spells=",u.proto.spells," damage=",battle.damage)
				if battle.winner==side:wins+=1
				if battle.winner<0:draws+=1
				seconds+=battle.world.time
				if battle.phase!=ArenaMatch.Phase.FINISHED:printerr("FAIL unfinished duel");get_tree().quit(1);return
				battle.queue_free();await get_tree().process_frame
			row.opponents.append({"family":baseline,"wins":wins,"draws":draws,"seconds":seconds/2})
		rows.append(row); print("ROSTER_MATCHUP ",JSON.stringify(row))
		var file:=FileAccess.open("user://roster-matchups-%d.json"%level,FileAccess.WRITE);file.store_string(JSON.stringify(rows,"\t"));file.close()
	get_tree().quit(0 if hash(GameData.db.tables)==native else 1)

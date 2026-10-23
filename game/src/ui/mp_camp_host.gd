class_name MpCampHost
extends Session
## The network character screen's View: the original opens its camp screen
## on the selected character, which dresses it from its bag (Equipment) and
## spends its experience (Skills/Spells). CampView works on a session, a hero
## unit and the party bag; this stands in for them outside any game. It never
## enters the tree (no network, no zone, no script VM). The camp's commands
## change the record at once, as the host of a single-player camp does, and
## the screen writes the record back when it closes.

var unit: GameUnit
var record: Dictionary


func _init(data: Dictionary) -> void:
	record = data
	var h := MpCharacter.hero_of(data)
	state = CampaignState.new()
	state.heroes = {0: [h]}
	state.money = int(data.get("money", 0))
	if not data.get("items") is Array:
		data["items"] = []
	state.items = data["items"]   # the same array: the bag is the record's
	world = GameWorld.new()
	unit = GameUnit.new()
	if not unit.setup(world, {"nid": 1, "player": 0, "prototype": h.prototype, "complexion": h.complexion,
			"armors": PackedStringArray(h.get("armors", [])), "weapons": PackedStringArray(h.get("weapons", []))}):
		push_warning("MpCampHost: no unit for " + String(h.prototype))
	unit.controller = 0
	unit.display_name = String(h.get("name", ""))
	unit.set_meta("hero", h)
	Combat.hero_stats(unit, h)
	world.set_unit(unit.uid, unit)
	game = Game.new()
	game.session = self
	game.world = world
	game.hud = GameHUD.new()
	game.hud.game = game


## The camp screen is always open here (CampView, Session.apply_command).
func camp_available() -> bool:
	return true


func party_units(player: int) -> Array:
	return [unit] if player == 0 else []


## A camp command from CampView.construct, applied here at once.
func camp_command(cmd: Dictionary) -> void:
	apply_command(cmd, 0)
	record.money = state.money


# Nothing to send or save: there is no game behind this screen.
func broadcast(_event: Dictionary) -> void:
	pass


func sync_state() -> void:
	pass


func _sync_menu_state() -> void:
	pass


func mark_dirty() -> void:
	pass


## Frees the stand-ins (none of them is in the tree).
func dispose() -> void:
	for n: Node in [game.hud, game, unit, world]:
		if is_instance_valid(n):
			n.free()
	free.call_deferred()

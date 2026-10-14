extends Node
## Shared rewards must change each distinct purse once and report only what
## that recipient received. Transport is suppressed; grant/routing code is real.
class QuietSession extends Session:
	var events: Array = []
	func sync_state() -> void: pass
	func broadcast(event: Dictionary) -> void: events.append(event.duplicate(true))

var checks := 0
var failures := 0
var session: QuietSession
var guest: Dictionary
const MATERIAL := "material.thick"
const QUEST := "driadidol00"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func notices(player: int) -> Array:
	return session.events.filter(func(event):
		return event.t == "got" and int(event.to) in [-1, player] \
			or event.t == "loot_copy" and int(event.to) == player)

func script_grant(items: Array, money := 0) -> void:
	for item: String in items: session.give_item(-1, item)
	if money:
		session.coop.with_purse(-1, func(): session.state.money += money, true)
	session.notify_got(-1, items, money)

func _ready() -> void:
	GameData.options.coop_share_loot = 1
	session = QuietSession.new()
	session.online = true
	session.state = CampaignState.new()
	session.coop = CoopProgress.new()
	session.coop.session = session
	session.players = {1:{"index":0,"name":"Host"},2:{"index":1,"name":"Private guest"},3:{"index":2,"name":"Class guest"}}
	guest = {"idx":1,"purse":{"money":0,"items":[]}}
	session.coop.joiners.guest = guest
	check(Items.kind(MATERIAL) == "material" and Items.kind(QUEST) == "quest", "real material and shared quest-item fixtures")
	for speed in [1.0, 2.0]:
		Engine.time_scale = speed
		session.events.clear()
		var host_before := session.state.items.count(MATERIAL)
		var guest_before: int = guest.purse.items.count(MATERIAL)
		session.give_item(-1, MATERIAL, 3)
		session.notify_got(-1, [MATERIAL, MATERIAL, MATERIAL])
		check(session.state.items.count(MATERIAL) == host_before + 3 and guest.purse.items.count(MATERIAL) == guest_before + 3, "scripted resource stack reaches each distinct bag once at %sx" % speed)
		check(notices(1).size() == 1 and notices(1)[0].t == "loot_copy", "private guest sees one resource grant at %sx" % speed)
		check(notices(0).size() == 1 and notices(2).size() == 1, "host and class guest each hear the shared-bag pickup at %sx" % speed)
	session.events.clear()
	script_grant([], 37)
	check(session.state.money == 37 and guest.purse.money == 37, "scripted money copied once per purse")
	check(notices(1).size() == 1 and notices(1)[0].money == 37, "private guest sees one money grant")
	session.events.clear()
	script_grant([QUEST, MATERIAL], 12)
	check(session.state.quest_items.has(QUEST) and not guest.purse.items.has(QUEST), "quest item remains in the shared story list")
	var quest_notice := notices(1).filter(func(e): return e.t == "got")
	check(quest_notice.size() == 1 and quest_notice[0].items == [QUEST] and quest_notice[0].money == 0, "mixed reward reports only the shared quest item in the guest pickup line")
	check(notices(1).filter(func(e): return e.t == "loot_copy").size() == 2, "mixed reward separately reports its material and money copies")
	var before := session.state.items.count(MATERIAL)
	session.coop.with_purse(1, func(): session.state.add_item(MATERIAL, 2), true)
	check(session.state.items.count(MATERIAL) == before + 2 and guest.purse.items.count(MATERIAL) == before + 2, "private guest pickup grants one stack per bag")
	before = session.state.items.count(MATERIAL)
	session.coop.with_purse(2, func(): session.state.add_item(MATERIAL, 2), true)
	check(session.state.items.count(MATERIAL) == before + 2 and guest.purse.items.count(MATERIAL) == before + 2, "class guest does not multiply the host's shared inventory")
	GameData.options.coop_share_loot = 0
	session.events.clear()
	script_grant([MATERIAL], 9)
	check(notices(1).is_empty(), "sharing disabled never tells a private guest they received campaign resources")
	check(notices(0).size() == 1 and notices(2).size() == 1, "sharing disabled still reports the campaign-bag reward")
	session.events.clear()
	script_grant([QUEST])
	check(notices(1).size() == 1, "sharing disabled still reports shared quest items")
	session.events.clear()
	session.notify_got(1, [MATERIAL], 7)
	check(notices(1).size() == 1 and notices(0).is_empty(), "direct pickup stays addressed to its finder")
	session.events.clear()
	session.notify_got(1, [MATERIAL], 0, true)
	check(notices(1).size() == 1 and notices(1)[0].broken, "broken-item message retains its owner and flag")
	session.events.clear()
	session.notify_got(-1, [])
	check(session.events.is_empty(), "empty grants produce no pickup messages")
	session.online = false
	session.notify_got(-1, [MATERIAL], 5)
	check(session.events.size() == 1 and session.events[0].to == -1, "single-player grant retains original broadcast")
	session.events.clear(); session.online = true; session.lmp = {"base":"bz1mpg"}
	session.notify_got(1, [MATERIAL], 5)
	check(notices(1).size() == 1 and notices(0).is_empty(), "native multiplayer grant retains its explicit owner")
	session.lmp = {}; GameData.options.coop_share_loot = 1
	session.state.items.clear(); session.state.money = 0
	guest.purse = {"items":[],"money":0}
	session.world = GameWorld.new(); session.world.session = session
	session.world.nav = NavGrid.new(); session.world.ai = UnitAI.new(session.world)
	var hero := GameUnit.new(); hero.controller = 1; hero.uid = 10001
	var corpse := GameUnit.new(); corpse.uid = 10002; corpse.dead = true
	session.world.set_unit(corpse.uid, corpse)
	corpse.set_meta("loot", [MATERIAL + "[3]", "money[19]"])
	session.coop.with_purse(1, session.take_loot.bind(hero, corpse), true)
	check(session.state.items.count(MATERIAL) == 3 and guest.purse.items.count(MATERIAL) == 3, "corpse resource stack grants one copy to each purse")
	check(session.state.money == 19 and guest.purse.money == 19, "corpse money grants one copy to each purse")
	check(not session.world.units.has(corpse.uid) and corpse.get_meta("looted", false), "corpse is removed from interaction targets and marked consumed")
	# A stale second completion cannot recreate the corpse's consumed loot.
	session.coop.with_purse(1, session.take_loot.bind(hero, corpse), true)
	check(session.state.items.count(MATERIAL) == 3 and guest.purse.items.count(MATERIAL) == 3 and session.state.money == 19 and guest.purse.money == 19, "repeated corpse completion grants no duplicate resources or money")
	session.state.coop = {"host":{"joiners":session.coop.joiners.duplicate(true)}}
	check(session.state.save("user://loot-grants.sav") == OK, "granted inventory saves")
	var saved := CampaignState.load_from("user://loot-grants.sav")
	check(saved.items.count(MATERIAL) == 3 and saved.coop.host.joiners.guest.purse.items.count(MATERIAL) == 3, "save/load preserves resource counts in both purses")
	hero.free(); session.world.free(); session.world = null
	Engine.time_scale = 1.0
	session.coop.free(); session.free()
	print("COOP_LOOT_GRANTS ", checks, " checks ", failures, " failures")
	get_tree().quit(int(failures > 0))

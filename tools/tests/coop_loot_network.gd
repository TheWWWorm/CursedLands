extends Node
## Real ENet commands, animation completion, inventory replication and pickup
## notices. Deliberately resend reliable/fast packets and race both players.
class ObservedSession extends Session:
	var notices: Array[Dictionary] = []
	func _on_event(event: Dictionary) -> void:
		if event.get("t", "") in ["got", "loot_copy"] and int(event.get("to", -1)) in [-1, my_index]:
			notices.append(event.duplicate(true))
		super._on_event(event)

const MATERIAL := "material.thick"
var host: ObservedSession
var guest: ObservedSession
var roots: Array[Node] = []
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func until(predicate: Callable, seconds := 30.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func settle() -> void:
	await get_tree().create_timer(0.3, true, false, true).timeout

func peer(label: String) -> ObservedSession:
	var root := SubViewport.new()
	root.name = label; root.size = Vector2i(320, 180); root.own_world_3d = true
	add_child(root); roots.append(root)
	var api := SceneMultiplayer.new(); api.root_path = root.get_path()
	get_tree().set_multiplayer(api, root.get_path())
	var s := ObservedSession.new(); root.add_child(s)
	var g := Game.new(); g.session = s; s.game = g; root.add_child(g)
	return s

func finish() -> void:
	Engine.time_scale = 1.0
	for s in [host, guest]:
		if s == null: continue
		s.online = false
		if s.multiplayer.multiplayer_peer: s.multiplayer.multiplayer_peer.close()
	for root in roots: root.queue_free()
	for i in 8: await get_tree().process_frame
	print("COOP_LOOT_NETWORK ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(int(failures > 0))

func _ready() -> void:
	GameData.options.merge({"autosave":0, "show_tutorial":0, "net_upnp":0, "net_lan":0,
		"net_directory":0, "auto_graphics":0, "coop_share_loot":1}, true)
	host = peer("LootHost"); guest = peer("LootGuest")
	check(host.host(0, 2) == OK, "authority opens isolated ENet port")
	GameData.player_name = "Loot Guest"
	check(guest.join("127.0.0.1", host.host_port) == OK, "guest connects over ENet")
	check(await until(func(): return host.players.size() == 2 and guest.my_index == 1), "distinct host and guest identities")
	if failures: await finish(); return
	host.state = CampaignState.new()
	host.state.ensure_hero(0, "Human Hero")
	host.state.ensure_hero(1, "Human Hero", "Loot Guest")
	var pid := guest.multiplayer.get_unique_id()
	host.coop._pending[pid] = {"hero":host.state.heroes[1][0].duplicate(true), "vars":{},
		"visited":{}, "side_quests":{}, "quest_items":{}, "seq":{}, "purse":{"items":[], "money":0}}
	host.coop.on_hello(pid, 1, "Loot Guest")
	await host.enter_zone("bz1g", 1, false)
	check(await until(func(): return guest.world != null and not guest.loading_game and not guest._remote_loading \
		and not guest.party_units(1).is_empty()), "guest loads original camp with private bag")
	if failures: await finish(); return
	host.world.vm.instances.clear()
	var entry := host.coop.purse_entry(1)
	check(not entry.is_empty(), "imported guest has a distinct purse")
	if failures: await finish(); return
	host.state.items = []; host.state.money = 0
	entry.purse = {"items":[], "money":0}; host.sync_state()
	check(await until(func(): return guest.state.items.is_empty() and guest.state.money == 0), "empty private inventory reaches guest")
	var record := {}
	for u: GameUnit in host.world.units.values():
		if not u.has_meta("hero") and not u.dead:
			record = u.info.duplicate(true); break
	check(not record.is_empty(), "fixture uses an original camp actor")
	if failures: await finish(); return
	var owner: GameUnit = host.party_units(1)[0]
	var hero: GameUnit = host.party_units(0)[0]
	# A partly robbed actor retains its pockets as corpse loot on death.
	# A later script grant must update that shared Array only once.
	record.nid = host.world.new_uid()
	var carried := host.world.spawn_unit(record.duplicate(true))
	carried.info.quest_items = ["driadidol00"]
	carried.set_meta("pockets", ["driadidol00"])
	carried.die()
	check(is_same(carried.get_meta("pockets"), carried.get_meta("loot")), "death retains one carried bag behind both metadata views")
	var instance := ScriptVM.Instance.new(); instance.locals.actor = carried
	host.world.vm._call("GiveUnitQuestItem", [[ScriptParser.N_VAR,"actor"], [ScriptParser.N_STR,MATERIAL]], instance)
	check(carried.get_meta("loot").count(MATERIAL) == 1 and carried.get_meta("pockets").count(MATERIAL) == 1,
		"script grant to a corpse with rolled pockets adds one item")
	host.world.vm._call("GiveUnitQuestItem", [[ScriptParser.N_VAR,"actor"], [ScriptParser.N_STR,MATERIAL]], instance)
	check(carried.get_meta("loot").count(MATERIAL) == 2, "two intentional grants retain both identical resources")
	# Save/load restores separate metadata arrays. Both views still need the
	# new item, even when their existing contents compare equal.
	carried.set_meta("pockets", carried.get_meta("pockets").duplicate())
	host.world.vm._call("GiveUnitQuestItem", [[ScriptParser.N_VAR,"actor"], [ScriptParser.N_STR,MATERIAL]], instance)
	check(carried.get_meta("loot").count(MATERIAL) == 3 and carried.get_meta("pockets").count(MATERIAL) == 3,
		"separate restored bag views each receive the scripted item")
	host.coop.with_purse(1, host.take_loot.bind(owner, carried), true)
	check(host.state.items.count(MATERIAL) == 3 and entry.purse.items.count(MATERIAL) == 3,
		"looting three scripted grants transfers exactly three resources to each bag")
	# Inventory snapshots and pickup notices use separate delivery paths. An
	# empty inventory can arrive before the previous corpse's notice; wait for
	# that fixture's actual event before clearing the observers for the race.
	check(await until(func(): return host.notices.size() == 1 and guest.notices.size() == 1),
		"scripted-corpse pickup notice reaches both peers before retry tests")
	if failures: await finish(); return
	host.state.items = []; entry.purse.items = []; host.sync_state()
	await settle()
	check(await until(func(): return guest.state.items.is_empty()), "scripted-corpse fixture inventory settles before retry tests")
	var expected_items := 0
	var expected_money := 0
	for speed in [1.0, 2.0]:
		Engine.time_scale = speed
		for race in [false, true]:
			host.notices.clear(); guest.notices.clear()
			record.nid = host.world.new_uid()
			var body := host.world.spawn_unit(record.duplicate(true))
			body.pos = owner.pos; hero.pos = owner.pos
			body.die()
			body.set_meta("loot", [MATERIAL + "[3]", "money[19]"])
			var uid := body.uid
			var cmd := {"t":"loot", "units":[owner.uid], "target":uid}
			guest.submit(cmd)
			var retry: Dictionary = guest._input_out.pending.get(guest._input_out.serial, {}).duplicate(true)
			check(not retry.is_empty(), "pickup enters retry transport at %sx race=%s" % [speed, race])
			if not retry.is_empty():
				guest._rpc_cmd_fast.rpc_id(1, var_to_bytes([retry, retry]))
				guest._rpc_cmd.rpc_id(1, retry)
			# Distinct user clicks are also valid new commands, not just retries.
			for i in 3: guest.submit(cmd)
			if race: host.submit({"t":"loot", "units":[hero.uid], "target":uid})
			check(await until(func(): return not host.world.units.has(uid)), "real use animation consumes corpse at %sx race=%s" % [speed, race])
			expected_items += 3; expected_money += 19
			check(await until(func(): return guest.state.items.count(MATERIAL) == expected_items and guest.state.money == expected_money), "one stack and money reach guest at %sx race=%s" % [speed, race])
			if not retry.is_empty():
				guest._rpc_cmd_fast.rpc_id(1, var_to_bytes([retry]))
				guest._rpc_cmd.rpc_id(1, retry)
			guest.submit(cmd)
			await settle()
			check(host.state.items.count(MATERIAL) == expected_items and entry.purse.items.count(MATERIAL) == expected_items
				and host.state.money == expected_money and entry.purse.money == expected_money,
				"simultaneous clicks and late packets cannot duplicate either purse at %sx race=%s" % [speed, race])
			check(host.notices.size() == 1 and guest.notices.size() == 1, "each player receives one corpse pickup notice at %sx race=%s" % [speed, race])
			if host.notices.size() != 1 or guest.notices.size() != 1:
				print("LOOT_NOTICE_MISMATCH ", JSON.stringify({"speed":speed,"race":race,"host":host.notices,"guest":guest.notices}))
	# Script rewards use the same reliable inventory/notice path as a quest.
	host.notices.clear(); guest.notices.clear()
	host.give_item(-1, MATERIAL, 3); host.notify_got(-1, [MATERIAL, MATERIAL, MATERIAL])
	expected_items += 3
	check(await until(func(): return guest.state.items.count(MATERIAL) == expected_items), "script resource stack replicates once to private guest")
	await settle()
	check(host.notices.size() == 1 and guest.notices.size() == 1, "one script reward produces one notice per recipient over ENet")
	check(host.apply_mod_rules({"coop_share_loot":0}, {}).is_empty(), "authority accepts disabling shared loot")
	check(await until(func(): return GameData.option("coop_share_loot") == 0), "changed sharing rule reaches guest")
	host.notices.clear(); guest.notices.clear()
	host.give_item(-1, MATERIAL); host.notify_got(-1, [MATERIAL]); host.sync_state()
	await settle()
	check(guest.state.items.count(MATERIAL) == expected_items and guest.notices.is_empty(), "disabled sharing gives private guest neither a resource nor a misleading notice")
	host.state.coop = {"host":{"joiners":host.coop.joiners.duplicate(true)}}
	check(host.state.save("user://network-loot.sav") == OK, "network pickup state saves")
	var saved := CampaignState.load_from("user://network-loot.sav")
	check(saved.items.count(MATERIAL) == expected_items + 1 and saved.money == expected_money,
		"host resource and money totals survive save/load")
	check(saved.coop.host.joiners.values().any(func(e): return e.get("purse", {}).get("items", []).count(MATERIAL) == expected_items \
		and int(e.get("purse", {}).get("money", -1)) == expected_money), "private guest totals survive save/load")
	await finish()

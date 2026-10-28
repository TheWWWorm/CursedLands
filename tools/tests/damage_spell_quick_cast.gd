extends "third_person_kbm.gd"
## Destruction (rick_magic) and Astral Rift (curse_magic) are damage spells
## outside the original's offensive list (prototype types 40 and 41), so its
## quick cast aimed them at the caster. Cursed Lands aims them at the nearest
## enemy, as the Rebirth edition does. Real spell column and belt commands.
class ProbeSession extends Session:
	var casts: Array[Dictionary] = []
	func submit(command: Dictionary) -> void:
		if command.get("t", "") == "cast":
			casts.append(command.duplicate(true))
		super.submit(command)

var enemy: GameUnit

func setup_hero() -> void:
	var h: Dictionary = hero.get_meta("hero")
	h.skills = {"melee":100, "archery":100, "science":100, "elemental":100, "sense":100, "astral":100}
	h.int = 200.0
	h.spells = ["rick_magic{}", "curse_magic{}", "arrow{}", "healing{}"]
	h.quick = []
	Combat.hero_stats(hero, h)
	hero.mana = hero.max_mana; hero.hp = hero.max_hp
	await frames(2)

func spawn_enemy() -> void:
	var at := free_point(3.0)
	enemy = s.world.spawn_unit({"nid":990101, "prototype":"Human Hero", "player":1, "position":Vector3(at.x, at.y, 0)})
	enemy.set_process(false); enemy.set_physics_process(false); enemy.controller = -1
	enemy.ai_next = INF; enemy._perceive_next = INF
	enemy.visible = true; enemy.fogged = false; enemy.hidden = false
	# Campaign diplomacy tables differ: take the first other side that the
	# authored relation update makes hostile.
	for side in range(1, 16):
		if side == hero.faction: continue
		enemy.faction = side
		s.world.set_relation(hero.faction, enemy.faction, 2)
		if s.world.is_enemy(enemy, hero): break
	# Single player lists the units near the camera point (UnitFog.relevant_for).
	g.rig.position = Vector3(hero.pos.x, g.rig.position.y, -hero.pos.y)
	check(s.world.is_enemy(enemy, hero), "the spawned unit is hostile")
	check(UnitFog.relevant_for(s, hero.controller).has(enemy), "the enemy is in the player's view")
	check(s.belt_enemy(hero) == enemy, "the enemy is the nearest one in view")

func classification() -> void:
	for spell in ["rick_magic{}", "curse_magic{}"]:
		check(Spells.offensive(spell), spell + " aims at enemies")
	check(Spells.offensive("arrow{}") and Spells.offensive("stun{}"), "original offensive spells keep enemy aim")
	for spell in ["healing{}", "antimagic{}", "speed{}"]:
		check(not Spells.offensive(spell), spell + " still targets the holder")

func column_cases() -> void:
	var slots: SpellSlots = g.hud._slots
	for i in 3:
		reset(); slots._process(0.0)
		var probe := s as ProbeSession
		probe.casts.clear()
		var spell := String(slots._entries[i][0])
		slots.use(i, true)
		check(probe.casts.size() == 1, spell + " quick cast issues one cast")
		var cmd: Dictionary = probe.casts.back() if not probe.casts.is_empty() else {}
		check(int(cmd.get("target", -1)) == enemy.uid, spell + " quick cast targets the enemy, not the caster")
	reset(); slots._process(0.0)
	(s as ProbeSession).casts.clear()
	slots.use(3, true)
	var heal: Dictionary = (s as ProbeSession).casts.back() if not (s as ProbeSession).casts.is_empty() else {}
	check(int(heal.get("target", -1)) == hero.uid, "quick heal still targets the caster")

func belt_use_cases() -> void:
	var h: Dictionary = hero.get_meta("hero")
	var wand := "wand 1.rock|curse_magic"
	check(Items.is_wand(wand) and Items.spell_of(wand).begins_with("curse_magic"), "Astral Rift wand fixture")
	h.quick = [wand]
	Combat.hero_stats(hero, h)
	reset()
	# Enough health that a self-hit (the unfixed behaviour) leaves the holder
	# alive, so the later cases still exercise a living unit.
	hero.max_hp = 100000.0; hero.hp = hero.max_hp; enemy.hp = enemy.max_hp
	var hero_hp := hero.hp; var enemy_hp := enemy.hp
	s.apply_command({"t":"use", "unit":hero.uid, "item":wand}, 0)
	# A belt use recomputes the holder's stats, which may lower the oversized
	# maximum; an unhurt holder stays at that maximum.
	check(not hero.dead and hero.hp >= minf(hero_hp, hero.max_hp), "belt Astral Rift does not hit its holder")
	check(enemy.hp < enemy_hp, "belt Astral Rift hits the nearest enemy")
	# Without an enemy in view the original plays "nomagic" and casts nothing.
	enemy.hidden = true; enemy.visible = false
	h.quick = [wand]; Combat.hero_stats(hero, h)
	hero.hp = hero.max_hp; hero_hp = hero.hp
	check(not hero.dead, "the holder is alive for the no-enemy case")
	s.apply_command({"t":"use", "unit":hero.uid, "item":wand}, 0)
	check(hero.hp == hero_hp and h.quick.size() == 1, "no enemy: nothing is cast and the charge stays")
	enemy.hidden = false; enemy.visible = true

func _ready() -> void:
	get_window().size = Vector2i(800, 600)
	GameData.options.merge({"autosave":0, "show_tutorial":0, "net_upnp":0, "net_lan":0, "net_directory":0, "auto_graphics":0, "control_mode":2, "pad_enabled":0, "blood":0}, true)
	PadInput.active = "kbm"; s = ProbeSession.new(); add_child(s); g = Game.new(); g.session = s; s.game = g; add_child(g)
	s.state = CampaignState.new(); s.state.ensure_hero(0, "Human Hero")
	mode = GameData.campaign_id
	classification()
	await s.enter_zone("gz1g", 1, false)   # a field zone: villages refuse casts
	await prepare(); await setup_hero(); spawn_enemy()
	column_cases(); belt_use_cases()
	g.queue_free(); s.queue_free(); await frames(10); TexUpscale.shutdown()
	print("DAMAGE_SPELL_QUICK_CAST ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)

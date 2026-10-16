extends "third_person_kbm.gd"
## Real shortcut routing with a deliberately stale global modifier/attack.
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"control_mode":3,
		"pad_enabled":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0},true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");await s.enter_zone("gz1g",1,false);mode="first-person spell selection";await prepare()
	for modifier: Key in [KEY_CTRL,KEY_ALT]:
		reset()
		var held:=InputEventKey.new();held.keycode=modifier;held.physical_keycode=modifier;held.pressed=true
		Input.parse_input_event(held);await frames(2)
		check(Input.is_key_pressed(modifier),"stale global modifier fixture is armed")
		var hotkey:=InputEventKey.new();hotkey.keycode=KEY_1;hotkey.physical_keycode=KEY_1;hotkey.pressed=true
		g._unhandled_input(hotkey)
		check(g.pending_spell=="healing{}" and hero.orders.is_empty(),"plain shortcut selects without stale modifier quick-cast")
		EIKeymap.release_keys();await frames(2)
	reset();g.direct._fire=true;g.direct._repeat=0
	g.begin_cast(0);g.direct.step(Vector2.ZERO,0.05)
	check(g.pending_spell=="healing{}" and hero.orders.is_empty() and not g.direct._fire,"held attack cannot confirm a newly selected spell")
	reset()
	var explicit:=InputEventKey.new();explicit.keycode=KEY_1;explicit.physical_keycode=KEY_1;explicit.pressed=true;explicit.ctrl_pressed=true
	g._unhandled_input(explicit)
	check(g.pending_spell.is_empty() and order_target(hero),"explicit Ctrl shortcut retains intentional self quick-cast")
	reset();g.begin_cast(0);g.direct.cast_self()
	check(g.pending_spell.is_empty() and order_target(hero),"fresh explicit self action still confirms selected spell")
	check(GameData.OPTIONS.any(func(row):return row[0]=="spell_double_tap_self" and row[5]==1),"double-tap self-cast defaults on")
	GameData.options.spell_double_tap_self=1
	reset();g._last_spell_key.clear();g._key_action("spell1",false,true)
	check(g.pending_spell=="healing{}" and hero.orders.is_empty(),"one key press still selects healing")
	g._key_action("spell1",false,true)
	check(g.pending_spell.is_empty() and order_target(hero),"quick second press self-casts healing")
	reset();g._key_action("spell1",false,true);g._last_spell_key.at=Time.get_ticks_msec()-1000;g._key_action("spell1",false,true)
	check(g.pending_spell.is_empty() and hero.orders.is_empty(),"slow second press retains ordinary selection cancellation")
	reset();g._key_action("spell2",false,true);g._key_action("spell2",false,true)
	check(hero.orders.is_empty(),"double-tap never targets an offensive spell at the caster or an automatic enemy")
	reset();g._key_action("spell1",false,true);g._key_action("spell8",false,true);g._key_action("spell8",false,true)
	check(hero.orders.is_empty() and g.pending_spell=="healing{}","empty spell slot cannot confirm a different pending spell")
	GameData.options.spell_double_tap_self=0
	reset();g._key_action("spell1",false,true);g._key_action("spell1",false,true)
	check(g.pending_spell.is_empty() and hero.orders.is_empty(),"disabled option restores second-key cancellation")
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
	print("DIRECT_SPELL_SELECTION ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)

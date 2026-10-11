extends Node
## Damage thresholds, actual rune assets, original LiA exit data and saved
## companion progress. The supplied save remains an external test fixture.
class PathUnit extends GameUnit:
	var repaths := 0
	func speed() -> float: return 2.0
	func _path_to(to: Vector2, _target: GameUnit = null, _flat := -1, _limit := 1e6) -> PackedVector2Array:
		repaths += 1
		return PackedVector2Array([to])

class SpellUnit extends GameUnit:
	func take_damage(amount: float, source: GameUnit, _part := -1, _types := PackedFloat32Array(), _hit_flags := 0, layers := Callable(), _owner_only := false) -> void:
		body_damage(amount * float(source.get_meta("coop_dmg_mul",1.0)) if source else amount,layers)

class DamageCombat extends Combat:
	func blank_hit(_def: GameUnit, _src: GameUnit, _owner_only := false, _hit_flags := 0) -> void: pass

var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	GameData.difficulty = 0
	GameData.options.armor_formula = 1
	var w := GameWorld.new(); add_child(w); w.set_process(false); w.set_physics_process(false)
	var c := DamageCombat.new(w);w.combat=c
	var u := GameUnit.new(); w.add_child(u); u.world = w
	u.stats.armor = PackedFloat32Array([0,0,0,0,0,0,0])
	var types := PackedFloat32Array([0,0,1,0,0,0,0])
	check(is_equal_approx(c.absorb(u,100,types),100), "unarmoured damage is unchanged")
	u.stats.armor[2] = 30
	check(is_equal_approx(c.absorb(u,100,types),70), "armour subtracts its threshold")
	u.stats.armor[2] = 500
	check(is_equal_approx(c.absorb(u,100,types),20), "armour cannot absorb more than 80 percent")
	check(is_equal_approx(c.last_wear.weapon,80), "weapon wear counts only absorbed damage")
	types = PackedFloat32Array([0.5,0,0.5,0,0,0,0])
	check(is_equal_approx(c.absorb(u,100,types),60), "mixed types keep independent armour thresholds")
	check(is_zero_approx(c.absorb(u,0,types)), "zero incoming damage stays zero")
	var protected:=SpellUnit.new();w.add_child(protected);protected.world=w;protected.max_hp=100.0
	protected.parts=[{"type":0,"state":0},{"type":1,"state":3,"max":100.0,"cur":100.0,"size":1.0,"lethal":1.0}]
	protected.stats.armor=PackedFloat32Array([500,500,500,500,500,500,500])
	protected.set_meta("hero",{"armors":["gipat medium plate.thin"]})
	var worn:=Combat.worn_layers(protected.get_meta("hero").armors,"torso")
	check(not worn.is_empty() and worn[0][1][3]>0.0,"spell armour fixture has real thermal protection")
	Spells._spell_damage(w,null,{"code":"fireball","subtype":"fire","duration":1,"effect":100.0},protected)
	check(is_equal_approx(protected.hp,80.0),"natural and worn spell armour share the 80 percent cap")
	protected.hp=100.0;protected.stats.armor.fill(0.0)
	Spells._spell_damage(w,null,{"code":"fireball","subtype":"fire","duration":1,"effect":0.1},protected)
	check(is_equal_approx(100.0-protected.hp,0.02),"worn spell armour alone also leaves 20 percent damage")
	protected.hp=100.0;u.set_meta("coop_dmg_mul",2.0)
	Spells._spell_damage(w,u,{"code":"fireball","subtype":"fire","duration":1,"effect":0.1},protected)
	check(is_equal_approx(100.0-protected.hp,0.04),"spell armour floor follows co-op incoming damage scaling")
	u.remove_meta("coop_dmg_mul")
	protected.hp=100.0;protected.stats.armor.fill(500.0)
	Spells._spell_damage(w,null,{"code":"fireball","subtype":"fire","duration":1,"effect":0.00001},protected)
	check(absf(100.0-protected.hp-0.000002)<0.00000001,"very small spell pulses retain the same proportional damage floor")
	GameData.options.armor_formula = 0
	check(is_zero_approx(c.absorb(u,100,PackedFloat32Array([0,0,1,0,0,0,0]))), "original armour can absorb all incoming damage")
	protected.hp=100.0
	Spells._spell_damage(w,null,{"code":"fireball","subtype":"fire","duration":1,"effect":100.0},protected)
	check(is_equal_approx(protected.hp,100.0),"original spell armour has no forced damage floor")
	u.pos = Vector2(5,5); u._radius_base = .3; u.figure_half_z = .9; u.stats.range = 0.0; u.uid = 1
	w.set_unit(1,u)
	var rat := GameUnit.new(); w.add_child(rat); rat.world = w; rat.uid = 2
	rat.pos = Vector2(5.6,5); rat._radius_base = .15; rat.figure_half_z = .2; w.set_unit(2,rat)
	check(DirectCombat.melee_target(u,Vector3.RIGHT)==rat, "level melee swing reaches a small nearby enemy")
	rat.figure_half_z = .05
	check(DirectCombat.melee_target(u,Vector3.RIGHT)==rat, "the swing also reaches the shortest ground creatures")
	check(DirectCombat.melee_target(u,Vector3.LEFT)==null, "small enemy behind the attacker is excluded")
	rat.pos = Vector2(5.2,5)
	check(NavGrid._separating_overlap(u,Vector2(4.9,5),rat), "an overlapping unit can separate")
	check(not NavGrid._separating_overlap(u,Vector2(5.1,5),rat), "separation does not allow deeper overlap")
	u.pos=Vector2(5.49,5.1);rat.pos=Vector2(5.51,5.49);rat._radius_base=.3
	u._seq=1;rat._seq=2
	w.nav.size=Vector2i(64,64);w.nav._occ.resize(64*64);w.nav.track_unit(u);w.nav.track_unit(rat)
	var escape:=Vector2(5.6,5.0)
	check(w.nav.step_blocker(u,escape,{})==null,"native movement allows separation across a quantized cell edge")
	check(w.nav.step_blocker_script(u,escape,{})==null,"script movement also allows overlap separation")
	check(w.nav.step_blocker(u,Vector2(5.53,5.45),{})==rat,"overlap escape cannot move farther into the other actor")
	var left := PathUnit.new(); var right := PathUnit.new()
	w.add_child(left); w.add_child(right)
	left.world=w; right.world=w; left.uid=3; right.uid=4
	left.pos=Vector2(8,8);right.pos=Vector2(9,8)
	left.path=PackedVector2Array([Vector2(12,8)]);right.path=PackedVector2Array([Vector2(5,8)])
	left.order={"type":"move","to":Vector2(12,8)};right.order={"type":"move","to":Vector2(5,8)}
	left._blocked_by(right,false);right._blocked_by(left,false)
	check(left.repaths==0 and right.repaths==1,"equal-speed head-on actors choose one deterministic detour")
	var icons := SpellSlots.rune_icons("healing{e0;m1;e0}")
	check(icons.size()==3 and icons[0] is AtlasTexture and icons[1] is AtlasTexture, "runes use transparent original inscriptions")
	check(icons[0]==icons[2] and icons[0]!=icons[1], "rune order and duplicate inscriptions survive")
	check(Spells.mod_short_title("m1").length()<=4, "spell descriptions use original short rune labels")
	var lang := RemakeText.lang
	for locale: String in ["ru","de"]:
		RemakeText.lang = locale
		for key: String in ["Game setup","Current defaults","Difficulty","Easy","Done","Mods and rules…","Ctrl: crouch"]:
			check(RemakeText.t(key)!=key, locale+" translates "+key)
	RemakeText.lang = lang
	var panel := SettingsDialog.new(); add_child(panel); panel.size=Vector2(2560,1440)
	panel.build_shell("Game setup",Vector2(960,720)); panel.size=Vector2(2560,1440); panel.layout_shell()
	check(panel.theme.default_font != Interface800.font(), "settings scaling does not mutate the shared HUD font")
	check(panel.theme.default_font.oversampling>=panel._ui_scale, "settings rasterize at display resolution")
	panel.queue_free()
	var fx := ParticleFx.new(); w.add_child(fx)
	var plain := fx.add_light(Vector3.ZERO,Color.YELLOW,5)
	var flame := fx.add_light(Vector3.ZERO,Color.YELLOW,5,-1,1,false,"fire")
	check(not plain.has("halo") and plain.light.light_volumetric_fog_energy==0.0, "script point lights do not create floating glow discs")
	check(flame.has("halo"), "identified fire sources retain their glow option")
	fx.remove_light(plain); fx.remove_light(flame)
	if GameData.campaign_id == CampaignProfile.ASTRAL:
		var map := CampaignMap.load_from(GameData.texts)
		var ex: Dictionary = map.zone("gz1h").exits[4]
		check(ex.remove==ex.deploy and ex.to=="gz1h_gz2h", "LiA's deployment-only exit has a departure area")
		var source := ""
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--save-fixture="): source=arg.trim_prefix("--save-fixture=")
		if not source.is_empty():
			var good := CampaignState.load_from(source.path_join("save5.sav"))
			var current := CampaignState.load_from(source.path_join("quick.sav"))
			check(good!=null and current!=null, "supplied save fixtures load")
			if good and current:
				var old: Dictionary = good.mercs[2].duplicate(true)
				current.dismissed_mercs[2]=old; current.mercs.erase(2)
				check(current.save("user://dismissed-kel.sav")==OK, "dismissed companion progress saves")
				var restored := CampaignState.load_from("user://dismissed-kel.sav")
				var hired := restored.make_merc(2,{})
				check(hired.str==21 and hired.dex==30 and hired.int==25 and hired.exp==150 and hired.exp_total==151, "replacement recruitment restores Kel's actual attributes and earned XP")
				check(hired.party=="FSusel" and not restored.dismissed_mercs.has(2), "recruitment adopts the current party and consumes its saved record")
	w.queue_free()
	for i in 4: await get_tree().process_frame
	print("PLAYER_FEEDBACK ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

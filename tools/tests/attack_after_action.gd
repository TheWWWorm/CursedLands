extends Node
## A completed cast/hit can still be the displayed action when the next
## attack commits. Its relaxed pose must not select the human bow fallback.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func unit(w: GameWorld, at: Vector3, weapon := "stone dagger.bronze") -> GameUnit:
	var u := w.spawn_unit({"prototype":"Human Hero", "position":at, "weapons":PackedStringArray([weapon])})
	u.set_process(false); u.set_physics_process(false)
	u.controller = 0; u._perceive_next = INF; u.ai_next = INF
	return u

func _ready() -> void:
	var w := GameWorld.new(); add_child(w)
	w.set_process(false); w.set_physics_process(false); w.zone = {"type":"game"}
	var rw := GameWorld.new(); add_child(rw); rw.authority = false
	rw.set_process(false); rw.set_physics_process(false)
	var target := unit(w, Vector3(5.6,5,0))
	target.controller = -1; target.faction = 1
	for direct in [false,true]:
		for prior in ["idle","cast","hit","attack"]:
			var u := unit(w, Vector3(5,5,0))
			u.direct_controlled = direct
			u._pose_snap = false; u.model.pose_state = EIUnitModel.ST_NEUTRAL
			u.alert = false; u.action = prior; u.facing = 0
			u._anim_lock = 0; u._attack_cd = 0
			u.order = {"type":"direct_attack", "direction":Vector3.RIGHT} if direct else {"type":"attack", "target":target}
			for tick in 60:
				w.time += GameUnit.TICK
				u._tick(GameUnit.TICK); u._draw_step(GameUnit.TICK); u.anim_flush()
				u.model.player.advance(GameUnit.TICK); u.model._process(0)
				if u.action == "attack" and u._anim_lock > 0: break
			var tag: String = ("direct" if direct else "targeted") + " after " + prior
			check(u.action == "attack" and u._anim_lock > 0, tag + " commits")
			var record: Dictionary = u.model._clip_records().get(u.model._current,{})
			check(u.model.pose_state == EIUnitModel.ST_ATTACK and (int(record.get("code",0)) & 4) != 0, tag + " uses a dagger attack")
			var replica := unit(rw, Vector3(5,5,0))
			replica.apply_snapshot(u.snapshot(),true)
			check(replica.model.pose_state == EIUnitModel.ST_ATTACK and replica.model._current == u.model._current, tag + " replicates posture and clip")
			u.free(); replica.free()
	# Rendering a still-locked cast must not consume its queued posture.
	var caster := unit(w,Vector3(10,10,0))
	caster._pose_snap = false; caster.model.pose_state = EIUnitModel.ST_NEUTRAL
	caster.action = "cast"; caster.alert = true; caster._anim_lock = 1.0
	caster._update_pose()
	check(caster.model.pose_state == EIUnitModel.ST_NEUTRAL, "locked cast keeps its displayed posture")
	w.free(); rw.free()
	print("ATTACK_AFTER_ACTION ",checks," checks ",failures," failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)

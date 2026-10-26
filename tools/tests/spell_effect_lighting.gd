extends Node
## Every installed spell's real casting emitter; healing's body sparks,
## overlapping casts, hidden actors, option changes and expired effects.
const DARK_OUTCOMES := ["invisibility","stench","possession","shapechange","vision_fog","stun",
	"strength","weak","comprehend","charm","enlarge","shrink","campfire"]
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func active(fx: ParticleFx) -> Array:
	return fx.get_children().filter(func(n):return n is OmniLight3D and n.is_in_group("ei_spell_glow") and n.visible and n.light_energy>0.001)
func step(fx: ParticleFx,count: int) -> void:
	for i in count: fx._tick();fx._draw(1.0)
func _ready() -> void:
	GameData.options.gfx_firelight=1
	var w:=GameWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false)
	var u:=w.spawn_unit({"prototype":"Human Hero","position":Vector3(5,5,0)})
	u.set_process(false);u.set_physics_process(false)
	var target:=w.spawn_unit({"prototype":"Human Hero","position":Vector3(8,5,0)})
	target.set_process(false);target.set_physics_process(false)
	var rows:=[]
	for row: Dictionary in GameData.db.table("spell_prototypes"):
		var fx:=ParticleFx.of(w);fx.set_process(false)
		fx.cast_fx({"uid":u.uid,"spell":String(row.code),"secs":1.0})
		step(fx,8)
		var lights:=active(fx)
		check(not lights.is_empty(),"casting light follows installed spell "+String(row.code))
		check(lights.all(func(l):return l.is_in_group(Gfx.POINT_LIGHT_GROUP) and l.omni_range<=4.0 and l.light_energy<=1.0),"bounded conventional/PT source "+String(row.code))
		var casting_count:=lights.size()
		fx.free()
		# Audit each production impact/status dispatcher separately from its
		# charge-up. Smoke, invisible transformations and UI glyphs do not
		# emit light. The script-only campfire damage prototype has no visual
		# dispatcher; its separately authored TORCH supplies the existing flame.
		fx=ParticleFx.of(w);fx.set_process(false)
		var ev:={"spell":String(row.code),"a":u.uid,"tu":target.uid,"x":target.pos.x,"y":target.pos.y}
		fx.spell_cast(ev)
		fx.magic_fx({"uid":target.uid,"code":String(row.code),"secs":2.0,"s":1.0})
		var native:=SpellFx.spawn_event(w,ev)
		if native:native.set_process(false)
		var outcome_peak:=0;var glow_peak:=0
		for age in 40:
			step(fx,1)
			if native and age<native._life:native.advance(age)
			var glowing:=active(fx).size()
			var traditional:=fx.lights.filter(func(d):return is_instance_valid(d.light) and d.light.visible and d.light.light_energy>0.001).size()
			if native and age<native._life and native._light.visible:traditional+=1
			outcome_peak=maxi(outcome_peak,glowing+traditional);glow_peak=maxi(glow_peak,glowing)
		check(outcome_peak>0 if String(row.code) not in DARK_OUTCOMES else glow_peak==0,"intentional impact/status illumination "+String(row.code))
		rows.append({"spell":row.code,"name":row.name,"casting_lights":casting_count,
			"outcome_peak":outcome_peak,"added_outcome_peak":glow_peak,"nonemissive_outcome":String(row.code) in DARK_OUTCOMES})
		if native:native.free()
		fx.free();target.remove_meta("fx_magic")
	var fx:=ParticleFx.of(w);fx.set_process(false)
	fx.spell_cast({"spell":"healing","a":u.uid,"tu":u.uid,"x":u.pos.x,"y":u.pos.y})
	step(fx,12)
	var lights:=active(fx)
	check(lights.size()==1,"healing body sparks illuminate their surroundings")
	if not lights.is_empty():
		var light: OmniLight3D=lights[0]
		check(light.light_color.b>light.light_color.r and light.global_position.distance_to(u.global_position)<3.0,"healing light is blue/violet and stays at its body particles")
		var energy:=light.light_energy
		for i in 40:fx.spell_cast({"spell":"healing","a":u.uid,"tu":u.uid,"x":u.pos.x,"y":u.pos.y})
		step(fx,3)
		check(active(fx).size()==1 and light.light_energy<=maxf(energy,1.0),"repeated healing shares a bounded body light")
		u.hidden=true;fx._draw(1.0)
		check(active(fx).is_empty(),"hidden carrier leaks no spell glow")
		u.hidden=false;fx._draw(1.0)
		check(active(fx).size()==1,"revealed carrier restores its existing glow")
	GameData.options.gfx_firelight=0;fx._draw(1.0)
	check(active(fx).is_empty(),"original lighting option disables added spell glow")
	GameData.options.gfx_firelight=1;step(fx,80)
	check(active(fx).is_empty(),"expired particles leave no residual illumination")
	check(fx.get_children().filter(func(n):return n is OmniLight3D and n.is_in_group("ei_spell_glow")).size()<=24,"light allocation remains bounded")
	FileAccess.open("user://spell-lighting-audit.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	w.free();TexUpscale.shutdown()
	print("SPELL_EFFECT_LIGHTING ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

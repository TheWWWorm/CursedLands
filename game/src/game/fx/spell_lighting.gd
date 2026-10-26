class_name SpellLighting
extends RefCounted
## Remake illumination from visible magic particles. Native light trajectories
## and spell clocks remain intact. One pooled source per emitter/carrier type,
## never one per spark; repeated effects on the same actor do not add energy.
const LIMIT := 24
const SAMPLES := 12
# Hue, range in metres, peak energy. Persistent status effects are deliberately
# dimmer than casts/healing. Smoke, blood, UI markers and modifier glyphs have
# no emitted light. Missiles, elemental impacts and walls have native lights.
const PROFILES := {
	0x2006:[Color(0.48,0.40,1.0),3.2,0.85], # healing spiral
	0x2009:[Color(1.0,0.55,0.25),3.0,0.35], # fireworks
	0x200b:[Color(0.6,0.65,1.0),2.5,0.35], # generic casting
	0x2014:[Color(0.65,0.45,1.0),2.0,0.18], # link
	0x2015:[Color(0.35,1.0,0.48),2.3,0.22],
	0x2016:[Color(0.35,0.65,1.0),2.3,0.22],
	0x2017:[Color(1.0,0.5,0.2),2.3,0.22],
	0x2018:[Color(0.7,0.55,1.0),2.6,0.28], # clairvoyance/lichdom ring
	0x2019:[Color(0.65,0.35,1.0),3.2,0.55],
	0x201a:[Color(0.55,0.4,1.0),2.3,0.18],
	0x2027:[Color(1.0,0.5,0.2),2.5,0.45],
	0x2028:[Color(0.35,0.65,1.0),2.5,0.45],
	0x2029:[Color(0.35,1.0,0.48),2.5,0.40],
	0x202a:[Color(0.7,0.75,1.0),2.5,0.30],
	0x202b:[Color(0.65,0.4,1.0),2.5,0.30],
	0x202c:[Color(0.85,0.4,0.75),2.5,0.30],
	0x202d:[Color(1.0,0.75,0.4),2.5,0.30],
	0x202e:[Color(0.48,0.40,1.0),2.5,0.40],
	0x2043:[Color(1.0,0.75,0.4),2.0,0.20],
	0x2044:[Color(0.7,0.75,1.0),1.8,0.12],
	0x2045:[Color(1.0,0.4,0.3),1.8,0.12],
	0x2046:[Color(0.4,1.0,0.55),1.8,0.12],
	0x2048:[Color(0.48,0.4,1.0),2.0,0.16],
	0x2049:[Color(0.65,0.4,1.0),1.8,0.12],
	0x204a:[Color(0.3,0.45,1.0),1.8,0.16],
	0x204b:[Color(1.0,0.4,0.25),1.8,0.16],
	0x204c:[Color(0.6,0.65,1.0),1.8,0.12],
}
var _pool: Array[OmniLight3D] = []
var _slots := {}

func update(fx: ParticleFx, fraction: float) -> void:
	var candidates := {}
	var camera := fx.get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else Vector3.ZERO
	if Gfx.on("gfx_firelight") and fx.is_visible_in_tree():
		for effect: ParticleFx.Effect in fx.effects:
			var e := effect.e
			if not PROFILES.has(e.type) or e.parts.is_empty(): continue
			if is_instance_valid(e.carrier) and e.carrier is GameUnit and (e.carrier.hidden or not e.carrier.is_visible_in_tree()): continue
			var row := sample(e,fraction)
			if row.is_empty(): continue
			row.position=ParticleFx.godot(row.position)+fx.display_origin()
			if camera and row.position.distance_squared_to(eye)>65.0*65.0: continue
			var key := "%d:%d"%[e.carrier.get_instance_id() if is_instance_valid(e.carrier) else effect.get_instance_id(),e.type]
			# Recasting refreshes one local contribution instead of turning a
			# crowd of coincident spirals into a floodlight.
			if not candidates.has(key) or float(row.energy)>float(candidates[key].energy): candidates[key]=row
	var keys := candidates.keys()
	if keys.size()>LIMIT:
		keys.sort_custom(func(a: String,b: String)->bool:
			var x: Dictionary=candidates[a];var y: Dictionary=candidates[b]
			return float(x.energy)/(1.0+x.position.distance_squared_to(eye))>float(y.energy)/(1.0+y.position.distance_squared_to(eye)))
		keys.resize(LIMIT)
	for key: String in _slots.keys():
		if not keys.has(key):
			var light: OmniLight3D=_slots[key]
			light.light_energy=0.0;light.hide();_slots.erase(key)
	for key: String in keys:
		var light: OmniLight3D=_slots.get(key)
		if light==null:
			for spare: OmniLight3D in _pool:
				if not spare.visible:light=spare;break
			if light==null:
				light=OmniLight3D.new();light.light_energy=0.0
				Gfx.mark_additive(light)
				light.add_to_group(Gfx.POINT_LIGHT_GROUP);light.add_to_group("ei_spell_glow")
				fx.add_child(light);_pool.append(light)
				var record:={"light":light,"kind":"spell","until":-1,"pos":Vector3.ZERO,"energy":1.0,"external_energy":true}
				LocalLighting.prepare_particle(record)
				light.set_meta(&"ei_local_light",record);light.add_to_group(&"ei_local_spell")
			_slots[key]=light
		var row: Dictionary=candidates[key]
		light.global_position=row.position;light.light_color=row.color
		var record: Dictionary=light.get_meta(&"ei_local_light")
		record.pos=row.position
		light.omni_range=row.radius;light.light_energy=row.energy
		light.light_volumetric_fog_energy=0.0 # the sparks already supply the visible glow
		light.show()

static func sample(e: FxEmitter,fraction: float) -> Dictionary:
	var profile: Array=PROFILES[e.type]
	var position:=Vector3.ZERO;var weight:=0.0
	var count:=mini(SAMPLES,e.parts.size())
	for i in count:
		var p: Array=e.parts[i*e.parts.size()/count]
		var alpha:=lerpf(float((int(p[0x17])>>24)&255),float((int(p[0x16])>>24)&255),fraction)/255.0
		if alpha<=0.0 or float(p[3])<=0.0:continue
		position+=Vector3(p[4],p[5],p[6]).lerp(Vector3(p[0],p[1],p[2]),fraction)*alpha
		weight+=alpha
	if weight<=0.001:return {}
	# Density saturates quickly; hundreds of tiny particles do not increase
	# emitted energy without bound. Alpha supplies their natural end fade.
	var density:=minf(1.0,float(e.parts.size())/8.0)*weight/maxf(count,1)
	return {"position":position/weight,"color":profile[0],"radius":profile[1],"energy":float(profile[2])*density}

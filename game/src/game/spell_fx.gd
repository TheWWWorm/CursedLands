class_name SpellFx
extends Node3D
## The light where a spell lands (all peers); the particles are ParticleFx.

const COLORS := {"fire": Color(1.0, 0.5, 0.15), "lightning": Color(0.6, 0.8, 1.0), "acid": Color(0.4, 1.0, 0.3),
	"healing": Color(1.0, 0.9, 0.5)}

var color := Color(0.8, 0.5, 1.0)
var radius := 1.0
## Seconds the light stays after the flash (fireworks, clairvoyance, campfire:
##  lights for the effect's duration).
var hold := 0.0
var light_color := Color.BLACK
var light_radius := 0.0
var light_energy := 1.0
## Spell codes whose light travels with the missile (ParticleFx).
const MISSILE_LIT := ["arrow", "acid_ray", "fireball"]
var _t := 0.0
var _light: OmniLight3D


## `proto`: the spells.sdb row. Its red / green / blue / light_radius are the
## spell's light (creates a light object with that colour and
## radius); spells with a black light light nothing.
static func spawn(w: GameWorld, at: Vector2, subtype: String, r: float, hold := 0.0, proto := {}) -> void:
	var fx := SpellFx.new()
	fx.hold = hold
	fx.color = COLORS.get(subtype, Color(0.8, 0.5, 1.0))
	fx.radius = maxf(0.6, r)
	var lc := Color(float(proto.get("red", 0.0)), float(proto.get("green", 0.0)), float(proto.get("blue", 0.0)))
	# Firearrow, Acidray and Fireball carry their light with the missile and
	# light the hit point only on arrival (radius × 1.5
	# ParticleFx._hit_light); no light at the target at cast time.
	if lc.get_luminance() > 0.0 and String(proto.get("code", "")).to_lower() not in MISSILE_LIT:
		#  passes the row's red / green / blue (..
		# about 0.4 at most) and light_radius to as
		# they are: the light adds that colour × (1 − d² / r²) after the
		# texture (flag 0x840). A row with a black light
		# (campfire, case 0x27, among others) creates no light object; a
		# camp fire's light is the TORCH object's own (: colour
		# 0.8 grey, radius = fire size × 10, ParticleFx.setup_zone).
		fx.light_color = lc
		fx.light_radius = float(proto.get("light_radius", 1.0))
		fx.light_energy = 1.0
	w.add_child(fx)
	fx.position = EISpace.pos(at.x, at.y, w.ground_at(at.x, at.y) + 0.8)


func _ready() -> void:
	# The visual is the particle effect (ParticleFx.spell_cast); this node is
	# only the spell's light.
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.omni_range = maxf(light_radius, 0.1)
	_light.light_energy = light_energy
	_light.visible = light_radius > 0.0
	# Spell lights carry flag 0x840: additive
	# on the terrain and figures (Gfx.light_code).
	Gfx.mark_additive(_light)
	_light.light_volumetric_fog_energy = Gfx.torch_fog_energy()   # option gfx_torch_glow
	_light.add_to_group(&"gfx_torch_glow")
	add_child(_light)
	if light_radius > 0.0:
		_light.add_child(Gfx.torch_halo(light_radius, light_color))
	if light_radius <= 0.0:
		queue_free()


func _process(dt: float) -> void:
	_t += dt
	var k := _t / 0.7
	if k >= 1.0:
		var h := (_t - 0.7) / maxf(hold, 0.001)
		if h >= 1.0:
			queue_free()
		else:
			_light.light_energy = light_energy * 0.67 * (1.0 - h * h)
		return
	_light.light_energy = light_energy * (1.0 - k) if hold <= 0.0 else light_energy

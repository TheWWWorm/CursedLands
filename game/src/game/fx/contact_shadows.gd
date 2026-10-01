class_name ContactShadows
extends Node
## Remake option gfx_contact_shadows: a soft dark blob on the ground under
## every creature (a Decal child of the unit, projected only onto the
## terrain and walkable object surfaces, EITerrain.DECAL_LAYER), so figures
## sit on the ground also where the sun shadow is missing (shade, night,
## caves). Not in the 2000 renderer. New units are picked up every 0.25 s;
## a decal goes with its unit.

const SCAN := 0.25
const ALPHA := 0.55
const SIZE_K := 2.6     # blob diameter / figure radius
const MIN_SIZE := 0.9

var game: Game
var _t := 0.0
static var _tex: GradientTexture2D


func _init(g: Game) -> void:
	game = g
	name = "ContactShadows"


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = SCAN
	if game == null or game.world == null:
		return
	var on := Gfx.on("gfx_contact_shadows")
	for u: GameUnit in game.world.units.values():
		if not is_instance_valid(u) or u.has_meta("contact_shadow"):
			continue
		if not on:
			continue
		var d := Decal.new()
		d.name = "ContactShadow"
		var s := maxf(MIN_SIZE, u.figure_radius * SIZE_K)
		d.size = Vector3(s, 2.0, s)
		d.texture_albedo = _texture()
		d.modulate = Color(0, 0, 0, ALPHA)
		d.albedo_mix = 1.0
		d.upper_fade = 0.35
		d.lower_fade = 0.35
		d.cull_mask = EITerrain.DECAL_LAYER
		d.distance_fade_enabled = true
		d.distance_fade_begin = 70.0
		d.distance_fade_length = 20.0
		d.add_to_group(&"gfx_contact_shadows")
		u.add_child(d)
		d.position = Vector3(0.0, 0.2, 0.0)
		u.set_meta("contact_shadow", d)


static func _texture() -> GradientTexture2D:
	if _tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		_tex = GradientTexture2D.new()
		_tex.width = 64
		_tex.height = 64
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)
		_tex.fill_to = Vector2(1.0, 0.5)
		_tex.gradient = g
	return _tex

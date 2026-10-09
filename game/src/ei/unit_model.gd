class_name EIUnitModel
extends Node3D
## Animated creature/character model.
## Appearance comes from the unit databases: race model (mesh template, skin set),
## monster prototype (skin, hair, complexion, worn armor, weapon) and the map's
## per-unit overrides. Human/orc textures are composed at runtime from a skin plus
## one overlay per worn item (res/redress.res), like the original "redress" system.

const ARMOR_PREFIX := {"helm": "hl", "plate": "pl", "leggings": "lg", "shirt": "sh",
	"pants": "pt", "boots": "bt", "gloves": "gl"}
## Inner-to-outer layering for texture composition (the original:
## skin, then the slots shirt, pants, boots, gloves, then plate / leggings
## sorted by the armour record's field, a tie keeping plate first — so
## the pants' leather waist wrap lies over the shirt).
const ARMOR_ORDER := ["shirt", "pants", "boots", "gloves", "plate", "leggings", "helm"]
const ARMOR_PARTS := {
	"plate": ["bd", "lh1", "lh2", "lh3", "rh1", "rh2", "rh3", "l_shell", "r_shell"],
	"leggings": ["hp", "ll1", "ll2", "ll3", "rl1", "rl2", "rl3"],
	"helm": ["hd"],
}
const WEAPON_PREFIX := {"sword": "sw", "axe": "ax", "dagger": "dg", "spear": "sp",
	"hammer": "hm", "bow": "bw", "crossbow": "cb"}
const WEAPON_MESH := {"sword": "rh3.sword%02d", "axe": "rh3.axe%02d", "dagger": "rh3.dagger%02d",
	"spear": "rh3.pike%02d", "hammer": "rh3.club%02d", "crossbow": "rh3.crbow%02dmain"}

static var _textures := {}
static var _surface_textures := {}
const AnimatedPart = preload("res://src/ei/anim_part.gd")
const SurfaceResponse = preload("res://src/game/surface_materials.gd")
const FigureMaterial = preload("res://src/ei/figure_material.gd")

## Remake option gfx_sharp_units ("Sharp character textures"; default on,
## off under "Original look"): the unit texture fetch of every unit material
## (bodies, armour, held weapons, DetailedHead faces, the Paperdoll /
## unit-panel figure). Global uniform ei_unit_sharp (Gfx.apply_unit_sharpness):
## x 1 = on, y the mip LOD bias. Off it is exactly texture(tex, uv).
##  - Magnified texels (the close camera: Zak's head at the 3 m modern zoom
##    is drawn ~2.6× its texture at 1080p, LOD p50 −1.4; 89 % of his pixels
##    are magnified): Catmull-Rom bicubic (5 bilinear taps) instead of plain
##    bilinear, faded in from LOD 0 to −0.5 and clamped to the 2×2 texels
##    bilinear reads, so UV island borders in the 256² atlas grow no seams
##    and edges no halos (4 texel fetches).
##  - Minified texels (mid / far camera): mip LOD bias −0.5. Against a 2×2
##    supersampled frame of the same view the mean error on unit pixels fell
##    2.26 → 1.70 (10 m) and 4.75 → 3.78 (24 m); −0.75 / −1.0 were no better
##    at 24 m and shimmered more (temporal second difference +6 % / +9 % of
##    the reference, −0.5 +4 %). The mip chain stays the box-filtered full
##    chain: Lanczos-resampled mips gained less than the bias at 24 m.
## Same image path on Forward+ and Compatibility (no new shader variant: the
## switch is a uniform branch, see ShaderWarmup).
const SHARP_FETCH := """
global uniform vec3 ei_unit_sharp;
vec4 ei_unit_tex(sampler2D tex, vec2 uv) {
	vec4 lin = texture(tex, uv, ei_unit_sharp.y);
	if (ei_unit_sharp.x < 0.5) {
		return lin;
	}
	ivec2 isz = textureSize(tex, 0);
	vec2 size = vec2(isz);
	vec2 p = uv * size;
	vec2 dx = dFdx(p);
	vec2 dy = dFdy(p);
	float k = clamp(-log2(max(dot(dx, dx), dot(dy, dy))), 0.0, 1.0);
	if (k <= 0.0) {
		return lin;
	}
	vec2 tc = floor(p - 0.5) + 0.5;
	vec2 f = p - tc;
	vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
	vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
	vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
	vec2 w3 = f * f * (-0.5 + 0.5 * f);
	vec2 w12 = w1 + w2;
	vec2 t0 = (tc - 1.0) / size;
	vec2 t3 = (tc + 2.0) / size;
	vec2 t12 = (tc + w2 / w12) / size;
	vec3 c = textureLod(tex, vec2(t12.x, t0.y), 0.0).rgb * (w12.x * w0.y)
		+ textureLod(tex, vec2(t0.x, t12.y), 0.0).rgb * (w0.x * w12.y)
		+ textureLod(tex, t12, 0.0).rgb * (w12.x * w12.y)
		+ textureLod(tex, vec2(t3.x, t12.y), 0.0).rgb * (w3.x * w12.y)
		+ textureLod(tex, vec2(t12.x, t3.y), 0.0).rgb * (w12.x * w3.y);
	c /= w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
	ivec2 i0 = ivec2(floor(tc));
	ivec2 i1 = ((i0 + 1) % isz + isz) % isz;
	i0 = (i0 % isz + isz) % isz;
	vec3 a = texelFetch(tex, i0, 0).rgb;
	vec3 b = texelFetch(tex, ivec2(i1.x, i0.y), 0).rgb;
	vec3 d = texelFetch(tex, ivec2(i0.x, i1.y), 0).rgb;
	vec3 e = texelFetch(tex, i1, 0).rgb;
	c = clamp(c, min(min(a, b), min(d, e)), max(max(a, b), max(d, e)));
	return vec4(mix(lin.rgb, c, k), lin.a);
}
"""
## Bias of option gfx_sharp_units (see SHARP_FETCH).
const SHARP_MIP_BIAS := -0.5

## Wounds retain their native ARGB4444-expanded bytes and independent mip chain.
## Sampling raw UNORM preserves the authored encoded-color interpolation; an
## sRGB sampler followed by encoding would instead interpolate linear colors.
## The base keeps its existing fetch. This explicitly replaces the old baked
## wound filtering, while retaining source-over texture alpha and applying the
## material opacity once in UNIT_SHADER. It is not a full D3D two-pass emulation.
const WOUND_FETCH := """
uniform sampler2D wound_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool wound_enabled = false;
vec3 wound_to_encoded(vec3 c) {
	if (OUTPUT_IS_SRGB) { return c; }
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
vec3 wound_to_render(vec3 c) {
	if (OUTPUT_IS_SRGB) { return c; }
	return mix(c / 12.92, pow(max((c + 0.055) / 1.055, vec3(0.0)), vec3(2.4)), step(vec3(0.04045), c));
}
vec4 ei_unit_wound(vec4 base, vec4 wound) {
	float a = wound.a + base.a * (1.0 - wound.a);
	vec3 rgb = (wound.rgb * wound.a + wound_to_encoded(base.rgb) * base.a * (1.0 - wound.a)) / max(a, 1e-8);
	return vec4(wound_to_render(rgb), a);
}
"""

## One shader for all world units, using the world's hourly light uniforms,
## point lights, shadow darkening and view-depth fog. Figure emissive is added
## after max(ambient, sun, point lights), before the shadow (TLP 1000d910).
const UNIT_SHADER := """
shader_type spatial;
render_mode cull_back, ambient_light_disabled, alpha_to_coverage;
#define EI_FIGURE_LIGHT
varying vec3 ei_e;
varying float ei_k;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 unit_emission = vec3(0.0);
""" + SHARP_FETCH + WOUND_FETCH + """
void vertex() {
	ei_e = max(unit_emission, ei_material_emissive);
	ei_k = 0.0;
}
void fragment() {
	FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec4 t = ei_unit_tex(albedo_tex, UV);
	if (wound_enabled) { t = ei_unit_wound(t, ei_unit_tex(wound_tex, UV)); }
	ALBEDO = t.rgb;
	ALPHA = t.a * ei_material_diffuse.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (ei_surface_fx.x > 0.5) {
		ei_surface = texture(surface_tex, UV).rgb;
	}
}
"""
static var _unit_shader: Shader


## Keep texture changes (redress / wounds) on the material that owns them.
## Its albedo property is also used by the existing UI material path.
class LitMaterial extends ShaderMaterial:
	@export var albedo_texture: Texture2D:
		get:
			return get_shader_parameter("albedo_tex")
		set(value):
			if value != albedo_texture:
				wound_texture = null
				remove_meta("wound_overlay_pend")
			set_shader_parameter("albedo_tex", value)
	@export var wound_texture: Texture2D:
		get:
			return get_shader_parameter("wound_tex")
		set(value):
			set_shader_parameter("wound_tex", value)
			set_shader_parameter("wound_enabled", value != null)

	func _init() -> void:
		if EIUnitModel._unit_shader == null:
			EIUnitModel._unit_shader = Gfx.make_shader(EIUnitModel.UNIT_SHADER)
		shader = EIUnitModel._unit_shader


## UI previews (Paperdoll, the portrait's world-model fallback): what a
## StandardMaterial3D with Lambert diffuse, roughness 1, no specular, alpha
## scissor 0.5 and alpha to coverage draws, lit by the preview's own light,
## with the unit texture fetch of option gfx_sharp_units (off: the same image).
const PREVIEW_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, alpha_to_coverage;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
""" + SHARP_FETCH + WOUND_FETCH + """
void fragment() {
	vec4 t = ei_unit_tex(albedo_tex, UV);
	if (wound_enabled) { t = ei_unit_wound(t, ei_unit_tex(wound_tex, UV)); }
	ALBEDO = t.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
"""
static var _preview_shader: Shader
static var _wisp_unit_shader: Shader
static var _wisp_preview_shader: Shader


class PreviewMaterial extends ShaderMaterial:
	@export var albedo_texture: Texture2D:
		get:
			return get_shader_parameter("albedo_tex")
		set(value):
			if value != albedo_texture:
				wound_texture = null
				remove_meta("wound_overlay_pend")
			set_shader_parameter("albedo_tex", value)
	@export var wound_texture: Texture2D:
		get:
			return get_shader_parameter("wound_tex")
		set(value):
			set_shader_parameter("wound_tex", value)
			set_shader_parameter("wound_enabled", value != null)

	func _init() -> void:
		if EIUnitModel._preview_shader == null:
			Gfx.ensure_globals()
			EIUnitModel._preview_shader = Shader.new()
			EIUnitModel._preview_shader.code = EIUnitModel.PREVIEW_SHADER
		shader = EIUnitModel._preview_shader


## Optional experiment, disabled by default to preserve the original shapes.
## the original draws every part rigidly with one matrix. Enabling
## this merges body meshes and blends the matrices near joints; it reduces
## some steps but distorts the authored silhouette and texture details.
static var smooth_joints := false

var template := ""
var player: AnimationPlayer
var weapon_type := ""
var _current := ""
var _animation_roots: Array[EIAnimPart] = []
## Hidden figures retain their playback clock while deferring pose work.
## Pose consumers and showing the figure materialize the current pose first.
var _pose_pending := false
var _timeline_pending := false


func flush_pending_pose() -> void:
	if not _pose_pending:
		return
	_pose_pending = false
	if _timeline_pending and player:
		_timeline_pending = false
		var already_batching := EIAnimPart.batch
		EIAnimPart.batch = true
		player.advance(0.0)
		EIAnimPart.batch = already_batching
	for root: EIAnimPart in _animation_roots:
		if is_instance_valid(root):
			root._apply_key()


## Vertex morph parts: [MeshInstance3D "morph", {clip: [first shape, frame
## count]}, [shape indices set last]] (_apply_morphs).
var _morph_parts: Array = []
## Option gfx_detailed_heads: the fitted HUD face under "hd" (DetailedHead)
## and the original head mesh and hair node it replaces.
var _detail: MeshInstance3D
var _plain_head: Array[Node3D] = []


## `unit` is a map object dictionary from EIMob (or a synthetic one with
## prototype/complexion/armors/weapons).
static func create(unit: Dictionary, ui_preview := false, initial_action := true) -> EIUnitModel:
	unit = CampaignState.map_unit_record(unit)
	var db := GameData.db
	var proto := db.find("monster_prototypes", unit.get("prototype", unit.get("parent_template", "")))
	var race := db.find("race_models", proto.get("base_race", ""))
	var tmpl: String = unit.get("template", "")
	if tmpl.is_empty():
		tmpl = String(race.get("mask", "")).to_lower()
	var model := EIFigure.get_model(tmpl)
	if model.is_empty():
		return null
	var m := EIUnitModel.new()
	m.template = tmpl
	m.name = tmpl
	m._build(model, unit, proto, race, ui_preview, initial_action)
	return m


func play(anim: String, blend := 0.15, restart := false) -> void:
	if not has_anim(anim):
		return
	# An explicitly requested clip replaces the logical action sequence.
	# Otherwise a script clip could retain a walk's queued follow-up, or be
	# mistaken for the idle cycle when the script finishes.
	_cycle = -1
	_resume = ""
	_resume_clip = ""
	_play(anim, blend, restart)


func _play(anim: String, blend: float, restart := false) -> void:
	if player == null or (anim == _current and not restart):
		return
	var key := "ei/" + anim
	if player.has_animation(key):
		player.play(key, blend)
		_current = anim
		if restart:
			# Store the exact native keys during seek, then compose each
			# hierarchy once. Nested mixer callbacks retain an outer batch.
			var already_batching := EIAnimPart.batch
			EIAnimPart.batch = true
			player.seek(0.0, true)
			EIAnimPart.batch = already_batching
			if not already_batching:
				for root: EIAnimPart in _animation_roots:
					root._apply_key()


## Plays a logical action: idle, walk, run, crawl, attack, hit, death, cast...
## Resolves to the original clip names ("cidle", "cidle01", "uattack03", ...).
func act(action: String, variant := 1, blend := 0.15) -> float:
	return _act(action, variant, blend, false)


##  builds a humanoid's movement start + cycle pair whenever
## weapon, state, gait or limp changes. Repeated requests keep that pair.
## Non-humanoids, absent start clips and other actions go straight to act().
func act_with_start(action: String, variant := 1, blend := 0.15) -> float:
	return _act(action, variant, blend, movement_starts and action in ["walk", "run", "crawl"])


func _act(action: String, variant: int, blend: float, with_start: bool) -> float:
	# The village screen owns an idle actor's presentation until it closes.
	# Ordinary movement, attacks, death and explicit script clips still play.
	if action == "idle" and _dialogue_active:
		if _current != _dialogue_clip or not player.is_playing():
			begin_dialogue(false)
		if _dialogue_active:
			return player.get_animation("ei/" + _dialogue_clip).length
	var clip := ""
	var requested := code_for(action) if _ACTION_CODE.has(action) else -1
	var cyc := requested >= 0 and requested & STAGE_CYCLE != 0
	# The unit calls this every tick, including during a start/cross clip.
	# Preserve its queued cycle before touching _resume.
	if cyc and requested == _cycle and _current != "":
		return player.get_animation("ei/" + _current).length
	_resume = ""
	_resume_clip = ""
	_cycle = requested if cyc else -1
	_cycle_pos = 0.0
	if not adb.is_empty() and _ACTION_CODE.has(action):
		var code := requested
		clip = pick(code, true, not cyc)
		if clip == "" and code & 0x3fc00000:
			code &= ~0x3fc00000     # no limping clip for this posture
			clip = pick(code, true, not cyc)
	if clip.is_empty():
		clip = resolve(action, variant)
	if clip.is_empty():
		_cycle = -1
		return 0.0
	if with_start and not adb.is_empty():
		#  adds the limp modifier only to the cycle query. The
		# start uses the same weapon/state/gait without stage or modifier bits.
		var start := pick((requested & 0x003fffff) | STAGE_START)
		if start != "":
			_resume = action
			_resume_clip = clip
			_play(start, blend, true)
			return player.get_animation("ei/" + start).length
	_play(clip, blend, not cyc and clip == _current)
	return player.get_animation("ei/" + clip).length


## The clip act(action) would play for a one-shot (not cycle) action, without
## playing it; "" when the figure has none.
func action_clip(action: String, variant := 1) -> String:
	var clip := ""
	if not adb.is_empty() and _ACTION_CODE.has(action):
		var code := code_for(action)
		clip = pick(code, true, true)
		if clip == "" and code & 0x3fc00000:
			clip = pick(code & ~0x3fc00000, true, true)
	if clip.is_empty():
		clip = resolve(action, variant)
	return clip


var _resolved := {}

## --- the original animation database (res/database.res "<template>.adb", read
## ). Each clip has a code: weapon mask bits 0-14 (1 << weapon type)
## state 15-17, action 18-21, modifier 22-29 (idle: 1 Stay, 2 LookAround; walk:
## 1/2 limp; attack/hit/death: direction), stage 30-31 (0 unique, 1 start,
## 2 cycle, 3 end). Names from the original's own dumper.
const ST_NEUTRAL := 0
const ST_REST := 0x8000
const ST_ATTACK := 0x10000
const ST_WARRY := 0x20000     # kneeling (sneak)
const ST_LIE := 0x30000       # crawling
const AC_SPECIAL := 0x40000
const AC_ATTACK := 0x80000
const AC_CAST := 0xc0000
const AC_RUN := 0x100000
const AC_WALK := 0x140000
const AC_IDLE := 0x180000
const AC_DEATH := 0x1c0000
const AC_SUFFER := 0x200000
const AC_CROSS := 0x240000
const MOD_1 := 0x400000
const STAGE_START := 0x40000000
const STAGE_CYCLE := 0x80000000
const WEAPON_BIT := {"sword": 1, "axe": 2, "dagger": 4, "spear": 8, "hammer": 16, "bow": 32, "crossbow": 64}
const _ACTION_CODE := {"idle": AC_IDLE, "walk": AC_WALK, "run": AC_RUN, "crawl": AC_WALK,
	"attack": AC_ATTACK, "cast": AC_CAST, "hit": AC_SUFFER, "death": AC_DEATH}

## Native village607a20: unhuma picks one of four speaking/listening
## specials; other templates use 1/2. 518fc0 matches only action/modifier,
## taking the first record, without the combat-state/weapon idle fallback.
const DIALOGUE_SPEAK := [1, 6, 7, 8]
const DIALOGUE_LISTEN := [2, 10, 12, 13]
var _dialogue_active := false
var _dialogue_clip := ""


func dialogue_clip(speaking: bool, special := 0) -> String:
	if special < 1:
		special = (DIALOGUE_SPEAK if speaking else DIALOGUE_LISTEN).pick_random() \
			if template.to_lower() == "unhuma" else 1 if speaking else 2
	for e: Dictionary in adb:
		if int(e.code) & 0x3c0000 == AC_SPECIAL and int(e.code) & 0x3fc00000 == special * MOD_1 \
				and has_anim(e.name):
			return e.name
	return ""


func begin_dialogue(speaking: bool, special := 0) -> bool:
	var clip := dialogue_clip(speaking, special)
	if clip.is_empty() or player == null:
		end_dialogue()
		return false
	_dialogue_active = true
	_dialogue_clip = clip
	play(clip, 0.1, true)
	return true


func end_dialogue() -> void:
	var held := _dialogue_active and _current == _dialogue_clip
	_dialogue_active = false
	_dialogue_clip = ""
	if held:
		act("idle", 1, 0.1)

static var _adbs := {}
## [{name, code, weight, speed}] for this template; empty = no database (old name rules).
var adb: Array = []
## The.adb height factor at this unit's height (height_scale).
var height_k := 1.0
## Set by the unit before act(): state bits, walk modifier (limp).
var pose_state := ST_ATTACK
var pose_mod := 0
var neutral := false
var movement_starts := false  # original character type 0x32
var _cycle := -1      # code of the playing cycle clip (re-picked when it wraps)
var _cycle_pos := 0.0


## the original: the.adb header's height factor, (h * (c28 - c20) +
## c20) / c24 at the unit's height complexion (1 without a database). The root
## part's translation keys are scaled by it.
static func height_scale(tmpl: String, h: float) -> float:
	var arc := EIResArchive.open_path(GameData.root.path_join("res/database.res")) if GameData.root != "" else null
	var b := arc.read(tmpl + ".adb") if arc else PackedByteArray()
	if b.size() < 0x2c or b.decode_float(0x24) == 0.0:
		return 1.0
	return (h * (b.decode_float(0x28) - b.decode_float(0x20)) + b.decode_float(0x20)) / b.decode_float(0x24)


static func load_adb(tmpl: String) -> Array:
	if _adbs.has(tmpl):
		return _adbs[tmpl]
	var out := []
	var arc := EIResArchive.open_path(GameData.root.path_join("res/database.res")) if GameData.root != "" else null
	var b := arc.read(tmpl + ".adb") if arc else PackedByteArray()
	if b.size() >= 0x2c and b.slice(0, 3).get_string_from_ascii() == "ADB":
		var n := b.decode_u32(4)
		for i in n:
			var p := 0x2c + i * 88
			if p + 88 > b.size():
				break
			out.append({"name": b.slice(p, p + 16).get_string_from_ascii(),
				"code": b.decode_u32(p + 20), "weight": b.decode_s32(p + 28),
				"speed": b.decode_float(p + 0x24)})
	_adbs[tmpl] = out
	return out


## the original (each drawn frame): the playback
## rate of a clip of the animation queue's mode 2 (unit, the walk / run
## starts and cycles), unit in keys per 55 ms tick =
## |spline tangent| x node speed (cells of 0.5 m a tick, terrain factor
## included) x 15 / (height factor x clip x 2), i.e.
## metres a tick x 15 / (H x clip): is the metres a second the
## clip covers at 15 keys a second at height factor 1. A clip = 0
## gets (1 for walk / run). Returns the factor on the normal
## rate (EIAnim.FPS keys a second) for `mps` metres a second, or 1 when the
## playing clip is not a walk / run clip.
func move_rate(mps: float) -> float:
	if not rate_scaling:
		return 1.0
	var e: Dictionary = _clip_records().get(_current, {})
	if e.is_empty() or not int(e.code) & 0x3c0000 in [AC_RUN, AC_WALK] or float(e.speed) == 0.0:
		return 1.0
	return mps * 15.0 / (height_k * float(e.speed) * EIAnim.FPS)


static var _by_name := {}
## Test switch (tools/anim_rate_test.gd --no-rate): every clip at the normal rate.
static var rate_scaling := true


func _clip_records() -> Dictionary:
	if not _by_name.has(template):
		var d := {}
		for e: Dictionary in adb:
			d[e.name] = e
		_by_name[template] = d
	return _by_name[template]


func weapon_bit() -> int:
	return WEAPON_BIT.get(weapon_type, 0)


## True when the database has relaxed (neutral) stand clips: humans and orcs.
## Monsters only have combat-state clips (the original: units of type != 0x32 always
## use the attack state).
func has_neutral() -> bool:
	return neutral


func _has_neutral() -> bool:
	for e: Dictionary in adb:
		if int(e.code) & 0x3f8000 == AC_IDLE | ST_NEUTRAL:
			return true
	return false


## exact code, then unarmed, then (rest state) neutral / attack
## then with `fallback` any clip of the same state/action/modifier/stage.
func pick(code: int, fallback := true, any_mod := false) -> String:
	var r := _match(code, any_mod)
	if r == "":
		r = _match(code & 0xffff8000, any_mod)
	if r == "" and code & 0x38000 == ST_REST:
		r = _match(code & 0xfffc0000, any_mod)
		if r == "":
			r = _match(code & 0xfffd0000 | ST_ATTACK, any_mod)
	if r == "" and fallback:
		var c := []
		for e: Dictionary in adb:
			if _same(int(e.code), code, any_mod) and has_anim(e.name):
				c.append(e.name)
		if not c.is_empty():
			r = c.pick_random()
	return r


func _same(a: int, b: int, any_mod: bool) -> bool:
	return (a ^ b) & (0xc03f8000 if any_mod else 0xffff8000) == 0


## the query's weapon bits must all be in the clip's mask (an
## unarmed query only takes unarmed clips); of several, one roll 0-99 drops
## the clips whose weight is below it, then a uniform pick (the first uniform
## pick stays when none is left).
func _match(q: int, any_mod: bool) -> String:
	var c := []
	for e: Dictionary in adb:
		var code: int = e.code
		var miss := code if q & 0x7fff == 0 else ~code & q
		if miss & 0x7fff == 0 and _same(code, q, any_mod) and has_anim(e.name):
			c.append(e)
	if c.is_empty():
		return ""
	if c.size() == 1:
		return c[0].name
	var roll := randi() % 100
	var first: Dictionary = c.pick_random()
	var kept := c.filter(func(e): return int(e.weight) >= roll)
	return (kept.pick_random() if not kept.is_empty() else first).name


## The original's query for a logical action (idle
## walk/run, attack, cast, hit/death).
func code_for(action: String) -> int:
	var st := pose_state
	if action == "crawl":
		st = ST_LIE
	if action == "run" and st & ST_WARRY:
		action = "walk"     # no running on knees or crawling (posture 3 = standing run)
	var code: int = _ACTION_CODE[action] | st | weapon_bit()
	match action:
		"idle": code |= STAGE_CYCLE | MOD_1
		"walk", "run", "crawl": code |= STAGE_CYCLE | pose_mod
	return code


## Stance change clip: from-state | cross | target modifier
## (1 neutral, 2 attack, 3 kneel, 4 crawl, 5 rest); `resume` plays after it.
const _CROSS_TO := {ST_NEUTRAL: 1, ST_ATTACK: 2, ST_WARRY: 3, ST_LIE: 4, ST_REST: 5}
var _resume := ""
var _resume_clip := ""  # cycle selected together with a movement start


func cross(from_st: int, to_st: int, resume: String) -> float:
	if _dialogue_active and resume == "idle":
		return 0.0
	if adb.is_empty() or not _CROSS_TO.has(to_st):
		return 0.0
	var clip := pick(weapon_bit() | from_st | AC_CROSS | _CROSS_TO[to_st] * MOD_1)
	if clip == "":
		return 0.0
	_play(clip, 0.1, true)
	_cycle = code_for(resume) if _ACTION_CODE.has(resume) else -1
	_cycle_pos = 0.0
	_resume = resume
	_resume_clip = ""
	return player.get_animation("ei/" + clip).length


func _process(_dt: float) -> void:
	# Native callback6023f0 resumes a listening special after each special
	# finishes. This keeps the Old Dragon in its authored grounded clips
	# throughout the conversation instead of falling back to flying idle.
	if _dialogue_active and _current == _dialogue_clip and player and not player.is_playing():
		begin_dialogue(false)
		return
	if _resume != "" and player and not player.is_playing():
		var r := _resume
		var clip := _resume_clip
		_resume = ""
		_resume_clip = ""
		_cycle_pos = 0.0
		if clip != "":
			_play(clip, 0.0, true)
		else:
			_cycle = -1
			act(r)
		return
	if _resume != "":
		return
	# A cycle clip that wrapped around picks again (the idle variants).
	if _cycle < 0 or player == null or not player.is_playing():
		return
	var t := player.current_animation_position
	if t < _cycle_pos and _cycle & 0x3c0000 == AC_IDLE:
		var clip := pick(_cycle)
		if clip != "" and clip != _current:
			_play(clip, 0.3)
	_cycle_pos = t


func resolve(action: String, variant := 1) -> String:
	var key := "%s%d" % [action, variant]
	if not _resolved.has(key):
		_resolved[key] = _resolve(action, variant)
	return _resolved[key]


func _resolve(action: String, variant := 1) -> String:
	var prefixes := ["c", "u", "s", "b"]
	for pre in prefixes:
		for name in ["%s%s%02d" % [pre, action, variant], "%s%s" % [pre, action], "%s%s01" % [pre, action]]:
			if has_anim(name):
				return name
	for a in anim_names():
		if a.substr(1).begins_with(action):
			return a
	return ""


func has_anim(anim: String) -> bool:
	return player != null and player.has_animation("ei/" + anim)


func anim_names() -> PackedStringArray:
	var out := PackedStringArray()
	if player:
		for a in player.get_animation_list():
			out.append(a.trim_prefix("ei/"))
	return out


func _build(model: Dictionary, unit: Dictionary, proto: Dictionary, race: Dictionary, ui_preview := false, initial_action := true) -> void:
	var db := GameData.db
	var complexion: Vector3 = unit.get("complexion", Vector3.ZERO)
	if complexion == Vector3.ZERO and not unit.get("effective_complexion", false):   # absent map override
		complexion = GameUnit.proto_complexion(proto)
	set_meta("complexion", complexion)
	var mask := String(race.get("mask", template)).to_lower()
	var parts: Dictionary = model.parts

	# --- which mesh goes on which part
	var mesh_for := {}  # part -> fig part name
	var body_parts: PackedStringArray = unit.get("parts", PackedStringArray())
	for link: Array in model.links:
		var p: String = link[0]
		if "." in p:
			continue
		# Without the map's part list only the body gets meshes; weapon and
		# armour variants are added below from what the unit carries.
		if p in body_parts or (body_parts.is_empty() and _is_body_part(p, model)):
			mesh_for[p] = p
	# Goblins carry an authored natural weapon rather than an inventory item.
	# The ranged prototype keeps its sling; the other prototypes keep the pike.
	if template == "unmogo":
		var ranged := int(proto.get("weapon_type_id", -1)) == 5
		mesh_for.erase("rh3.axeth00")
		mesh_for.erase("rh3.sword00")
		mesh_for.erase("rh3.pike00" if ranged else "sling")
		var natural := "sling" if ranged else "rh3.pike00"
		if parts.has(natural) and (body_parts.is_empty() or natural in body_parts):
			mesh_for[natural] = natural
	# The lizard's trident is part of its authored figure, with no inventory
	# weapon entry. The generic dotted-variant filter otherwise drops it.
	if template == "unmoli" and parts.has("rh3.trident") \
			and (body_parts.is_empty() or "rh3.trident" in body_parts):
		mesh_for["rh3.trident"] = "rh3.trident"
	var layers: Array[String] = []
	var surfaces: Array[Vector3] = []
	#  formats the prototype's skin index directly. The race's
	# texture list is incomplete (e.g. unhuma has 29 entries but skins 0..36).
	# An absent prototype alone uses skin 00.
	var skin_i: int = proto.get("skin", 0)
	var skin := "skin_%02d" % skin_i
	if not race.is_empty() and int(race.get("type_id", 0)) != 0x32:
		# Creature figures use named textures (e.g. Wolf00), not redress skins.
		# The redress is for characters (race
		# type 0x32) only; a creature keeps its map record's texture (0xB007,
		# record): WolfWhite* "wolf01", BoarDark* "boar01", though every
		# wolf / boar prototype has skin 0. Without a record: the race list.
		var skins: PackedStringArray = race.get("textures", PackedStringArray())
		skin = skins[skin_i] if skin_i >= 0 and skin_i < skins.size() else (skins[0] if skins.size() else "")
		if String(unit.get("texture", "")) != "":
			skin = String(unit.texture)
	layers.append(skin.to_lower())
	surfaces.append(SurfaceResponse.SKIN)

	# Hair is a variant under the head ("hr.00".."hr.02" = prototype hair
	# 0..2); there is no base "hr" part. A helmet selects its armoured variant
	# if present, otherwise hides the hair.
	var hair_part := "hr.%02d" % int(unit.get("hair", proto.get("hair", 0)))
	if not parts.has(hair_part):
		hair_part = ""

	var wears: Array = Array(unit.get("armors", PackedStringArray()))
	if not unit.has("armors"):
		wears = Array(proto.get("wears", PackedStringArray()))
	var armors := []
	var helm_layer := ""
	var helm_surface := SurfaceResponse.DULL
	var helm_parts := {}
	for w: String in wears:
		var nm := w.get_slice("@", 0).get_slice("|", 0).split(".")
		var a := db.find("armors", nm[0])
		if a.is_empty():
			continue
		armors.append([a, db.find("materials", nm[1] if nm.size() > 1 else "")])
	armors.sort_custom(func(x, y):
		var xi := ARMOR_ORDER.find(x[0].type)
		var yi := ARMOR_ORDER.find(y[0].type)
		if xi in [4, 5] and yi in [4, 5]:
			#  field 0x18 -> record
			# returns a uint and compares it with JAE.
			var xp := int(x[0].get("layer_order", 0))
			var yp := int(y[0].get("layer_order", 0))
			if xp != yp:
				return xp < yp
		return xi < yi)
	for am: Array in armors:
		var a: Dictionary = am[0]
		var t1: int = a.get("texture1", -1)
		if t1 < 0 or not ARMOR_PREFIX.has(a.type):
			continue
		var layer := "%s_%02d.%s.%d" % [ARMOR_PREFIX[a.type], t1, am[1].get("code", ""), a.get("texture2", 0)]
		if a.type == "helm":
			# The 128 px helm atlas is separate from the 256 px body atlas
			# . Stretching it over the body paints the arms / face.
			helm_layer = layer
			helm_surface = SurfaceResponse.equipment(am[1])
			#  ("hr", "hd" row 2): the helmet is
			# added under the head, preserving the face. Hair is replaced by
			# its armoured variant, or removed when the figure has none.
			var helm := "hd.armor%02d" % t1
			if parts.has(helm):
				mesh_for[helm] = helm
				helm_parts[helm] = true
			if hair_part:
				var armored_hair := hair_part + ".armor%02d" % t1
				hair_part = armored_hair if parts.has(armored_hair) else ""
			continue
		layers.append(layer)
		surfaces.append(SurfaceResponse.equipment(am[1]))
		for p: String in ARMOR_PARTS.get(a.type, []):
			var v := "%s.armor%02d" % [p, t1]
			if parts.has(v):
				mesh_for[p] = v

	#  secondary 128 px atlas contains the helmet, then the
	# active weapon, with no skin or clothing from the 256 px body atlas.
	var weapon_layer := ""
	var weapon_surface := SurfaceResponse.DULL
	var before := mesh_for.duplicate()
	# Weapon meshes ("rh3.dagger01", "lh3.bwpartb01") are the weapon alone:
	# the original draws them in addition to the hand (its fist grips the
	# handle), unlike armour variants, which replace the part's mesh.
	var held := {}   # part -> weapon fig part
	var weapons: Array = Array(unit.get("weapons", PackedStringArray()))
	if not unit.has("weapons") and String(proto.get("weapon", "")) != "":
		weapons = [proto.weapon]
	for w: String in weapons.slice(0, 1):
		var nm := w.get_slice("@", 0).get_slice("|", 0).split(".")
		var wd := db.find("weapons", nm[0])
		if wd.is_empty():
			continue
		weapon_type = wd.type
		var t1: int = wd.get("texture1", 1)
		var mat := db.find("materials", nm[1] if nm.size() > 1 else "")
		weapon_surface = SurfaceResponse.equipment(mat)
		if WEAPON_PREFIX.has(wd.type):
			weapon_layer = ("%s_%02d.%s.%d" % [WEAPON_PREFIX[wd.type], t1, mat.get("code", ""), wd.get("texture2", 0)])
		if WEAPON_MESH.has(wd.type):
			for idx in [t1, t1 - 1]:   # "%02d" of the weapon record (texture1)
				var v: String = WEAPON_MESH[wd.type] % idx
				if parts.has(v):
					held["rh3"] = v
					break
		elif wd.type == "bow":
			for idx in [t1, t1 - 1]:   # "%02d" of the weapon record (texture1)
				if parts.has("lh3.bwpartb%02d" % idx):
					held["lh3"] = "lh3.bwpartb%02d" % idx
					for extra in ["bwparta%02d", "bwtetivaa%02d", "bwtetivab%02d"]:
						if parts.has(extra % idx):
							mesh_for[extra % idx] = extra % idx
					break
		if wd.type == "crossbow":
			for extra in ["crbow%02dpart01", "crbow%02dpart02", "crbow%02dtetiva01", "crbow%02dtetiva02"]:
				if parts.has(extra % t1):
					mesh_for[extra % t1] = extra % t1

	var weapon_parts := {}
	for p: String in mesh_for:
		if before.get(p, "") != mesh_for[p]:
			weapon_parts[p] = true
	# Weapon variants live below animated mount nodes in the original LNK.
	# For example rh3 -> rh3.sword00 -> rh3.dagger03: sword00 supplies both
	# a BON offset and an ANM track. Attaching the blade directly to rh3 puts
	# its handle through the wrist and discards the weapon's animation.
	for p: String in held:
		mesh_for[held[p]] = held[p]
		weapon_parts[held[p]] = true

	var mat = _material(ui_preview, mask == "unmowi")
	mat.albedo_texture = _compose(mask, layers)
	if mat is LitMaterial:
		mat.set_shader_parameter("surface_tex", _compose_surface(mask, layers, surfaces))
	set_meta("layers", [mask, layers])
	var secondary: Array[String] = []
	var secondary_surfaces: Array[Vector3] = []
	if helm_layer:
		secondary.append(helm_layer)
		secondary_surfaces.append(helm_surface)
	if weapon_layer:
		secondary.append(weapon_layer)
		secondary_surfaces.append(weapon_surface)
	var wmat = mat
	var hmat = mat
	if not secondary.is_empty():
		wmat = mat.duplicate()
		wmat.albedo_texture = _compose(mask, secondary)
		if wmat is LitMaterial:
			wmat.set_shader_parameter("surface_tex", _compose_surface(mask, secondary, secondary_surfaces))
		hmat = wmat.duplicate()

	# --- node hierarchy (base parts + extras that have meshes)
	var weld: bool = smooth_joints and bool(unit.get("weld", true))
	var morphs := EIAnim.morphs(template)
	var nodes := {}
	var geometry_parts: Array[WeakRef] = []
	set_meta(EIFigureGeometry.PARTS, geometry_parts)
	var paths := {}
	var root_part := ""
	var rest_pos := {}      # part -> position in the model at rest (no rotations)
	var parent_of_node := {}
	var welded := {}        # part -> ArrayMesh in part space
	var lighting_parts := {}   # per-build native material variants
	var parent_of := {}
	var needed := {}
	for link: Array in model.links:
		parent_of[link[0]] = link[1]
		if not "." in link[0] and _is_body_part(link[0], model):
			needed[link[0]] = true
	for p: String in mesh_for:
		var ancestor := p
		while ancestor != "":
			needed[ancestor] = true
			ancestor = parent_of.get(ancestor, "")
	for link: Array in model.links:
		var p: String = link[0]
		if not needed.has(p):
			continue
		var n := AnimatedPart.new()
		n.name = p.replace(".", "_")
		var bone: PackedFloat32Array = model.bones.get(p, PackedFloat32Array())
		if bone.size() >= 24:
			n.position = EISpace.vec(EIFigure.bone_pos(bone, complexion))
		var par_name := String(link[1])
		var parent: Node3D = nodes.get(par_name, self)
		if parent == self:
			root_part = p
			_animation_roots.append(n)
		else:
			parent_of_node[p] = par_name
			n.animation_parent = parent as EIAnimPart
			if n.animation_parent:
				n.animation_parent.animation_children.append(n)
		parent.add_child(n)
		nodes[p] = n
		rest_pos[p] = rest_pos.get(par_name, Vector3.ZERO) + n.position if parent != self else n.position
		if mesh_for.has(p):
			var fig: Dictionary = parts[mesh_for[p]]
			EIFigureGeometry.attach(n, fig, complexion, geometry_parts)
			# Parts with vertex morph keys (EIAnim.morphs: wing membranes and
			# the like) get them as blend shapes of a "morph" mesh.
			var morph: Dictionary = morphs.get(p, {}) if mesh_for[p] == p else {}
			var mesh := EIFigure.build_mesh(fig, complexion) if morph.is_empty() \
					else EIFigure.build_anim_morph_mesh(fig, complexion, morph.names, morph.frames)
			var part_mat: Material = wmat if weapon_parts.has(p) else (hmat if helm_parts.has(p) else mat)
			if not ui_preview:
				part_mat = FigureMaterial.part_material(part_mat, fig.get("material", 0), lighting_parts)
			if weld and morph.is_empty() and not weapon_parts.has(p) and not helm_parts.has(p):
				welded[p] = [mesh, part_mat]
				n.set_meta("weld_mesh", welded[p])   # SeveredLimb: the part's own mesh
				continue
			var mi := MeshInstance3D.new()
			if not morph.is_empty():
				mi.name = "morph"
				_morph_parts.append([mi, _morph_ranges(morph.names), PackedInt32Array()])
			mi.mesh = mesh
			mi.material_override = part_mat
			n.add_child(mi)
	if weld:
		_weld(nodes, rest_pos, parent_of_node, welded)

	if hair_part and nodes.has("hd"):
		var hn := Node3D.new()
		hn.name = "hr"
		var hb: PackedFloat32Array = model.bones.get(hair_part, PackedFloat32Array())
		if hb.size() >= 24:
			hn.position = EISpace.vec(EIFigure.bone_pos(hb, complexion))
		nodes["hd"].add_child(hn)
		EIFigureGeometry.attach(hn, parts[hair_part], complexion, geometry_parts)
		var hm := MeshInstance3D.new()
		hm.mesh = EIFigure.build_mesh(parts[hair_part], complexion)
		hm.material_override = hmat if helm_layer else mat
		if not ui_preview:
			hm.material_override = FigureMaterial.part_material(hm.material_override, parts[hair_part].get("material", 0), lighting_parts)
		hn.add_child(hm)

	# Remake option gfx_detailed_heads: the HUD face model on the body
	# (DetailedHead; not with a helmet or the welded body).
	if not weld and helm_layer == "" and nodes.has("hd") and mesh_for.get("hd", "") == "hd":
		var face := DetailedHead.face_names(proto, race, complexion,
			int(unit.get("hair", proto.get("hair", 0))))
		var head_mi: MeshInstance3D = null
		for c in (nodes["hd"] as Node3D).get_children():
			if c is MeshInstance3D:
				head_mi = c
				break
		if not face.is_empty() and head_mi:
			_detail = DetailedHead.attach(nodes["hd"], face, model, mask, hair_part, head_mi.mesh, ui_preview)
			if _detail:
				_plain_head = [head_mi]
				var hr := (nodes["hd"] as Node3D).get_node_or_null("hr")
				if hr:
					_plain_head.append(hr)
				add_to_group(&"detailed_heads")
				set_detailed_head(GameData.option("gfx_detailed_heads") != 0)

	player = AnimationPlayer.new()
	# The authored rig/library is fixed for this model's lifetime. Finishing
	# a movement-start or cross clip need not re-resolve every track in it.
	if ClassDB.class_has_method("AnimationPlayer", "set_preserve_track_caches_on_finish") \
			and not OS.get_cmdline_user_args().has("--ei-rebuild-animation-caches"):
		player.call("set_preserve_track_caches_on_finish", true)
	player.name = "AnimationPlayer"
	add_child(player)
	player.root_node = NodePath("..")
	if not _morph_parts.is_empty():
		player.mixer_applied.connect(_apply_morphs)
	# Track paths follow the full part hierarchy so one library fits every unit of this template.
	for p: String in parent_of:
		var chain := PackedStringArray([p.replace(".", "_")])
		var q: String = parent_of[p]
		while parent_of.has(q):
			chain.insert(0, q.replace(".", "_"))
			q = parent_of[q]
		paths[p] = NodePath("/".join(chain))
	adb = load_adb(template)
	height_k = height_scale(template, complexion.z)
	player.add_animation_library("ei", EIAnim.library(template, paths, root_part, height_k, true))
	neutral = _has_neutral()
	movement_starts = int(race.get("type_id", 0)) == 0x32
	pose_state = ST_NEUTRAL if neutral else ST_ATTACK
	if initial_action:
		act("idle", 1, 0.0)


## clip -> [first blend shape, frame count] of a morph mesh's shapes
## (EIAnim.morphs appends a clip's frames in order, named "<clip>_<k>").
static func _morph_ranges(names: PackedStringArray) -> Dictionary:
	var out := {}
	for i in names.size():
		var clip := names[i].substr(0, names[i].rfind("_"))
		if out.has(clip):
			out[clip][1] += 1
		else:
			out[clip] = [i, 1]
	return out


## The vertex morph of the playing clip, after every mixer pass: as the original
##  keys the frame by modf(clip time in keys), offsets of frames
## k and k + 1 blend by the fraction (the last frame holds), and only the
## current clip's track gives the part its offsets (copies the
##  track's buffer; drops them for a track with none).
## Every other shape is 0, so offsets never add up across clips.
func _apply_morphs() -> void:
	var anim := String(player.assigned_animation)
	var clip := anim.substr(anim.find("/") + 1)
	var f := 0.0
	if anim != "":
		f = maxf(player.current_animation_position * EIAnim.FPS, 0.0)
	for mp: Array in _morph_parts:
		var mi: MeshInstance3D = mp[0]
		var set_last: PackedInt32Array = mp[2]
		var now := PackedInt32Array()
		var w := PackedFloat32Array()
		var r: Array = mp[1].get(clip, [])
		if not r.is_empty():
			var first: int = r[0]
			var count: int = r[1]
			var k := int(f)
			if k + 1 < count:
				var t := f - k
				now.append_array([first + k, first + k + 1])
				w.append_array([1.0 - t, t])
			else:
				now.append(first + count - 1)
				w.append(1.0)
		for i in set_last:
			if not now.has(i):
				mi.set_blend_shape_value(i, 0.0)
		for j in now.size():
			mi.set_blend_shape_value(now[j], w[j])
		mp[2] = now


## UI previews have their own light and camera, and must not inherit the
## loaded map's depth / border fog. World figures share the cached Gfx shader.
## PreviewMaterial culls back faces as the original's render state.
static func _material(ui_preview: bool, soft_alpha := false) -> Material:
	var material: ShaderMaterial = PreviewMaterial.new() if ui_preview else LitMaterial.new()
	if not soft_alpha:
		return material
	# The authored wisp atlas is translucent throughout (maximum alpha119/255).
	# Ordinary unit cutouts discard every one of its texels, including in the HUD.
	if ui_preview:
		if _wisp_preview_shader == null:
			_wisp_preview_shader = Shader.new()
			_wisp_preview_shader.code = _soft_alpha(PREVIEW_SHADER)
		material.shader = _wisp_preview_shader
	else:
		if _wisp_unit_shader == null:
			_wisp_unit_shader = Gfx.make_shader(_soft_alpha(UNIT_SHADER))
		material.shader = _wisp_unit_shader
	return material


static func _soft_alpha(code: String) -> String:
	return code.replace(", alpha_to_coverage", "").replace("\tALPHA_SCISSOR_THRESHOLD = 0.5;\n", "") \
		.replace("\tALPHA_ANTIALIASING_EDGE = 0.3;\n", "") \
		.replace("\tALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));\n", "")


## Builds the skinned body (see `smooth_joints`): a flat Skeleton3D with one
## bone per part node, driven by the part nodes (BoneAttachment3D with
## override_pose, so the animation tracks and code that looks parts up by
## name keep working), and one mesh of all welded parts, one surface per
## material (the held weapon's hand has its own texture). Across each joint
## the weight ramps from the part's own bone to 0.5/0.5 at the joint plane,
## measured along the child bone's axis within `r`, so both sides of a joint
## converge on the same transform and overlapping ends (the forearm reaches
## ~5 mm into the fist in the data) move together instead of poking out.
func _weld(nodes: Dictionary, rest_pos: Dictionary, parent_of: Dictionary, welded: Dictionary) -> void:
	if welded.is_empty():
		return
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	add_child(skel)
	var bone_of := {}
	var skin := Skin.new()
	for p: String in nodes:
		var i := skel.add_bone(p)
		bone_of[p] = i
		var rest := Transform3D(Basis(), rest_pos[p])
		skel.set_bone_rest(i, rest)
		skel.set_bone_pose(i, rest)
		skin.add_named_bind(p, rest.affine_inverse())
	for p: String in nodes:
		var ba := nodes[p] as BoneAttachment3D
		ba.override_pose = true   # first, so setting the bone never moves the node
		ba.use_external_skeleton = true
		ba.external_skeleton = ba.get_path_to(skel)
		ba.bone_name = p
	var children := {}
	for c: String in parent_of:
		# Attachment mounts move weapons; they must not bend the hand mesh.
		if not welded.has(c) or not welded.has(parent_of[c]):
			continue
		if not children.has(parent_of[c]):
			children[parent_of[c]] = []
		children[parent_of[c]].append(c)
	# Joint of part c with its parent, in model rest space: position, axis
	# (c's own bone direction, pointing away from the parent), radius.
	var joints := {}
	for c: String in parent_of:
		var par: String = parent_of[c]
		if not welded.has(c) or not welded.has(par):
			continue
		var axis: Vector3 = rest_pos[c] - rest_pos[par]
		var kids: Array = children.get(c, [])
		if not kids.is_empty():
			axis = rest_pos[kids[0]] - rest_pos[c]
		var length := axis.length()
		joints[c] = [rest_pos[c], axis.normalized() if length > 1e-5 else Vector3.DOWN,
			clampf(length * 0.25, 0.02, 0.06)]
	var surf := {}   # material -> [pos, nrm, uv, bones, weights, idx]
	for p: String in welded:
		var mesh: ArrayMesh = welded[p][0]
		var m: Material = welded[p][1]
		if not surf.has(m):
			surf[m] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(),
				PackedInt32Array(), PackedFloat32Array(), PackedInt32Array()]
		var s: Array = surf[m]
		var arr := mesh.surface_get_arrays(0)
		# The joints this part takes part in: [joint, other bone, side] where
		# side = +1 if this part is the child (its body lies along +axis).
		var mine := []
		if joints.has(p):
			mine.append([joints[p], bone_of[parent_of[p]], 1.0])
		for c: String in children.get(p, []):
			mine.append([joints[c], bone_of[c], -1.0])
		var base: int = s[0].size()
		for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
			var mv: Vector3 = v + rest_pos[p]
			s[0].append(mv)
			var other: int = bone_of[p]
			var w := 0.0
			for jt: Array in mine:
				var j: Array = jt[0]
				var r: float = j[2]
				var rel: Vector3 = mv - j[0]
				var along: float = rel.dot(j[1]) * jt[2]   # > 0 inside this part
				if rel.length() > r * 4.0:   # far from the joint (other side of the torso)
					continue
				var d := maxf(along, 0.0)
				if d < r:
					var jw := 0.5 * (1.0 - d / r)
					if jw > w:
						w = jw
						other = jt[1]
			s[3].append_array([bone_of[p], other, 0, 0])
			s[4].append_array([1.0 - w, w, 0.0, 0.0])
		s[1].append_array(arr[Mesh.ARRAY_NORMAL])
		s[2].append_array(arr[Mesh.ARRAY_TEX_UV])
		for i: int in arr[Mesh.ARRAY_INDEX]:
			s[5].append(base + i)
	var body := ArrayMesh.new()
	var mats := []
	for m: Material in surf:
		var s: Array = surf[m]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s[0]
		arrays[Mesh.ARRAY_NORMAL] = s[1]
		arrays[Mesh.ARRAY_TEX_UV] = s[2]
		arrays[Mesh.ARRAY_BONES] = s[3]
		arrays[Mesh.ARRAY_WEIGHTS] = s[4]
		arrays[Mesh.ARRAY_INDEX] = s[5]
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mats.append(m)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = body
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
	skel.add_child(mi)
	mi.skin = skin
	mi.skeleton = NodePath("..")


## Option gfx_detailed_heads: the HUD face model in place of the original
## head and hair (only figures DetailedHead could fit one to).
func set_detailed_head(on: bool) -> void:
	if _detail == null:
		return
	_detail.visible = on
	for n in _plain_head:
		n.visible = not on


func has_detailed_head() -> bool:
	return _detail != null


func detailed_head_shown() -> bool:
	return _detail != null and _detail.visible


## Gfx.apply_env (group "detailed_heads"): follows the option.
func refresh_detailed_head() -> void:
	set_detailed_head(GameData.option("gfx_detailed_heads") != 0)


## Shows or hides a part and everything below it (severed limbs). The welded
## body has no per-part mesh, so the part is also shrunk to its joint.
func set_part_visible(part: String, on: bool) -> void:
	var n := find_child(part, true, false) as Node3D
	if n == null:
		return
	n.visible = on
	n.scale = Vector3.ONE if on else Vector3.ONE * 0.001


## Body parts are the non-variant parts that have bones; weapon/armor extras
## (bows, quivers, shells) are only created when worn.
static func _is_body_part(p: String, model: Dictionary) -> bool:
	return model.parts.has(p) and not (p.begins_with("bw") or p.begins_with("crbow")
		or p.begins_with("base") or p in ["arrows", "quiver", "l_shell", "r_shell"])


static func _compose(mask: String, layers: Array[String]) -> Texture2D:
	var key := mask + "|" + "|".join(layers)
	if _textures.has(key):
		return _textures[key]
	var base: Image = null
	for i in layers.size():
		var img := _load_layer(mask, layers[i])
		if img == null:
			continue
		if base == null:
			base = img
			continue
		if img.get_size() != base.get_size():
			img.resize(base.get_width(), base.get_height(), Image.INTERPOLATE_BILINEAR)
		base.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	var tex: Texture2D = null
	if base:
		var wound_source := base.duplicate() as Image
		base.generate_mipmaps()
		tex = ImageTexture.create_from_image(base)
		tex.set_meta(UnitWounds.SOURCE_IMAGE, wound_source)
	_textures[key] = tex
	return tex


static func _load_layer(mask: String, layer: String) -> Image:
	var d := GameData.redress.read(mask + layer + ".mmp")
	if d.is_empty():
		d = GameData.textures.read(layer + ".mmp")
	return EIMmp.decode(d) if not d.is_empty() else null


## Independent texture ownership is intentional: UnitWounds changes albedo,
## and OrderMarks duplicates the material, without replacing its redress mask.
## Profiles are part of the key because bone and bronze both use code "br".
static func _compose_surface(mask: String, layers: Array[String], profiles: Array[Vector3]) -> Texture2D:
	var key := mask + "|" + "|".join(layers) + "|" + str(profiles)
	if _surface_textures.has(key):
		return _surface_textures[key]
	var base: Image = null
	for i in layers.size():
		var layer := _load_layer(mask, layers[i])
		if layer == null:
			continue
		if base == null:
			base = Image.create(layer.get_width(), layer.get_height(), false, Image.FORMAT_RGBA8)
			base.fill(Color(SurfaceResponse.SKIN.x, SurfaceResponse.SKIN.y, SurfaceResponse.SKIN.z))
		var profile: Vector3 = profiles[i] if i < profiles.size() else SurfaceResponse.DULL
		SurfaceResponse.blend_layer(base, layer, profile)
	var texture: Texture2D = null
	if base:
		base.generate_mipmaps()
		texture = ImageTexture.create_from_image(base)
	_surface_textures[key] = texture
	return texture

class_name FxTypes
extends RefCounted
## Per-type setup and callbacks of the original particle types, ported from
## the original: Create (jump table) and the spawn / update
## control callbacks it installs (addresses in the comments). Values and
## tables are the original's; summarises them.
## Callbacks take the emitter `e` and a particle `p` (FxEmitter layout) or a
## control point `c`. Frames are ints, colours ARGB ints.

const W := FxEmitter.WHITE
const RGB := 0xffffff
const TAU_ := 6.2831855
const DEG := PI / 180.0

## Script name table (name -> type, the unknown param in the comment).
const NAMES := {
	"fireball": 0x2000, "campfire": 0x2001, "fireblast": 0x2002, "fire": 0x2003, "smoke": 0x2004,
	"vulcansmoke": 0x2005, "healing": 0x2006, "poisonfog": 0x2007, "geyser": 0x2009, "tornado": 0x200a,
	"casting": 0x200b, "nuke": 0x200c, "mushroom": 0x200e, "firearrow": 0x2011, "acidray": 0x2012,
	"bluegas": 0x2013, "link": 0x2014, "sphereacid": 0x2015, "sphereelectricity": 0x2016,
	"spherefire": 0x2017, "clayring": 0x2018, "teleport": 0x2019, "antimagic": 0x201a,
	"modifier1": 0x201b, "modifier2": 0x201c, "modifier3": 0x201d, "modifier4": 0x201e,
	"modifier5": 0x201f, "modifier6": 0x2020, "modifier7": 0x2021, "modifier8": 0x2022,
	"modifier9": 0x2023, "modifier10": 0x2024, "modifier11": 0x2025, "modifier12": 0x2026,
	"castingfire": 0x2027, "castingelectricity": 0x2028, "castingacid": 0x2029,
	"castingdivination": 0x202a, "castingillusion": 0x202b, "castingdomination": 0x202c,
	"castingenchantment": 0x202d, "castinghealing": 0x202e, "lightningblast": 0x2030,
	"zoneexit": 0x2038, "portalstar": 0x203d, "portal": 0x203e, "cylinder1": 0x203f,
	"cylinder2": 0x2040, "firestar": 0x2041, "acidstar": 0x2042, "sparks": 0x2043,
	"visionstar1": 0x2044, "visionstar2": 0x2045, "visionstar3": 0x2046, "regeneration": 0x2047,
	"silence": 0x2048, "feeblemind": 0x2049, "feetcloud1": 0x204a, "feetcloud2": 0x204b,
	"cursestars": 0x204f, "curseholder": 0x2050, "starttrans": 0x2051, "transform": 0x2052,
}

## Tables read from the original.rdata.
const T_EXPL_A := [255, 255, 207, 175, 128, 128, 128, 128, 128, 175, 207, 192, 128, 48, 0, 0]
const T_ACID_R := [0.0, 0.85, 0.93, 1.0, 0.97, 0.93, 0.87, 0.8, 0.73, 0.65, 0.55, 0.43, 0.3, 0.2, 0.0, 0.0]
const T_ACID_S := [1.1, 0.85, 0.93, 1.0, 0.97, 0.93, 0.87, 0.8, 0.73, 0.65, 0.55, 0.43, 0.3, 0.2, 0.0, 0.0]
const T_BLOOD_A := [0, 64, 128, 192, 255, 255, 255, 255]
const T_CLAY_IN := [0.0, 0.025, 0.056, 0.092, 0.136, 0.188, 0.251, 0.326, 0.417, 0.525, 0.656, 0.812, 1.0, 1.0, 1.0]  #  (reads it backwards)
const T_CLAY_A := [0, 128, 255, 255, 255, 255, 255, 255, 255, 160, 80, 32, 0, 0, 0, 0]
const T_MOD_IN := [0, 32, 64, 128, 255, 255, 255, 255, 255, 255, 255, 128, 0, 0, 0, 0]
const T_MOD_OUT := [0, 128, 255, 255, 255, 255, 255, 255, 192, 128, 64, 32, 0, 0, 0, 0]
const T_CAST_A := [0, 255, 255, 255, 255, 255, 255, 255, 224, 192, 128, 64, 32, 16, 0, 0]
const T_CAST_DIV := [0, 32, 64, 112, 160, 208, 255, 255, 224, 192, 128, 64, 32, 16, 0, 0]
const T_CAST_CTL := [0, 32, 64, 112, 160, 208, 255, 0, 32, 64, 112, 160, 208, 255]
const T_BOLT_A := [0, 80, 176, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255]
const T_PATH_A := [0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
const T_TARGET_A := [0, 64, 144, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 128, 64]
const T_TARGET_DX := [0.707, -0.707, -0.707, 0.707]
const T_TARGET_DY := [0.707, -0.707, 0.707, -0.707]
const T_EXIT_A := [0, 80, 176, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 128, 64]
const T_SPARK_A := [0, 64, 128, 255, 255, 255, 255, 255]
const T_FADE_IN := [0, 32, 64, 128, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255]
const T_SPHERE := [0.01, 0.02, 0.03, 0.035, 0.035, 0.035, 0.035, 0.035, 0.035, 0.035, 0.035, 0.035, 0.035, 0.03, 0.02, 0.01]
const T_ANTIMAGIC := [0.01, 0.015, 0.02, 0.03, 0.015, 0.01, 0.5, 0.3]
## the orbiter trail alpha of 202b..202e (= index + 1).
const T_ORBIT_A := [0, 0, 32, 64, 112, 160, 208, 255]


# ------------------------------------------------------------------ helpers

static func rnd(e: FxEmitter) -> int:
	return e.rnd()


static func u01(e: FxEmitter) -> float:
	return float(e.rnd()) * 2.3283064e-10


static func u2(e: FxEmitter) -> float:
	return float(e.rnd()) * 4.656613e-10 - 1.0


## uniform in [a, b].
static func rr(e: FxEmitter, a: float, b: float) -> float:
	return a + (b - a) * u01(e)


## The original's 10-try rejection loop for a point in the unit ball.
static func ball(e: FxEmitter) -> Vector3:
	var v := Vector3.ZERO
	for i in 10:
		v = Vector3(u2(e), rr(e, -1.0, 1.0), rr(e, -1.0, 1.0))
		if v.length_squared() < 1.0:
			break
	return v


static func setp(p: Array, v: Vector3) -> void:
	p[0] = v.x
	p[1] = v.y
	p[2] = v.z


static func getp(p: Array) -> Vector3:
	return Vector3(p[0], p[1], p[2])


static func setv(p: Array, i: int, v: Vector3) -> void:
	p[i] = v.x
	p[i + 1] = v.y
	p[i + 2] = v.z


static func getv(p: Array, i: int) -> Vector3:
	return Vector3(p[i], p[i + 1], p[i + 2])


static func alpha(a: int, rgb := RGB) -> int:
	return (clampi(a, 0, 255) << 24) | rgb


static func a_of(p: Array) -> int:
	return (int(p[0x16]) >> 24) & 0xff


static func tab(t: Array, i: int) -> Variant:
	return t[clampi(i, 0, t.size() - 1)]


## the carrier's centre offset (z) and radius.
static func carrier_size(e: FxEmitter) -> Vector2:
	if not e.has_carrier:
		return Vector2(0.0, 0.1)
	return e.fx.carrier_size(e.carrier)


# ------------------------------------------------------------------ create

## Create for `type`; null for types the remake does not draw.
static func create(fx, type: int) -> FxEmitter:
	var e := FxEmitter.new()
	e.fx = fx
	e.rng.seed = fx.rnd()
	e.type = type
	#  defaults, then the Create base values.
	e.e0 = 4
	e.cc = 100
	e.d8 = 500
	e.flags = FxEmitter.F_EMIT
	e.dc = 16
	var T = fx.types
	match type:
		0x2000:
			e.ec = 15; e.dc = 15; e.vmin = Vector3(-0.2, -0.2, -1.0); e.vmax = Vector3(0.2, 0.2, 0.0)
			e.cc = 88; e.d0 = 1; e.d4 = 0.09; e.e4 = 1; e.s = 0.8; e.m114 = 0.94
			e.spawn_fn = T.sp_fireball; e.upd_fn = T.up_fireball
			e.texture = "firesmoke"
		0x2001, 0x2003, 0x2004, 0x2010:
			e.vmin = Vector3(-0.2, -0.2, 0.0); e.vmax = Vector3(0.2, 0.2, 0.0); e.cc = 88; e.d0 = 6
			e.ec = 32; e.dc = 15; e.e4 = 1; e.s = 0.8; e.a110 = 0.3; e.m114 = 0.85
			e.spawn_fn = T.sp_fire; e.upd_fn = T.up_fire
			if type == 0x2010:
				e.d0 = 20; e.d8 = 1500
				e.set_controls(1)
				e.spawn_fn = T.sp_firewall; e.ctl_fn = T.ct_firewall
			e.texture = "tendrismoke"
		0x2002:
			e.vmin = Vector3(-0.02, -0.02, -0.02); e.vmax = Vector3(0.02, 0.02, 0.02); e.cc = 100
			e.d0 = 60; e.d8 = 600; e.ec = 15; e.e4 = 1; e.s = 0.6; e.a110 = 1.0; e.m114 = 0.8
			e.spawn_fn = T.sp_blast; e.upd_fn = T.up_blast; e.ctl_fn = T.ct_blast
			e.texture = "explosion"
			e.set_controls(15)
			for c: Array in e.cp:
				var d := Vector3.ZERO
				var l := 1.0
				for i in 10:
					d = Vector3(u2(e), rr(e, -1.0, 1.0), rr(e, -1.0, 1.0) + 0.7)
					l = d.length_squared()
					if l < 1.0:
						break
				d = d / maxf(sqrt(l), 0.0001)
				var k := float(e.rnd()) * 9.313226e-11 + 0.8
				c[3] = d.x * k * 0.8
				c[4] = d.y * k * 0.8
				c[5] = d.z * k * 0.8
				c[0xc] = 0
				c[6] = 0.0
				c[7] = 0.4
				c[8] = 0.7
				c[9] = float(e.rnd() % 6)
				c[0xa] = float(e.rnd() & 1)
		0x2006:
			e.add = 1; e.flags |= 3; e.d0 = 0x7fffffff; e.ec = 8; e.e4 = 1; e.s = 0.5
			e.spawn_fn = T.sp_healing; e.upd_fn = T.up_healing; e.ctl_fn = T.ct_healing
			e.texture = "healing"
		0x2007, 0x2008:
			e.cc = 50; e.d0 = 1; e.d8 = 0x7fffffff; e.ec = 0xca4; e.dc = 15; e.e4 = 1
			e.spawn_fn = T.sp_fog; e.upd_fn = T.up_fog
			e.texture = "poisoncloud"
		0x2009:
			e.vmin = Vector3(-0.1, -0.1, -0.02); e.vmax = Vector3(0.1, 0.1, 0.02); e.cc = 88; e.d0 = 20
			e.e4 = 100; e.a110 = 0.3
			e.set_controls(3)
			e.spawn_fn = T.sp_fireworks; e.upd_fn = T.up_fireworks; e.ctl_fn = T.ct_fireworks
			e.texture = "fireworks"; e.add = 1
		0x200a:
			# Create: colour = alpha 0x19, rgb = the light
			#  (.. × 255; taken as the sun, Gfx.sun); six
			# control points up the funnel at z = i · 12 · 0.2, control 0
			#  = 12 (height), = 0.5 (lean), = 0.99 (radius
			# factor per tick).
			e.cc = 100; e.d0 = 4; e.d8 = 800; e.a110 = 0.2
			var sun: Color = Gfx.sun
			e.e4 = (0x19 << 24) | (int(sun.r * 255.0) & 0xff) << 16 | (int(sun.g * 255.0) & 0xff) << 8 \
				| (int(sun.b * 255.0) & 0xff)
			e.set_controls(6)
			for i in 6:
				e.cp[i][2] = float(i) * 12.0 * 0.2
			e.cp[0][9] = 12.0; e.cp[0][0xa] = 0.5; e.cp[0][0xb] = 0.99
			e.spawn_fn = T.sp_tornado; e.upd_fn = T.up_tornado; e.ctl_fn = T.ct_tornado
			e.texture = "tornado"
		0x200b:
			e.flags |= 3; e.d0 = 0x7fffffff; e.ec = -1; e.e4 = 1
			e.spawn_fn = T.sp_casting; e.upd_fn = T.up_casting; e.ctl_fn = T.ct_casting
			e.texture = "firesmoke"
		0x200c:
			e.d0 = 0x80; e.d8 = 400; e.ec = -1; e.e4 = 1; e.a110 = 1.0
			e.set_controls(1)
			e.spawn_fn = T.sp_nuke; e.upd_fn = T.up_nuke; e.ctl_fn = T.ct_nuke
			e.texture = "acidray"
		0x200e, 0x2052:
			# The original's texture test (type == 0x2002 -> Explosion) never holds here.
			e.d0 = 10; e.d8 = 4000; e.ec = -1; e.e4 = 1; e.a110 = 1.0
			e.set_controls(1)
			e.cp[0][0xc] = -1   # the control is made by the first spawn
			e.spawn_fn = T.sp_mushroom; e.upd_fn = T.up_mushroom; e.ctl_fn = T.ct_mushroom
			e.texture = "changehero"
		0x200f, 0x2031, 0x2032, 0x2033:
			e.bone = 7; e.flags |= 0x13; e.vmin = Vector3(-0.2, -0.2, -0.2); e.vmax = Vector3(0.2, 0.2, 0.2)
			e.d0 = 10; e.d8 = 300; e.ec = 6; e.e4 = 0xf
			e.set_controls(1)
			e.cp[0][0xc] = -100
			e.cp[0][0xd] = {0x200f: 12, 0x2031: 13, 0x2032: 14, 0x2033: 15}[type]
			e.spawn_fn = T.sp_blood; e.upd_fn = T.up_blood; e.ctl_fn = T.ct_blood
			e.texture = "rainsnow"
		0x2011, 0x204e:
			e.ec = 15; e.dc = 15; e.vmin = Vector3(-0.2, -0.2, -0.2); e.vmax = Vector3(0.2, 0.2, 0.2)
			e.d0 = 1; e.d4 = 0.06; e.e4 = 1; e.s = 0.3; e.m114 = 1.03; e.c12c = 0
			e.spawn_fn = T.sp_arrow; e.upd_fn = T.up_arrow
			e.texture = "rikarrowsmoke" if type == 0x204e else "firearrowsmoke"
		0x2012:
			e.ec = 15; e.dc = 15; e.vmin = Vector3(-1, -1, -1); e.vmax = Vector3(1, 1, 1)
			e.d0 = 1; e.d4 = 0.06; e.e4 = 1; e.s = 0.3
			e.spawn_fn = T.sp_acidray; e.upd_fn = T.up_acidray
			e.texture = "acidray"
		0x2013:
			e.flags |= 3; e.vmin = Vector3(-1, -1, -1); e.vmax = Vector3(1, 1, 1); e.cc = 80; e.d0 = 5
			e.ec = 45; e.dc = 15; e.e4 = 3; e.s = 1.0
			e.spawn_fn = T.sp_stench; e.upd_fn = T.up_stench
			e.texture = "stench"
		0x2014:
			e.vmin = Vector3(-0.2, -0.2, -0.2); e.vmax = Vector3(0.2, 0.2, 0.2); e.cc = 80
			e.v130 = Vector3(-10, 0, 0); e.d0 = 10; e.ec = 45; e.dc = 15; e.e4 = 3; e.s = 1.0
			e.spawn_fn = T.sp_link; e.upd_fn = T.up_link; e.ctl_fn = T.ct_link
			e.texture = "link"
		0x2015, 0x2016, 0x2017, 0x201a:
			e.add = 1; e.flags |= 3; e.cc = 90; e.d0 = 1; e.ec = 4 if type == 0x201a else 15
			e.dc = 15; e.vmin = Vector3(-0.2, -0.2, -1.0); e.vmax = Vector3(0.2, 0.2, 0.0); e.e4 = 1; e.s = 1.0
			e.spawn_fn = T.sp_sphere; e.upd_fn = T.up_sphere
			e.texture = {0x2015: "protectiona", 0x2016: "protectione", 0x2017: "protectionf", 0x201a: "antimagic"}[type]
		0x2018:
			e.add = 1; e.d0 = 80; e.ec = 15; e.e4 = 2
			e.set_controls(10)
			for i in 10:
				var c: Array = e.cp[i]
				c[6] = sin(i * 0.62832)
				c[7] = cos(i * 0.62832)
				c[8] = 0.0
				c[0xd] = 14
			e.spawn_fn = T.sp_clay; e.upd_fn = T.up_clay; e.ctl_fn = T.ct_clay
			e.texture = "clayring"
		0x2019:
			e.d0 = 20; e.d8 = 320; e.ec = 14; e.e4 = 1
			e.set_controls(1)
			e.spawn_fn = T.sp_teleport; e.upd_fn = T.up_teleport; e.ctl_fn = T.ct_teleport
			e.texture = "teleport"
		0x201b, 0x201c, 0x201d, 0x201e, 0x201f, 0x2020, 0x2021, 0x2022, 0x2023, 0x2024, 0x2025, 0x2026:
			e.flags |= 3; e.d0 = 80; e.ec = 14; e.e4 = 2
			e.spawn_fn = T.sp_modifier; e.upd_fn = T.up_modifier; e.ctl_fn = T.ct_modifier
			e.texture = "stun"
		0x2027, 0x2028, 0x2029, 0x202a:
			e.flags |= 0x13; e.bone = 0
			e.spawn_fn = T.sp_castel; e.upd_fn = T.up_castel; e.ctl_fn = T.ct_castel
			match type:
				0x2027: e.d0 = 20; e.ec = 5; e.e4 = 5; e.texture = "firesmoke"
				0x2028: e.d0 = 20; e.ec = 5; e.e4 = 1; e.texture = "casting8"
				0x2029: e.d0 = 20; e.ec = 5; e.e4 = 5; e.texture = "casting7"
				0x202a: e.d0 = 6; e.ec = 5; e.e4 = 1; e.bone = 2; e.add = 1; e.texture = "casting4"
		0x202b, 0x202c, 0x202d, 0x202e:
			e.flags |= 3; e.vmin = Vector3(-0.04, -0.04, -0.04); e.vmax = Vector3(0.04, 0.04, 0.04)
			e.d0 = 10; e.e4 = 1; e.d8 = 600
			e.ec = {0x202b: 2, 0x202c: 1, 0x202d: 2, 0x202e: 1}[type]
			e.spawn_fn = T.sp_orbit; e.upd_fn = T.up_orbit; e.ctl_fn = T.ct_orbit
			e.texture = {0x202b: "casting2", 0x202c: "casting3", 0x202d: "casting6", 0x202e: "casting1"}[type]
		0x2030:
			e.ec = 15; e.dc = 15; e.vmin = Vector3(-0.2, -0.2, -0.2); e.vmax = Vector3(0.2, 0.2, 0.2)
			e.cc = 88; e.d0 = 250; e.d8 = 600; e.e4 = 1; e.s = 1.0; e.add = 1
			e.set_controls(10)
			e.spawn_fn = T.sp_lblast; e.upd_fn = T.up_lblast; e.ctl_fn = T.ct_lblast
			e.texture = "tendrilight"
		0x2038:
			e.flags |= 0x20; e.d0 = 10; e.d8 = 600; e.k118 = 5.0; e.k11c = 5.0
			e.spawn_fn = T.sp_exit; e.upd_fn = T.up_exit
			e.texture = "zoneexit"
		0x2039:
			e.flags |= 8; e.d0 = 2500; e.d8 = 2500
			e.spawn_fn = T.sp_path; e.upd_fn = T.up_path; e.ctl_fn = T.ct_path
			e.texture = "shapechange"
		0x203a, 0x203b:
			e.d0 = 0x80 if type == 0x203a else 0x100; e.d8 = e.d0
			e.set_controls(1)
			e.cp[0][0xc] = 0x40ff40 if type == 0x203a else 0xff4040
			e.spawn_fn = T.sp_target; e.upd_fn = T.up_target; e.ctl_fn = T.ct_target
			e.texture = "shapechange"
		0x203c:   # "Bag": the swarm of the quest messenger (CEffectMoshka)
			e.d0 = 100; e.d8 = 800; e.flags |= 3
			e.set_controls(80)
			e.spawn_fn = T.sp_bag; e.upd_fn = T.up_bag; e.ctl_fn = T.ct_bag
			e.texture = "bag"
		0x203d:
			e.d0 = 1; e.d8 = 1
			e.spawn_fn = T.sp_pstar; e.upd_fn = T.up_pstar
			e.texture = "casting6"
		0x203e:
			e.d0 = 50; e.d8 = 800; e.ec = 10; e.e4 = 3; e.add = 1
			e.set_controls(1)
			e.spawn_fn = T.sp_portal; e.upd_fn = T.up_portal; e.ctl_fn = T.ct_portal
			e.texture = "teleport"
		0x2041, 0x2042:
			e.flags |= 0x13; e.bone = 7; e.d0 = 1; e.ec = 15
			e.spawn_fn = T.sp_star; e.upd_fn = T.up_star
			e.texture = "firearrowsmoke" if type == 0x2041 else "acidray"
		0x2043:
			e.add = 1; e.flags |= 0x13; e.bone = 7; e.d0 = 10; e.d8 = 300
			e.spawn_fn = T.sp_sparks; e.upd_fn = T.up_sparks
			e.texture = "casting6"
		0x2044, 0x2045, 0x2046, 0x204c:
			e.add = 1; e.flags |= 0x13; e.bone = 2; e.d0 = 3
			e.ec = {0x2044: 0, 0x2045: 1, 0x2046: 2, 0x204c: 3}[type]
			e.spawn_fn = T.sp_vstar; e.upd_fn = T.up_vstar
			e.texture = "stun"
		0x2048:
			e.add = 1; e.flags |= 0x13; e.bone = 7; e.d0 = 4; e.d8 = 300
			e.spawn_fn = T.sp_silence; e.upd_fn = T.up_silence
			e.texture = "stun"
		0x2049:
			e.add = 1; e.flags |= 0x13; e.bone = 1; e.d0 = 5; e.d8 = 300
			e.spawn_fn = T.sp_feeble; e.upd_fn = T.up_feeble
			e.texture = "link"
		0x204a, 0x204b:
			e.add = 1; e.flags |= 3; e.d0 = 8; e.d8 = 300
			e.set_controls(2)
			for i in 2:
				e.cp[i][0xc] = -1
				e.cp[i][0xd] = i
			e.ec = 0xff if type == 0x204a else 0xff0000
			e.spawn_fn = T.sp_feet; e.upd_fn = T.up_feet; e.ctl_fn = T.ct_feet
			e.texture = "visionfog"
		0x2051:
			e.flags |= 0x13; e.bone = 7; e.d0 = 1; e.d8 = 300
			e.set_controls(1)
			e.cp[0][0xd] = 30
			e.cp[0][6] = 0.0
			e.cp[0][7] = 1.0
			e.spawn_fn = T.sp_trans; e.upd_fn = T.up_trans; e.ctl_fn = T.ct_trans
			e.texture = "zoneexit"
		_:
			return null
	if e.spawn_fn == T.sp_fire and e.upd_fn == T.up_fire and not e.ctl_fn.is_valid():
		e.prepare_fire_batch()
	if e.spawn_fn in [T.sp_modifier, T.sp_orbit]:
		e.prepare_spell_batch()
	e.par = not (SERIAL.has(e.spawn_fn.get_method()) or SERIAL.has(e.upd_fn.get_method()) \
		or SERIAL.has(e.ctl_fn.get_method()))
	return e


## Remake: the callbacks that read units, bones, the camera, a shared
## table, the nav grid, the water levels or an option (directly or through
## a helper: plane_ground, under_water, through_alpha); an emitter using one
## is updated on the main thread (FxEmitter.par). The others may only touch
## their emitter, its particles and control points, and FxEmitter.ground.
const SERIAL := {&"_sphere_base": 1, &"carrier_size": 1, &"ct_feet": 1, &"sp_bag": 1, &"sp_castel": 1,
	&"sp_casting": 1, &"sp_healing": 1, &"sp_modifier": 1, &"sp_orbit": 1, &"sp_sphere": 1, &"sp_stench": 1,
	&"up_bag": 1, &"up_silence": 1, &"sp_path": 1, &"up_path": 1, &"up_target": 1, &"ct_target": 1}


# ------------------------------------------------------ 2000 FireBall

func sp_fireball(e: FxEmitter, p: Array, idx: int) -> bool:
	p[0x16] = W
	p[0x14] = e.ec
	p[0x11] = 0
	p[0x13] = e.e4
	setp(p, e.wp)
	var h := e.s * 0.5
	var t := 0.0
	if idx == 0:
		p[0x15] = 1
		p[3] = e.s * 1.2
	else:
		p[3] = h
		p[0x15] = 0
		t = u01(e) - 1.0   # somewhere along this tick's path
	if e.moved <= 1e-5:
		setv(p, 8, Vector3.ZERO)
		return true
	setp(p, getp(p) + e.dl * t)
	var a := rr(e, e.vmin.x - h, e.vmax.x + h)
	var b := rr(e, e.vmin.y - h, e.vmax.y + h)
	var v := e.sd * a + e.upv * b
	setv(p, 8, v)
	if p[0x15] == 0:
		setp(p, getp(p) + v)
	return true


func up_fireball(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	p[0x13] -= 1
	if p[0x13] == 0:
		p[0x11] += 1
		if p[0x11] >= e.dc:
			return false
		p[0x13] = e.e4
	p[3] = e.m114 * p[3]
	if p[0x15] == 0:
		setp(p, getp(p) - getv(p, 8))
	else:
		p[0x15] = 0
		p[3] = p[3] * 0.5
	setv(p, 8, getv(p, 8) * 0.95)
	setp(p, getp(p) + getv(p, 8))
	return true


# ------------------------------------- 2001 / 2003 / 2004 / 2010 fire and smoke

func sp_fire(e: FxEmitter, p: Array, _idx: int) -> bool:
	var k := 0.0
	p[0x16] = W
	p[0x14] = e.ec
	p[0x11] = 8 if e.type == 0x2004 else 0
	p[0x13] = e.e4
	p[3] = e.s
	if e.rnd() % 100 + 1 <= 40:
		p[3] = e.s * 0.5
		k = e.s * 0.3
	var vx := rr(e, e.vmin.x - k, e.vmax.x + k)
	var vy := rr(e, e.vmin.y - k, e.vmax.y + k)
	setv(p, 8, Vector3(vx, vy, 0.0) * 0.5)
	p[0] = e.wp.x + p[8]
	p[1] = e.wp.y + p[9]
	p[2] = e.wp.z + u01(e) * e.a110
	p[0xe] = 0.0
	p[0xf] = 0.0
	p[0x10] = e.a110
	return true


func up_fire(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	p[0x13] -= 1
	if p[0x13] == 0:
		p[0x11] += 1
		if p[0x11] >= e.dc:
			return false
		p[0x13] = e.e4
		if p[0x11] > 7:
			if e.type == 0x2003 or e.type == 0x2010:
				return false
			p[0x13] = e.e4 << 2
			if (e.rnd() & 3) == 0:
				return false
		if p[0x11] == 8:
			p[0x10] = p[0x10] * 0.5
	p[2] = p[2] + p[0x10]
	if p[0x11] < 2:
		p[0] += p[8]
		p[1] += p[9]
		p[2] += p[10]
	if p[0x11] < 7:
		p[3] = e.m114 * p[3]
		return true
	p[3] = p[3] * 1.06
	var w: float = p[3] * e.wind_s * 0.15
	setp(p, getp(p) + e.wind * w)
	return true


## FireWall, a random point of the wall's box on the ground.
func sp_firewall(e: FxEmitter, p: Array, idx: int) -> bool:
	sp_fire(e, p, idx)
	var t := u2(e)
	p[0] = t * e.v130.x + p[0]
	var y: float = t * e.v130.y + p[1]
	p[1] = y
	p[2] = p[2] - e.wp.z + e.ground(p[0], y)
	return true


## Tornado 0x200a spawn: height share h, a ring round the funnel
## axis (control points lerped at h · 5), dust (frames 0..11, two in three) or
## small bits (12..15).
func sp_tornado(e: FxEmitter, p: Array, _idx: int) -> bool:
	var h := u01(e)
	p[0x15] = rnd(e) % 3
	p[0x16] = e.e4
	var c0: Array = e.cp[0]
	p[0] = e.wp.x
	p[1] = e.wp.y
	p[2] = e.wp.z + float(c0[2])
	p[0x14] = rnd(e) % 9 + 100
	var i := mini(roundi(h * 5.0), e.cp.size() - 2)
	var f := minf(h * 5.0 - float(i), 1.0)
	var a: Array = e.cp[i]
	var b: Array = e.cp[i + 1]
	p[0xc] = 0.1
	p[0xb] = h
	var ang := float(rnd(e)) * TAU_ * 2.3283064e-10 - PI
	var q := 1.0 - h
	var r := 2.0 * (q * q * q * q + 0.2) * (float(rnd(e)) * 2.793967696741381e-10 + 0.8)
	p[8] = ang
	p[9] = r
	p[0xe] = (1.1 - q * q) * ((PI * 0.07 - PI * 0.06) * float(rnd(e)) * 2.3283064e-10 + PI * 0.06) * 1.5
	p[0x10] = 0.0
	p[0xf] = c0[0xb]
	p[0] = sin(ang) * r + float(p[0]) + ((1.0 - f) * float(a[0]) + f * float(b[0]))
	p[1] = cos(ang) * r + (f * float(b[1]) + (1.0 - f) * float(a[1])) + float(p[1])
	p[2] = h * float(c0[9]) + float(p[2])
	if p[0x15] != 0:
		p[3] = (r + 0.3) * e.s
		p[0x11] = rnd(e) % 12
	else:
		p[0x11] = (rnd(e) & 3) + 12
		p[3] = e.s * 0.15
	return true


## Tornado update: rises faster and faster (h += +=
## 0.0001), spins up (× 1.01) and narrows (radius × control 0); fades
## by 0.1 a tick until 8 ticks before its end (then the original keeps max(fade
## 0.1)); alpha = sqrt(1 − h) · fade · 255.
func up_tornado(e: FxEmitter, p: Array) -> bool:
	p[0x14] = int(p[0x14]) - 1
	if int(p[0x14]) == 0:
		return false
	p[0xb] = float(p[0xb]) + float(p[0x10])
	p[0x10] = float(p[0x10]) + 0.0001
	if float(p[0xb]) > 1.0:
		return false
	var h: float = p[0xb]
	var i := mini(int(h * 5.0), e.cp.size() - 2)
	var f := minf(h * 5.0 - float(i), 1.0)
	var a: Array = e.cp[i]
	var b: Array = e.cp[i + 1]
	var c0: Array = e.cp[0]
	p[8] = float(p[8]) + float(p[0xe])
	p[0xe] = float(p[0xe]) * 1.01
	var r := float(p[0xf]) * float(p[9])
	p[9] = r
	p[0] = sin(float(p[8])) * r + e.wp.x + ((1.0 - f) * float(a[0]) + f * float(b[0]))
	p[1] = cos(float(p[8])) * r + e.wp.y + f * float(b[1]) + (1.0 - f) * float(a[1])
	p[2] = float(c0[9]) * h + (float(c0[2]) + e.wp.z)
	if int(p[0x14]) < 9:
		p[0xc] = float(p[0xc]) if 0.1 < float(p[0xc]) else 0.1
	else:
		p[0xc] = minf(float(p[0xc]) + 0.1, 1.0)
	p[0x16] = (int(p[0x16]) & 0xffffff) | (roundi(sqrt(1.0 - h) * float(p[0xc]) * 255.0) << 24)
	if p[0x15] != 0:
		p[3] = (r + 0.3) * e.s
		p[0x11] = (int(p[0x11]) + 1) % 12
	else:
		p[0x11] = ((int(p[0x11]) + 1) & 3) + 12
	return true


## Tornado control, on control 0 only: its z = 1 m over the ground
## below the emitter; with a lean (≠ 0) the funnel bends against the
## motion: D = −(motion · 20 + control 0) normalised × min(|…| / 2, 0.01),
## then control i = (D + control 0) · ((1 − t) · lean + cos(t · π) + 1) · 0.4,
## t = i / (n − 1). Without a lean the controls lie on a quarter cosine.
func ct_tornado(e: FxEmitter, c: Array) -> void:
	if not is_same(c, e.cp[0]):
		return
	var n := e.cp.size()
	var g := e.ground(e.wp.x, e.wp.y)
	if float(c[0xa]) == 0.0:
		var d := Vector3(c[0], c[1], c[2]) - e.dl
		for i in n:
			var k := cos(float(i) / float(n - 1) * PI * 0.5)
			e.cp[i][0] = d.x * 0.95 * k
			e.cp[i][1] = d.y * 0.95 * k
			e.cp[i][2] = k * 0.0
		e.cp[0][2] = g - e.wp.z + 1.0
	else:
		c[2] = g - e.wp.z + 1.0
		var v := -(e.dl * 20.0 + Vector3(c[0], c[1], c[2]))
		var l := v.length()
		if l != 0.0:
			v /= l
		v *= minf(l * 0.5, 0.01)
		var base := Vector3(c[0], c[1], c[2])
		var lean := float(c[0xa])
		for i in n:
			var t := float(i) / float(n - 1)
			var w := ((1.0 - t) * lean + cos(t * PI) + 1.0) * 0.4
			e.cp[i][0] = (v.x + base.x) * w
			e.cp[i][1] = (v.y + base.y) * w
			e.cp[i][2] = (v.z + base.z) * w
	if not e.has_carrier and float(e.cp[0][0xa]) == 0.0 and not e.parts.is_empty():
		e.flags &= ~(FxEmitter.F_EMIT | FxEmitter.F_KEEP)


## attempts per tick from the wall length, 6.. d8 / 16.
func ct_firewall(e: FxEmitter, _c: Array) -> void:
	var n := maxi(6, roundi(e.v130.length() * 20.0 / maxf(e.k128, 0.01)))
	e.d0 = mini(n, e.d8 >> 4)


# ------------------------------------------------------ 2002 FireBlast

func sp_blast(e: FxEmitter, p: Array, _idx: int) -> bool:
	var k := int(e.rnd() % 0x1d) - 0xe
	p[0x16] = W
	if e.live() == 0 and int(e.cp[0][0xc]) == 1:
		p[0x15] = -1
		setp(p, e.wp)
		p[0x11] = 15
		p[3] = 0.0
		return true
	if k >= 0:
		var c: Array = e.cp[k]
		p[0x11] = e.rnd() % 3
		if c[9] == 0.0:
			p[0x11] = 8
		var f := u01(e)
		var base := e.wp + Vector3(c[0], c[1], c[2])
		p[0] = base.x
		p[1] = base.y
		p[2] = base.z - f * c[5] * e.s
		p[3] = (float(c[6]) * 0.14285715 + 0.3) * (0.3 - f * 0.15) * (float(e.rnd()) * 1.8626451e-10 + 0.7)
		p[3] = p[3] * float(c[0xa] + 1.0) * e.s
		setv(p, 8, Vector3(rr(e, e.vmin.x, e.vmax.x), rr(e, e.vmin.y, e.vmax.y), rr(e, e.vmin.z, e.vmax.z)))
		p[0x15] = -2
		p[0xb] = p[3]
		p[0xc] = float(p[0x11])
		p[0xd] = float(e.rnd()) * 8.149072e-11 + 0.35
		return true
	p[0x14] = 0
	var v := ball(e)
	var q := 1.0 - v.length_squared()
	var cs: Array = e.cp[0]
	setp(p, e.wp + v * e.s * float(cs[6] if cs[6] != 0.0 else 1.0))
	p[3] = 0.0
	var lim := float(int(cs[0xc]) / 7) + 0.2
	p[0x15] = -2
	if q < lim:
		p[0x11] = 8
		p[0xb] = e.s * (float(e.rnd()) * 9.313226e-11 + 0.8) * 0.6
		p[0xc] = float(p[0x11])
		p[0xd] = float(e.rnd()) * 8.149072e-11 + 0.35
		return true
	p[0x11] = e.rnd() % 3
	p[0xb] = e.s * (float(e.rnd()) * 9.313226e-11 + 0.8) * 0.6
	p[0xc] = float(p[0x11])
	p[0xd] = (q * 0.35) / lim + float(e.rnd()) * 8.149072e-11 * 0.5 + 0.175
	return true


func up_blast(e: FxEmitter, p: Array) -> bool:
	if p[0x15] < 0:
		if p[0x11] < 0xe and p[0x15] == -2:
			p[0x14] += 1
			setp(p, getp(p) + getv(p, 8))
			var sz: float = p[0xb]
			if p[0x11] < 8:
				p[3] = sz * 1.01
			else:
				p[3] = sz * 1.03
			p[0xc] = p[0xc] + p[0xd]
			p[0xd] = p[0xd] * 1.02
			p[0x11] = roundi(p[0xc])
			p[0xb] = p[3]
			var d := float(e.cp[0][8]) - 0.03
			setv(p, 8, getv(p, 8) * d)
			p[0x16] = alpha(tab(T_EXPL_A, p[0x11]))
			return true
		if p[0x15] == -1:
			# The flash: 2.3 s, blinking on alternate ticks while debris flies.
			if p[3] == 0.0:
				p[3] = e.s * 2.3
			else:
				p[3] = 0.0
			return int(e.cp[0][0xc]) < 3
		return false
	return false


## the debris points fly out and fall.
func ct_blast(e: FxEmitter, c: Array) -> void:
	c[0xc] = int(c[0xc]) + 1
	c[6] = c[6] + c[7]
	c[7] = c[8] * c[7]
	if c[0xc] > 6:
		e.flags &= ~FxEmitter.F_EMIT
	c[0] += e.s * c[3]
	c[1] += e.s * c[4]
	c[2] += e.s * c[5]
	c[3] *= 0.75
	c[4] *= 0.75
	c[5] = c[5] * 0.75 - 0.03


# ------------------------------------------------------ 2006 Healing

## streams on a spiral around the carrier, heads then sparkles.
func sp_healing(e: FxEmitter, p: Array, _idx: int) -> bool:
	if e.cp.is_empty():
		if not e.has_carrier:
			return false
		var n := roundi(e.s * 6.0 + 2.0)
		e.d0 = n
		if n == 0:
			return false
		e.set_controls(n)
		var step := DEG * (360.0 / n)
		var cs := carrier_size(e)
		var r := cs.y
		var c0 := Vector3(0, 0, cs.x - r)
		var ang := 0.0
		var r11 := r * 1.1
		var h2 := r + r
		e.a110 = r11 * 0.027777778 + r11 * 0.027777778
		e.m114 = (e.s + 1.0) * 0.0069444445
		for c: Array in e.cp:
			c[0xc] = 0
			c[0xd] = 0x24
			var z := rr(e, h2 * -0.1, h2 * 0.1)
			c[6] = c0.x
			c[7] = c0.y
			c[8] = c0.z + z
			c[0] = c[6]
			c[1] = c[7]
			c[2] = c[8]
			c[3] = 0.0
			c[4] = ang
			c[5] = (h2 - z) * 0.027777778
			ang += step
		e.c12c = 0
		e.d0 = e.d0 * 3
	var n := e.cp.size()
	if n < e.c12c:
		# sparkle next to a random stream head
		var c: Array = e.cp[e.rnd() % n]
		p[0x16] = W
		p[0x11] = 8
		p[0x14] = 8
		p[0x13] = 1
		p[0x15] = -1
		var j: float = c[3] * 0.15
		p[0] = rr(e, -j, j) + c[0] + e.wp.x
		p[1] = rr(e, -j, j) + c[1] + e.wp.y
		p[2] = c[2] - u01(e) * -j + e.wp.z - j
		p[3] = (e.s + 1.0) * 0.07
		return true
	if e.c12c != n:
		var c: Array = e.cp[e.c12c]
		p[0x16] = W
		p[0x11] = 0
		p[0x14] = 36
		p[0x13] = 1
		p[0x15] = e.c12c
		p[0] = c[0] + e.wp.x
		p[1] = c[1] + e.wp.y
		p[2] = c[2] + e.wp.z
		p[3] = (e.s + 1.0) * 0.1
		e.c12c += 1
		return true
	e.c12c += 1
	return false


func up_healing(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		if p[0x15] >= 0 and p[0x15] != 0x10000:
			p[0x15] = 0x10000   # the head ends as a fading sparkle
			p[0x14] = 8
			return true
		return false
	if p[0x15] == 0x10000:
		p[0x16] = alpha(a_of(p) - 30)
		return true
	if p[0x15] >= 0:
		p[0x11] += 1
		if p[0x11] > 7:
			p[0x11] = 0
		p[0x13] = 1
		if p[0x14] < 0x12:
			p[3] = p[3] - e.m114
		else:
			p[3] = e.m114 + p[3]
		var c: Array = e.cp[p[0x15]]
		p[0] = e.wp.x + c[0]
		p[1] = e.wp.y + c[1]
		p[2] = e.wp.z + c[2]
		return true
	p[0x11] += 1
	p[0x16] = alpha(a_of(p) - 30)
	return a_of(p) > 0


## each stream turns 10 degrees a tick, radius out then , rising.
func ct_healing(e: FxEmitter, c: Array) -> void:
	c[0xd] = int(c[0xd]) - 1
	if c[0xd] == 0:
		e.flags &= ~FxEmitter.F_EMIT
		return
	if c[0xd] < 0x12:
		c[3] = c[3] - e.a110
	else:
		c[3] = e.a110 + c[3]
	c[4] = c[4] + DEG * 10.0
	c[0] = sin(c[4]) * c[3] + c[6]
	c[1] = cos(c[4]) * c[3] + c[7]
	c[2] = c[5] + c[2]


# ------------------------------------------------------ 2007 / 2008 PoisonFog

## the whole cloud on the first tick, a 1 m grid inside radius s.
func sp_fog(e: FxEmitter, _p: Array, _idx: int) -> bool:
	if e.live() != 0:
		return false
	var r := e.s
	var n := int(r)
	for iy in range(-n, n + 1):
		for ix in range(-n, n + 1):
			var x := u01(e) * 0.5 - 0.25 + ix
			var y := u01(e) * 0.5 - 0.25 + iy
			if x * x + y * y >= r * r:
				continue
			var q := FxEmitter.new_particle()
			q[0] = x + e.ofs.x
			q[1] = y + e.ofs.y
			q[3] = float(e.rnd()) * 1.1641532e-10 + 1.0 - 0.25
			q[2] = e.ground(q[0], q[1]) + q[3]
			q[0x16] = W if e.type == 0x2008 else alpha(mini(255, roundi(e.k118 * 160.0)))
			q[0x14] = e.ec
			q[0x11] = e.rnd() % e.dc
			q[0x13] = e.e4
			e.push(q)
	return false


func up_fog(e: FxEmitter, p: Array) -> bool:
	p[0x13] -= 1
	if p[0x13] == 0:
		p[0x11] += 1
		if p[0x11] >= e.dc:
			p[0x11] = 0
		p[0x13] = e.e4
	if (e.flags & FxEmitter.F_EMIT) == 0:
		var a := a_of(p)
		if a < 10:
			return false
		var k := maxi(1, roundi(e.k118 * 4.5))
		p[0x16] = alpha(a - k, 0xffaf7f if e.type == 0x2008 else RGB)
	return true


# ------------------------------------------------------ 2009 Fireworks (Geyser)

func sp_fireworks(e: FxEmitter, p: Array, _idx: int) -> bool:
	var ci := e.rnd() % e.cp.size()
	p[0x16] = W
	setp(p, e.wp)
	if e.live() == 0:
		p[3] = 0.0
		p[0x15] = 1
		p[0x11] = 15
		return true
	p[0x15] = 0
	var c: Array = e.cp[ci]
	p[0x11] = e.rnd() % 12
	var sz := e.s * 0.2
	p[0x14] = 20
	if int(c[0xd]) > 0:
		p[0x14] = 0x7fffffff
		var yaw: float = DEG * (float(e.rnd()) * 9.313226e-09 - 20.0) + c[0]
		var pitch: float = DEG * (float(e.rnd()) * 4.656613e-09 - 10.0) + c[1]
		var sp: float = float(e.rnd()) * 4.656613e-11 + c[2] - 0.1
		p[0xe] = sin(yaw) * sin(pitch) * sp * e.a110
		p[0xf] = cos(yaw) * sin(pitch) * sp * e.a110
		p[0x10] = cos(pitch) * sp * e.a110
		p[0] = rr(e, e.vmin.x, e.vmax.x) + p[0]
		p[1] = rr(e, e.vmin.y, e.vmax.y) + p[1]
		p[2] = rr(e, e.vmin.z, e.vmax.z) + p[2]
		p[3] = 0.0
		p[8] = sz
		return true
	p[0x14] = 1
	p[0xe] = 0.0
	p[0xf] = 0.0
	p[0x10] = 0.0
	p[0] = rr(e, e.vmin.x * 0.5, e.vmax.x * 0.5) + p[0]
	p[1] = rr(e, e.vmin.y * 0.5, e.vmax.y * 0.5) + p[1]
	p[3] = e.s * 0.01
	return true


func up_fireworks(e: FxEmitter, p: Array) -> bool:
	if p[0x15] != 0:
		if (e.flags & FxEmitter.F_EMIT) == 0:
			p[3] = 0.0
			return false
		p[3] = (float(e.rnd()) * 6.2864277e-11 + 0.03) * e.s
		return true
	if a_of(p) < 10:
		return false
	p[0x14] -= 1
	if p[0x14] < 1:
		return false
	var sz: float = p[8]
	p[8] = sz * 0.9
	setp(p, getp(p) + getv(p, 0xe))
	var f: int = p[0x11]
	p[0x11] = ((f + 1) & 3) | (f & ~3)
	p[3] = sz * 0.9
	p[0x16] = alpha(a_of(p) - 9)
	p[0x10] = p[0x10] - e.a110 * 0.06
	return true


## each rocket waits 3..36 ticks, then bursts for 1..7 ticks.
func ct_fireworks(e: FxEmitter, c: Array) -> void:
	if int(c[0xd]) < 1:
		c[0xc] = int(c[0xc]) - 1
		if int(c[0xc]) < 1:
			c[0xd] = e.rnd() % 7 + 1
			c[0] = DEG * float(e.rnd()) * 8.381903e-08
			c[1] = DEG * float(e.rnd()) * 2.3283064e-09
			c[2] = float(e.rnd()) * 1.3969838e-10 + 0.4
	else:
		c[0xd] = int(c[0xd]) - 1
		if c[0xd] == 0:
			c[0xc] = e.rnd() % 0x22 + 3


# ------------------------------------------------------ 200b Casting

## three spiral streams for 45 ticks, then a ring burst.
func sp_casting(e: FxEmitter, p: Array, _idx: int) -> bool:
	if e.cp.is_empty():
		if not e.has_carrier:
			return false
		e.d0 = 3
		e.set_controls(3)
		var step := DEG * (360.0 / 3.0)
		var cs := carrier_size(e)
		var r := cs.y
		var c0 := Vector3(0, 0, cs.x - r)
		e.m114 = 0.0
		var r11 := r * 1.1
		var h2 := r + r
		e.a110 = r11 * 0.027777778 + r11 * 0.027777778
		var ang := 0.0
		for c: Array in e.cp:
			c[0xc] = 0
			c[0xd] = 0x2d
			var z := rr(e, h2 * -0.1, h2 * 0.1)
			c[6] = c0.x
			c[7] = c0.y
			c[8] = c0.z + z
			c[0] = c[6]
			c[1] = c[7]
			c[2] = c[8]
			c[3] = 0.0
			c[4] = ang
			c[5] = (h2 - z) * 0.027777778
			ang += step
		e.c12c = 0
		e.d0 = e.d0 * 9
	var n := e.cp.size()
	if e.c12c <= n:
		if e.c12c == n:
			e.c12c += 1
			return false
		var c: Array = e.cp[e.c12c]
		p[0x16] = W
		p[0x11] = 0
		p[0x14] = 36
		p[0x13] = 1
		p[0x15] = e.c12c
		p[0] = c[0] + e.wp.x
		p[1] = c[1] + e.wp.y
		p[2] = c[2] + e.wp.z
		p[3] = e.s * 0.0015
		e.c12c += 1
		return true
	var c0: Array = e.cp[0]
	if int(c0[0xd]) < 9:
		# ring burst at the end
		e.d0 = 0x48
		var rad: float = c0[3]
		var ang := u01(e) * TAU_
		var k := mini(int(c0[0xd]), 5)
		p[0x16] = W
		p[0x11] = 1
		p[0x13] = 1
		p[0x15] = -1
		p[0x14] = e.rnd() % 4 + k + 1
		var lo := (rad - e.a110 * 20.0) * 0.5 + rad
		var rr_ := rr(e, lo, rad)
		p[0] = e.wp.x + c0[0] + sin(ang) * rr_
		p[1] = e.wp.y + c0[1] + cos(ang) * rr_
		p[2] = e.wp.z + c0[2]
		p[3] = e.s * 0.1
		return true
	var c: Array = e.cp[e.rnd() % n]
	p[0x11] = 1
	p[0x14] = 7
	p[0x13] = 1
	p[0x16] = W
	p[0x15] = -1
	var j: float = c[3] * 0.1 + 0.001
	p[0] = rr(e, -j, j) + c[0] + e.wp.x
	p[1] = rr(e, -j, j) + c[1] + e.wp.y
	p[2] = c[2] - u01(e) * -j + e.wp.z - j
	p[3] = e.s * 0.1
	return true


func up_casting(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		if p[0x15] >= 0 and p[0x15] != 0x10000:
			p[0x15] = 0x10000
			p[0x14] = 8
			return true
		return false
	if p[0x15] == 0x10000:
		p[3] = p[3] * 0.7692308
		p[0x16] = alpha(a_of(p) - 31)
		return true
	if p[0x15] >= 0:
		p[0x13] = 1
		if p[0x14] < 0x24 and p[0x14] > 0x11:
			p[3] = p[3] - e.m114
		else:
			p[3] = e.m114 + p[3]
		var c: Array = e.cp[p[0x15]]
		p[0] = e.wp.x + c[0]
		p[1] = e.wp.y + c[1]
		p[2] = e.wp.z + c[2]
		return true
	p[0x11] += 1
	return p[0x11] < 16


func ct_casting(e: FxEmitter, c: Array) -> void:
	c[0xd] = int(c[0xd]) - 1
	if c[0xd] == 0:
		e.flags &= ~FxEmitter.F_EMIT
		return
	if c[0xd] < 0x1b:
		if c[0xd] < 9:
			var f := e.a110 * 20.0
			c[3] = (c[3] - f) * 0.5 + f
		else:
			c[3] = c[3] - e.a110
	else:
		c[3] = e.a110 + c[3]
	if c[0xd] > 8:
		c[4] = c[4] + DEG * 10.0
		c[0] = sin(c[4]) * c[3] + c[6]
		c[1] = cos(c[4]) * c[3] + c[7]
		c[2] = c[5] + c[2]


# ------------------------------------------------------ 200c Nuke (acid column)

func sp_nuke(e: FxEmitter, p: Array, _idx: int) -> bool:
	var k := int(e.cp[0][0xd])
	var r := u01(e) * e.s * 0.2
	var a := u01(e) * TAU_
	p[0xe] = sin(a)
	p[0xf] = cos(a)
	p[0] = r * sin(a) + e.wp.x
	p[1] = r * cos(a) + e.wp.y
	p[2] = u01(e) * (e.s + e.s) + e.wp.z
	p[3] = e.s * 0.2
	p[0x10] = float(11 - k) * e.s * 0.1
	p[0x14] = 41 - k
	p[0x11] = k / 3
	p[0x15] = 0
	p[0x16] = alpha(mini(255, int(pow(4.0, k))))
	return true


func up_nuke(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	if p[0x15] == 0:
		p[0x10] = p[0x10] * 0.85 - 0.055
		p[2] = p[0x10] + p[2]
		if p[0x10] < 0.0 and p[2] < e.s * 0.5 + e.wp.z:
			p[0x15] = 1
			p[0xe] = absf(p[0x10]) * p[0xe]
			p[0xf] = absf(p[0x10]) * p[0xf]
		return true
	if p[0x11] < 0xe:
		p[0x11] += 1
		p[0] += p[0xe]
		p[1] += p[0xf]
		p[0xe] *= 0.85
		p[0xf] *= 0.85
		p[3] *= 1.13
		p[0x16] = alpha(maxi(0, a_of(p) - 0x10))
		return true
	return false


func ct_nuke(e: FxEmitter, c: Array) -> void:
	c[0xd] = int(c[0xd]) + 1
	if e.d0 > 8:
		e.d0 = e.d0 / 2
	if c[0xd] == 0xd:
		e.flags &= ~FxEmitter.F_EMIT


# ------------------------------------------- 200e Mushroom / 2052 Transform

## . The first spawn makes the one control: radius 0 (ln 1), rise 0
## centre = the emitter position. Each particle starts at (0.8..1)·radius
## along a random direction (x, y in −1..1, z 0.1..1, normalised, z + 0.12),
## moves 0.06·s along it, lives 16..19 ticks, size (k·0.008 + 0.1)·s, frame
## max(0, k / 10 + rand % 3 − 1), colour (k = the control count).
func sp_mushroom(e: FxEmitter, p: Array, _idx: int) -> bool:
	var c: Array = e.cp[0]
	if int(c[0xc]) < 0:
		c[0xc] = 0
		c[0xd] = 0
		c[0] = 0.0
		c[2] = 0.0
		c[6] = e.wp.x
		c[7] = e.wp.y
		c[8] = e.wp.z
	var r := (float(e.rnd()) * 9.313226e-11 + 0.8) * float(c[0])
	var x := u2(e)
	var y := u2(e)
	var z := float(e.rnd()) * 2.0954757e-10 + 0.1
	var inv := 1.0 / sqrt(x * x + y * y + z * z)
	x *= inv
	y *= inv
	z = z * inv + 0.12
	var k := int(c[0xd])
	p[0] = x * r + e.wp.x
	p[1] = y * r + e.wp.y
	p[2] = z * r + e.wp.z + float(c[2])
	p[0xe] = x * e.s * 0.06
	p[0xf] = y * e.s * 0.06
	p[0x10] = z * e.s * 0.06
	p[3] = (k * 0.008 + 0.1) * e.s
	p[0x14] = (e.rnd() & 3) + 0x10
	p[0x13] = 2
	p[0x11] = maxi(0, k / 10 + e.rnd() % 3 - 1)
	p[0x16] = alpha(0x40)
	return true


## frames step every tick up to 14 (size × 1.1 below frame 8)
## alpha a tick (max 0xff), −0x40 in the last four ticks (a byte add
## that wraps, so the last tick is opaque again); velocity × 0.7; below the
## control's rise the particle is pulled 0.02·s toward the centre axis.
func up_mushroom(e: FxEmitter, p: Array) -> bool:
	p[0x14] = int(p[0x14]) - 1
	if p[0x14] == 0:
		return false
	if int(p[0x11]) < 0xe:
		p[0x13] = int(p[0x13]) - 1
		if p[0x13] == 0:
			p[0x13] = 1
			p[0x11] = int(p[0x11]) + 1
		if int(p[0x11]) < 8:
			p[3] = p[3] * 1.1
	var a := a_of(p)
	if int(p[0x14]) < 5:
		a = (a + 0xc0) & 0xff
	else:
		a = mini(a + 0x40, 0xff)
	p[0x16] = alpha(a)
	p[0] += p[0xe]
	p[1] += p[0xf]
	p[2] += p[0x10]
	p[0xe] *= 0.7
	p[0xf] *= 0.7
	p[0x10] *= 0.7
	var c: Array = e.cp[0]
	var dx: float = p[0] - float(c[6])
	var dy: float = p[1] - float(c[7])
	var d := sqrt(dx * dx + dy * dy)
	if p[2] - float(c[8]) < float(c[2]) and d > 0.0:
		p[0xe] -= dx * e.s * 0.02 / d
		p[0xf] -= dy * e.s * 0.02 / d
	return true


## 0x200e shakes the camera on its first control tick
## ((position, 5, s, 0.25)); the radius is ln(k + 2)·0.2·s and the
## cloud rises 0.12·s a tick; emission ends after 30 ticks.
func ct_mushroom(e: FxEmitter, c: Array) -> void:
	if int(c[0xc]) < 0:
		return
	var k := int(c[0xd])
	if e.type == 0x200e and k == 0:
		# Remake: may run on a worker; ParticleFx starts it after the tick.
		e.shakes.append([Vector2(e.wp.x, e.wp.y), 5.0, e.s, 0.25])
	c[0xd] = k + 1
	c[0] = log(float(k + 2)) * e.s * 0.2
	c[2] = float(c[2]) + e.s * 0.12
	if k + 1 == 30:
		e.flags &= ~FxEmitter.F_EMIT


# ------------------------------------------------------ 200f / 2031..2033 blood

## a burst in random directions from the struck bone.
func sp_blood(e: FxEmitter, p: Array, _idx: int) -> bool:
	var c0: Array = e.cp[0]
	if int(c0[0xc]) < 0:
		var n := maxi(1, roundi(e.k118 * 8.0))
		e.e4 = n
		e.d0 = n * 10
		var frame: int = c0[0xd]
		e.set_controls(n)
		for c: Array in e.cp:
			var v := ball(e)
			v = v.normalized() if v.length() > 0.0001 else Vector3.UP
			c[0] = v.x
			c[1] = v.y
			c[2] = v.z
			c[0xc] = 0
			c[0xd] = frame
		c0 = e.cp[0]
	p[0x16] = W
	p[0x14] = e.ec
	p[0x11] = c0[0xd]
	var c: Array = e.cp[e.rnd() % e.cp.size()]
	setp(p, e.wp)
	p[3] = e.k11c
	var d := Vector3(e.s * (float(e.rnd()) * 1.3969838e-11 - 0.03 + c[0]),
		e.s * (float(e.rnd()) * 1.3969838e-11 - 0.03 + c[1]),
		e.s * (float(e.rnd()) * 1.3969838e-11 - 0.03 + c[2]))
	var k := (1.0 / maxf(d.length(), 0.0001)) * e.s * 0.16666667
	if (e.rnd() & 7) == 0:
		k *= 1.5
	setv(p, 0xe, d * k)
	p[8] = 0.9
	p[9] = 0.8
	setp(p, getp(p) + getv(p, 0xe) * u01(e))
	return true


func up_blood(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	setp(p, getp(p) + getv(p, 0xe))
	p[0x16] = alpha(tab(T_BLOOD_A, p[0x14]))
	p[3] = p[9] * p[3]
	setv(p, 0xe, getv(p, 0xe) * float(p[8]))
	p[0x10] = p[0x10] - e.s * 0.05
	return true


## the emitter stops after 5 ticks and lets go of the unit.
func ct_blood(e: FxEmitter, c: Array) -> void:
	c[0xc] = int(c[0xc]) + 1
	if int(c[0xc]) > 5:
		e.flags &= ~FxEmitter.F_EMIT
		e.attach(null)


# ------------------------------------------------------ 2011 / 204e FireArrow

func sp_arrow(e: FxEmitter, p: Array, idx: int) -> bool:
	p[0x16] = W
	p[0x14] = e.ec
	p[0x13] = e.e4
	setp(p, e.wp)
	p[3] = 1.0
	var t := 0.0
	if idx == 0 and e.c12c == 0:
		e.c12c = 1
		p[0x15] = 2   # the head
		p[0x11] = 0
		p[3] = e.s * 0.4
	else:
		p[3] = e.s * 0.2
		t = u01(e) - 1.0
		p[0x15] = 0
		if e.rnd() % 100 > 0x46:
			p[0x15] = 1
		p[0x11] = (e.rnd() & 1) + 2
	if e.moved <= 1e-5:
		setv(p, 8, Vector3.ZERO)
		return true
	setp(p, getp(p) + e.dl * t)
	var a := rr(e, e.vmin.x, e.vmax.x)
	var b := rr(e, e.vmin.y, e.vmax.y)
	var v := e.sd * a + e.upv * b
	setv(p, 8, v)
	if p[0x15] == 0:
		setp(p, getp(p) + v)
	return true


func up_arrow(e: FxEmitter, p: Array) -> bool:
	if p[0x15] == 2:
		setp(p, e.dl + e.wp)
		p[0x11] = e.rnd() % 3
		return (e.flags & FxEmitter.F_EMIT) != 0
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	p[0x13] -= 1
	if p[0x13] == 0:
		p[0x11] += 1
		if p[0x11] >= e.dc:
			return false
		p[0x13] = e.e4
	if p[0x15] == 0:
		p[3] = p[3] * 1.4 if p[0x11] < 6 else e.m114 * p[3]
		setp(p, getp(p) - getv(p, 8))
		setv(p, 8, getv(p, 8) * 1.1)
		setp(p, getp(p) + getv(p, 8))
		return true
	if p[0x11] < 6:
		p[3] = p[3] * 1.4
	setv(p, 8, getv(p, 8) * 0.95)
	return true


# ------------------------------------------------------ 2012 AcidRay

## particles leave the path radially by age (tables).
func sp_acidray(e: FxEmitter, p: Array, _idx: int) -> bool:
	p[0x16] = W
	p[0x14] = e.ec
	p[0x13] = e.e4
	setp(p, e.wp)
	p[3] = 1.0
	var t := u01(e) - 1.0
	p[0x15] = 0
	p[0x11] = e.rnd() & 1
	if e.moved <= 1e-5:
		setv(p, 8, Vector3.ZERO)
	else:
		setp(p, getp(p) + e.dl * t)
		setv(p, 8, e.sd * u2(e) + e.upv * u2(e))
	setv(p, 0xe, getp(p))
	var age: int = e.ec - p[0x14]
	setp(p, getv(p, 0xe) + getv(p, 8) * e.s * float(tab(T_ACID_R, age)))
	p[3] = float(tab(T_ACID_S, age)) * e.s
	return true


func up_acidray(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	var age: int = e.ec - p[0x14]
	setp(p, getv(p, 0xe) + getv(p, 8) * e.s * float(tab(T_ACID_R, age)))
	p[3] = float(tab(T_ACID_S, age)) * e.s
	p[0x13] -= 1
	if p[0x13] == 0:
		p[0x11] += 1
		if p[0x11] >= e.dc:
			return false
		p[0x13] = e.e4
	return true


# ------------------------------------------------------ 2013 BlueGas (Stench)

func sp_stench(e: FxEmitter, p: Array, _idx: int) -> bool:
	if e.cp.is_empty():
		if not e.has_carrier:
			return false
		var cs := carrier_size(e)
		e.set_controls(1)
		e.cp[0][2] = cs.x
		e.cp[0][6] = cs.y * 0.3
		e.cp[0][8] = cs.y + cs.y
		e.d0 = maxi(1, roundi(e.s * 5.0))
	var c: Array = e.cp[0]
	var rad: float = c[6]
	var h: float = c[8]
	var r := u01(e) * rad
	var a := u01(e) * TAU_
	var turn := (r * 0.3) / maxf(rad, 0.0001)
	p[0x16] = W
	p[0x11] = 0
	p[0x14] = e.ec
	p[0x13] = e.e4
	setv(p, 8, Vector3(sin(a) * r, cos(a) * r, 0.0))
	p[0xe] = sin(turn)
	p[0xf] = cos(turn)
	p[0x10] = rr(e, h * 0.02, h * 0.03)
	setp(p, e.wp + Vector3(c[0], c[1], c[2]) + getv(p, 8))
	p[3] = rad * 0.7 * e.s
	return true


## wisps turn around z and rise faster and faster.
func up_stench(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	p[0x13] -= 1
	if p[0x13] == 0:
		p[0x11] += 1
		if p[0x11] >= e.dc:
			return false
		p[0x13] = e.e4
	setp(p, getp(p) - getv(p, 8))
	var vx: float = p[8]
	p[8] = p[0xf] * vx - p[9] * p[0xe]
	p[9] = p[9] * p[0xf] + vx * p[0xe]
	p[10] = p[0x10] + p[10]
	p[0x10] = p[0x10] * 1.02
	setp(p, getp(p) + getv(p, 8))
	p[3] = p[3] * 1.01
	if p[0x14] < 8:
		p[0x16] = alpha(a_of(p) - 32)
	return true


# ------------------------------------------------------ 2014 Link

## a beam of particles along.
func sp_link(e: FxEmitter, p: Array, _idx: int) -> bool:
	if e.cp.is_empty():
		e.set_controls(4)
		var len := e.v130.length()
		e.cp[0][6] = len
		e.cp[0][7] = 1.0 / maxf(len, 0.0001)
		var a := Vector3(e.v130.y, -e.v130.x, 0.0)
		if a.length() < 1e-10:
			a = Vector3(e.v130.y - e.v130.z, -e.v130.x, e.v130.x)
		a = a.normalized()
		var b := a.cross(e.v130).normalized()
		var d := e.v130 / maxf(len, 0.0001)
		e.cp[1][6] = d.x; e.cp[1][7] = d.y; e.cp[1][8] = d.z
		e.cp[2][6] = a.x; e.cp[2][7] = a.y; e.cp[2][8] = a.z
		e.cp[3][6] = b.x; e.cp[3][7] = b.y; e.cp[3][8] = b.z
		e.cp[0][0xd] = 0xff
	p[0x16] = RGB
	var x := u2(e)
	var y := u2(e)
	setv(p, 8, Vector3(x * e.vmin.x, y * e.vmin.y, u2(e) * e.vmin.z))
	var r := sqrt(x * x + y * y)
	p[0xb] = cos(r * 0.2)
	p[0xc] = sin(r * 0.2)
	if (e.rnd() & 3) != 0 or r >= 0.5:
		p[0xf] = rr(e, 0.17, 0.25)
		p[0x10] = rr(e, 0.1, 0.12) * e.s
	else:
		p[0xf] = rr(e, 0.1, 0.12)
		p[0x10] = rr(e, 0.1, 0.125) * e.s
	p[0xe] = 0.0
	p[3] = p[0x10]
	p[0x11] = e.rnd() % (e.dc + 1)
	setp(p, e.wp)
	return true


## travels along the beam with an arc and a spiral.
func up_link(e: FxEmitter, p: Array) -> bool:
	p[0x11] = (p[0x11] + 1) % e.dc
	var along: float = p[0xf] + p[0xe]
	p[0xe] = along
	var c0: Array = e.cp[0]
	if c0[6] < along:
		return false
	var t: float = along * c0[7]
	var vx: float = p[8]
	var vy: float = p[9]
	var sp: float = vx * p[0xc] + vy * p[0xb]
	p[8] = p[0xb] * vx - vy * p[0xc]
	p[9] = sp
	var d := Vector3(e.cp[1][6], e.cp[1][7], e.cp[1][8])
	var a := Vector3(e.cp[2][6], e.cp[2][7], e.cp[2][8])
	var b := Vector3(e.cp[3][6], e.cp[3][7], e.cp[3][8])
	var arc: float = 0.9 * c0[6] * (0.25 - (t - 0.5) * (t - 0.5))
	var pos: Vector3 = e.wp + e.v130 * t + a * p[8] + b * sp + d * p[10] + Vector3(0, 0, arc)
	setp(p, pos)
	p[3] = p[0x10]
	p[0x16] = alpha(mini(int(c0[0xd]), roundi(minf(t, 1.0 - t) * 4.0 * 255.0)))
	return true


## fades out after emission stops.
func ct_link(e: FxEmitter, c: Array) -> void:
	if (e.flags & FxEmitter.F_EMIT) == 0:
		c[0xd] = int(c[0xd]) - 0x10
	c[0xd] = maxi(0, int(c[0xd]))


# ------------------------------------- 2015 / 2016 / 2017 / 201a protection spheres

func _sphere_base(e: FxEmitter) -> void:
	var cs := carrier_size(e)
	var rad := cs.y * 1.2
	if e.cp.is_empty():
		e.set_controls(2)
		e.cp[1][6] = cos(0.01)
		e.cp[1][7] = sin(0.01)
		e.cp[1][0] = 0.0
		e.cp[1][1] = 0.0
		e.cp[1][2] = 0.0
		e.cp[0][2] = cs.x
		e.cp[0][6] = rad
	var c: Array = e.cp[0]
	c[2] = cs.x * 0.1 + c[2] * 0.9
	c[6] = c[6] * 0.9 + rad * 0.1
	e.d0 = roundi(e.s * (24.0 if e.type == 0x201a else 6.0))
	var m: Array = e.cp[1]
	m[0] = m[0] * 0.7 + e.dl.x
	m[1] = m[1] * 0.7 + e.dl.y
	m[2] = m[2] * 0.7 + e.dl.z
	c[8] = Vector3(m[0], m[1], m[2]).length()
	if c[8] < 0.01:
		c[8] = 0.0


## Squashes a point of the sphere along the carrier's motion.
func _sphere_squash(e: FxEmitter, v: Vector3) -> Vector3:
	var c: Array = e.cp[0]
	var m: Array = e.cp[1]
	if c[8] <= 0.01:
		return v
	var dir := Vector3(m[0], m[1], m[2]) / float(c[8])
	var k := clampf(-v.dot(dir) / maxf(v.length(), 0.0001), 0.0, 1.0)
	return v - dir * v.dot(dir) * k * minf(c[8], 1.0)


func _sphere_size(e: FxEmitter, p: Array) -> void:
	var rad: float = e.cp[0][6]
	match e.type:
		0x2017: p[3] = float(tab(T_SPHERE, p[0x14])) * p[0xe] * rad * 2.0
		0x201a: p[3] = float(tab(T_ANTIMAGIC, p[0x14])) * p[0xe] * rad
		0x2016: p[3] = float(tab(T_SPHERE, p[0x14])) * p[0xe] * rad
		_: p[3] = float(tab(T_SPHERE, p[0x14])) * p[0xe] * rad * 1.6


func sp_sphere(e: FxEmitter, p: Array, idx: int) -> bool:
	if idx == 0:
		if not e.has_carrier:
			return false
		_sphere_base(e)
	if e.cp.is_empty():
		return false
	var rad: float = e.cp[0][6]
	var k: float
	if e.rnd() % 11 == 0:
		k = u01(e) + (2.5 if e.type == 0x201a else 3.5 if e.type == 0x2016 else 1.5)
	else:
		k = float(e.rnd()) * 1.3969838e-10 + 0.7
	p[0xe] = k
	var v := ball(e)
	v = v * ((rad * 0.65) / maxf(v.length(), 0.0001))
	setv(p, 8, v)
	p[0x16] = W
	p[0x11] = e.rnd() % 11
	p[0x14] = e.ec
	p[0x13] = 1
	setp(p, e.wp + Vector3(0, 0, e.cp[0][2]) + _sphere_squash(e, v))
	_sphere_size(e, p)
	return true


## the sphere turns 0.01 rad a tick about z.
func up_sphere(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	p[0x11] = (p[0x11] + 1) % e.dc
	var cs: float = e.cp[1][6]
	var sn: float = e.cp[1][7]
	var vx: float = p[8]
	p[8] = cs * vx - sn * p[9]
	p[9] = vx * sn + cs * p[9]
	setp(p, e.wp + Vector3(0, 0, e.cp[0][2]) + _sphere_squash(e, getv(p, 8)))
	_sphere_size(e, p)
	return true


# ------------------------------------------------------ 2018 ClayRing

func sp_clay(e: FxEmitter, p: Array, idx: int) -> bool:
	var k: int = e.cp[0][0xd]
	p[0x16] = alpha(tab(T_CLAY_A, k))
	p[0x14] = e.ec
	p[0x11] = 1
	p[0x13] = e.e4
	if k == 0xd and idx < e.cp.size():
		setv(p, 8, Vector3.ZERO)
		p[3] = 0.2
		p[0x11] = 0
		p[0x15] = idx
		return true
	var c: Array = e.cp[e.rnd() % e.cp.size()]
	p[0x14] = 5
	var t := u01(e)
	var cur := Vector3(c[0], c[1], c[2])
	var prev := Vector3(c[3], c[4], c[5])
	setv(p, 8, cur * t + prev * (1.0 - t))
	p[0xb] = float(e.rnd()) * 4.656613e-11 - 0.1
	p[0xc] = float(e.rnd()) * 4.656613e-11 - 0.1
	p[0xd] = float(e.rnd()) * 4.656613e-11 - 0.1
	setp(p, getv(p, 8))
	p[3] = 0.1
	p[0x15] = -1
	return true


func up_clay(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	if p[0x11] == 0 and p[0x15] >= 0:
		p[0x16] = alpha(tab(T_CLAY_A, e.cp[0][0xd]))
		var c: Array = e.cp[p[0x15]]
		setp(p, Vector3(c[0], c[1], c[2]))
		p[3] = 0.2
		p[0x14] = 2
		return true
	p[0x13] -= 1
	if p[0x13] == 0:
		p[0x11] += 1
		if p[0x11] >= e.dc:
			return false
		p[0x13] = e.e4
	p[0xb] *= 0.9
	p[0xc] *= 0.9
	p[0xd] *= 0.9
	p[0] = p[8] + p[0xb]
	p[1] = p[9] + p[0xc]
	p[2] = p[10] + p[0xd]
	p[3] = p[3] * 0.9
	p[0x16] = alpha(a_of(p) - 0x30)
	return true


## the ring grows (s >= 0) or shrinks (s < 0) and turns.
func ct_clay(e: FxEmitter, c: Array) -> void:
	c[0xd] = int(c[0xd]) - 1
	var k: int = c[0xd]
	if k < 0:
		e.flags &= ~FxEmitter.F_EMIT
		return
	c[3] = c[0]
	c[4] = c[1]
	c[5] = c[2]
	var f: float
	if e.s >= 0.0:
		f = float(tab(T_CLAY_IN, 13 - k))
	else:
		f = float(tab(T_CLAY_IN, k))
	var sz := absf(e.s)
	c[0] = sz * c[6] * f + e.wp.x
	c[1] = sz * c[7] * f + e.wp.y
	c[2] = e.ground(c[0], c[1]) + 1.0
	var x: float = c[6]
	c[6] = c[7] * 0.31225 + c[6] * 0.95
	c[7] = c[7] * 0.95 - x * 0.31225
	if c[3] == 0.0 and c[4] == 0.0:
		c[3] = c[0]
		c[4] = c[1]
		c[5] = c[2]


# ------------------------------------------------------ 2019 Teleport

func sp_teleport(e: FxEmitter, p: Array, _idx: int) -> bool:
	p[0x16] = W
	p[0x14] = e.ec
	p[0x11] = 0
	p[0x13] = e.e4
	var sz := absf(e.s)
	var f := (u01(e) + 1.0) * u01(e) * 0.5
	var a := float(e.rnd()) * 1.4629215e-09
	p[0] = sz * f * sin(a) + e.wp.x
	p[1] = sz * f * cos(a) + e.wp.y
	p[3] = 0.0
	p[2] = (float(e.rnd()) * 4.656613e-11 - 0.4) * sz + e.wp.z
	p[0xb] = (2.0 - f) * 0.2
	if u01(e) <= f:
		p[0x11] = e.rnd() & 3
	else:
		p[0x11] = e.rnd() % 12 + 4
	if e.s <= 0.0:
		p[0x16] = RGB
		p[8] = 0.8333333
		p[0x15] = 19
		p[10] = ((1.0 - f) + 3.0) * sz * 2.25
	else:
		p[8] = 1.2
		p[0x15] = 0
		p[10] = ((1.0 - f) + 3.0) * sz * 0.15
	p[2] = p[10] + p[2]
	return true


func up_teleport(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	p[0x13] -= 1
	if p[0x13] == 0:
		p[0x11] += 1
		if p[0x11] == 4:
			p[0x11] = 0
		if p[0x11] == 0x10:
			p[0x11] = 4
		p[0x13] = e.e4
	p[2] = p[2] - p[10]
	p[10] = p[8] * p[10]
	p[2] = p[10] + p[2]
	p[3] = 0.0 if p[0x14] == 1 else p[0xb]
	p[0x16] = alpha(mini(255, a_of(p) + int(p[0x15])))
	return true


## emits for 35 ticks.
func ct_teleport(e: FxEmitter, c: Array) -> void:
	c[0xd] = int(c[0xd]) + 1
	if int(c[0xd]) > 0x23:
		e.flags &= ~FxEmitter.F_EMIT


# ------------------------------------------------------ 201b..2026 Modifier1..12

func sp_modifier(e: FxEmitter, p: Array, idx: int) -> bool:
	p[0x16] = W
	p[0x14] = e.ec
	p[0x13] = e.e4
	if e.cp.is_empty():
		if not e.has_carrier:
			return false
		var n := maxi(1, int(absf(e.s)))
		e.set_controls(n)
		var cs := carrier_size(e)
		var rad := cs.y + cs.y
		var zoff := cs.y
		var axis := Vector3(0, 0, 1)
		match e.type:
			0x201c, 0x201d: zoff += rad * 0.4
			0x201e: zoff -= rad * 0.4
			0x201f, 0x2020, 0x2021, 0x2022: axis = e.fx.view_dir()
			0x2023, 0x2024, 0x2025, 0x2026: axis = Vector3.ZERO
		e.vmin.x = zoff
		for c: Array in e.cp:
			c[0xd] = 0
			var v := Vector3.ZERO
			for i in 20:
				v = Vector3(u2(e), u2(e), u2(e))
				v -= axis * axis.dot(v)
				if v.length_squared() > 0.0:
					break
			var k := rad / maxf(v.length(), 0.0001)
			if e.s < 0.0:
				k *= 0.04347826
			v *= k
			c[6] = v.x
			c[7] = v.y
			c[8] = v.z
			c[0] = v.x + e.wp.x
			c[1] = v.y + e.wp.y
			c[2] = v.z + e.wp.z + zoff
	if int(e.cp[0][0xd]) == 0 and idx < e.cp.size():
		# a head per control point
		p[0x11] = e.type - 0x201b
		p[0x15] = idx
		var c: Array = e.cp[idx]
		setp(p, Vector3(c[0], c[1], c[2]))
		p[3] = 0.125 if e.s >= 0.0 else 0.2
		return true
	var c: Array = e.cp[e.rnd() % e.cp.size()]
	var t := u01(e)
	var cur := Vector3(c[0], c[1], c[2])
	var prev := Vector3(c[3], c[4], c[5])
	setv(p, 8, cur * t + prev * (1.0 - t))
	p[0xb] = float(e.rnd()) * 1.8626451e-11 - 0.04
	p[0xc] = float(e.rnd()) * 1.8626451e-11 - 0.04
	p[0xd] = float(e.rnd()) * 1.8626451e-11 - 0.04
	setp(p, getv(p, 8))
	p[3] = 0.06
	p[0x11] = 12 + (e.rnd() & 3)
	p[0x15] = -1
	return true


func up_modifier(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	if p[0x11] < 0xc and p[0x15] >= 0:
		var c: Array = e.cp[p[0x15]]
		setp(p, Vector3(c[0], c[1], c[2]))
		if e.s < 0.0:
			p[3] = p[3] * 0.9345794
			p[0x16] = alpha(tab(T_MOD_OUT, c[0xd]))
		else:
			p[3] = p[3] * 1.07
			p[0x16] = alpha(tab(T_MOD_IN, c[0xd]))
		return true
	p[0x13] -= 1
	if p[0x13] == 0:
		p[0x11] += 1
		if p[0x11] >= e.dc:
			p[0x11] = 12
		p[0x13] = e.e4
	p[0xb] *= 0.9
	p[0xc] *= 0.9
	p[0xd] *= 0.9
	p[0] = p[0xb] + p[8]
	p[1] = p[0xc] + p[9]
	p[2] = p[0xd] + p[10]
	p[3] = p[3] * 0.9
	p[0x16] = alpha(a_of(p) - 0x30)
	return true


## converge (s >= 0, x0.714) or spread (x1.4) for 10 ticks.
func ct_modifier(e: FxEmitter, c: Array) -> void:
	c[0xd] = int(c[0xd]) + 1
	if int(c[0xd]) > 10:
		e.flags &= ~FxEmitter.F_EMIT
		return
	c[3] = c[0]
	c[4] = c[1]
	c[5] = c[2]
	c[0] = e.wp.x + c[6]
	c[1] = e.wp.y + c[7]
	c[2] = e.wp.z + c[8] + e.vmin.x
	var k := 0.71428573 if e.s >= 0.0 else 1.4
	c[6] *= k
	c[7] *= k
	c[8] *= k


# ------------------------------------------------ 2027..202a elemental casting

## particles fall in on the caster from a sphere around it.
func sp_castel(e: FxEmitter, p: Array, _idx: int) -> bool:
	if e.cp.is_empty():
		if not e.has_carrier:
			return false
		var h: float = e.fx.carrier_height(e.carrier)
		var rad := (h * 2.0 if e.type == 0x202a else h * 3.0) * 0.8
		e.set_controls(e.ec + 1)
		var c0: Array = e.cp[0]
		c0[0xc] = 0xff
		c0[0xd] = 6
		c0[6] = rad
		if e.type == 0x202a:
			c0[7] = 0.07
			c0[3] = 1.05
		else:
			c0[7] = 0.08
			c0[3] = 1.07
		c0[0] = 1.0
		for i in range(1, e.ec + 1):
			var c: Array = e.cp[i]
			var a := ball(e) * 10.0
			c[6] = a.x
			c[7] = a.y
			c[8] = a.z
			var b := ball(e) * 0.1
			c[9] = b.x
			c[0xa] = b.y
			c[0xb] = b.z
			c[0] = 0.0
		if e.type == 0x202a:
			# the centre glow
			p[0x16] = RGB
			p[0x11] = 0
			p[0x15] = 1
			setp(p, e.wp)
			p[3] = 0.0
			return true
	var c0: Array = e.cp[0]
	p[0x16] = RGB
	p[0x11] = 14
	p[0x14] = 13
	p[0x15] = 0
	p[0x13] = 1
	var v := Vector3.ZERO
	for i in 20:
		v = Vector3(u2(e), u2(e), u2(e))
		var l := v.length_squared()
		if l <= 1.0 and l > 0.0:
			break
	var k := e.rnd() % (e.e4 * e.ec + 1)
	if k > 0:
		var c: Array = e.cp[(k - 1) % e.ec + 1]
		v += Vector3(c[6], c[7], c[8])
	v = v.normalized()
	setv(p, 8, v)
	var rad: float = c0[6] * 0.6
	p[0xb] = rad
	p[0xc] = rad * (0.03846154 if e.type == 0x202a else 0.07692308)
	p[0xd] = c0[3]
	setp(p, e.wp + v * rad)
	p[3] = (float(e.rnd()) * 1.862645e-10 + 0.6) * c0[7] * rad
	return true


func up_castel(e: FxEmitter, p: Array) -> bool:
	var c0: Array = e.cp[0]
	if int(c0[0xc]) == 0:
		return false
	if p[0x15] != 0:
		setp(p, e.wp)
		p[3] = (float(e.rnd()) * 6.984918e-11 + 0.85) * c0[6] * 0.3
		p[0x16] = alpha(int(c0[0xc]))
		return true
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	var t: Array = T_CAST_DIV if e.type == 0x202a else T_CAST_A
	p[0x16] = alpha(mini(int(tab(t, p[0x14])), int(c0[0xc])))
	if e.type == 0x2027 and (p[0x14] & 3) == 0:
		p[0x11] += 1
	p[0xb] = p[0xb] - p[0xc]
	p[0x11] -= 1
	if p[0x11] < 0:
		p[0x11] = 0
	setp(p, e.wp + getv(p, 8) * float(p[0xb]))
	p[3] = p[3] * p[0xd]
	return true


## the attractor points wander; the control alpha fades at the end.
func ct_castel(e: FxEmitter, c: Array) -> void:
	if c[0] == 0.0:
		c[6] = c[9] + c[6]
		c[7] = c[0xa] + c[7]
		c[8] = c[0xb] + c[8]
		c[9] = (c[9] * 0.95 + u01(e) * 0.2 - 0.1) - c[6] * 0.0005
		c[0xa] = (c[0xa] * 0.95 + u01(e) * 0.2 - 0.1) - c[7] * 0.0005
		c[0xb] = (c[0xb] * 0.95 + u01(e) * 0.2 - 0.1) - c[8] * 0.0005
	elif (e.flags & FxEmitter.F_EMIT) == 0 or not e.has_carrier:
		if int(c[0xd]) > 0:
			c[0xd] = int(c[0xd]) - 1
		c[0xc] = tab(T_CAST_CTL, int(c[0xd]))


# ------------------------------------------------ 202b..202e orbiting casting

## orbiters around the caster leave trails.
func sp_orbit(e: FxEmitter, p: Array, _idx: int) -> bool:
	if e.cp.size() >= e.ec:
		var ci := e.rnd() % e.ec
		var o: Array = e.cp[ci]
		p[0x16] = W
		p[0x11] = 12
		p[0x14] = 28
		p[0x13] = 1
		p[0x15] = ci
		var f := u01(e)
		p[0xc] = 1.03
		p[0xd] = (float(e.rnd()) * 8.149073e-11 + 0.85) * float(o[5]) * 0.03
		var v := Vector3(rr(e, e.vmin.x, e.vmax.x), rr(e, e.vmin.y, e.vmax.y), rr(e, e.vmin.z, e.vmax.z))
		var prev := Vector3(o[9], o[0xa], o[0xb])
		var cur := Vector3(o[0], o[1], o[2])
		setp(p, prev + v)
		setv(p, 8, cur * (1.0 - f) + prev * f + v)
		p[3] = (float(e.rnd()) * 1.862645e-10 + 0.6) * e.s * 0.2
		return true
	if not e.has_carrier:
		return false
	var cs := carrier_size(e)
	var rad := cs.y * 0.5
	var h: float = e.fx.carrier_height(e.carrier)
	var i := e.cp.size()
	e.cp.append(FxEmitter.new_control())
	var o: Array = e.cp[i]
	var ang := (i * PI + i * PI) / e.ec
	var z := h * 0.4
	var turn := 0.3
	var dir := 1.0
	match e.type:
		0x202c:
			turn = 0.5
			z = h * 1.6
			dir = -1.0
		0x202e:
			turn = 0.5
	o[0xc] = 0
	o[0xd] = 1
	o[6] = cos(ang) * rad
	o[7] = sin(ang) * rad
	o[8] = z
	o[0] = e.wp.x + o[6]
	o[1] = e.wp.y + o[7]
	o[2] = e.wp.z + o[8]
	o[9] = o[0]
	o[0xa] = o[1]
	o[0xb] = o[2]
	o[3] = cos(turn)
	o[4] = sin(turn)
	o[5] = dir * h
	p[0x16] = W
	p[0x11] = 0
	p[0x14] = 6
	p[0x13] = 1
	p[0x15] = -1 - i
	setp(p, Vector3(o[0], o[1], o[2]))
	p[3] = 0.0
	return true


func up_orbit(e: FxEmitter, p: Array) -> bool:
	if p[0x15] < 0:
		var o: Array = e.cp[-1 - int(p[0x15])]
		setp(p, Vector3(o[0], o[1], o[2]))
		p[3] = (float(e.rnd()) * 9.313226e-11 + 0.8) * e.s * 0.4
		if (e.flags & FxEmitter.F_EMIT) == 0 or not e.has_carrier:
			if p[0x14] < 0:
				return false
			p[0x16] = alpha(tab(T_ORBIT_A, p[0x14] + 1))
			p[0x14] -= 1
		return true
	p[0x14] -= 1
	if p[0x14] == 0:
		return false
	if p[0x14] < 7:
		p[0x16] = alpha(tab(T_ORBIT_A, p[0x14]))
	p[0x11] += 1
	if p[0x11] == 0x10:
		p[0x11] = 0xc
	setp(p, getv(p, 8))
	p[3] = p[3] * 0.97
	p[10] = p[10] + p[0xd]
	p[0xd] = p[0xc] * p[0xd]
	return true


## the orbiters turn around the caster.
func ct_orbit(e: FxEmitter, c: Array) -> void:
	var x: float = c[6]
	c[9] = c[0]
	c[0xa] = c[1]
	c[0xb] = c[2]
	c[6] = c[7] * c[4] + c[6] * c[3]
	c[7] = c[3] * c[7] - x * c[4]
	c[0] = e.wp.x + c[6]
	c[1] = e.wp.y + c[7]
	c[2] = e.wp.z + c[8]


# ------------------------------------------------------ 2030 LightningBlast

## 10 bolt points fall with gravity for 10 ticks, throwing sparks.
func sp_lblast(e: FxEmitter, p: Array, _idx: int) -> bool:
	if e.cp[0][9] == 0.0:   # first spawn: place the bolt points (set)
		for c: Array in e.cp:
			var r := rr(e, 0.0, 1.0)
			var a := rr(e, 0.0, 6.2831855)
			var v := Vector3(sin(a) * r, cos(a) * r, 0.0) * e.s
			var q := e.wp + v * 0.3
			q.z = e.ground(q.x, q.y)
			var d := Vector3(v.x, v.y, 0.5)
			d = d / sqrt(v.x * v.x + v.y * v.y + 0.25)
			c[0] = q.x
			c[1] = q.y
			c[2] = q.z
			c[3] = d.x * 0.5
			c[4] = d.y * 0.5
			c[5] = d.z * 0.5
			c[6] = q.x
			c[7] = q.y
			c[8] = q.z
			c[9] = 1.0
			c[0xc] = 0
			c[0xd] = 0
	var n := e.cp.size()
	var c0: Array = e.cp[0]
	p[0x16] = W
	if int(c0[0xc]) < n * 2:
		# the bolt points and their glows
		var i := int(c0[0xc]) / 2
		p[0x11] = 0
		p[0x14] = 10
		p[0x13] = int(c0[0xc]) & 1
		p[0x15] = i + 1
		var c: Array = e.cp[i]
		setp(p, Vector3(c[0], c[1], c[2]))
		p[3] = 0.0
		p[0xb] = 0.1
		c0[0xc] = int(c0[0xc]) + 1
		if p[0x13] != 0:
			p[0xb] = (float(e.rnd()) * 2.0954757e-10 + 0.5) * e.s * 0.2
			p[0x11] = (e.rnd() & 3) + 0xc
		else:
			p[0xb] = e.s * 0.4
		p[3] = p[0xb]
		return true
	p[0x15] = 0
	if e.live() < 200 and int(c0[0xd]) < 5:
		# ground sparks around the centre
		p[0x16] = alpha(0x3f)
		p[0x11] = 8
		var f := 1.0 - u01(e) * u01(e)
		var a := float(e.rnd()) * 1.4621765e-09
		setv(p, 0xe, Vector3(cos(a) * f, sin(a) * f, 0.0) * (e.s * 0.3))
		p[0] = e.cp[0][0] + p[0xe]
		p[1] = e.cp[0][1] + p[0xf]
		p[2] = (1.0 - f) * e.s * 0.1 + float(e.cp[0][2])
		p[3] = 0.0
		p[0x13] = 0
		p[0x14] = roundi(9.0 - f * 3.0)
		p[0xb] = (2.0 - f) * (float(e.rnd()) * 9.313226e-12 + 0.1) * e.s
		return true
	# a spark along a falling bolt segment
	var c: Array = e.cp[e.rnd() % n]
	p[0x11] = 1
	p[0x14] = 6
	p[0x13] = 1
	p[0xb] = float(e.rnd()) * 2.3283064e-12 * 3.0 + 0.06
	var f := u01(e)
	setp(p, Vector3(c[0], c[1], c[2]))
	p[3] = 0.0
	setv(p, 8, Vector3(c[0], c[1], c[2]) * f + Vector3(c[6], c[7], c[8]) * (1.0 - f))
	return true


func up_lblast(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] < 0:
		return false
	if p[0x15] == 0:
		p[0x16] = ((int(tab(T_BOLT_A, p[0x14])) << 22) & 0xff000000) | RGB
		if p[0x13] != 0:
			p[0x11] += 1
			setp(p, getv(p, 8))
			p[3] = p[0xb]
			p[0xb] = p[0xb] * 0.9
			return true
		var f: int = p[0x11]
		p[0x11] = ((f + 1) & 3) | (f & ~3)
		setp(p, getp(p) + getv(p, 0xe))
		p[3] = p[0xb]
		p[0xb] = p[0xb] * 0.9
		setv(p, 0xe, getv(p, 0xe) * 0.6)
		return true
	var c: Array = e.cp[int(p[0x15]) - 1]
	if p[0x13] == 0:
		setp(p, Vector3(c[0], c[1], c[2]))
		p[3] = p[0xb]
		return true
	setp(p, Vector3(c[0], c[1], c[2]))
	if p[3] == 0.0:
		e.d0 = 0x32
		p[3] = p[0xb]
	else:
		p[3] = 0.0
	return true


func ct_lblast(e: FxEmitter, c: Array) -> void:
	e.d0 = 0x32
	c[6] = c[0]
	c[7] = c[1]
	c[8] = c[2]
	c[0xd] = int(c[0xd]) + 1
	c[0] += c[3]
	c[1] += c[4]
	c[2] += c[5]
	c[5] = c[5] - 0.075
	if int(c[0xd]) > 9:
		e.flags &= ~FxEmitter.F_EMIT


# ------------------------------------------------------ 2038 ZoneExit

## stars in the exit rectangle, rising.
func sp_exit(e: FxEmitter, p: Array, _idx: int) -> bool:
	e.d0 = mini(40, roundi(e.k118 * e.k11c))
	p[0x16] = W if e.v130.x == 0.0 else 0x00ff6060
	p[0x14] = 15
	p[0x11] = e.rnd() & 15
	p[0x13] = 1
	p[0x15] = 0
	var x := u2(e)
	var y := u2(e)
	var px := (x * e.k118 * e.k120 + e.wp.x) - y * e.k124 * e.k11c
	var py := y * e.k120 * e.k11c + e.k124 * e.k118 * x + e.wp.y
	p[0] = px
	p[1] = py
	p[3] = 0.0
	p[2] = e.ground(px, py) + 0.1
	p[0xb] = (float(e.rnd()) * 1.3969838e-10 + 0.7) * ((1.9 - x * x) - y * y) * 0.05
	return true


func up_exit(_e: FxEmitter, p: Array) -> bool:
	p[0x16] = alpha(tab(T_EXIT_A, p[0x14]), int(p[0x16]) & RGB)
	p[0x14] -= 1
	if p[0x14] < 0:
		return false
	var f: int = p[0x11]
	p[2] = p[2] + 0.05
	p[0x11] = ((f + 1) & 3) | (f & ~3)
	p[3] = p[0xb]
	return true


# ------------------------------------------------------ 2051 StartTrans

func sp_trans(e: FxEmitter, p: Array, _idx: int) -> bool:
	if e.live() == 0:
		p[0x14] = 4
		p[0x15] = 1
		p[0x11] = 12
		setp(p, e.wp)
		p[3] = 1.0
	else:
		p[0x14] = 15
		p[0x15] = 0
		p[0x11] = e.rnd() % 12
		var v := ball(e).normalized()
		setv(p, 8, v * e.s)
		setp(p, e.wp + getv(p, 8))
		var d := float(p[0x14] + 3)
		setv(p, 0xe, -getv(p, 8) / d)
		p[0xb] = e.s * 0.05
	p[0x16] = RGB
	p[3] = 0.0
	return true


func up_trans(e: FxEmitter, p: Array) -> bool:
	if p[0x15] == 0:
		p[0x14] -= 1
		if p[0x14] < 0:
			return false
		if not e.has_carrier and p[0x14] > 3:
			p[0x14] = 4
		var f: int = p[0x11]
		p[0x11] = ((f + 1) & 3) | (f & ~3)
		setp(p, getp(p) + getv(p, 0xe))
		p[3] = p[0xb]
		p[0x16] = alpha(tab(T_EXIT_A, p[0x14]))
		return true
	if not e.has_carrier:
		p[0x14] -= 1
		if p[0x14] < 0:
			return false
		p[0x16] = alpha(tab(T_EXIT_A, p[0x14]))
		p[3] = p[3] * 0.6
		return true
	setp(p, e.wp)
	p[0x16] = W
	p[3] = (float(e.rnd()) * 9.313226e-11 + 0.8) * float(e.cp[0][6])
	return true


## the head grows for 30 ticks, the spawn rate with it (max 8).
func ct_trans(e: FxEmitter, c: Array) -> void:
	c[0xd] = int(c[0xd]) - 1
	if int(c[0xd]) < 0:
		e.flags &= ~(FxEmitter.F_EMIT | FxEmitter.F_KEEP)
		e.attach(null)
	c[6] = e.s * 0.02 + c[6]
	c[7] = c[7] + 0.4
	e.d0 = mini(8, roundi(c[7]))


# ------------------------------------------------------ 203c Bag

## colour per control step (r, g, b), yellow through pink to violet.
const T_BAG_RGB := [0xfbfe8f, 0xfce395, 0xfcc99a, 0xffb09a, 0xff9ba3, 0xfc98b0, 0xfa96c3, 0xf795d4,
	0xf393ed, 0xef90f9, 0xef90f9, 0xef90f9]
## alpha by remaining life.
const T_BAG_A := [0, 64, 112, 255, 255, 255, 255, 255, 255, 255]
## size per control step, filled by the first spawn: 1.0 × 0.93^i.
static var _bag_size := []


static func _bag_t(i: int) -> float:
	if _bag_size.is_empty():
		var v := 1.0
		for k in 12:
			_bag_size.append(v)
			v *= 0.93
	return _bag_size[clampi(i, 0, 11)]


## . The first 80 particles are the midges, one per control point
## (= its index); beyond that each spawn is a trail mote on a random
## midge's last step (pos + u·step, u in [−1, 0]), its colour, frame 4 and a
## life of min(steps left + 1, 5).
func sp_bag(e: FxEmitter, p: Array, _idx: int) -> bool:
	_bag_t(0)
	if e.live() < 80:
		p[0x11] = rnd(e) & 3
		p[0x15] = e.live()
		p[0x16] = RGB
		p[0x14] = 15
		setp(p, e.wp)
		p[3] = 0.0
		return true
	var c: Array = e.cp[rnd(e) % 80]
	var ci := int(c[0xc])
	p[0x16] = tab(T_BAG_RGB, ci)
	p[0x14] = mini(int(c[0xd]) + 1, 5)
	p[0x11] = 4
	p[0x15] = -1
	var f := u01(e) - 1.0
	setp(p, getv(c, 0) + getv(c, 3) * f)
	p[3] = _bag_t(ci) * e.s * 0.1
	return true


## . Trail motes fade out by T_BAG_A over their life; a midge sits
## on its control point (size 0.15, colour of its step) and dies with it.
func up_bag(e: FxEmitter, p: Array) -> bool:
	if int(p[0x15]) < 0:
		p[0x14] = int(p[0x14]) - 1
		if int(p[0x14]) <= 0:
			return false
		p[0x11] = int(p[0x11]) + 1
		p[0x16] = alpha(tab(T_BAG_A, int(p[0x14])), int(p[0x16]) & RGB)
		return true
	var c: Array = e.cp[int(p[0x15])]
	if int(c[0xd]) == -13:
		return false
	p[0x11] = (int(p[0x11]) + 1) & 3
	setp(p, getv(c, 0))
	p[3] = _bag_t(int(c[0xc])) * e.s * 0.15
	p[0x16] = alpha(tab(T_BAG_A, mini(int(p[0x14]), 9)), tab(T_BAG_RGB, int(c[0xc])))
	if getv(c, 3) == Vector3.ZERO:   # a fresh midge: no interpolation from the old spot
		p[4] = p[0]
		p[5] = p[1]
		p[6] = p[2]
		p[7] = p[3]
		p[0x17] = p[0x16]
		p[3] = e.s * 0.15
	return true


## per control point each tick: counts the steps left. At
## its end the midge restarts within ±0.2·size of the carrier with colour
## step rand % 3, a random velocity ball · size · 0.2 and 7..9 steps (no
## carrier: −13, the midge dies). Each step: colour step + 1, one time in six
## a kick ball · size · 0.05, position += velocity, = the step.
func ct_bag(e: FxEmitter, c: Array) -> void:
	c[0xd] = int(c[0xd]) - 1
	if int(c[0xd]) < 0:
		if not e.has_carrier:
			c[0xd] = -13
			return
		c[0xc] = rnd(e) % 3
		var a := e.s * 0.2
		var b := e.s * -0.2
		var q := e.wp
		q.x += u01(e) * (a - b) + b
		q.y += u01(e) * (a - b) + b
		q.z += u01(e) * (a - b) + b
		setv(c, 0, q)
		setv(c, 6, ball(e) * e.s * 0.2)
		c[0xd] = rnd(e) % 3 + 7
		setv(c, 3, Vector3.ZERO)
		return
	c[0xc] = int(c[0xc]) + 1
	if rnd(e) % 6 == 0:
		setv(c, 6, getv(c, 6) + ball(e) * e.s * 0.05)
	setv(c, 0, getv(c, 0) + getv(c, 6))
	setv(c, 3, getv(c, 6))


# ------------------------------------------------------ 203d PortalStar

func sp_pstar(e: FxEmitter, p: Array, _idx: int) -> bool:
	p[0x16] = RGB
	p[0x14] = 15
	p[0x11] = 0
	setp(p, e.wp)
	p[3] = 0.0
	return true


func up_pstar(e: FxEmitter, p: Array) -> bool:
	if (e.flags & FxEmitter.F_EMIT) == 0:
		return false
	p[0x16] = W
	p[3] = (float(e.rnd()) * 9.313226e-11 + 0.8) * e.s
	setp(p, e.wp)
	return true


# ------------------------------------------------------ 203e Portal

## a spiral rising to 8 m and a glow 6.4 m up.
func sp_portal(e: FxEmitter, p: Array, _idx: int) -> bool:
	if e.live() == 0:
		setp(p, e.wp)
		p[3] = 0.0
		p[0x16] = 0x60ffffff
		p[0x15] = 1
		p[0x11] = 15
		p[2] = p[2] + 6.4
		return true
	p[0x15] = 0
	p[0x16] = RGB
	p[0x14] = e.ec
	p[0x13] = e.e4
	var f := (u01(e) + 1.0) * u01(e) * 0.5
	var a := float(e.rnd()) * 1.4629215e-09
	var r := f * 2.5 * absf(e.s)
	p[0] = sin(a) * r + e.wp.x
	p[1] = cos(a) * r + e.wp.y
	p[2] = e.wp.z
	p[3] = 0.0
	p[0xd] = (2.0 - f) * 0.3
	var turn: float
	if u01(e) <= f:
		p[0x11] = e.rnd() & 3
		turn = -0.1
	else:
		p[0x11] = e.rnd() % 11 + 4
		turn = 0.1
	p[8] = cos(turn)
	p[9] = sin(turn)
	p[0xb] = p[0] - e.wp.x
	p[0xc] = p[1] - e.wp.y
	p[10] = ((1.0 - f) + 3.0) * 2.5 * 0.015
	p[2] = (u01(e) - 0.5) * p[10] + p[2]
	p[0x14] = 1
	return true


func up_portal(e: FxEmitter, p: Array) -> bool:
	if p[0x15] == 0:
		if p[0x14] == 0:
			return false
		var x: float = p[8] * p[0xb] + p[0xc] * p[9]
		var y: float = p[0xc] * p[8] - p[0xb] * p[9]
		p[0xb] = x
		p[0xc] = y
		p[0] = x + e.wp.x
		p[1] = y + e.wp.y
		p[2] = e.s * p[10] + p[2]
		p[10] = p[10] * 1.03
		p[0x13] -= 1
		if p[0x13] == 0:
			p[0x11] += 1
			if p[0x11] == 4:
				p[0x11] = 0
			if p[0x11] == 15:
				p[0x11] = 4
			p[0x13] = e.e4
		var h: float = p[2] - e.wp.z
		if h > 8.0:
			p[3] = 0.0
			p[0x14] = 0
			p[0x16] = RGB
			return true
		p[3] = p[0xd]
		p[0x16] = alpha(mini(0x40, (roundi((8.0 - h) * 25.0) + 0x37) >> 2))
		return true
	if (e.flags & FxEmitter.F_EMIT) == 0:
		return false
	if e.s >= 1.0:
		p[3] = float(e.rnd()) * 9.313226e-11 * 1.5 + 1.2
	else:
		p[3] = 0.0
	return true


## the spawn rate follows the size.
func ct_portal(e: FxEmitter, _c: Array) -> void:
	e.d0 = roundi(50.0 * clampf(e.s / maxf(e.k128, 0.01), 0.0, 4.0))


# ------------------------------------------------ 2041 / 2042 FireStar, AcidStar

func sp_star(e: FxEmitter, p: Array, _idx: int) -> bool:
	p[0x16] = W
	p[0x14] = 3
	p[0x11] = e.ec
	setp(p, e.wp)
	p[3] = e.s
	e.flags &= ~FxEmitter.F_EMIT
	return true


func up_star(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] < 0:
		return false
	setp(p, e.wp)
	p[3] = p[3] * 0.9
	return true


# ------------------------------------------------------ 2043 Sparks

func sp_sparks(e: FxEmitter, p: Array, _idx: int) -> bool:
	if e.live() == 0:
		p[0x16] = W
		setp(p, e.wp)
		p[3] = 0.0
		p[0x11] = 0
		p[0x15] = 1
		return true
	e.flags &= ~FxEmitter.F_EMIT
	p[0x16] = W
	var k := float(e.rnd()) * 1.3969838e-10 + 0.8
	var v := ball(e).normalized()
	var sp := k * e.s * k * 0.2
	setv(p, 0xe, v * sp)
	setp(p, e.wp + getv(p, 0xe) * u01(e))
	p[3] = (float(e.rnd()) * 9.313226e-11 + 0.8) * e.s * 0.2
	p[0x14] = 6
	p[0x15] = 0
	p[0x11] = e.rnd() % 3 + 1
	return true


func up_sparks(e: FxEmitter, p: Array) -> bool:
	if p[0x15] == 0:
		p[0x14] -= 1
		if p[0x14] < 0:
			return false
		p[0x16] = alpha(tab(T_SPARK_A, p[0x14]))
		setp(p, getp(p) + getv(p, 0xe))
		p[3] = p[3] * 0.9
		setv(p, 0xe, getv(p, 0xe) * 0.6)
		p[0x11] += 1
		return p[0x11] < 16
	if p[3] == 0.0:
		p[3] = (float(e.rnd()) * 9.313226e-11 + 0.8) * e.s * 0.55
		return true
	p[3] = 0.0
	return false


# ------------------------------------- 2044..2046 / 204c VisionStar1..3, Silence

## up to 5 stars circling over the head (one for ec != 1).
func sp_vstar(e: FxEmitter, p: Array, _idx: int) -> bool:
	var n := e.live()
	if n > 4 or (n > 0 and e.ec != 1):
		return false
	p[0x16] = RGB
	p[0x11] = e.ec
	setp(p, e.wp)
	p[3] = 0.0
	if e.ec != 1:
		return true
	var a := TAU_ * 0.2 * n
	setv(p, 8, Vector3(cos(a), sin(a), 0.0) * 0.5)
	setp(p, getp(p) + getv(p, 8))
	return true


func up_vstar(e: FxEmitter, p: Array) -> bool:
	var sz: float = p[3]
	p[0x16] = W
	setp(p, e.wp)
	var k := 0.3
	if e.ec == 1:
		k = 0.17
		var vx: float = p[8]
		p[8] = vx * cos(0.07) - p[9] * sin(0.07)
		p[9] = p[9] * cos(0.07) + vx * sin(0.07)
		setp(p, getp(p) + getv(p, 8))
	if e.type == 0x204c:
		p[2] = p[2] + 0.7
	var s2 := sz * 0.95 + (float(e.rnd()) * 4.1909515e-10 + 0.1) * e.s * k * 0.05
	if (e.flags & FxEmitter.F_EMIT) == 0 or not e.has_carrier:
		s2 = s2 * 0.95
		e.s = 0.0
		if s2 < 0.03:
			p[3] = 0.0
			p[0x16] = RGB
			return false
	p[3] = s2
	return true


# ------------------------------------------------------ 2048 (Regeneration effect)

## two orbiters, phases 0 and pi, plus a sparkle trail.
func sp_silence(e: FxEmitter, p: Array, _idx: int) -> bool:
	var n := e.live()
	if n < 2:
		p[0x16] = RGB
		p[0x11] = 6
		setp(p, e.wp)
		p[3] = 0.0
		var ph := 3.1416 if n == 0 else 0.0
		p[8] = ph
		p[0xb] = ph
		p[9] = 0.1
		p[0xc] = 0.12
		p[0xd] = 1.0
		p[0x15] = 1
		return true
	var o: Array = e.parts[e.rnd() & 1]
	var f := u01(e)
	var v := ball(e)
	var r: float = o[3]
	p[3] = 0.0
	setp(p, v * r * 0.8 + getp(o) - getv(o, 0xe) * f)
	p[0x16] = W
	p[0x11] = 6
	p[0x15] = 0
	p[0x14] = 7
	p[8] = (float(e.rnd()) * 9.313226e-11 + 0.8) * e.s * 0.08
	return true


func up_silence(e: FxEmitter, p: Array) -> bool:
	if (e.flags & FxEmitter.F_EMIT) == 0 or not e.has_carrier:
		if p[0x15] != 0:
			e.s = e.s * 0.85
		if e.s < 0.02:
			p[3] = 0.0
			p[0x16] = RGB
			return false
	if p[0x15] != 0:
		var r: float = p[0xd]
		if e.carrier != null:
			r = carrier_size(e).y * 0.5
			p[0xd] = r
		var a := Vector3(cos(p[8]), sin(p[8]), sin(p[0xb]) * 0.5)
		var k := r / maxf(a.length(), 0.0001)
		var pos := Vector3(k * a.x + e.wp.x, k * a.y + e.wp.y, r * 0.5 + k * a.z + e.wp.z)
		setv(p, 0xe, pos - getp(p))
		setp(p, pos)
		p[0x16] = W
		p[8] = p[9] + p[8]
		p[0xb] = p[0xc] + p[0xb]
		p[3] = (float(e.rnd()) * 4.656614e-11 + 0.9) * e.s * 0.22
		return true
	p[0x14] -= 1
	if p[0x14] < 1:
		p[3] = 0.0
		return false
	p[3] = p[8]
	p[8] = p[8] * 0.8
	return true


# ------------------------------------------------------ 2049 FeebleMind

func sp_feeble(e: FxEmitter, p: Array, _idx: int) -> bool:
	e.d0 = roundi(e.s + e.s)
	p[0x16] = RGB
	p[0x11] = e.rnd() & 0xf
	setp(p, e.wp)
	p[3] = 0.0
	p[0x14] = 20
	var a := u01(e) * 6.2831855
	setv(p, 8, Vector3(cos(a) * 0.05, sin(a) * 0.05, 0.0))
	setp(p, getp(p) + getv(p, 8))
	p[0xd] = (float(e.rnd()) * 4.656614e-11 + 0.9) * e.s * 0.035
	return true


## spirals outward, turning 0.07 rad x1.1, rising 0.05.
func up_feeble(_e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] < 0:
		return false
	p[0x16] = alpha(tab(T_FADE_IN, p[0x14]))
	setp(p, getp(p) - getv(p, 8))
	var vx: float = p[8]
	p[8] = (p[9] * sin(0.07) + vx * cos(0.07)) * 1.1
	p[9] = (p[9] * cos(0.07) - vx * sin(0.07)) * 1.1
	p[0] += p[8]
	p[1] += p[9]
	p[3] = p[0xd]
	p[0x11] = (p[0x11] + 1) & 0xf
	p[2] = p[10] + p[2] + 0.05
	p[0xd] = p[0xd] * 1.04
	return true


# ------------------------------------------------------ 204a / 204b FeetCloud

func sp_feet(e: FxEmitter, p: Array, _idx: int) -> bool:
	e.d0 = roundi(e.s * 8.0)
	p[0x16] = RGB
	p[0x11] = e.rnd() & 0xf
	var ci := e.rnd() & 1
	var c: Array = e.cp[ci]
	if int(c[0xc]) < 0:
		setp(p, e.wp)
	else:
		setp(p, Vector3(c[0], c[1], c[2]))
	p[3] = 0.0
	var v := Vector3.ZERO
	for i in 10:
		v = Vector3(u2(e), u2(e), 0.0)
		if v.length_squared() < 1.0:
			break
	setv(p, 0xe, v * e.s * 0.02)
	p[0xb] = 0.0
	p[9] = 1.0
	p[0xc] = 0.0
	p[0x14] = 10
	p[0xd] = 0.0
	p[0x15] = ci
	p[8] = e.s * e.s * 0.4 * 0.25
	p[2] = p[8] * 1.2 + p[2]
	return true


func up_feet(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] < 0:
		return false
	if ((e.flags & FxEmitter.F_EMIT) == 0 or not e.has_carrier) and p[0x14] > 8:
		p[0x14] = 8
	p[0x16] = (int(tab(T_FADE_IN, p[0x14])) << 24) | (e.ec & RGB)
	p[0xb] = p[0xe] + p[0xb]
	p[0xc] = p[0xf] + p[0xc]
	p[0xd] = p[0x10] + p[0xd]
	var c: Array = e.cp[p[0x15]]
	var w: float = p[9]
	p[1] = (1.0 - w) * p[1] + (p[0xc] + c[1]) * w
	p[0] = (1.0 - w) * p[0] + (p[0xb] + c[0]) * w
	p[2] = (1.0 - w) * p[2] + (p[0xd] + c[2]) * w
	p[3] = p[8]
	p[8] = p[8] * 0.8
	p[9] = p[9] * 0.98
	setv(p, 0xe, getv(p, 0xe) * 0.9)
	return true


## the two clouds follow the feet ("ll3" / "rl3").
func ct_feet(e: FxEmitter, c: Array) -> void:
	var q: Vector3 = e.fx.bone_point(e.carrier, "ll3" if int(c[0xd]) == 0 else "rl3") if e.carrier else e.wp
	c[0] = q.x
	c[1] = q.y
	c[2] = q.z
	c[0xc] = 0


# ------------------------------------------------- DrawPath

##  (on the global, its plane list): the landscape
## height, raised to the highest object plane over (x, y). The planes are the
## upward faces (normal z >= 0.8) of the boxes of the "BASE*"
## parts (part flag 0x400)
## i.e. the floors the AI map lays, e.g. the stone platforms
## of the gz1g ruins. The path dots and the target marks (
## the same list) sit on them, not on the land below.
static func plane_ground(e: FxEmitter, x: float, y: float) -> float:
	var g: float = e.ground(x, y)
	var w: GameWorld = e.fx.world
	if w and w.nav:
		g = float(w.nav.plane_at(Vector2(x,y),g).height)
	return g


## The path dots and target marks are depth tested like every particle: the
## world pass draws the land, the objects, then the
## liquids (the second texture set) with Z
## write on (render state 0xe is 1 and only switched off for
## the sky and the particle block), then, in the 0x400 block, the particles
##  with Z write off but the Z test on (state 7 untouched; the
## TLP gives every corner its real depth). So a dot or mark
## under the water surface is hidden, as is one behind a hill or under an
## overhang. Godot draws the water without a depth write, so the remake hides
## a particle of these types whose centre is under the cell's water level.
## Remake option path_through (ParticleFx.THROUGH_TYPES, default on): they are
## drawn over everything instead, a dot or mark under the water at
## ParticleFx.THROUGH_ALPHA (see through_alpha).
static func under_water(e: FxEmitter, x: float, y: float, z: float) -> bool:
	var w: GameWorld = e.fx.world
	return w != null and w.terrain != null and w.terrain.water_at(x, y) > z


## The alpha a dot or mark under the water keeps: 0 (hidden, the original)
## or, with option path_through, ParticleFx.THROUGH_ALPHA of it.
static func through_alpha(a: int) -> int:
	return roundi(a * ParticleFx.THROUGH_ALPHA) if ParticleFx.through_on() else 0


## one dot per logic tick along the carrier's predicted path
## (at tick + idx), up to ticks, skipping repeats. The
## original's carrier is a ghost character moving at base 0.5 (0.25 m a tick
## level ground, OrderMarks.GHOST_BASE); the remake passes its predicted
## per-tick positions as the emitter's "path" meta. The colour:
## 0, 1, 2 → (kept in the control point).
func sp_path(e: FxEmitter, p: Array, idx: int) -> bool:
	if e.cp.is_empty():
		e.set_controls(1)
		var c: Array = e.cp[0]
		c[6] = -1.0
		c[7] = -1.0
		c[8] = -1.0
		c[0xc] = 0xb0b0b0 if e.k118 == 0.0 else (0x40ff40 if e.k118 == 1.0 else (0xff8028 if e.k118 == 2.0 else 0))
	var path: PackedVector3Array = e.get_meta("path", PackedVector3Array())
	if path.is_empty() or e.k11c < float(idx):
		return false
	var q := path[mini(idx, path.size() - 1)]
	var cc: Array = e.cp[0]
	if cc[6] == q.x and cc[7] == q.y and cc[8] == q.z:
		return false
	cc[6] = q.x
	cc[7] = q.y
	cc[8] = q.z
	p[0] = q.x
	p[1] = q.y
	p[2] = plane_ground(e, q.x, q.y) + 0.15
	p[3] = 0.07
	p[0x11] = 15
	p[0x14] = -10
	p[0x13] = idx
	p[0x16] = cc[0xc]
	return true


## the first update gives life idx · 8 / live + 7, so the dots fade
## out nearest first; alpha.
func up_path(e: FxEmitter, p: Array) -> bool:
	if p[0x14] == -10:
		p[0x14] = int(p[0x13]) * 8 / maxi(1, e.live()) + 7
	p[0x14] -= 1
	if p[0x14] < 0:
		return false
	var a := roundi(float(tab(T_PATH_A, p[0x14])) * 255.0)
	if under_water(e, p[0], p[1], p[2]):
		a = through_alpha(a)
	p[0x16] = alpha(a, int(p[0x16]) & RGB)
	return true


## emits once (the control point exists from the first spawn ).
func ct_path(e: FxEmitter, _c: Array) -> void:
	e.flags &= ~FxEmitter.F_EMIT


## 128 dots on a ring growing from the target (angle i · 0.0491)
## for 0x203b also four diagonal lines of 32 (a red cross).
func sp_target(e: FxEmitter, p: Array, idx: int) -> bool:
	var vx: float
	var vy: float
	if idx < 0x80:
		vx = sin(idx * 0.049140625) * 0.1
		vy = cos(idx * 0.049140625) * 0.1
	else:
		var k := (idx - 0x80) & 31
		var j := clampi((idx - 0x80) >> 5, 0, 3)
		vx = k * 0.0032258064 * T_TARGET_DX[j]
		vy = k * 0.0032258064 * T_TARGET_DY[j]
	p[0] = e.wp.x
	p[1] = e.wp.y
	p[2] = e.wp.z
	p[3] = 0.0
	p[8] = vx
	p[9] = vy
	p[10] = 0.0
	p[0x14] = 6
	p[0x11] = 15
	p[0xb] = 0.07
	p[0xc] = 1.0
	p[0x16] = e.cp[0][0xc]
	return true


## moves out ×1.05 per tick, kept 0.1 above the ground and above
## the plane of the ground at the target.
func up_target(e: FxEmitter, p: Array) -> bool:
	p[0x14] -= 1
	if p[0x14] < 0:
		return false
	p[0x16] = alpha(tab(T_TARGET_A, p[0x14]), int(p[0x16]) & RGB)
	p[0] += p[8]
	p[1] += p[9]
	p[2] += p[10]
	var c: Array = e.cp[0]
	var g: float = e.ground(p[0], p[1]) + 0.1
	var pl: float = c[3] - ((p[1] - e.wp.y) * c[7] + (p[0] - e.wp.x) * c[6]) * c[8] + 0.1
	p[2] = maxf(g, pl)
	if under_water(e, p[0], p[1], p[2]):   # hidden or faded under the water (see under_water)
		p[0x16] = alpha(through_alpha(tab(T_TARGET_A, p[0x14])), int(p[0x16]) & RGB)
	p[3] = p[0xb]
	p[8] *= 1.05
	p[9] *= 1.05
	p[10] *= 1.05
	p[0xb] = p[0xc] * p[0xb]
	return true


## the object plane at the target on the first tick (:
## the highest plane of the list over the point, see plane_ground
## height and normal, normal z inverted; none: height 0, normal up, so the
## marks keep to the ground + 0.1), emitting stops after two ticks.
func ct_target(e: FxEmitter, c: Array) -> void:
	if int(c[0xd]) == 0:
		var x := e.wp.x
		var y := e.wp.y
		var h := 0.0
		var n := Vector3(0, 0, 1)
		var world: GameWorld = e.fx.world
		if world and world.nav:
			var plane := world.nav.plane_at(Vector2(x,y))
			h = float(plane.height)
			n = plane.normal
		c[3] = h
		c[6] = n.x
		c[7] = n.y
		c[8] = 1.0 / n.z if n.z != 0.0 else 0.0
	c[0xd] = int(c[0xd]) + 1
	if int(c[0xd]) > 1:
		e.flags &= ~FxEmitter.F_EMIT

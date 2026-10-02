class_name FxRainSnow
extends MeshInstance3D
## Rain and snow, the original's client precipitation object "RainSnow" (world
## drawn each frame from the world render
## between SetRenderState SRCBLEND = SRCALPHA / DESTBLEND = INVSRCALPHA;
## texture "rainsnow", unlit pre-transformed vertices, diffuse white, no fog).
## It is the last draw of the effects block (after the particles
## and the lightning), with the depth test on and z writes off
## (state 0xe = 0): drops nearer than a tree, rock or unit cover it, farther
## ones are hidden. The drop positions are world points (camera eye = world
## as for the sky dome), run through the device's own
## world→clip transform (with the top of the matrix stack, then
##  to XYZRHW). Godot draws units, foliage and map objects in its
## transparent pass, sorted by their centres; the mesh's centre is the world
## origin, so without RENDER_PRIORITY the rain went first and every object
## was drawn over it.
##
## Grid: offsets 40, −40, 39, −39 … 1, −1, 0 (81 × 81 cells
## 0.5 m, far to near) around the camera's point projected along the fall
## direction to the reference height 40 m. Per cell a hash h = table[(ix² + iy)
## & 31] + ix · a + iy · b & 0xffff, t = h + world ticks (+ the tick fraction),
## u = round(t / P); the cell has a drop when (u & 63) < density (0..64
## faded with the sound by (1 − cos) / 2 over the fade time).
## Phase tt = t − u · P, height 40 + tt · vz, horizontal jitter
## ((u · −0x3b) & 0xff − 128) / 128 · 0.5 m and ((u · 0x43) & 0xff − 128) /
## 128 · 0.5 m plus tt · wind, vertical ((u · −0x7f) & 0xff − 128) / 128 · 10 m,
## frame u & 3 (a column of the texture row).
## Rain (table, a = 0xac, b = 0xd, P = 200, vz = wind z −
## 0.5 m per tick): heights wrap into [max(camera − 30, 0), camera + 30]; a
## triangle with a 6.6 cm base across the view axis (x or y by the larger cell
## offset) and its tip 1 m up against the wind, UV row v 0.75 (base) → 1.0 (tip);
## drops nearer than 4 m (view depth) are skipped.
## Snow (table, a = −0x7570, b = 0x45b3, P = 1000, vz =
## wind z − 0.1): flakes outside [max(camera − 30, 0), camera + 30] are skipped;
## sway x += A(z) + B(fmod(x + 1000, 50)), y += C(z) + D(fmod(y + 1000, 50)),
## z += E(z) with five smooth random curves (×5 at start-up: 128
## rand() − 0x3fff values smoothed 0.3 / 0.7 forward and back, shifted by 20,
## scaled to RMS 0.5 m, cubic Hermite with central tangents, segments 0..123);
## a triangle offset in clip space by (∓0.1, −0.06) / (0, +0.14) (× w, so a
## fixed size in the world, ~0.1 m), UV row v 0.5 (base) → 0.74 (tip).
## The wind is only set by a SetWind network message
## (FUN_00669...); nothing sends it at zone
## start, so it is 0 here. **Approx.**: the curves come from Godot's RNG, not
## the original's rand sequence; drops partly outside the view are clipped, not
## dropped.

const RAIN_TAB := [17, 43, 456, 942, 32, 234, 865, 95, 321, 47, 909, 284, 543, 396, 193, 120,
	98, 784, 633, 10, 259, 77, 118, 66, 921, 849, 356, 80, 475, 235, 213, 826]
const SNOW_TAB := [5417, 2343, 34456, 12942, 8832, 12234, 45865, 8395, 45321, 8847, 99009, 55284,
	76543, 45396, 12193, 98120, 6798, 79784, 11633, 5710, 54259, 3477, 78118, 1266, 97821, 80949,
	35786, 8780, 78475, 72235, 34213, 92826]
const N := 81
## After the particles (ParticleFx.RENDER_PRIORITY, see-through ones + 2) and
## the lightning (+ 1): the last effect drawn, as.
const RENDER_PRIORITY := ParticleFx.RENDER_PRIORITY + 3

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D curves : filter_nearest;   // 128 x 5, R = value
uniform int mode = 1;          // 1 rain, 2 snow
uniform int density = 0;
uniform float t_now = 0.0;     // world ticks + fraction
uniform vec3 cam_ei;
uniform vec3 wind_ei = vec3(0.0);
uniform int tab[32];
varying vec2 uv;

float curve(int row, float a) {
	int i = int(a);   // __ftol truncates
	if (i < 0 || i > 123) {
		return 0.0;
	}
	float f = a - float(i);
	float p0 = texelFetch(curves, ivec2(max(i - 1, 0), row), 0).r;
	float p1 = texelFetch(curves, ivec2(i, row), 0).r;
	float p2 = texelFetch(curves, ivec2(i + 1, row), 0).r;
	float p3 = texelFetch(curves, ivec2(min(i + 2, 127), row), 0).r;
	float m1 = i == 0 ? p2 - p1 : (p2 - p0) * 0.5;
	float m2 = (p3 - p1) * 0.5;
	float d = (p2 - p1 - m1) * 2.0;
	float c3 = (m2 - m1) - d;
	float c2 = (d - 2.0 * c3) * 0.5;
	return ((c3 * f + c2) * f + m1) * f + p1;
}

vec3 godot_pos(vec3 e) {
	return vec3(e.x, e.z, -e.y);
}

void vertex() {
	int ox = int(VERTEX.x);
	int oy = int(VERTEX.y);
	int k = int(VERTEX.z);
	bool rain = mode == 1;
	float vz = wind_ei.z - (rain ? 0.5 : 0.1);
	float f13 = (cam_ei.z - 40.0) / vz;
	int ix = int(roundEven((cam_ei.x - wind_ei.x * f13) * 2.0)) + ox;
	int iy = int(roundEven((cam_ei.y - wind_ei.y * f13) * 2.0)) + oy;
	int h = rain ? (tab[(ix * ix + iy) & 31] + ix * 0xac + iy * 0xd) & 0xffff
		: (tab[(ix * ix + iy) & 31] + ix * -0x7570 + iy * 0x45b3) & 0xffff;
	float period = rain ? 200.0 : 1000.0;
	float t = float(h) + t_now;
	int u = int(roundEven(t / period));
	bool on = (u & 63) < density;
	float tt = t - float(u) * period;
	float hi = cam_ei.z + 30.0;
	float lo = max(cam_ei.z - 30.0, 0.0);
	float z = tt * vz + 40.0;
	if (rain) {
		if (z > hi) { z -= ceil((z - hi) / 60.0) * 60.0; }
		if (z < lo) { z += ceil((lo - z) / 60.0) * 60.0; }
	} else if (z < lo || z > hi) {
		on = false;
	}
	float x = float(((u * -0x3b) & 0xff) - 0x80) * 0.5 * 0.0078125 + tt * wind_ei.x + float(ix) * 0.5;
	float y = float(((u * 0x43) & 0xff) - 0x80) * 0.5 * 0.0078125 + tt * wind_ei.y + float(iy) * 0.5;
	float fr = float(u & 3) * 0.25;
	z += float(((u * -0x7f) & 0xff) - 0x80) * 10.0 * 0.0078125;
	vec4 clip;
	if (rain) {
		vec3 p = vec3(x, y, z);
		vec3 c = (VIEW_MATRIX * vec4(godot_pos(p), 1.0)).xyz;
		if (-c.z < 4.0) {
			on = false;
		}
		if (k == 2) {
			float wl = length(vec3(wind_ei.xy, vz));
			p = vec3(x - wind_ei.x / wl, y - wind_ei.y / wl, z + 1.0);
			uv = vec2(fr + 0.125, 1.0);
		} else {
			float s = k == 0 ? -0.033 : 0.033;
			if (abs(oy) < abs(ox)) {
				p.y += s;
			} else {
				p.x += s;
			}
			uv = vec2(fr + (k == 0 ? 0.0 : 0.25), 0.75);
		}
		clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(godot_pos(p), 1.0);
	} else {
		float sx = x + curve(0, z) + curve(1, mod(x + 1000.0, 50.0));
		float sy = y + curve(2, z) + curve(3, mod(y + 1000.0, 50.0));
		float sz = z + curve(4, z);
		clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(godot_pos(vec3(sx, sy, sz)), 1.0);
		if (k == 2) {
			clip.y += 0.2 * 0.7;
			uv = vec2(fr + 0.125, 0.74);
		} else {
			clip.x += k == 0 ? -0.1 : 0.1;
			clip.y -= 0.2 * 0.3;
			uv = vec2(fr + (k == 0 ? 0.0 : 0.25), 0.5);
		}
	}
	POSITION = on ? clip : vec4(2.0, 2.0, 2.0, 1.0);
}

void fragment() {
	vec4 c = texture(tex, uv);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"""

static var _mesh: ArrayMesh
static var _curves: ImageTexture

var game: Node
var _mat: ShaderMaterial
var _mode := 0


func _init(g: Node) -> void:
	game = g
	name = "RainSnow"
	mesh = _grid_mesh()
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_mat.render_priority = RENDER_PRIORITY
	_mat.set_shader_parameter("tex", GameData.get_texture("rainsnow"))
	_mat.set_shader_parameter("curves", _curve_texture())
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	visible = false


func _process(_dt: float) -> void:
	var snd = game.get("sound")
	var w: Weather = snd.weather if snd else null
	var cam := get_viewport().get_camera_3d()
	if w == null or w._shown == 0 or cam == null:
		visible = false
		return
	var now: float = snd._ticks + snd._tick_acc / GameSound.TICK
	var dens := 64
	# follows the sound's fade.
	if w._fade != 0.0:
		var f := (now - w._start) / w._fade
		if f <= 1.0:
			var c := cos(f * PI)
			c = c + 1.0 if w._target == 0 else 1.0 - c
			dens = roundi(c * 0.5 * 64.0)
	var mode := w._shown
	if mode != _mode:
		_mode = mode
		_mat.set_shader_parameter("mode", mode)
		_mat.set_shader_parameter("tab", PackedInt32Array(RAIN_TAB if mode == 1 else SNOW_TAB))
	var p := cam.global_position
	_mat.set_shader_parameter("cam_ei", Vector3(p.x, -p.z, p.y))
	_mat.set_shader_parameter("density", dens)
	_mat.set_shader_parameter("t_now", now)
	visible = mode == 1 or mode == 2


## 81 x 81 triangles in the original's order (rows by the y offset, far to near)
## VERTEX carries (x offset, y offset, corner).
static func _grid_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var offs := []
	for i in range(40, 0, -1):
		offs.append(i)
		offs.append(-i)
	offs.append(0)
	var v := PackedVector3Array()
	for oy: int in offs:
		for ox: int in offs:
			for k in 3:
				v.append(Vector3(ox, oy, k))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh


##  (× 5, RMS 0.5 m): the snow sway curves, rows 0..4 =
static func _curve_texture() -> ImageTexture:
	if _curves:
		return _curves
	var img := Image.create(128, 5, false, Image.FORMAT_RF)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for row in 5:
		var a := PackedFloat32Array()
		a.resize(128)
		for i in 128:
			a[i] = float(rng.randi_range(0, 0x7fff) - 0x3fff)
		for i in range(1, 128):
			a[i] = a[i] * 0.3 + a[i - 1] * 0.7
		for i in range(127, 1, -1):
			a[i] = a[i] * 0.3 + a[i + 1] * 0.7 if i < 127 else a[i]
		for i in 0x6c:
			a[i] = a[i + 0x14]
		var ss := 0.0
		for i in 128:
			ss += a[i] * a[i]
		var k := 0.5 / sqrt(ss / 128.0)
		for i in 128:
			img.set_pixel(i, row, Color(a[i] * k, 0, 0))
	_curves = ImageTexture.create_from_image(img)
	return _curves

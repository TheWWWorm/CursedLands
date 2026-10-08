extends Node
## Real game/menu direction updates. Run on desktop Compatibility and
## Forward+, both normally and with --held-sun to exercise the fallback.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	GameData.options["gfx_volumetric"] = 0
	GameData.options["gfx_ssao"] = 0
	var fallback := Portability.constrained() or OS.get_cmdline_user_args().has("--held-sun")
	var game := Game.new()
	game._setup_env()
	check((game.sun_aim_mode == 0) == fallback, "game uses held aiming only for constrained devices or explicit override")
	check(game.sun_grid_lock == (Portability.compatibility() or fallback), "Compatibility grid orientation survives independent of held aiming")
	var bias := 2.0 if Portability.compatibility() or fallback else 1.2
	check(is_equal_approx(game._sun.shadow_normal_bias, bias), "backend acne correction retains its previous bias")
	var first := Vector3(0.4, -0.7, 0.5).normalized()
	var next := first.rotated(Vector3.UP, deg_to_rad(0.2))
	game._aim_sun(first, true)
	game._aim_sun(next, false)
	var expected := first if fallback else next
	check(game._held_sun.is_equal_approx(expected), "small clock movement follows desktop sun or holds fallback")
	check((-game._sun.basis.z).is_equal_approx(expected), "rendered light direction follows selected aiming policy")
	var far := first.rotated(Vector3.UP, deg_to_rad(25))
	game._aim_sun(far, false)
	check(game._held_sun.is_equal_approx(far), "fallback still catches up at its maximum lag")
	game._aim_sun(next, true)
	check(game._held_sun.is_equal_approx(next), "zone transition always re-aims")
	# The existing device diagnostic must be able to bypass holding, including
	# in a desktop --held-sun run used to reproduce the fallback.
	game.sun_aim_mode = 1
	game._aim_sun(first, false)
	game._aim_sun(next, false)
	check(game._held_sun.is_equal_approx(next), "continuous diagnostic bypasses the fallback")
	game.free()
	var menu := MenuScene.new()
	menu._env = Environment.new()
	menu._sun = DirectionalLight3D.new()
	menu.add_child(menu._sun)
	menu._lights = EILights.load_for("Gipat", false)
	menu._sky = EISky.material(false)
	menu.set_hour(12.0)
	var before := -menu._sun.basis.z
	menu.set_hour(12.01)
	var clock_direction := EISpace.vec(EISky.light_dir_ei(12.01)).normalized()
	check((-menu._sun.basis.z).is_equal_approx(before if fallback else clock_direction),
			"menu follows the same desktop/fallback direction policy")
	menu.set_hour(14.0)
	check((-menu._sun.basis.z).is_equal_approx(EISpace.vec(EISky.light_dir_ei(14)).normalized()),
			"menu fallback catches up after a large clock change")
	menu.free()
	print("SUN_AIMING ", JSON.stringify({"checks": checks, "failures": failures,
			"held": fallback, "renderer": RenderingServer.get_current_rendering_method(),
			"editor": OS.has_feature("editor")}))
	get_tree().quit(1 if failures else 0)

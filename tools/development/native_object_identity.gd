extends SceneTree
## Asset-free regression for the native Variant -> ObjectID conversion.
class Unit extends RefCounted:
	var uid: String
	func _init(value: String) -> void:
		uid = value

var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _initialize() -> void:
	check(GDExtensionManager.load_extension("res://native.gdextension") == GDExtensionManager.LOAD_STATUS_OK, "compiled library loads")
	check(ClassDB.class_exists("UnitQueryKernel"), "compiled native class loads")
	if failures.is_empty():
		var kernel: Object = ClassDB.instantiate("UnitQueryKernel")
		var first := Unit.new("one")
		var second := Unit.new("two")
		var replacement := Unit.new("one")
		var registry := {"one": first, "two": second}
		var epoch: int = kernel.begin_registry_batch(registry)
		check(epoch > 0, "initial registry has an identity epoch")
		check(kernel.prune_units([replacement, first, null, 0, second], registry) == [first, second], "distinct objects retain only registered identities")
		check(kernel.begin_registry_batch(registry) == epoch, "unchanged identities preserve the epoch")
		registry["one"] = replacement
		var replaced_epoch: int = kernel.begin_registry_batch(registry)
		check(replaced_epoch > epoch, "same UID with another object advances the epoch")
		check(kernel.prune_units([first, replacement, second], registry) == [replacement, second], "replacement invalidates the old object")
		registry.erase("two")
		check(kernel.begin_registry_batch(registry) > replaced_epoch, "removal advances the epoch")
		check(kernel.prune_units([first, replacement, second], registry) == [replacement], "removed identity is rejected")
		kernel.end_batch()
		check(kernel.prune_units([second, replacement, null], registry) == [replacement], "unbatched validation retains the same identity")
	print("NATIVE_OBJECT_IDENTITY ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

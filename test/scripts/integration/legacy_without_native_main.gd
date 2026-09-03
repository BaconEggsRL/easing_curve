extends SceneTree

const LEGACY_CURVE_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve.gd"
)

var _failures := 0


func _initialize() -> void:
	_check(
		not ClassDB.class_exists(&"NativeEasingCurve"),
		"NativeEasingCurve unexpectedly exists in the legacy-only fixture"
	)
	var test_scene := load("res://addons/easing_curve/_test_scene/test.tscn") as PackedScene
	_check(test_scene != null, "dual-backend test scene does not parse without Native")
	if test_scene != null:
		var test_instance := test_scene.instantiate()
		_check(test_instance != null, "dual-backend test scene does not instantiate without Native")
		if test_instance != null:
			_check(
				not bool(test_instance.get("use_native_curve")),
				"dual-backend test scene did not fall back to legacy"
			)
			test_instance.free()

	var curve := LEGACY_CURVE_SCRIPT.new()
	curve.trans_type = LEGACY_CURVE_SCRIPT.TRANS.CUBIC
	curve.ease_type = LEGACY_CURVE_SCRIPT.EASE.OUT
	_check(is_equal_approx(curve.sample(0.0), 0.0), "legacy curve start changed")
	_check(is_equal_approx(curve.sample(1.0), 1.0), "legacy curve end changed")
	_check(curve.sample(0.5) > 0.5, "legacy cubic-out sampling failed")

	var path := "res://legacy_only_curve.tres"
	_check(ResourceSaver.save(curve, path) == OK, "legacy resource save failed")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null and loaded.get_script() == LEGACY_CURVE_SCRIPT, "legacy resource loaded as the wrong type")
	if loaded != null and loaded.has_method(&"sample"):
		_check(is_equal_approx(loaded.sample(1.0), 1.0), "loaded legacy curve sampling failed")

	if _failures == 0:
		print("PASS: legacy API loads, samples, and serializes without Native")
		quit(0)
	else:
		push_error("Legacy-only validation failed: %d check(s)" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)

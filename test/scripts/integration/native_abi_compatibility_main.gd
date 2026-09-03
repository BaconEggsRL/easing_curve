extends SceneTree

var _failures := 0


func _initialize() -> void:
	_check(ClassDB.class_exists(&"NativeEasingCurve"), "NativeEasingCurve is unavailable")
	_check(ClassDB.class_exists(&"NativeEasingCurvePoint"), "NativeEasingCurvePoint is unavailable")
	if _failures > 0:
		_finish()
		return

	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	_check(curve != null, "NativeEasingCurve could not be instantiated")
	if curve != null:
		curve.set(&"transition", 7)
		curve.set(&"ease_type", 1)
		_check(is_equal_approx(curve.call(&"sample", 0.0), 0.0), "built-in start changed")
		_check(is_equal_approx(curve.call(&"sample", 1.0), 1.0), "built-in end changed")
		curve.call(&"cubic_bezier", 0.42, 0.0, 0.58, 1.0)
		_check(curve.call(&"get_point_count") == 2, "custom topology was not created")
		var midpoint: float = curve.call(&"sample", 0.5)
		_check(absf(midpoint - 0.5) <= 0.000002, "custom solver changed")

	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


func _finish() -> void:
	if _failures == 0:
		print("PASS: Native ABI compatibility")
		quit(0)
	else:
		push_error("Native ABI compatibility failed: %d check(s)" % _failures)
		quit(1)

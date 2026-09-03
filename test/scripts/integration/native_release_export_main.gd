extends Node

const BUILTIN_PATH := "res://builtin_native_curve.tres"
const CUSTOM_PATH := "res://custom_native_curve.tres"
const SAMPLE_OFFSET := 0.37

var _failures: Array[String] = []


func _ready() -> void:
	_check(ClassDB.class_exists(&"NativeEasingCurve"), "release GDExtension did not register NativeEasingCurve")
	var builtin := ResourceLoader.load(BUILTIN_PATH)
	var custom := ResourceLoader.load(CUSTOM_PATH)
	_check(builtin != null, "exported project could not load the built-in Native curve")
	_check(custom != null, "exported project could not load the custom Native curve")

	if builtin != null:
		_check(builtin.get_class() == &"NativeEasingCurve", "built-in fixture loaded as the wrong resource type")
		var expected: float = Tween.interpolate_value(
			0.0,
			1.0,
			SAMPLE_OFFSET,
			1.0,
			Tween.TRANS_SINE,
			Tween.EASE_IN_OUT,
		)
		_check(is_equal_approx(builtin.call(&"sample", SAMPLE_OFFSET), expected), "loaded built-in Native curve sampled incorrectly")

	if custom != null:
		_check(custom.get_class() == &"NativeEasingCurve", "custom fixture loaded as the wrong resource type")
		_check(custom.get(&"transition") == 100, "loaded custom Native curve lost its transition")
		_check(custom.get(&"points").size() == 2, "loaded custom Native curve lost its points")
		var expected: float = custom.get_meta(&"validation_sample", NAN)
		_check(is_finite(expected), "custom fixture lost its validation sample")
		_check(is_equal_approx(custom.call(&"sample", SAMPLE_OFFSET), expected), "loaded custom Native curve sampled incorrectly")

	if _failures.is_empty():
		print("PASS: Windows release export loaded built-in and custom Native curves")
		get_tree().quit()
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

extends Node

const BUILTIN_PATH := "res://builtin_native_curve.tres"
const CUSTOM_PATH := "res://custom_native_curve.tres"
const SAMPLE_OFFSET := 0.37

var _failures: Array[String] = []


func _ready() -> void:
	_check(ClassDB.class_exists(&"NativeEasingCurve"), "Web GDExtension did not register NativeEasingCurve")
	_check(ClassDB.class_exists(&"NativeEasingCurvePoint"), "Web GDExtension did not register NativeEasingCurvePoint")
	var builtin := ResourceLoader.load(BUILTIN_PATH)
	var custom := ResourceLoader.load(CUSTOM_PATH)
	_check(builtin != null, "Web export could not load the built-in Native curve")
	_check(custom != null, "Web export could not load the custom Native curve")

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
		_check(is_equal_approx(builtin.call(&"sample", SAMPLE_OFFSET), expected), "built-in Native curve sampled incorrectly")

	if custom != null:
		_check(custom.get_class() == &"NativeEasingCurve", "custom fixture loaded as the wrong resource type")
		_check(custom.get(&"transition") == 100, "custom Native curve lost its transition")
		var custom_points: Array = custom.get(&"points")
		_check(custom_points.size() == 2, "custom Native curve lost its points")
		var expected: float = custom.get_meta(&"validation_sample", NAN)
		_check(is_finite(expected), "custom fixture lost its validation sample")
		_check(is_equal_approx(custom.call(&"sample", SAMPLE_OFFSET), expected), "custom Native curve sampled incorrectly")
		var runtime_copy := custom.call(&"create_runtime_copy") as Resource
		_check(runtime_copy != null, "Web runtime copy could not be created")
		if runtime_copy != null:
			var runtime_points: Array = runtime_copy.get(&"points")
			_check(runtime_points.size() == custom_points.size(), "Web runtime copy changed point topology")
			_check(runtime_points[0] != custom_points[0], "Web runtime copy shared authored point resources")
			_check(is_equal_approx(runtime_copy.call(&"sample", SAMPLE_OFFSET), expected), "Web runtime copy changed sampling")

	if _failures.is_empty():
		print("PASS: Web export loaded built-in and custom Native curves")
		_set_browser_result("pass")
	else:
		for failure in _failures:
			push_error(failure)
		_set_browser_result("fail")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _set_browser_result(result: String) -> void:
	JavaScriptBridge.eval(
		"document.documentElement.setAttribute('data-native-curve-test', '%s');" % result,
	)

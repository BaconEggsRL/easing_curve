extends "res://test/scripts/support/test_case.gd"

const LEGACY_CURVE_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve.gd"
)
const SAMPLE_COUNT := 256
const TRANS_CUBIC := 2
const TRANS_SINE := 1
const TRANS_ELASTIC := 3
const EASE_IN := 0
const EASE_OUT := 1
const EASE_IN_OUT := 2
const EASE_OUT_IN := 3


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ClassDB.class_exists(&"NativeEasingCurve"), "NativeEasingCurve is not registered")
	_expect(ClassDB.class_exists(&"NativeEasingCurvePoint"), "NativeEasingCurvePoint is not registered")
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		_finish("native v2 smoke")
		return

	_test_points_property_metadata()
	_test_builtin_equivalence()
	_test_custom_bezier_equivalence()
	_test_point_change_invalidates_compiled_segments()
	_test_points_array_assignment()
	_test_resource_round_trip()
	_finish("native v2 smoke")


func _test_points_property_metadata() -> void:
	var curve := _new_native_curve(TRANS_CUBIC, EASE_OUT)
	var points_property := {}
	for property in curve.get_property_list():
		if property[&"name"] == &"points":
			points_property = property
			break
	_expect(not points_property.is_empty(), "points property is missing")
	_expect(
		String(points_property.get(&"hint_string", "")).contains("NativeEasingCurvePoint"),
		"points does not expose NativeEasingCurvePoint as its array element type",
	)


func _test_builtin_equivalence() -> void:
	var transitions := {
		TRANS_CUBIC: Tween.TRANS_CUBIC,
		TRANS_SINE: Tween.TRANS_SINE,
		TRANS_ELASTIC: Tween.TRANS_ELASTIC,
	}
	var eases := {
		EASE_IN: Tween.EASE_IN,
		EASE_OUT: Tween.EASE_OUT,
		EASE_IN_OUT: Tween.EASE_IN_OUT,
		EASE_OUT_IN: Tween.EASE_OUT_IN,
	}
	for native_transition_value in transitions:
		var native_transition := int(native_transition_value)
		for native_ease_value in eases:
			var native_ease := int(native_ease_value)
			var curve := _new_native_curve(native_transition, native_ease)
			var max_error := 0.0
			for index in range(SAMPLE_COUNT + 1):
				var offset := float(index) / SAMPLE_COUNT
				var expected: float = Tween.interpolate_value(
					0.0,
					1.0,
					offset,
					1.0,
					transitions[native_transition],
					eases[native_ease],
				)
				max_error = maxf(max_error, absf(curve.call(&"sample", offset) - expected))
			_expect(
				max_error <= 0.000002,
				"native transition %d ease %d differs from Tween by %.9f" % [
					native_transition,
					native_ease,
					max_error,
				],
			)


func _test_custom_bezier_equivalence() -> void:
	var native_curve := _new_native_curve(TRANS_CUBIC, EASE_OUT)
	native_curve.call(&"cubic_bezier", 0.42, 0.0, 0.58, 1.0)
	var legacy_curve := LEGACY_CURVE_SCRIPT.new()
	legacy_curve.cubic_bezier(0.42, 0.0, 0.58, 1.0)
	var max_error := 0.0
	for index in range(SAMPLE_COUNT + 1):
		var offset := float(index) / SAMPLE_COUNT
		max_error = maxf(
			max_error,
			absf(native_curve.call(&"sample", offset) - legacy_curve.sample(offset)),
		)
	_expect(max_error <= 0.000002, "native custom Bézier differs by %.9f" % max_error)


func _test_point_change_invalidates_compiled_segments() -> void:
	var curve := _new_native_curve(TRANS_CUBIC, EASE_OUT)
	curve.call(&"cubic_bezier", 0.42, 0.0, 0.58, 1.0)
	var before: float = curve.call(&"sample", 0.25)
	var points: Array = curve.get(&"points")
	var first_point := points[0] as Resource
	first_point.set(&"right_control_point", Vector2(0.1, 0.9))
	var after: float = curve.call(&"sample", 0.25)
	_expect(not is_equal_approx(before, after), "point edits did not invalidate compiled segments")


func _test_points_array_assignment() -> void:
	var curve := _new_native_curve(TRANS_CUBIC, EASE_OUT)
	curve.call(&"cubic_bezier", 0.42, 0.0, 0.58, 1.0)
	var updated_points: Array = curve.get(&"points")
	var midpoint := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	midpoint.set(&"position", Vector2(0.5, 0.5))
	updated_points.insert(1, midpoint)
	curve.set(&"points", updated_points)
	_expect(curve.get(&"points").size() == 3, "assigned point topology was not stored")

	updated_points.remove_at(1)
	_expect(
		curve.get(&"points").size() == 3,
		"external array mutation bypassed point topology invalidation",
	)
	curve.call(&"remove_point", 1)
	_expect(curve.get(&"points").size() == 2, "remove_point did not update topology")


func _test_resource_round_trip() -> void:
	var curve := _new_native_curve(TRANS_CUBIC, EASE_OUT)
	curve.call(&"cubic_bezier", 0.42, 0.0, 0.58, 1.0)
	var expected: float = curve.call(&"sample", 0.37)
	var path := "res://test/_temp/native_v2_curve.tres"
	var error := ResourceSaver.save(curve, path)
	_expect(error == OK, "native curve could not be saved: %s" % error_string(error))
	var loaded := ResourceLoader.load(path)
	_expect(loaded != null, "native curve could not be loaded")
	if loaded != null:
		_expect(
			is_equal_approx(expected, loaded.call(&"sample", 0.37)),
			"native curve changed after save/load",
		)


func _new_native_curve(transition: int, ease_type: int) -> Resource:
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", transition)
	curve.set(&"ease_type", ease_type)
	return curve

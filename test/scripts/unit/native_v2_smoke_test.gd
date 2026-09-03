extends "res://test/scripts/support/test_case.gd"

const LEGACY_CURVE_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve.gd"
)
const SAMPLE_COUNT := 256
const TRANS_CUSTOM := 100


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ClassDB.class_exists(&"NativeEasingCurve"), "NativeEasingCurve is not registered")
	_expect(ClassDB.class_exists(&"NativeEasingCurvePoint"), "NativeEasingCurvePoint is not registered")
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		_finish("native v2 smoke")
		return

	_test_points_property_metadata()
	_test_stable_enum_contract()
	_test_resource_version_contract()
	_test_invalid_property_contract()
	_test_builtin_equivalence()
	_test_custom_bezier_equivalence()
	_test_point_ordering_contract()
	_test_point_change_invalidates_compiled_segments()
	_test_points_array_assignment()
	_test_point_ownership_and_change_propagation()
	_test_deep_runtime_copy()
	_test_resource_round_trip()
	_finish("native v2 smoke")


func _test_points_property_metadata() -> void:
	var curve := _new_native_curve(Tween.TRANS_CUBIC, Tween.EASE_OUT)
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


func _test_stable_enum_contract() -> void:
	var transitions := [
		[NativeEasingCurve.TRANS_LINEAR, Tween.TRANS_LINEAR],
		[NativeEasingCurve.TRANS_SINE, Tween.TRANS_SINE],
		[NativeEasingCurve.TRANS_QUINT, Tween.TRANS_QUINT],
		[NativeEasingCurve.TRANS_QUART, Tween.TRANS_QUART],
		[NativeEasingCurve.TRANS_QUAD, Tween.TRANS_QUAD],
		[NativeEasingCurve.TRANS_EXPO, Tween.TRANS_EXPO],
		[NativeEasingCurve.TRANS_ELASTIC, Tween.TRANS_ELASTIC],
		[NativeEasingCurve.TRANS_CUBIC, Tween.TRANS_CUBIC],
		[NativeEasingCurve.TRANS_CIRC, Tween.TRANS_CIRC],
		[NativeEasingCurve.TRANS_BOUNCE, Tween.TRANS_BOUNCE],
		[NativeEasingCurve.TRANS_BACK, Tween.TRANS_BACK],
		[NativeEasingCurve.TRANS_SPRING, Tween.TRANS_SPRING],
	]
	for transition_pair in transitions:
		_expect(
			transition_pair[0] == transition_pair[1],
			"native transition ID %d does not match Tween ID %d" % transition_pair,
		)
	_expect(NativeEasingCurve.TRANS_CUSTOM == TRANS_CUSTOM, "custom transition ID changed")
	_expect(NativeEasingCurve.EASE_IN == Tween.EASE_IN, "EASE_IN ID does not match Tween")
	_expect(NativeEasingCurve.EASE_OUT == Tween.EASE_OUT, "EASE_OUT ID does not match Tween")
	_expect(NativeEasingCurve.EASE_IN_OUT == Tween.EASE_IN_OUT, "EASE_IN_OUT ID does not match Tween")
	_expect(NativeEasingCurve.EASE_OUT_IN == Tween.EASE_OUT_IN, "EASE_OUT_IN ID does not match Tween")


func _test_resource_version_contract() -> void:
	var curve := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_OUT)
	_expect(NativeEasingCurve.FORMAT_VERSION == 1, "native format version changed unexpectedly")
	_expect(curve.get(&"format_version") == NativeEasingCurve.FORMAT_VERSION, "new native curve has the wrong format version")

	var version_property := {}
	for property in curve.get_property_list():
		if property[&"name"] == &"format_version":
			version_property = property
			break
	_expect(not version_property.is_empty(), "format_version property is missing")
	_expect(
		(int(version_property.get(&"usage", 0)) & PROPERTY_USAGE_STORAGE) != 0,
		"format_version is not serialized",
	)
	_expect(
		(int(version_property.get(&"usage", 0)) & PROPERTY_USAGE_EDITOR) == 0,
		"format_version should not be editable in the Inspector",
	)
	curve.set(&"format_version", 0)
	_expect(curve.get(&"format_version") == NativeEasingCurve.FORMAT_VERSION, "invalid format version was accepted")


func _test_invalid_property_contract() -> void:
	var curve := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_OUT)
	curve.set(&"transition", 999)
	_expect(curve.get(&"transition") == NativeEasingCurve.TRANS_CUBIC, "invalid transition was accepted")
	curve.set(&"ease_type", 999)
	_expect(curve.get(&"ease_type") == NativeEasingCurve.EASE_OUT, "invalid ease type was accepted")

	curve.set(&"amplitude", 0.25)
	_expect(is_equal_approx(curve.get(&"amplitude"), 1.0), "amplitude minimum is not 1.0")
	curve.set(&"amplitude", 2.0)
	curve.set(&"amplitude", NAN)
	_expect(is_equal_approx(curve.get(&"amplitude"), 2.0), "non-finite amplitude was accepted")
	curve.set(&"amplitude", INF)
	_expect(is_equal_approx(curve.get(&"amplitude"), 2.0), "infinite amplitude was accepted")

	curve.set(&"period", 0.0)
	_expect(is_equal_approx(curve.get(&"period"), 0.01), "period minimum is not 0.01")
	curve.set(&"period", 0.5)
	curve.set(&"period", NAN)
	_expect(is_equal_approx(curve.get(&"period"), 0.5), "non-finite period was accepted")
	_expect(is_equal_approx(curve.call(&"sample", NAN), 0.0), "non-finite sample input is not deterministic")
	_expect(is_equal_approx(curve.call(&"sample", INF), 0.0), "infinite sample input is not deterministic")

	var point := _new_native_point(Vector2(0.25, 0.75))
	point.set(&"position", Vector2(NAN, 0.5))
	_expect(point.get(&"position") == Vector2(0.25, 0.75), "non-finite point position was accepted")


func _test_builtin_equivalence() -> void:
	for native_transition in range(Tween.TRANS_SPRING + 1):
		for native_ease in range(Tween.EASE_OUT_IN + 1):
			var curve := _new_native_curve(native_transition, native_ease)
			var max_error := 0.0
			for index in range(SAMPLE_COUNT + 1):
				var offset := float(index) / SAMPLE_COUNT
				var expected: float = Tween.interpolate_value(
					0.0,
					1.0,
					offset,
					1.0,
					native_transition as Tween.TransitionType,
					native_ease as Tween.EaseType,
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
	var native_curve := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_OUT)
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


func _test_point_ordering_contract() -> void:
	var start := _new_native_point(Vector2(0.0, 0.0))
	var middle := _new_native_point(Vector2(0.5, 0.8))
	var end := _new_native_point(Vector2(1.0, 1.0))
	var sorted := _new_native_curve(TRANS_CUSTOM, Tween.EASE_OUT)
	var unsorted := _new_native_curve(TRANS_CUSTOM, Tween.EASE_OUT)
	sorted.set(&"points", [start, middle, end])
	unsorted.set(&"points", [end, start, middle])
	for index in range(SAMPLE_COUNT + 1):
		var offset := float(index) / SAMPLE_COUNT
		_expect(
			is_equal_approx(sorted.call(&"sample", offset), unsorted.call(&"sample", offset)),
			"point order changed sampling at %.6f" % offset,
		)

	var duplicate_low := _new_native_point(Vector2(0.5, 0.2))
	var duplicate_high := _new_native_point(Vector2(0.5, 0.8))
	var duplicate_curve := _new_native_curve(TRANS_CUSTOM, Tween.EASE_OUT)
	duplicate_curve.set(&"points", [start, duplicate_low, duplicate_high, end])
	_expect(
		is_equal_approx(duplicate_curve.call(&"sample", 0.5), 0.8),
		"the last point at a duplicate x coordinate did not win",
	)


func _test_point_change_invalidates_compiled_segments() -> void:
	var curve := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_OUT)
	curve.call(&"cubic_bezier", 0.42, 0.0, 0.58, 1.0)
	var before: float = curve.call(&"sample", 0.25)
	var points: Array = curve.get(&"points")
	var first_point := points[0] as Resource
	first_point.set(&"right_control_point", Vector2(0.1, 0.9))
	var after: float = curve.call(&"sample", 0.25)
	_expect(not is_equal_approx(before, after), "point edits did not invalidate compiled segments")


func _test_points_array_assignment() -> void:
	var curve := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_OUT)
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


func _test_point_ownership_and_change_propagation() -> void:
	var start := _new_native_point(Vector2.ZERO)
	var end := _new_native_point(Vector2.ONE)
	var assigned_points := [start, end]
	var curve := _new_native_curve(TRANS_CUSTOM, Tween.EASE_OUT)
	curve.set(&"points", assigned_points)

	var stored_points: Array = curve.get(&"points")
	_expect(stored_points[0] == start, "authored point Resources are not shared after assignment")
	assigned_points.clear()
	_expect(curve.get(&"points").size() == 2, "curve does not own its points array topology")

	var notifications := {&"changed": 0, &"points_changed": 0}
	curve.changed.connect(func() -> void: notifications[&"changed"] += 1)
	curve.connect(&"points_changed", func(_points: Array) -> void: notifications[&"points_changed"] += 1)
	start.set(&"right_control_point", Vector2(0.2, 0.8))
	_expect(notifications[&"changed"] == 1, "nested point edit did not propagate Resource.changed exactly once")
	_expect(notifications[&"points_changed"] == 1, "nested point edit did not propagate points_changed exactly once")

	curve.call(&"remove_point", 0)
	_expect(notifications[&"changed"] == 2, "point removal did not propagate Resource.changed")
	_expect(notifications[&"points_changed"] == 2, "point removal did not propagate points_changed")
	start.set(&"right_control_point", Vector2(0.3, 0.7))
	_expect(notifications[&"changed"] == 2, "removed point still propagated Resource.changed")
	_expect(notifications[&"points_changed"] == 2, "removed point still propagated points_changed")


func _test_deep_runtime_copy() -> void:
	var source := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_OUT)
	source.call(&"cubic_bezier", 0.42, 0.0, 0.58, 1.0)
	var source_before: float = source.call(&"sample", 0.25)
	var runtime := source.call(&"create_runtime_copy") as Resource
	_expect(runtime != null, "create_runtime_copy did not return a NativeEasingCurve")
	if runtime == null:
		return

	var source_points: Array = source.get(&"points")
	var runtime_points: Array = runtime.get(&"points")
	_expect(runtime_points.size() == source_points.size(), "runtime copy changed point topology")
	_expect(runtime_points[0] != source_points[0], "runtime copy shares point Resources with its source")
	_expect(
		is_equal_approx(runtime.call(&"sample", 0.25), source_before),
		"runtime copy changed the sampled curve",
	)
	_expect(
		runtime.get(&"format_version") == source.get(&"format_version"),
		"runtime copy lost the resource format version",
	)

	var runtime_notifications := {&"count": 0}
	runtime.connect(&"points_changed", func(_points: Array) -> void: runtime_notifications[&"count"] += 1)
	(source_points[0] as Resource).set(&"right_control_point", Vector2(0.1, 0.95))
	_expect(not is_equal_approx(source.call(&"sample", 0.25), source_before), "source edit did not change source sampling")
	_expect(is_equal_approx(runtime.call(&"sample", 0.25), source_before), "source edit changed the runtime copy")
	_expect(runtime_notifications[&"count"] == 0, "source edit signaled the independent runtime copy")


func _test_resource_round_trip() -> void:
	var curve := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_OUT)
	curve.call(&"cubic_bezier", 0.42, 0.0, 0.58, 1.0)
	var expected: float = curve.call(&"sample", 0.37)
	const EXPLICIT_SAVED_VERSION := 7
	curve.set(&"format_version", EXPLICIT_SAVED_VERSION)
	var path := "res://test/_temp/native_v2_curve.tres"
	var error := ResourceSaver.save(curve, path)
	_expect(error == OK, "native curve could not be saved: %s" % error_string(error))
	var serialized := FileAccess.get_file_as_string(path)
	_expect(
		serialized.contains("format_version = %d" % EXPLICIT_SAVED_VERSION),
		"explicit native curve format version was not serialized",
	)
	var loaded := ResourceLoader.load(path)
	_expect(loaded != null, "native curve could not be loaded")
	if loaded != null:
		_expect(
			loaded.get(&"format_version") == EXPLICIT_SAVED_VERSION,
			"native curve format version changed after save/load",
		)
		_expect(
			is_equal_approx(expected, loaded.call(&"sample", 0.37)),
			"native curve changed after save/load",
		)


func _new_native_curve(transition: int, ease_type: int) -> Resource:
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", transition)
	curve.set(&"ease_type", ease_type)
	return curve


func _new_native_point(position: Vector2) -> Resource:
	var point := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	point.set(&"position", position)
	return point

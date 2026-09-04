extends "res://test/scripts/support/test_case.gd"

const LEGACY_CURVE_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve.gd"
)
const LEGACY_POINT_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/point.gd"
)
const PRESET_FACTORY := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_preset_geometry_factory.gd"
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
	_test_default_contract()
	_test_resource_version_contract()
	_test_invalid_property_contract()
	_test_builtin_equivalence()
	_test_extended_transition_parity()
	_test_callable_baking()
	_test_custom_bezier_equivalence()
	_test_point_ordering_contract()
	_test_point_change_invalidates_compiled_segments()
	_test_points_array_assignment()
	_test_point_ownership_and_change_propagation()
	_test_point_editor_state_contract()
	_test_deferred_point_edit_transaction()
	_test_resource_free_editor_snapshot()
	_test_editable_preset_geometry()
	_test_modified_preset_round_trip()
	_test_point_mode_differential()
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
	_expect(NativeEasingCurve.TRANS_CONSTANT == 101, "constant transition ID changed")
	_expect(NativeEasingCurve.TRANS_JITTER == 102, "jitter transition ID changed")
	_expect(NativeEasingCurve.TRANS_IRREGULAR == 103, "irregular transition ID changed")
	_expect(NativeEasingCurve.TRANS_STEP == 104, "step transition ID changed")
	_expect(NativeEasingCurve.TRANS_POWER == 105, "power transition ID changed")
	_expect(NativeEasingCurve.TRANS_PHYSICS_SPRING == 106, "physics spring transition ID changed")
	_expect(NativeEasingCurve.TRANS_CSS_LINEAR == 107, "CSS linear transition ID changed")
	_expect(NativeEasingCurve.TRANS_CSS_CUBIC_BEZIER == 108, "CSS cubic Bezier transition ID changed")
	_expect(NativeEasingCurve.EASE_IN == Tween.EASE_IN, "EASE_IN ID does not match Tween")
	_expect(NativeEasingCurve.EASE_OUT == Tween.EASE_OUT, "EASE_OUT ID does not match Tween")
	_expect(NativeEasingCurve.EASE_IN_OUT == Tween.EASE_IN_OUT, "EASE_IN_OUT ID does not match Tween")
	_expect(NativeEasingCurve.EASE_OUT_IN == Tween.EASE_OUT_IN, "EASE_OUT_IN ID does not match Tween")


func _test_default_contract() -> void:
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	_expect(curve.get(&"transition") == NativeEasingCurve.TRANS_LINEAR, "new native curve does not default to Linear")
	_expect(curve.get(&"ease_type") == NativeEasingCurve.EASE_IN, "new native curve does not default to Ease In")


func _test_resource_version_contract() -> void:
	var curve := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_OUT)
	_expect(NativeEasingCurve.FORMAT_VERSION == 3, "native production format version changed unexpectedly")
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
	_expect(curve.get(&"format_version") == 0, "invalid format version was not retained for diagnosis")
	_expect(not curve.call(&"is_format_supported"), "invalid format version was accepted")
	_expect(not is_finite(curve.call(&"sample", 0.5)), "invalid format version sampled silently")


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


func _test_extended_transition_parity() -> void:
	var cases := [
		[NativeEasingCurve.TRANS_CONSTANT, EasingCurve.TRANS.CONSTANT, {&"constant_value": 0.37}],
		[NativeEasingCurve.TRANS_STEP, EasingCurve.TRANS.STEP, {&"steps": 7, &"from_start": true, &"y_offset": 0.08}],
		[NativeEasingCurve.TRANS_POWER, EasingCurve.TRANS.POWER, {&"power": 3.25}],
		[NativeEasingCurve.TRANS_BACK, EasingCurve.TRANS.BACK, {&"overshoot": 2.4}],
		[NativeEasingCurve.TRANS_ELASTIC, EasingCurve.TRANS.ELASTIC, {&"amplitude": 1.7, &"period": 0.42}],
		[NativeEasingCurve.TRANS_SPRING, EasingCurve.TRANS.SPRING, {&"frequency": 3.4, &"decay": 3.1}],
		[NativeEasingCurve.TRANS_PHYSICS_SPRING, EasingCurve.TRANS.PHYSICS_SPRING, {&"stiffness": 180.0, &"damping": 14.0, &"mass": 1.8, &"velocity": -0.75}],
	]
	for transition_case in cases:
		for ease in range(NativeEasingCurve.EASE_OUT_IN + 1):
			var native_curve := _new_native_curve(transition_case[0], ease)
			var legacy_curve := LEGACY_CURVE_SCRIPT.new() as EasingCurve
			legacy_curve.trans_type = transition_case[1]
			legacy_curve.ease_type = ease
			for property_name: StringName in transition_case[2]:
				native_curve.set(property_name, transition_case[2][property_name])
				legacy_curve.set(property_name, transition_case[2][property_name])
			var max_error := 0.0
			for index in range(SAMPLE_COUNT + 1):
				var offset := float(index) / SAMPLE_COUNT
				max_error = maxf(max_error, absf(native_curve.call(&"sample", offset) - legacy_curve.sample(offset)))
			_expect(
				max_error <= 0.00001,
				"extended native transition %d ease %d differs from legacy by %.9f" % [transition_case[0], ease, max_error],
			)

	var transformed := _new_native_curve(NativeEasingCurve.TRANS_POWER, NativeEasingCurve.EASE_IN)
	transformed.set(&"power", 2.5)
	transformed.set(&"reverse", true)
	transformed.set(&"invert", true)
	_expect(
		is_equal_approx(transformed.call(&"sample", 0.25), 1.0 - pow(0.75, 2.5)),
		"native reverse/invert transform changed",
	)


func _test_callable_baking() -> void:
	var curve := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_OUT)
	var calls := {&"count": 0}
	var source := func(offset: float) -> float:
		calls[&"count"] += 1
		return offset * offset
	_expect(curve.call(&"bake_callable", source, 64), "Native rejected a valid Callable bake")
	_expect(calls[&"count"] == 65, "Callable bake used the wrong sample count")
	_expect(curve.get(&"transition") == NativeEasingCurve.TRANS_CUSTOM, "Callable bake did not produce a custom curve")
	_expect(curve.call(&"get_point_count") == 65, "Callable bake produced the wrong point count")
	var calls_after_bake: int = calls[&"count"]
	var max_error := 0.0
	for index in range(SAMPLE_COUNT + 1):
		var offset := float(index) / SAMPLE_COUNT
		max_error = maxf(max_error, absf(curve.call(&"sample", offset) - offset * offset))
	_expect(max_error <= 0.0001, "Callable bake approximation error is %.9f" % max_error)
	_expect(calls[&"count"] == calls_after_bake, "Native invoked the Callable during sampling")
	_expect(not curve.call(&"bake_callable", Callable(), 64), "Native accepted an invalid Callable")
	_expect(not curve.call(&"bake_callable", source, 0), "Native accepted an invalid bake resolution")


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
	_expect(curve.call(&"get_point_count") == 2, "get_point_count did not report topology")
	_expect(curve.call(&"get_point", 0) != null, "get_point did not return a valid point")
	_expect(curve.call(&"get_point", -1) == null, "get_point accepted an invalid index")
	_expect(not curve.call(&"insert_point", -1, midpoint), "insert_point accepted an invalid index")
	_expect(curve.call(&"insert_point", 1, midpoint), "insert_point rejected a valid point")
	_expect(curve.call(&"get_point_count") == 3, "insert_point did not update topology")
	_expect(curve.call(&"set_point", 1, midpoint), "set_point rejected a valid no-op replacement")
	_expect(not curve.call(&"set_point", 3, midpoint), "set_point accepted an invalid index")
	curve.call(&"clear_points")
	_expect(curve.call(&"get_point_count") == 0, "clear_points did not clear topology")


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


func _test_point_editor_state_contract() -> void:
	_expect(NativeEasingCurvePoint.HANDLE_FREE == 0, "native free handle ID changed")
	_expect(NativeEasingCurvePoint.HANDLE_LINEAR == 1, "native linear handle ID changed")
	_expect(NativeEasingCurvePoint.HANDLE_BALANCED == 2, "native balanced handle ID changed")
	_expect(NativeEasingCurvePoint.HANDLE_MIRRORED == 3, "native mirrored handle ID changed")
	_expect(NativeEasingCurvePoint.HANDLE_LINKED == 4, "native linked handle ID changed")

	var point := _new_native_point(Vector2(0.5, 0.5))
	point.set(&"left_control_point", Vector2(0.25, 0.25))
	point.set(&"right_control_point", Vector2(0.75, 0.75))
	point.call(&"set_locked", &"left_control_point", true)
	point.set(&"position", Vector2(0.6, 0.6))
	_expect(point.get(&"left_control_point") == Vector2(0.25, 0.25), "locked control moved with the point")
	_expect(point.get(&"right_control_point") == Vector2(0.85, 0.85), "free control did not move with the point")

	point.call(&"set_locked", &"left_control_point", false)
	point.set(&"handle_mode", NativeEasingCurvePoint.HANDLE_MIRRORED)
	point.set(&"right_control_point", Vector2(0.8, 0.7))
	_expect(
		point.get(&"left_control_point").is_equal_approx(Vector2(0.4, 0.5)),
		"mirrored mode did not reflect the opposite handle",
	)
	point.set(&"handle_mode", NativeEasingCurvePoint.HANDLE_FREE)
	point.set(&"left_force_linear", true)
	_expect(point.get(&"left_control_point") == point.get(&"position"), "force-linear did not collapse the handle")

	var state: Dictionary = point.call(&"capture_state")
	state[&"position"] = Vector2(0.3, 0.4)
	state[&"handle_mode"] = NativeEasingCurvePoint.HANDLE_LINKED
	state[&"left_control_point"] = Vector2(0.2, 0.4)
	state[&"right_control_point"] = Vector2(0.2, 0.4)
	var changes := {&"count": 0}
	point.changed.connect(func() -> void: changes[&"count"] += 1)
	_expect(point.call(&"apply_state", state), "valid atomic point state was rejected")
	_expect(changes[&"count"] == 1, "atomic point state did not emit exactly one change")
	_expect(point.get(&"position") == Vector2(0.3, 0.4), "atomic point state lost position")
	_expect(point.get(&"handle_mode") == NativeEasingCurvePoint.HANDLE_LINKED, "atomic point state lost handle mode")
	state[&"position"] = Vector2(NAN, 0.0)
	_expect(not point.call(&"apply_state", state), "non-finite atomic point state was accepted")

	var curve := _new_native_curve(NativeEasingCurve.TRANS_CUSTOM, NativeEasingCurve.EASE_OUT)
	var end := _new_native_point(Vector2.ONE)
	curve.set(&"points", [point, end])
	var original_identity := curve.call(&"get_point", 0) as Resource
	var states: Array = curve.call(&"capture_point_states")
	states[0][&"position"] = Vector2(0.2, 0.3)
	states[1][&"position"] = Vector2(0.9, 1.0)
	var curve_changes := {&"count": 0}
	curve.connect(&"points_changed", func(_points: Array) -> void: curve_changes[&"count"] += 1)
	_expect(curve.call(&"apply_point_states", states), "valid curve point snapshot was rejected")
	_expect(curve.call(&"get_point", 0) == original_identity, "curve point snapshot replaced point identity")
	_expect(curve_changes[&"count"] == 1, "curve point snapshot amplified change propagation")
	states[0][&"position"] = Vector2(NAN, 0.0)
	var before_rejected_state: Vector2 = (curve.call(&"get_point", 1) as Resource).get(&"position")
	_expect(not curve.call(&"apply_point_states", states), "invalid curve point snapshot was accepted")
	_expect(
		(curve.call(&"get_point", 1) as Resource).get(&"position") == before_rejected_state,
		"rejected curve point snapshot partially mutated points",
	)


func _test_deferred_point_edit_transaction() -> void:
	var curve := _new_native_curve(TRANS_CUSTOM, NativeEasingCurve.EASE_IN)
	var point := curve.call(&"get_point", 0) as Resource
	var changes := {&"curve": 0, &"points": 0}
	curve.changed.connect(func() -> void: changes[&"curve"] += 1)
	curve.connect(&"points_changed", func(_points: Array) -> void: changes[&"points"] += 1)
	var sample_before: float = curve.call(&"sample", 0.25)
	curve.call(&"begin_point_edit")
	point.set(&"right_control_point", Vector2(0.2, 0.8))
	var preview_sample: float = curve.call(&"sample", 0.25)
	point.set(&"right_control_point", Vector2(0.15, 0.9))
	_expect(not is_equal_approx(sample_before, preview_sample), "point transaction did not compile local previews")
	_expect(changes[&"curve"] == 0 and changes[&"points"] == 0, "point transaction published during drag")
	curve.call(&"finish_point_edit")
	_expect(changes[&"curve"] == 1 and changes[&"points"] == 1, "point transaction did not publish once on release")
	curve.call(&"finish_point_edit")
	_expect(changes[&"curve"] == 1 and changes[&"points"] == 1, "unbalanced transaction finish published")
	changes[&"curve"] = 0
	changes[&"points"] = 0
	var committed_control: Vector2 = point.get(&"right_control_point")
	curve.call(&"begin_point_edit")
	point.set(&"right_control_point", Vector2(0.4, 0.4))
	point.set(&"right_control_point", committed_control)
	curve.call(&"finish_point_edit")
	_expect(changes[&"curve"] == 0 and changes[&"points"] == 0, "canceled point transaction published")


func _test_resource_free_editor_snapshot() -> void:
	var curve := _new_native_curve(TRANS_CUSTOM, NativeEasingCurve.EASE_OUT)
	_expect(not curve.call(&"_dont_undo_redo"), "Native curve bypasses Inspector Undo outside snapshot publication")
	curve.set_meta(&"_easing_curve_publishing_editor_snapshot", true)
	_expect(curve.call(&"_dont_undo_redo"), "Native snapshot publication did not bypass duplicate Inspector Undo")
	curve.remove_meta(&"_easing_curve_publishing_editor_snapshot")
	_expect(not curve.call(&"_dont_undo_redo"), "Native snapshot publication left Inspector Undo bypass active")
	var snapshot: Dictionary = curve.call(&"get_editor_state_snapshot")
	_expect(not _contains_object(snapshot), "Native editor snapshot contains a Resource")
	var local_point := curve.call(&"get_point", 0) as Resource
	curve.call(&"set_editor_state_snapshot", snapshot)
	_expect(curve.call(&"get_point", 0) == local_point, "Equal live snapshot replaced local point identity")
	var remote := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	var remote_publications := [0]
	remote.changed.connect(func(): remote_publications[0] += 1)
	remote.call(&"set_editor_state_snapshot", snapshot)
	_expect(remote_publications[0] == 1, "editor snapshot amplified running-resource publication")
	_expect(remote.get(&"transition") == curve.get(&"transition"), "editor snapshot lost transition")
	_expect(remote.get(&"ease_type") == curve.get(&"ease_type"), "editor snapshot lost ease")
	_expect(remote.call(&"capture_point_states") == curve.call(&"capture_point_states"), "editor snapshot lost point geometry")


func _test_editable_preset_geometry() -> void:
	var presets := [
		[NativeEasingCurve.TRANS_CONSTANT, &"CONSTANT"],
		[NativeEasingCurve.TRANS_LINEAR, &"LINEAR"],
		[NativeEasingCurve.TRANS_SINE, &"SINE"],
		[NativeEasingCurve.TRANS_QUAD, &"QUAD"],
		[NativeEasingCurve.TRANS_CUBIC, &"CUBIC"],
		[NativeEasingCurve.TRANS_QUART, &"QUART"],
		[NativeEasingCurve.TRANS_QUINT, &"QUINT"],
		[NativeEasingCurve.TRANS_EXPO, &"EXPO"],
		[NativeEasingCurve.TRANS_CIRC, &"CIRC"],
		[NativeEasingCurve.TRANS_BACK, &"BACK"],
	]
	var ease_names := [&"IN", &"OUT", &"IN_OUT", &"OUT_IN"]
	for preset in presets:
		for ease in range(4):
			var curve := _new_native_curve(preset[0], ease)
			var legacy_points: Array[EasingCurvePoint] = PRESET_FACTORY.build(
				preset[1],
				ease_names[ease],
				float(curve.get(&"constant_value")),
				float(curve.get(&"overshoot")),
			)
			var native_states: Array = curve.call(&"capture_point_states")
			_expect(native_states.size() == legacy_points.size(), "%s/%s preset point count differs" % [preset[1], ease_names[ease]])
			for index in range(mini(native_states.size(), legacy_points.size())):
				var state: Dictionary = native_states[index]
				_expect(state[&"position"].is_equal_approx(legacy_points[index].position), "%s/%s position differs" % [preset[1], ease_names[ease]])
				_expect(state[&"left_control_point"].is_equal_approx(legacy_points[index].left_control_point), "%s/%s left control differs" % [preset[1], ease_names[ease]])
				_expect(state[&"right_control_point"].is_equal_approx(legacy_points[index].right_control_point), "%s/%s right control differs" % [preset[1], ease_names[ease]])
			_expect(not curve.call(&"is_selected_preset_modified"), "%s/%s started modified" % [preset[1], ease_names[ease]])

	var modified := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_IN)
	var clean_sample: float = modified.call(&"sample", 0.25)
	var start := modified.call(&"get_point", 0) as Resource
	start.set(&"right_control_point", Vector2(0.1, 0.9))
	_expect(modified.call(&"is_selected_preset_modified"), "preset point edit did not set modified state")
	_expect(not is_equal_approx(clean_sample, modified.call(&"sample", 0.25)), "modified preset did not use compiled geometry")
	modified.set(&"ease_type", NativeEasingCurve.EASE_OUT)
	_expect(modified.get(&"ease_type") == NativeEasingCurve.EASE_IN, "modified preset accepted an incompatible ease change")
	var extra := _new_native_point(Vector2(0.5, 0.5))
	_expect(modified.call(&"insert_point", 1, extra), "editable preset rejected point insertion")
	_expect(modified.call(&"get_point_count") == 3, "editable preset did not retain inserted point")
	_expect(modified.call(&"remove_point", 1), "editable preset rejected point removal")
	modified.call(&"reset_selected_preset")
	_expect(not modified.call(&"is_selected_preset_modified"), "preset reset did not clear modified state")
	_expect(is_equal_approx(clean_sample, modified.call(&"sample", 0.25)), "preset reset did not restore analytic sampling")
	var assigned := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_IN)
	assigned.set(&"points", [_new_native_point(Vector2.ZERO), _new_native_point(Vector2(1.0, 0.0))])
	_expect(assigned.call(&"is_selected_preset_modified"), "current-format point assignment did not mark a preset modified")
	_expect(not is_equal_approx(assigned.call(&"sample", 0.5), 0.125), "current-format point assignment did not activate compiled geometry")

	var migrated := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_IN)
	migrated.set(&"format_version", 2)
	migrated.set(&"points", [_new_native_point(Vector2.ZERO), _new_native_point(Vector2(1.0, 0.0))])
	_expect(not migrated.call(&"is_selected_preset_modified"), "v2 standard resource was treated as a modified preset")
	_expect(is_equal_approx(migrated.call(&"sample", 0.5), 0.125), "v2 standard resource did not retain analytic behavior")


func _test_modified_preset_round_trip() -> void:
	var curve := _new_native_curve(NativeEasingCurve.TRANS_QUAD, NativeEasingCurve.EASE_OUT)
	var start := curve.call(&"get_point", 0) as Resource
	start.set(&"right_control_point", Vector2(0.1, 0.8))
	var expected: float = curve.call(&"sample", 0.35)
	var save_path := "res://test/_temp/native_modified_preset_round_trip.tres"
	_expect(ResourceSaver.save(curve, save_path) == OK, "modified preset could not be saved")
	var loaded := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	_expect(loaded != null, "modified preset could not be loaded")
	if loaded != null:
		_expect(loaded.call(&"is_selected_preset_modified"), "modified preset lost its saved override marker")
		_expect(is_equal_approx(loaded.call(&"sample", 0.35), expected), "modified preset round trip changed sampling")
		loaded.call(&"reset_selected_preset")
		var clean_path := "res://test/_temp/native_clean_preset_round_trip.tres"
		_expect(ResourceSaver.save(loaded, clean_path) == OK, "clean preset could not be saved")
		var clean_file := FileAccess.open(clean_path, FileAccess.READ)
		_expect(clean_file != null, "clean preset save could not be inspected")
		if clean_file != null:
			var serialized := clean_file.get_as_text()
			_expect(not serialized.contains("points ="), "clean preset serialized redundant point geometry")
			_expect(not serialized.contains("preset_override_active = true"), "clean preset serialized a stale override marker")


func _contains_object(value: Variant) -> bool:
	if value is Object:
		return true
	if value is Dictionary:
		for key in value:
			if _contains_object(key) or _contains_object(value[key]):
				return true
	elif value is Array:
		for item in value:
			if _contains_object(item):
				return true
	return false


func _test_point_mode_differential() -> void:
	for mode in range(EasingCurvePoint.HandleMode.LINKED + 1):
		var native := _new_native_point(Vector2(0.5, 0.5))
		var legacy := LEGACY_POINT_SCRIPT.new(Vector2(0.5, 0.5)) as EasingCurvePoint
		for candidate in [native, legacy]:
			candidate.set(&"left_control_point", Vector2(0.2, 0.4))
			candidate.set(&"right_control_point", Vector2(0.85, 0.7))
			candidate.set(&"handle_mode", mode)
		_expect_native_point_matches_legacy(native, legacy, "mode %d selection" % mode)
		native.set(&"right_control_point", Vector2(0.75, 0.2))
		legacy.right_control_point = Vector2(0.75, 0.2)
		_expect_native_point_matches_legacy(native, legacy, "mode %d control move" % mode)

	for mode in [EasingCurvePoint.HandleMode.FREE, EasingCurvePoint.HandleMode.LINKED]:
		var native := _new_native_point(Vector2(0.5, 0.5))
		var legacy := LEGACY_POINT_SCRIPT.new(Vector2(0.5, 0.5)) as EasingCurvePoint
		native.set(&"handle_mode", mode)
		legacy.handle_mode = mode
		native.set(&"left_force_linear", true)
		legacy.left_force_linear = true
		_expect_native_point_matches_legacy(native, legacy, "mode %d force linear" % mode)

	var native_locked := _new_native_point(Vector2(0.5, 0.5))
	var legacy_locked := LEGACY_POINT_SCRIPT.new(Vector2(0.5, 0.5)) as EasingCurvePoint
	for candidate in [native_locked, legacy_locked]:
		candidate.set(&"left_control_point", Vector2(0.2, 0.4))
		candidate.call(&"set_locked", "left_control_point", true)
		candidate.set(&"position", Vector2(0.6, 0.7))
	_expect_native_point_matches_legacy(native_locked, legacy_locked, "locked position move")


func _expect_native_point_matches_legacy(
		native: Resource,
		legacy: EasingCurvePoint,
		context: String,
) -> void:
	_expect(
		(native.get(&"left_control_point") as Vector2).is_equal_approx(legacy.left_control_point),
		"%s left control differs" % context,
	)
	_expect(
		(native.get(&"right_control_point") as Vector2).is_equal_approx(legacy.right_control_point),
		"%s right control differs" % context,
	)


func _test_deep_runtime_copy() -> void:
	var source := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_OUT)
	source.call(&"cubic_bezier", 0.42, 0.0, 0.58, 1.0)
	var source_points: Array = source.get(&"points")
	(source_points[0] as Resource).set(&"handle_mode", NativeEasingCurvePoint.HANDLE_LINKED)
	(source_points[0] as Resource).set(&"left_force_linear", true)
	(source_points[0] as Resource).call(&"set_locked", &"position", true)
	var source_before: float = source.call(&"sample", 0.25)
	var runtime := source.call(&"create_runtime_copy") as Resource
	_expect(runtime != null, "create_runtime_copy did not return a NativeEasingCurve")
	if runtime == null:
		return

	var runtime_points: Array = runtime.get(&"points")
	_expect(runtime_points.size() == source_points.size(), "runtime copy changed point topology")
	_expect(runtime_points[0] != source_points[0], "runtime copy shares point Resources with its source")
	_expect(
		(runtime_points[0] as Resource).get(&"handle_mode") == NativeEasingCurvePoint.HANDLE_LINKED,
		"runtime copy lost point handle mode",
	)
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
	var changed_source_state: Dictionary = (source_points[0] as Resource).call(&"capture_state")
	changed_source_state[&"handle_mode"] = NativeEasingCurvePoint.HANDLE_FREE
	changed_source_state[&"left_force_linear"] = false
	changed_source_state[&"right_control_point"] = Vector2(0.1, 0.95)
	(source_points[0] as Resource).call(&"apply_state", changed_source_state)
	_expect(not is_equal_approx(source.call(&"sample", 0.25), source_before), "source edit did not change source sampling")
	_expect(is_equal_approx(runtime.call(&"sample", 0.25), source_before), "source edit changed the runtime copy")
	_expect(runtime_notifications[&"count"] == 0, "source edit signaled the independent runtime copy")


func _test_resource_round_trip() -> void:
	var curve := _new_native_curve(NativeEasingCurve.TRANS_CUBIC, NativeEasingCurve.EASE_OUT)
	curve.call(&"cubic_bezier", 0.42, 0.0, 0.58, 1.0)
	var authored_point := curve.call(&"get_point", 0) as Resource
	authored_point.set(&"handle_mode", NativeEasingCurvePoint.HANDLE_LINKED)
	authored_point.call(&"set_locked", &"position", true)
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
		_expect(not loaded.call(&"is_format_supported"), "future native format version was accepted")
		_expect(not is_finite(loaded.call(&"sample", 0.37)), "future native format sampled silently")
		var loaded_point := loaded.call(&"get_point", 0) as Resource
		_expect(
			loaded_point.get(&"handle_mode") == NativeEasingCurvePoint.HANDLE_LINKED,
			"native point handle mode changed after save/load",
		)
		_expect(
			loaded_point.call(&"is_lock_active", &"position"),
			"native point lock changed after save/load",
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

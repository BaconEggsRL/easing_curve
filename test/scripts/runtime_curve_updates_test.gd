extends SceneTree

const EASING_LIBRARY = preload("res://addons/easing_curve/scripts/easing.gd")
const ROUND_TRIP_PATH := "res://test/_runtime_curve_round_trip.tres"
const GENERATED_ROUND_TRIP_PATH := "res://test/_generated_curve_round_trip.tres"
const BACK_ROUND_TRIP_PATH := "res://test/_back_overshoot_round_trip.tres"
const CSS_CUBIC_ROUND_TRIP_PATH := "res://test/_css_cubic_bezier_round_trip.tres"

var _failures := 0
var _checks := 0


func _init() -> void:
	seed(123456)
	_test_legacy_resources_and_nested_changes()
	_test_bezier_point_operations()
	_test_resource_free_point_snapshots()
	_test_parameter_drag_transactions()
	_test_preset_parameter_notification_counts()
	_test_back_overshoot_contract()
	_test_back_overshoot_geometry()
	_test_back_overshoot_runtime_updates()
	_test_back_overshoot_round_trip()
	_test_css_cubic_bezier()
	_test_flat_storage_and_round_trip()
	_test_generated_curve_round_trip()
	_test_generated_transition_semantics()
	_test_function_parameters()
	_test_every_transition_and_runtime_switching()

	if _failures == 0:
		print("PASS: %d runtime curve update checks" % _checks)
	else:
		push_error("FAIL: %d of %d runtime curve update checks failed" % [_failures, _checks])
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error(message)


func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


func _float_arrays_equal_approx(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if not is_equal_approx(a[i], b[i]):
			return false
	return true


func _signal_counts(curve: EasingCurve) -> Dictionary:
	var counts := {"changed": 0, "points": 0}
	curve.changed.connect(func() -> void: counts.changed += 1)
	curve.points_changed.connect(
		func(_updated_points: Array[EasingCurvePoint]) -> void: counts.points += 1,
	)
	return counts


func _test_legacy_resources_and_nested_changes() -> void:
	var packed_scene := load("res://addons/easing_curve/_test_scene/test.tscn") as PackedScene
	var instance := packed_scene.instantiate()
	var scene_curve := instance.get("easing_curve") as EasingCurve
	if scene_curve == null:
		instance.set("easing_curve", EasingCurve.new())
		scene_curve = instance.get("easing_curve") as EasingCurve
	_expect(scene_curve != null, "Demo scene did not load its curve resource")
	_expect(scene_curve.changed.is_connected(Callable(instance, "_on_easing_curve_changed")), "Demo does not restart for ordinary mode or parameter changes")
	instance.call("_capture_runtime_curves")
	var runtime_scene_curve := instance.get("_runtime_easing_curve") as EasingCurve
	_expect(runtime_scene_curve != null and runtime_scene_curve != scene_curve, "Demo animation did not capture an independent runtime curve")
	_expect(runtime_scene_curve != null and is_equal_approx(runtime_scene_curve.sample(0.37), scene_curve.sample(0.37)), "Captured runtime curve changed the animation output")
	instance.free()

	var curve := EasingCurve.new()
	var counts := _signal_counts(curve)
	var before_position := curve.sample(0.5)
	curve.points[1].position = Vector2(1.0, 0.25)
	_expect(not is_equal_approx(before_position, curve.sample(0.5)), "Loaded point position did not change sampled output")
	_expect(counts.changed > 0 and counts.points > 0, "Loaded point position did not propagate curve signals")

	counts.changed = 0
	counts.points = 0
	var before_handle := curve.sample(0.25)
	curve.points[0].right_control_point = Vector2(0.2, 0.9)
	_expect(not is_equal_approx(before_handle, curve.sample(0.25)), "Loaded control handle did not change sampled output")
	_expect(counts.changed > 0 and counts.points > 0, "Loaded control handle did not propagate curve signals")
	var preset := load("res://addons/easing_curve/presets/triangle_linear.tres") as EasingCurve
	_expect(preset != null and preset.points.size() == 3, "Legacy preset did not load its three points")
	_expect(preset.sample(0.5) > 0.9, "Legacy preset output changed while loading old Array[Resource] data")


func _test_bezier_point_operations() -> void:
	var curve := EasingCurve.new()
	var counts := _signal_counts(curve)
	var midpoint := EasingCurvePoint.new(Vector2(0.5, 0.8))
	midpoint.left_control_point = Vector2(0.35, 0.8)
	midpoint.right_control_point = Vector2(0.65, 0.8)
	var before_add := curve.sample(0.5)
	curve.add_point(midpoint)
	_expect(curve.points.size() == 3, "add_point() did not add a point")
	_expect(not is_equal_approx(before_add, curve.sample(0.5)), "add_point() did not immediately affect output")
	_expect(counts.changed > 0 and counts.points > 0, "add_point() did not propagate curve signals")

	counts.changed = 0
	counts.points = 0
	curve.remove_point(midpoint)
	_expect(curve.points.size() == 2 and is_equal_approx(curve.sample(0.5), 0.5), "remove_point() did not restore the linear curve")
	_expect(counts.changed > 0 and counts.points > 0, "remove_point() did not propagate curve signals")

	counts.changed = 0
	counts.points = 0
	curve.set_point(1, EasingCurvePoint.new(Vector2(1.0, 0.4)))
	_expect(curve.sample(0.5) < 0.5, "set_point() did not immediately affect output")
	_expect(counts.changed > 0 and counts.points > 0, "set_point() did not propagate curve signals")

	counts.changed = 0
	counts.points = 0
	curve.points.append(EasingCurvePoint.new(Vector2(0.75, 0.75)))
	curve.sample(0.5)
	_expect(counts.changed > 0 and counts.points > 0, "External points array mutation was not detected during evaluation")

	curve.set("_point_count", 3)
	curve.set("_point_0/position", Vector2.ZERO)
	curve.set("_point_0/right_control_point", Vector2(0.2, 0.0))
	curve.set("_point_1/position", Vector2(0.5, 0.9))
	curve.set("_point_1/left_control_point", Vector2(0.35, 0.9))
	curve.set("_point_1/right_control_point", Vector2(0.65, 0.9))
	curve.set("_point_2/position", Vector2.ONE)
	curve.set("_point_2/left_control_point", Vector2(0.8, 1.0))
	_expect(curve.sample(0.5) > 0.85, "Flattened runtime point updates did not immediately affect output")
	curve.set("_point_count", 2)
	_expect(curve.points.size() == 2, "Flattened runtime point removal did not resize the point list")


func _test_resource_free_point_snapshots() -> void:
	var curve := EasingCurve.new()
	var counts := _signal_counts(curve)
	var original_points: Array[EasingCurvePoint] = curve.points.duplicate()
	var changed_snapshot := curve.get_point_snapshot()
	var changed_positions: PackedVector2Array = changed_snapshot.positions
	changed_positions[1] = Vector2(1.0, 0.25)
	changed_snapshot.positions = changed_positions
	curve.set(EasingCurve.POINT_SNAPSHOT_PROPERTY, changed_snapshot)
	for index in range(original_points.size()):
		_expect(curve.points[index] == original_points[index], "Same-size point snapshots replaced point resource %d" % index)
	_expect(curve.sample(0.5) < 0.5, "Point snapshot property change did not immediately affect output")

	counts.changed = 0
	counts.points = 0
	var running_curve := curve.duplicate() as EasingCurve
	var running_handle := running_curve.points[0].right_control_point
	var dragging_snapshot := curve.get_point_snapshot()
	var dragging_handles: PackedVector2Array = dragging_snapshot.right_control_points
	dragging_handles[0] = Vector2(0.25, 0.8)
	dragging_snapshot.right_control_points = dragging_handles
	dragging_snapshot.changing = true
	curve.set(EasingCurve.POINT_SNAPSHOT_PROPERTY, dragging_snapshot)
	_expect(curve.points[0].right_control_point == Vector2(0.25, 0.8), "Handle drag did not update curve geometry immediately")
	_expect(running_curve.points[0].right_control_point == running_handle, "Draft handle edit disrupted the captured running animation curve")
	_expect(counts.changed == 0 and counts.points == 0, "Handle drag emitted restart signals before mouse release")
	var released_snapshot := curve.get_point_snapshot()
	released_snapshot.changing = false
	curve.set(EasingCurve.POINT_SNAPSHOT_PROPERTY, released_snapshot)
	_expect(counts.changed == 1 and counts.points == 1, "Handle release did not emit exactly one restart notification")

	var added_points: Array[EasingCurvePoint] = curve.points.duplicate()
	added_points.append(EasingCurvePoint.new(Vector2(0.5, 0.9)))
	added_points.sort_custom(func(a: EasingCurvePoint, b: EasingCurvePoint) -> bool: return a.position.x < b.position.x)
	curve.set(EasingCurve.POINT_SNAPSHOT_PROPERTY, curve.make_point_snapshot(added_points))
	_expect(curve.points.size() == 3 and curve.sample(0.5) > 0.85, "Point snapshot addition did not immediately affect output")
	for original_point in original_points:
		_expect(original_point not in curve.points, "Topology-changing snapshot retained an existing point resource")

	var removed_points: Array[EasingCurvePoint] = curve.points.duplicate()
	removed_points.remove_at(1)
	curve.set(EasingCurve.POINT_SNAPSHOT_PROPERTY, curve.make_point_snapshot(removed_points))
	_expect(curve.points.size() == 2, "Point snapshot removal did not immediately affect output")
	_expect(counts.changed > 0 and counts.points > 0, "Point snapshot edits did not propagate curve signals")
	_expect(not _contains_resource(curve.get_point_snapshot()), "Editor point snapshot still contains Resource values")


func _test_parameter_drag_transactions() -> void:
	var curve := EasingCurve.new()
	var counts := _signal_counts(curve)
	var edits := {
		&"steps": 7,
		&"y_offset": 0.2,
		&"power": 3.5,
		&"amplitude": 2.0,
		&"period": 0.5,
	}

	for property_name: StringName in edits:
		var running_curve := curve.duplicate() as EasingCurve
		var running_counts := _signal_counts(running_curve)
		var original_value: Variant = curve.get(property_name)
		var original_snapshot := curve.get_function_snapshot()
		var changed_before: int = counts.changed
		curve._begin_editor_parameter_edit()
		curve.set(property_name, edits[property_name])
		_expect(curve.get(property_name) == edits[property_name], "%s drag did not update the authoring curve immediately" % property_name)
		_expect(running_curve.get(property_name) == original_value, "%s drag disrupted the captured running curve" % property_name)
		_expect(counts.changed == changed_before, "%s drag emitted a restart signal before mouse release" % property_name)
		var final_snapshot := curve.get_function_snapshot()
		curve.set_function_snapshot(original_snapshot)
		curve._cancel_editor_parameter_edit()
		curve.set(EasingCurve.FUNCTION_SNAPSHOT_PROPERTY, final_snapshot)
		running_curve.set(EasingCurve.FUNCTION_SNAPSHOT_PROPERTY, final_snapshot)
		_expect(curve.get(property_name) == edits[property_name] and original_value != edits[property_name], "%s snapshot commit lost the final value" % property_name)
		_expect(counts.changed == changed_before + 1, "%s release did not commit exactly once in the editor" % property_name)
		_expect(running_counts.changed == 1, "%s release did not apply exactly once to the running scene" % property_name)

	var changed_before_noop: int = counts.changed
	curve._begin_editor_parameter_edit()
	curve._cancel_editor_parameter_edit()
	_expect(counts.changed == changed_before_noop, "An unchanged parameter drag emitted a restart signal")

	for transition: EasingCurve.TRANS in [EasingCurve.TRANS.JITTER, EasingCurve.TRANS.IRREGULAR]:
		var mode_curve := EasingCurve.new()
		mode_curve.trans_type = transition
		var mode_counts := _signal_counts(mode_curve)
		for property_name: StringName in {&"num_points": 6, &"randomness": 1.5}:
			var running_curve := mode_curve.duplicate() as EasingCurve
			var running_counts := _signal_counts(running_curve)
			var original_snapshot := mode_curve.get_function_snapshot()
			mode_curve._begin_editor_parameter_edit()
			mode_curve.set(property_name, {&"num_points": 6, &"randomness": 1.5}[property_name])
			var expected_point_count := mode_curve.num_points if transition == EasingCurve.TRANS.JITTER else mode_curve.num_points + 1
			_expect(mode_curve._irregular_points_x.size() == expected_point_count, "%s %s drag did not regenerate graph data" % [EasingCurve.TRANS.keys()[transition], property_name])
			_expect(mode_counts.changed == 0, "%s %s drag emitted a restart signal" % [EasingCurve.TRANS.keys()[transition], property_name])
			var final_snapshot := mode_curve.get_function_snapshot()
			var preview_points_y: PackedFloat64Array = final_snapshot.generated_points_y
			mode_curve.set_function_snapshot(original_snapshot)
			mode_curve._cancel_editor_parameter_edit()
			mode_curve.set(EasingCurve.FUNCTION_SNAPSHOT_PROPERTY, final_snapshot)
			running_curve.set(EasingCurve.FUNCTION_SNAPSHOT_PROPERTY, final_snapshot)
			_expect(PackedFloat64Array(mode_curve._irregular_points_y) == preview_points_y, "%s %s release replaced the graph's generated curve" % [EasingCurve.TRANS.keys()[transition], property_name])
			_expect(PackedFloat64Array(running_curve._irregular_points_y) == preview_points_y, "%s %s running scene received a different generated curve" % [EasingCurve.TRANS.keys()[transition], property_name])
			_expect(mode_counts.changed == 1, "%s %s release did not commit exactly once in the editor" % [EasingCurve.TRANS.keys()[transition], property_name])
			_expect(running_counts.changed == 1, "%s %s release did not apply exactly once to the running scene" % [EasingCurve.TRANS.keys()[transition], property_name])
			mode_counts.changed = 0

		var generated_original := mode_curve.get_function_snapshot()
		mode_curve._begin_editor_parameter_edit()
		mode_curve.generate_irregular()
		var generated_snapshot := mode_curve.get_function_snapshot()
		mode_curve.set_function_snapshot(generated_original)
		mode_curve._cancel_editor_parameter_edit()
		generated_snapshot.force_notify = true
		var generated_running_curve := mode_curve.duplicate() as EasingCurve
		var generated_running_counts := _signal_counts(generated_running_curve)
		mode_curve.set(EasingCurve.FUNCTION_SNAPSHOT_PROPERTY, generated_snapshot)
		generated_running_curve.set(EasingCurve.FUNCTION_SNAPSHOT_PROPERTY, generated_snapshot)
		_expect(mode_counts.changed == 1, "%s Generate did not restart the editor scene exactly once" % EasingCurve.TRANS.keys()[transition])
		_expect(generated_running_counts.changed == 1, "%s Generate did not restart the running scene exactly once" % EasingCurve.TRANS.keys()[transition])
		_expect(PackedFloat64Array(generated_running_curve._irregular_points_y) == PackedFloat64Array(mode_curve._irregular_points_y), "%s Generate applied different editor and runtime curves" % EasingCurve.TRANS.keys()[transition])
		mode_counts.changed = 0


func _test_back_overshoot_contract() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.BACK
	var property_names: Array[StringName] = []
	for property: Dictionary in curve.get_property_list():
		property_names.append(StringName(property.name))
	var overshoot_index := property_names.find(&"overshoot")
	var points_index := property_names.find(&"points")
	_expect(
		overshoot_index >= 0 and points_index >= 0 and overshoot_index < points_index,
		"Back Overshoot is not displayed above the Points section",
	)
	_expect(is_equal_approx(curve.overshoot, 1.70158), "Back Overshoot lost its legacy default")
	_expect(EasingCurve.get_transition_definition(EasingCurve.TRANS.BACK).get("mode") == EasingCurve.CurveMode.BEZIER, "Back was not registered as a Bezier transition")
	_expect(EasingCurve.get_transition_parameters(EasingCurve.TRANS.BACK) == [&"overshoot"], "Back Overshoot is not registered as a transition parameter")
	_expect(not EasingCurve.is_function_transition(EasingCurve.TRANS.BACK), "Back was classified as a function transition")
	_expect(not curve.get_function_snapshot().has(&"overshoot"), "Back Overshoot leaked into the function snapshot")
	_expect(EasingCurve.has_parameter_default(&"overshoot"), "Overshoot is missing its Inspector reset default")
	_expect(
		is_equal_approx(float(EasingCurve.get_parameter_default(&"overshoot")), 1.70158),
		"Overshoot Inspector reset default changed",
	)
	_expect(EasingCurve.is_deferred_parameter(&"overshoot"), "Overshoot does not use deferred parameter editing")
	_expect(not EasingCurve.is_deferred_function_parameter(&"overshoot"), "Overshoot was treated as a function parameter")

	for transition: EasingCurve.TRANS in EasingCurve.TRANS.values():
		curve.trans_type = transition
		var found := false
		var visible := false
		for property: Dictionary in curve.get_property_list():
			if StringName(property.name) != &"overshoot":
				continue
			found = true
			visible = bool(property.usage & PROPERTY_USAGE_EDITOR)
			if transition == EasingCurve.TRANS.BACK:
				_expect(property.hint == PROPERTY_HINT_RANGE, "Overshoot lost its range hint")
				var range_parts := String(property.hint_string).split(",")
				_expect(
					range_parts.size() >= 3
					and is_equal_approx(range_parts[0].to_float(), 0.0)
					and is_equal_approx(range_parts[1].to_float(), 5.0)
					and is_equal_approx(range_parts[2].to_float(), 0.001),
					"Overshoot range is not 0.0-5.0 with a 0.001 step",
				)
			break
		_expect(found, "Overshoot is missing from the property list")
		_expect(
			visible == (transition == EasingCurve.TRANS.BACK),
			"Overshoot visibility is wrong for %s" % EasingCurve.TRANS.keys()[transition],
		)

	curve.trans_type = EasingCurve.TRANS.BACK
	_expect(curve.curve_mode == EasingCurve.CurveMode.BEZIER, "Back did not remain Bezier-backed")


func _test_back_overshoot_geometry() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.BACK
	var strengths: Array[float] = [0.0, 0.5, 1.70158, 3.0, 5.0]

	for ease: EasingCurve.EASE in EasingCurve.EASE.values():
		curve.ease_type = ease
		for strength in strengths:
			curve.overshoot = strength
			_validate_back_geometry(curve, ease, strength)
			_expect(
				not curve.is_selected_preset_modified(),
				"Changing Back/%s Overshoot to %.5f marked the preset modified"
				% [EasingCurve.EASE.keys()[ease], strength],
			)

		curve.overshoot = 0.5
		var low_first := curve.sample(0.25 if ease in [EasingCurve.EASE.IN_OUT, EasingCurve.EASE.OUT_IN] else 0.5)
		var low_second := curve.sample(0.75)
		curve.overshoot = 4.0
		var high_first := curve.sample(0.25 if ease in [EasingCurve.EASE.IN_OUT, EasingCurve.EASE.OUT_IN] else 0.5)
		var high_second := curve.sample(0.75)
		match ease:
			EasingCurve.EASE.IN:
				_expect(high_first < low_first, "Higher Back/In Overshoot did not strengthen the undershoot")
			EasingCurve.EASE.OUT:
				_expect(high_first > low_first, "Higher Back/Out Overshoot did not strengthen the overshoot")
			EasingCurve.EASE.IN_OUT:
				_expect(high_first < low_first and high_second > low_second, "Higher Back/In Out Overshoot did not strengthen both halves")
			EasingCurve.EASE.OUT_IN:
				_expect(high_first > low_first and high_second < low_second, "Higher Back/Out In Overshoot did not strengthen both halves")


func _validate_back_geometry(curve: EasingCurve, ease: EasingCurve.EASE, strength: float) -> void:
	var label := "Back/%s %.5f" % [EasingCurve.EASE.keys()[ease], strength]
	var expected_count := 2 if ease in [EasingCurve.EASE.IN, EasingCurve.EASE.OUT] else 3
	_expect(curve.points.size() == expected_count, "%s has the wrong point count" % label)
	if curve.points.size() != expected_count:
		return

	_expect(curve.points[0].position.is_equal_approx(Vector2.ZERO), "%s has the wrong start point" % label)
	_expect(curve.points[-1].position.is_equal_approx(Vector2.ONE), "%s has the wrong end point" % label)
	match ease:
		EasingCurve.EASE.IN:
			_expect(curve.points[0].right_control_point.is_equal_approx(Vector2(1.0 / 3.0, 0.0)), "%s has the wrong outgoing handle" % label)
			_expect(curve.points[1].left_control_point.is_equal_approx(Vector2(2.0 / 3.0, -strength / 3.0)), "%s has the wrong incoming handle" % label)
		EasingCurve.EASE.OUT:
			_expect(curve.points[0].right_control_point.is_equal_approx(Vector2(1.0 / 3.0, 1.0 + strength / 3.0)), "%s has the wrong outgoing handle" % label)
			_expect(curve.points[1].left_control_point.is_equal_approx(Vector2(2.0 / 3.0, 1.0)), "%s has the wrong incoming handle" % label)
		EasingCurve.EASE.IN_OUT:
			var combined_strength := strength * 1.525
			_expect(curve.points[1].position.is_equal_approx(Vector2(0.5, 0.5)), "%s has the wrong midpoint" % label)
			_expect(curve.points[0].right_control_point.is_equal_approx(Vector2(1.0 / 6.0, 0.0)), "%s has the wrong first handle" % label)
			_expect(curve.points[1].left_control_point.is_equal_approx(Vector2(1.0 / 3.0, -combined_strength / 6.0)), "%s did not apply the 1.525 incoming multiplier" % label)
			_expect(curve.points[1].right_control_point.is_equal_approx(Vector2(2.0 / 3.0, 1.0 + combined_strength / 6.0)), "%s did not apply the 1.525 outgoing multiplier" % label)
			_expect(curve.points[2].left_control_point.is_equal_approx(Vector2(5.0 / 6.0, 1.0)), "%s has the wrong final handle" % label)
		EasingCurve.EASE.OUT_IN:
			_expect(curve.points[1].position.is_equal_approx(Vector2(0.5, 0.5)), "%s has the wrong midpoint" % label)
			_expect(curve.points[0].right_control_point.is_equal_approx(Vector2(1.0 / 6.0, 0.5 + strength / 6.0)), "%s has the wrong first handle" % label)
			_expect(curve.points[1].left_control_point.is_equal_approx(Vector2(1.0 / 3.0, 0.5)), "%s has the wrong incoming midpoint handle" % label)
			_expect(curve.points[1].right_control_point.is_equal_approx(Vector2(2.0 / 3.0, 0.5)), "%s has the wrong outgoing midpoint handle" % label)
			_expect(curve.points[2].left_control_point.is_equal_approx(Vector2(5.0 / 6.0, 0.5 - strength / 6.0)), "%s has the wrong final handle" % label)


func _test_back_overshoot_runtime_updates() -> void:
	var curve := EasingCurve.new()
	curve.ease_type = EasingCurve.EASE.IN_OUT
	curve.trans_type = EasingCurve.TRANS.BACK
	var counts := _signal_counts(curve)
	var before_sample := curve.sample(0.25)
	curve.overshoot = 3.25
	_expect(not is_equal_approx(curve.sample(0.25), before_sample), "Back Overshoot did not immediately change sampled output")
	_expect(counts.changed > 0 and counts.points > 0, "Back Overshoot did not immediately publish regenerated geometry")
	_expect(curve.get_point_snapshot() == curve.get_canonical_preset_point_snapshot(), "Back Overshoot did not generate canonical geometry")
	_expect(not curve.is_selected_preset_modified(), "Changing Back Overshoot alone produced Back *")

	curve.points[1].left_control_point += Vector2(0.0, 0.1)
	_expect(curve.is_selected_preset_modified(), "Manually editing a generated Back handle did not produce Back *")
	curve.overshoot = 4.0
	_expect(not curve.is_selected_preset_modified(), "Changing Back Overshoot did not replace manually modified geometry")
	_expect(curve.get_point_snapshot() == curve.get_canonical_preset_point_snapshot(), "Back regeneration did not use the current Overshoot")

	curve.trans_type = EasingCurve.TRANS.SINE
	var sine_snapshot := curve.get_point_snapshot()
	var sine_points: Array[EasingCurvePoint] = curve.points.duplicate()
	counts.changed = 0
	counts.points = 0
	curve.overshoot = 2.75
	_expect(curve.get_point_snapshot() == sine_snapshot, "Changing Overshoot rebuilt a non-Back preset")
	_expect(curve.points == sine_points, "Changing Overshoot replaced non-Back point resources")
	_expect(counts.points == 0, "Changing Overshoot emitted non-Back point changes")
	curve.trans_type = EasingCurve.TRANS.BACK
	_validate_back_geometry(curve, EasingCurve.EASE.IN_OUT, 2.75)

	var deferred_curve := EasingCurve.new()
	deferred_curve.ease_type = EasingCurve.EASE.OUT_IN
	deferred_curve.trans_type = EasingCurve.TRANS.BACK
	var running_curve := deferred_curve.duplicate() as EasingCurve
	var deferred_counts := _signal_counts(deferred_curve)
	var running_counts := _signal_counts(running_curve)
	deferred_curve._begin_editor_parameter_edit()
	deferred_curve.overshoot = 2.0
	var first_drag_sample := deferred_curve.sample(0.25)
	deferred_curve.overshoot = 3.5
	_expect(not is_equal_approx(deferred_curve.sample(0.25), first_drag_sample), "Deferred Back drag did not update authoring geometry immediately")
	_expect(deferred_counts.changed == 0 and deferred_counts.points == 0, "Deferred Back drag emitted restart signals before release")
	var final_snapshot := deferred_curve.get_editor_state_snapshot()
	deferred_curve._finish_editor_parameter_edit()
	_expect(deferred_counts.changed == 1 and deferred_counts.points == 1, "Deferred Back release did not publish one geometry update")
	running_curve.set(EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY, final_snapshot)
	_expect(is_equal_approx(running_curve.overshoot, 3.5), "Runtime snapshot lost Back Overshoot")
	_expect(running_curve.get_point_snapshot() == deferred_curve.get_point_snapshot(), "Runtime snapshot applied different Back geometry")
	_expect(running_counts.changed == 1 and running_counts.points == 1, "Runtime snapshot did not publish one Back update")


func _test_preset_parameter_notification_counts() -> void:
	var constant_curve := EasingCurve.new()
	constant_curve.trans_type = EasingCurve.TRANS.CONSTANT
	var constant_regenerated_counts := _signal_counts(constant_curve)
	constant_curve.constant_value = 0.75
	_expect(
		constant_regenerated_counts.changed == 1
		and constant_regenerated_counts.points == 1,
		"Constant regeneration did not publish exactly one change and point update",
	)
	_expect(
		not constant_curve.is_selected_preset_modified(),
		"Constant regeneration changed the selected preset state",
	)

	constant_curve.trans_type = EasingCurve.TRANS.SINE
	var constant_snapshot := constant_curve.get_point_snapshot()
	var constant_non_regenerated_counts := _signal_counts(constant_curve)
	constant_curve.constant_value = 0.25
	_expect(
		constant_non_regenerated_counts.changed == 1
		and constant_non_regenerated_counts.points == 0,
		"Constant non-regeneration did not publish exactly one parameter change",
	)
	_expect(
		constant_curve.get_point_snapshot() == constant_snapshot,
		"Constant non-regeneration changed Sine geometry",
	)

	var back_curve := EasingCurve.new()
	back_curve.trans_type = EasingCurve.TRANS.BACK
	var back_regenerated_counts := _signal_counts(back_curve)
	back_curve.overshoot = 3.25
	_expect(
		back_regenerated_counts.changed == 1 and back_regenerated_counts.points == 1,
		"Back regeneration did not publish exactly one change and point update",
	)
	_expect(
		not back_curve.is_selected_preset_modified(),
		"Back regeneration changed the selected preset state",
	)

	back_curve.trans_type = EasingCurve.TRANS.SINE
	var back_snapshot := back_curve.get_point_snapshot()
	var back_non_regenerated_counts := _signal_counts(back_curve)
	back_curve.overshoot = 4.0
	_expect(
		back_non_regenerated_counts.changed == 1 and back_non_regenerated_counts.points == 0,
		"Back non-regeneration did not publish exactly one parameter change",
	)
	_expect(
		back_curve.get_point_snapshot() == back_snapshot,
		"Back non-regeneration changed Sine geometry",
	)


func _test_back_overshoot_round_trip() -> void:
	var default_curve := EasingCurve.new()
	default_curve.ease_type = EasingCurve.EASE.IN_OUT
	default_curve.trans_type = EasingCurve.TRANS.BACK
	var save_error := ResourceSaver.save(default_curve, BACK_ROUND_TRIP_PATH)
	_expect(save_error == OK, "Default Back curve could not be saved")
	if save_error == OK:
		var saved_text := FileAccess.get_file_as_string(BACK_ROUND_TRIP_PATH)
		_expect("overshoot =" not in saved_text, "Default Back Overshoot was unnecessarily serialized")
		var loaded_default := ResourceLoader.load(BACK_ROUND_TRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EasingCurve
		_expect(loaded_default != null, "Back resource without a stored Overshoot could not be loaded")
		if loaded_default != null:
			_expect(is_equal_approx(loaded_default.overshoot, 1.70158), "Back resource without a stored Overshoot lost the legacy default")
			_expect(not loaded_default.is_selected_preset_modified(), "Default Back geometry changed after save/load")

	var custom_curve := EasingCurve.new()
	custom_curve.ease_type = EasingCurve.EASE.OUT_IN
	custom_curve.trans_type = EasingCurve.TRANS.BACK
	custom_curve.overshoot = 3.25
	var custom_samples := PackedFloat64Array([
		custom_curve.sample(0.17),
		custom_curve.sample(0.4),
		custom_curve.sample(0.83),
	])
	save_error = ResourceSaver.save(custom_curve, BACK_ROUND_TRIP_PATH)
	_expect(save_error == OK, "Parameterized Back curve could not be saved")
	if save_error == OK:
		var saved_text := FileAccess.get_file_as_string(BACK_ROUND_TRIP_PATH)
		_expect("overshoot = 3.25" in saved_text, "Non-default Back Overshoot was not serialized")
		var loaded_custom := ResourceLoader.load(BACK_ROUND_TRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EasingCurve
		_expect(loaded_custom != null, "Parameterized Back curve could not be loaded")
		if loaded_custom != null:
			_expect(is_equal_approx(loaded_custom.overshoot, 3.25), "Back Overshoot changed after save/load")
			_expect(loaded_custom.curve_mode == EasingCurve.CurveMode.BEZIER, "Parameterized Back loaded outside Bezier mode")
			_expect(not loaded_custom.is_selected_preset_modified(), "Parameterized Back geometry changed after save/load")
			_expect(
				_float_arrays_equal_approx(
					PackedFloat64Array([loaded_custom.sample(0.17), loaded_custom.sample(0.4), loaded_custom.sample(0.83)]),
					custom_samples,
				),
				"Parameterized Back samples changed after save/load",
			)

	if FileAccess.file_exists(BACK_ROUND_TRIP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACK_ROUND_TRIP_PATH))


func _test_css_cubic_bezier() -> void:
	_expect(EasingCurve.TRANS.SINE == 19, "Adding CSS Cubic Bezier changed the serialized Sine transition ID")
	_expect(EasingCurve.TRANS.CSS_CUBIC_BEZIER == 20, "CSS Cubic Bezier did not use the next serialized transition ID")
	_expect(
		EasingCurve.is_function_transition(EasingCurve.TRANS.CSS_CUBIC_BEZIER),
		"CSS Cubic Bezier was not registered as a function transition",
	)

	var source := "cubic-bezier(0.8, -0.4, 0.5, 1)"
	var expected_controls := PackedFloat64Array([0.8, -0.4, 0.5, 1.0])
	_expect(
		_float_arrays_equal_approx(EASING_LIBRARY.CSSCubicBezier.parse(source), expected_controls),
		"CSS Cubic Bezier did not parse valid CSS controls",
	)
	_expect(
		_float_arrays_equal_approx(
			EASING_LIBRARY.CSSCubicBezier.parse("CUBIC-BEZIER(0.8, -0.4, 0.5, 1)"),
			expected_controls,
		),
		"CSS Cubic Bezier did not accept CSS function-name casing",
	)
	for invalid_source in [
		"cubic-bezier(0.8, -0.4, 0.5)",
		"cubic-bezier(0.8, -0.4, 0.5, 1,)",
		"cubic-bezier(1.2, 0, 0.5, 1)",
		"cubic-bezier(0.8, 0, -0.1, 1)",
	]:
		_expect(
			EASING_LIBRARY.CSSCubicBezier.parse(invalid_source).is_empty(),
			"CSS Cubic Bezier accepted invalid input: %s" % invalid_source,
		)

	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CSS_CUBIC_BEZIER
	_expect(curve.curve_mode == EasingCurve.CurveMode.FUNCTION, "CSS Cubic Bezier selected the wrong curve mode")
	_expect(curve.function_callable.is_valid(), "CSS Cubic Bezier did not initialize its runtime callable")
	var css_property_visible := false
	var css_linear_property_visible := false
	for property: Dictionary in curve.get_property_list():
		if StringName(property.name) == &"css_cubic_bezier":
			css_property_visible = bool(property.usage & PROPERTY_USAGE_EDITOR)
		elif StringName(property.name) == &"css_linear":
			css_linear_property_visible = bool(property.usage & PROPERTY_USAGE_EDITOR)
	_expect(css_property_visible, "CSS Cubic Bezier input is hidden for its transition")
	_expect(not css_linear_property_visible, "CSS Linear input remained visible for CSS Cubic Bezier")

	var before := curve.sample(0.5)
	var counts := _signal_counts(curve)
	curve.css_cubic_bezier = source
	_expect(counts.changed == 1, "Changing CSS Cubic Bezier did not publish one immediate update")
	_expect(not is_equal_approx(curve.sample(0.5), before), "Changing CSS Cubic Bezier did not update the curve")
	var expected_samples := PackedFloat64Array([
		0.0,
		-0.04283762349101638,
		-0.07186802022414875,
		0.07564250168800712,
		0.7980103905238238,
		0.9776273520112461,
		1.0,
	])
	var offsets := PackedFloat64Array([0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0])
	for ease: EasingCurve.EASE in EasingCurve.EASE.values():
		curve.ease_type = ease
		for i in offsets.size():
			_expect(
				absf(curve.sample(offsets[i]) - expected_samples[i]) <= 0.000001,
				"CSS Cubic Bezier %s sample changed at %.2f" % [EasingCurve.EASE.keys()[ease], offsets[i]],
			)

	var save_error := ResourceSaver.save(curve, CSS_CUBIC_ROUND_TRIP_PATH)
	_expect(save_error == OK, "CSS Cubic Bezier curve could not be saved")
	if save_error == OK:
		var loaded := ResourceLoader.load(
			CSS_CUBIC_ROUND_TRIP_PATH,
			"",
			ResourceLoader.CACHE_MODE_IGNORE,
		) as EasingCurve
		_expect(loaded != null, "CSS Cubic Bezier curve could not be loaded")
		if loaded != null:
			_expect(loaded.trans_type == EasingCurve.TRANS.CSS_CUBIC_BEZIER, "CSS Cubic Bezier transition changed after save/load")
			_expect(loaded.css_cubic_bezier == source, "CSS Cubic Bezier input changed after save/load")
			_expect(is_equal_approx(loaded.sample(0.5), curve.sample(0.5)), "CSS Cubic Bezier output changed after save/load")

	if FileAccess.file_exists(CSS_CUBIC_ROUND_TRIP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CSS_CUBIC_ROUND_TRIP_PATH))


func _test_flat_storage_and_round_trip() -> void:
	var curve := EasingCurve.new()
	curve.set_trans(EasingCurve.TRANS.CUSTOM)
	var saved_points: Array[EasingCurvePoint] = curve.points.duplicate()
	saved_points.append(EasingCurvePoint.new(Vector2(0.5, 0.75)))
	saved_points.sort_custom(func(a: EasingCurvePoint, b: EasingCurvePoint) -> bool: return a.position.x < b.position.x)
	curve.set(EasingCurve.POINT_SNAPSHOT_PROPERTY, curve.make_point_snapshot(saved_points))
	curve.points[1].set_locked("position", true)

	var points_property_found := false
	var points_property_is_editor_visible := false
	var resource_array_is_stored := false
	var flat_count_found := false
	var snapshot_is_editor_only := false
	var function_snapshot_is_editor_only := false
	for property in curve.get_property_list():
		if property.name == "points":
			points_property_found = true
			points_property_is_editor_visible = bool(property.usage & PROPERTY_USAGE_EDITOR)
			resource_array_is_stored = bool(property.usage & PROPERTY_USAGE_STORAGE)
		elif property.name == "_point_count":
			flat_count_found = bool(property.usage & PROPERTY_USAGE_STORAGE)
		elif property.name == EasingCurve.POINT_SNAPSHOT_PROPERTY:
			snapshot_is_editor_only = bool(property.usage & PROPERTY_USAGE_EDITOR) and not bool(property.usage & PROPERTY_USAGE_STORAGE)
		elif property.name == EasingCurve.FUNCTION_SNAPSHOT_PROPERTY:
			function_snapshot_is_editor_only = bool(property.usage & PROPERTY_USAGE_EDITOR) and not bool(property.usage & PROPERTY_USAGE_STORAGE)
	_expect(points_property_found and not resource_array_is_stored, "Public points API is still serialized as Array[Resource]")
	_expect(points_property_is_editor_visible, "Public points API is no longer available to the custom inspector")
	_expect(flat_count_found, "Flattened primitive point storage is missing")
	_expect(snapshot_is_editor_only, "Point snapshot bridge must remain editor-only and must not alter saved resources")
	_expect(function_snapshot_is_editor_only, "Function snapshot bridge must remain editor-only and must not alter saved resources")
	_expect(not _contains_resource(curve.get_function_snapshot()), "Editor function snapshot contains a Resource value")

	var save_error := ResourceSaver.save(curve, ROUND_TRIP_PATH)
	_expect(save_error == OK, "Could not save flattened curve resource")
	var saved_text := FileAccess.get_file_as_string(ROUND_TRIP_PATH)
	_expect("_point_count" in saved_text and "_point_1/position" in saved_text, "Saved curve does not contain flattened point properties")
	_expect("points = Array" not in saved_text, "Saved curve still contains Array[Resource] point storage")

	var loaded := ResourceLoader.load(ROUND_TRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EasingCurve
	_expect(loaded != null and loaded.points.size() == curve.points.size(), "Flattened curve did not round-trip its point count")
	_expect(loaded != null and loaded.points[1].position == curve.points[1].position, "Flattened curve did not round-trip point positions")
	_expect(loaded != null and loaded.points[1].locked.position, "Flattened curve did not round-trip nested point properties")
	_expect(loaded != null and is_equal_approx(loaded.sample(0.5), curve.sample(0.5)), "Flattened curve output changed after round-trip")

	var duplicate := curve.duplicate() as EasingCurve
	_expect(duplicate != null and duplicate.points.size() == curve.points.size(), "Resource duplication lost flattened point data")
	_expect(duplicate != null and duplicate.points[0] != curve.points[0], "Resource duplication still shares nested point resources")

	var absolute_path := ProjectSettings.globalize_path(ROUND_TRIP_PATH)
	if FileAccess.file_exists(ROUND_TRIP_PATH):
		DirAccess.remove_absolute(absolute_path)


func _test_generated_curve_round_trip() -> void:
	for transition: EasingCurve.TRANS in [EasingCurve.TRANS.JITTER, EasingCurve.TRANS.IRREGULAR]:
		var curve := EasingCurve.new()
		curve.trans_type = transition
		curve.num_points = 6
		curve.randomness = 1.5
		curve.generate_irregular()
		var saved_points_x := PackedFloat64Array(curve._irregular_points_x)
		var saved_points_y := PackedFloat64Array(curve._irregular_points_y)
		var saved_samples := PackedFloat64Array([
			curve.sample(0.17),
			curve.sample(0.4),
			curve.sample(0.83),
		])
		var save_error := ResourceSaver.save(curve, GENERATED_ROUND_TRIP_PATH)
		_expect(save_error == OK, "%s curve could not be saved" % EasingCurve.TRANS.keys()[transition])
		var loaded := ResourceLoader.load(GENERATED_ROUND_TRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EasingCurve
		_expect(loaded != null, "%s curve could not be loaded" % EasingCurve.TRANS.keys()[transition])
		if loaded == null:
			continue
		_expect(_float_arrays_equal_approx(PackedFloat64Array(loaded._irregular_points_x), saved_points_x), "%s saved different generated X points" % EasingCurve.TRANS.keys()[transition])
		_expect(
			_float_arrays_equal_approx(PackedFloat64Array(loaded._irregular_points_y), saved_points_y),
			"%s saved different generated Y points: %s -> %s" % [EasingCurve.TRANS.keys()[transition], saved_points_y, PackedFloat64Array(loaded._irregular_points_y)],
		)
		_expect(
			_float_arrays_equal_approx(PackedFloat64Array([loaded.sample(0.17), loaded.sample(0.4), loaded.sample(0.83)]), saved_samples),
			"%s sampled output changed after saving" % EasingCurve.TRANS.keys()[transition],
		)

	if FileAccess.file_exists(GENERATED_ROUND_TRIP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GENERATED_ROUND_TRIP_PATH))


func _test_generated_transition_semantics() -> void:
	var sample_positions: Array[float] = [0.13, 0.37, 0.61, 0.87]
	for transition: EasingCurve.TRANS in [EasingCurve.TRANS.JITTER, EasingCurve.TRANS.IRREGULAR]:
		var curve := EasingCurve.new()
		curve.trans_type = transition
		curve.num_points = 8
		curve.randomness = 3.0
		seed(1024 + int(transition))
		curve.generate_irregular()
		var points_x: Array[float] = curve._irregular_points_x
		var points_y: Array[float] = curve._irregular_points_y
		for sample_x in sample_positions:
			var expected: float = float(EasingCurve.EASING_LIBRARY.Irregular.easeIn(
				sample_x,
				0.0,
				1.0,
				1.0,
				points_x,
				points_y,
			))
			var first_sample := curve.sample(sample_x)
			_expect(is_equal_approx(first_sample, curve.sample(sample_x)), "%s changed between samples without regeneration" % EasingCurve.TRANS.keys()[transition])
			_expect(is_equal_approx(first_sample, expected), "%s no longer uses the generated-array Irregular backend" % EasingCurve.TRANS.keys()[transition])

		curve.randomness = 0.0
		seed(2048 + int(transition))
		curve.generate_irregular()
		for sample_x in sample_positions:
			_expect(is_equal_approx(curve.sample(sample_x), sample_x), "%s with zero randomness did not generate a linear curve" % EasingCurve.TRANS.keys()[transition])

	var irregular_low := EasingCurve.new()
	irregular_low.trans_type = EasingCurve.TRANS.IRREGULAR
	irregular_low.num_points = 4
	irregular_low.randomness = 3.5
	seed(4096)
	irregular_low.generate_irregular()
	var irregular_high := EasingCurve.new()
	irregular_high.trans_type = EasingCurve.TRANS.IRREGULAR
	irregular_high.num_points = 40
	irregular_high.randomness = 3.5
	seed(4096)
	irregular_high.generate_irregular()
	var low_deviation := 0.0
	var high_deviation := 0.0
	for i in range(1, 10):
		var sample_x := float(i) / 10.0
		low_deviation += absf(irregular_low.sample(sample_x) - sample_x)
		high_deviation += absf(irregular_high.sample(sample_x) - sample_x)
	_expect(high_deviation < low_deviation * 0.6, "Irregular deviations did not shrink materially with more points")

	var jitter := EasingCurve.new()
	jitter.trans_type = EasingCurve.TRANS.JITTER
	jitter.num_points = 40
	jitter.randomness = 3.5
	seed(8192)
	jitter.generate_irregular()
	var maximum_jitter_deviation := 0.0
	for i in range(1, jitter._irregular_points_y.size() - 1):
		maximum_jitter_deviation = maxf(
			maximum_jitter_deviation,
			absf(jitter._irregular_points_y[i] - jitter._irregular_points_x[i]),
		)
	_expect(maximum_jitter_deviation > 0.1, "Jitter offsets were scaled down by point count")


func _test_function_parameters() -> void:
	var curve := EasingCurve.new()
	var counts := _signal_counts(curve)

	curve.trans_type = EasingCurve.TRANS.STEP
	curve.steps = 4
	curve.from_start = false
	curve.y_offset = 0.0
	var step_before := curve.sample(0.3)
	curve.steps = 2
	_expect(not is_equal_approx(step_before, curve.sample(0.3)), "Step count update did not immediately affect output")
	var start_before := curve.sample(0.3)
	curve.from_start = true
	_expect(not is_equal_approx(start_before, curve.sample(0.3)), "Step start mode update did not immediately affect output")
	var offset_before := curve.sample(0.3)
	curve.y_offset = 0.1
	_expect(not is_equal_approx(offset_before, curve.sample(0.3)), "Step offset update did not immediately affect output")

	curve.trans_type = EasingCurve.TRANS.POWER
	curve.power = 2.0
	var power_before := curve.sample(0.5)
	curve.power = 3.0
	_expect(not is_equal_approx(power_before, curve.sample(0.5)), "Power update did not immediately affect output")

	curve.trans_type = EasingCurve.TRANS.ELASTIC
	curve.amplitude = 1.0
	curve.period = 0.3
	var elastic_before := curve.sample(0.4)
	curve.amplitude = 2.0
	curve.period = 0.5
	_expect(not is_equal_approx(elastic_before, curve.sample(0.4)), "Elastic parameters did not immediately affect output")

	curve.trans_type = EasingCurve.TRANS.IRREGULAR
	curve.num_points = 5
	curve.randomness = 2.0
	_expect(curve._irregular_points_x.size() == 6 and curve._irregular_points_y.size() == 6, "Irregular parameters did not rebuild generated data")
	curve.num_points = 2
	_expect(curve._irregular_points_x.size() == 3 and curve._irregular_points_y.size() == 3, "Irregular density-scaled generation did not rebuild generated data")
	_expect(_is_finite(curve.sample(0.4)), "Irregular output became invalid after parameter updates")

	curve.trans_type = EasingCurve.TRANS.JITTER
	curve.num_points = 6
	curve.randomness = 0.5
	var jitter_sample := curve.sample(0.4)
	_expect(_is_finite(jitter_sample), "Jitter output became invalid after parameter updates")
	_expect(is_equal_approx(jitter_sample, curve.sample(0.4)), "Jitter output changed between samples without regeneration")
	_expect(counts.changed > 0, "Function parameter updates did not emit the resource changed signal")


func _test_every_transition_and_runtime_switching() -> void:
	var curve := EasingCurve.new()
	var counts := _signal_counts(curve)
	for transition in EasingCurve.TRANS.values():
		var changed_before: int = counts.changed
		curve.trans_type = transition
		_expect(counts.changed > changed_before or transition == EasingCurve.TRANS.LINEAR, "%s did not emit a runtime change notification" % EasingCurve.TRANS.keys()[transition])
		for ease in EasingCurve.EASE.values():
			curve.ease_type = ease
			var expected_mode := (
				EasingCurve.CurveMode.FUNCTION
				if EasingCurve.is_function_transition(transition)
				else EasingCurve.CurveMode.BEZIER
			)
			_expect(curve.curve_mode == expected_mode, "%s/%s selected the wrong runtime mode" % [EasingCurve.TRANS.keys()[transition], EasingCurve.EASE.keys()[ease]])
			if expected_mode == EasingCurve.CurveMode.FUNCTION:
				_expect(curve.function_callable.is_valid(), "%s/%s did not rebuild its runtime callable" % [EasingCurve.TRANS.keys()[transition], EasingCurve.EASE.keys()[ease]])
			else:
				_expect(curve.points.size() >= 2, "%s/%s did not rebuild its runtime points" % [EasingCurve.TRANS.keys()[transition], EasingCurve.EASE.keys()[ease]])
			for offset in [0.0, 0.17, 0.5, 0.83, 1.0]:
				_expect(_is_finite(curve.sample(offset)), "%s/%s produced invalid runtime output" % [EasingCurve.TRANS.keys()[transition], EasingCurve.EASE.keys()[ease]])

	curve.ease_type = EasingCurve.EASE.IN
	curve.trans_type = EasingCurve.TRANS.POWER
	_expect(curve.curve_mode == EasingCurve.CurveMode.FUNCTION, "Bezier-to-function runtime switch failed")
	_expect(curve.function_callable.is_valid(), "Function transition did not initialize its runtime callable")
	curve.trans_type = EasingCurve.TRANS.QUAD
	_expect(curve.curve_mode == EasingCurve.CurveMode.BEZIER and curve.points.size() >= 2, "Function-to-Bezier runtime switch failed")
	_expect(not curve.function_callable.is_valid(), "Function-to-Bezier switch retained a stale runtime callable")
	_expect(is_equal_approx(curve.sample(0.5), 0.25), "Function-to-Bezier switch changed Bézier sampling")
	curve.trans_type = EasingCurve.TRANS.IRREGULAR
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	_expect(curve.curve_mode == EasingCurve.CurveMode.BEZIER and curve.points.size() >= 2, "Function-to-custom runtime switch failed")


func _contains_resource(value: Variant) -> bool:
	if value is Resource:
		return true
	if value is Dictionary:
		for key in value:
			if _contains_resource(key) or _contains_resource(value[key]):
				return true
	if value is Array:
		for item in value:
			if _contains_resource(item):
				return true
	return false

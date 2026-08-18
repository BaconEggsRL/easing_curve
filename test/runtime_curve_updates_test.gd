extends SceneTree

const ROUND_TRIP_PATH := "res://test/_runtime_curve_round_trip.tres"
const GENERATED_ROUND_TRIP_PATH := "res://test/_generated_curve_round_trip.tres"
const FUNCTION_TRANSITIONS := [
	EasingCurve.TRANS.JITTER,
	EasingCurve.TRANS.IRREGULAR,
	EasingCurve.TRANS.STEP,
	EasingCurve.TRANS.POWER,
	EasingCurve.TRANS.ELASTIC,
	EasingCurve.TRANS.BOUNCE,
	EasingCurve.TRANS.SPRING,
]

var _failures := 0
var _checks := 0


func _init() -> void:
	seed(123456)
	_test_legacy_resources_and_nested_changes()
	_test_bezier_point_operations()
	_test_handle_control_signal_suppression()
	_test_resource_free_point_snapshots()
	_test_parameter_drag_transactions()
	_test_flat_storage_and_round_trip()
	_test_generated_curve_round_trip()
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
	var packed_scene := load("res://addons/easing_curve/test_scene/test.tscn") as PackedScene
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


func _test_handle_control_signal_suppression() -> void:
	var point := EasingCurvePoint.new()
	var x_input := SpinBox.new()
	var y_input := SpinBox.new()
	x_input.step = 0.001
	y_input.step = 0.001
	var emitted := {"x": 0, "y": 0}
	x_input.value_changed.connect(func(_value: float) -> void: emitted.x += 1)
	y_input.value_changed.connect(func(_value: float) -> void: emitted.y += 1)
	point.set_input_control("right_control_point", "x", x_input)
	point.set_input_control("right_control_point", "y", y_input)

	point.right_control_point = Vector2(0.4, 0.6)
	_expect(x_input.value == 0.4 and y_input.value == 0.6, "Control handle edit did not refresh Inspector inputs")
	_expect(emitted.x == 0 and emitted.y == 0, "Control handle refresh recursively emitted another Inspector edit")
	x_input.free()
	y_input.free()


func _test_resource_free_point_snapshots() -> void:
	var curve := EasingCurve.new()
	var counts := _signal_counts(curve)
	var original_first_point := curve.points[0]
	var changed_snapshot := curve.get_point_snapshot()
	var changed_positions: PackedVector2Array = changed_snapshot.positions
	changed_positions[1] = Vector2(1.0, 0.25)
	changed_snapshot.positions = changed_positions
	curve.set(EasingCurve.POINT_SNAPSHOT_PROPERTY, changed_snapshot)
	_expect(curve.points[0] == original_first_point, "Same-size point snapshots replaced existing point resources")
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
			var expected_point_count := mode_curve.num_points + 1 if transition == EasingCurve.TRANS.JITTER else mode_curve.num_points
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
	_expect(curve._irregular_points_x.size() == 5 and curve._irregular_points_y.size() == 5, "Irregular parameters did not rebuild generated data")
	curve.num_points = 2
	_expect(curve._irregular_points_x.size() == 2 and curve._irregular_points_y.size() == 2, "Irregular two-point fallback did not rebuild generated data")
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
				if transition in FUNCTION_TRANSITIONS
				else EasingCurve.CurveMode.BEZIER
			)
			_expect(curve.curve_mode == expected_mode, "%s/%s selected the wrong runtime mode" % [EasingCurve.TRANS.keys()[transition], EasingCurve.EASE.keys()[ease]])
			if expected_mode == EasingCurve.CurveMode.FUNCTION:
				_expect(curve.function_callable.is_valid(), "%s/%s did not rebuild its runtime callable" % [EasingCurve.TRANS.keys()[transition], EasingCurve.EASE.keys()[ease]])
			else:
				_expect(curve.points.size() >= 2, "%s/%s did not rebuild its runtime points" % [EasingCurve.TRANS.keys()[transition], EasingCurve.EASE.keys()[ease]])
			for offset in [0.0, 0.17, 0.5, 0.83, 1.0]:
				_expect(_is_finite(curve.sample(offset)), "%s/%s produced invalid runtime output" % [EasingCurve.TRANS.keys()[transition], EasingCurve.EASE.keys()[ease]])

	curve.trans_type = EasingCurve.TRANS.POWER
	_expect(curve.curve_mode == EasingCurve.CurveMode.FUNCTION, "Bezier-to-function runtime switch failed")
	curve.trans_type = EasingCurve.TRANS.QUAD
	_expect(curve.curve_mode == EasingCurve.CurveMode.BEZIER and curve.points.size() >= 2, "Function-to-Bezier runtime switch failed")
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

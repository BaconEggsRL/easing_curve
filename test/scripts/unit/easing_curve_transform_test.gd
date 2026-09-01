extends "res://test/scripts/support/test_case.gd"

const EDITOR_UNDO := preload("res://addons/easing_curve/scripts/editor/easing_curve_editor_undo.gd")
const CUSTOM_SAVE_PATH := "res://test/_transform_custom_round_trip.tres"
const PRESET_SAVE_PATH := "res://test/_transform_preset_round_trip.tres"
const SNAPSHOT_GEOMETRY_TOLERANCE := EasingCurve.PRESET_GEOMETRY_TOLERANCE

func _init() -> void:
	_test_bezier_reverse()
	_test_bezier_invert()
	_test_handle_mode_transform_state_and_notifications()
	_test_transform_composition()
	_test_canonical_presets_and_switching()
	_test_function_mode()
	_test_undo_redo()
	_test_save_load()
	_test_runtime_sampling()
	_cleanup_saved_files()

	_finish("EasingCurve global transform")


func _expect_snapshot(actual: Dictionary, expected: Dictionary, label: String) -> void:
	_expect(actual == expected, "%s\nexpected: %s\nactual: %s" % [label, expected, actual])


func _vector_equal_approx(a: Vector2, b: Vector2) -> bool:
	return (
		absf(a.x - b.x) <= SNAPSHOT_GEOMETRY_TOLERANCE
		and absf(a.y - b.y) <= SNAPSHOT_GEOMETRY_TOLERANCE
	)


func _expect_geometry_snapshot(
	actual: Dictionary,
	expected: Dictionary,
	label: String,
) -> void:
	var actual_positions: PackedVector2Array = actual.get("positions", PackedVector2Array())
	var expected_positions: PackedVector2Array = expected.get("positions", PackedVector2Array())
	var actual_left_controls: PackedVector2Array = actual.get("left_control_points", PackedVector2Array())
	var expected_left_controls: PackedVector2Array = expected.get("left_control_points", PackedVector2Array())
	var actual_right_controls: PackedVector2Array = actual.get("right_control_points", PackedVector2Array())
	var expected_right_controls: PackedVector2Array = expected.get("right_control_points", PackedVector2Array())
	var actual_locks: Array = actual.get("locks", [])
	var expected_locks: Array = expected.get("locks", [])
	_expect(
		actual_positions.size() == expected_positions.size()
		and actual_left_controls.size() == expected_left_controls.size()
		and actual_right_controls.size() == expected_right_controls.size()
		and actual_locks.size() == expected_locks.size(),
		"%s has different point topology" % label,
	)
	if (
		actual_positions.size() != expected_positions.size()
		or actual_left_controls.size() != expected_left_controls.size()
		or actual_right_controls.size() != expected_right_controls.size()
		or actual_locks.size() != expected_locks.size()
	):
		return
	for index in range(actual_positions.size()):
		_expect(_vector_equal_approx(actual_positions[index], expected_positions[index]), "%s position %d differs" % [label, index])
		_expect(_vector_equal_approx(actual_left_controls[index], expected_left_controls[index]), "%s left control %d differs" % [label, index])
		_expect(_vector_equal_approx(actual_right_controls[index], expected_right_controls[index]), "%s right control %d differs" % [label, index])
		_expect(actual_locks[index] == expected_locks[index], "%s locks %d differ" % [label, index])
	_expect(actual.get("handle_modes", PackedInt32Array()) == expected.get("handle_modes", PackedInt32Array()), "%s handle modes differ" % label)
	_expect(actual.get("left_force_linear", PackedByteArray()) == expected.get("left_force_linear", PackedByteArray()), "%s left Force Linear state differs" % label)
	_expect(actual.get("right_force_linear", PackedByteArray()) == expected.get("right_force_linear", PackedByteArray()), "%s right Force Linear state differs" % label)


func _custom_curve() -> EasingCurve:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var points: Array[EasingCurvePoint] = [
		EasingCurvePoint.new(Vector2(0.0, 0.1)),
		EasingCurvePoint.new(Vector2(0.35, 0.8)),
		EasingCurvePoint.new(Vector2(1.0, 0.9)),
	]
	points[0].left_control_point = Vector2(-0.1, 0.2)
	points[0].right_control_point = Vector2(0.12, 0.4)
	points[1].left_control_point = Vector2(0.2, 0.7)
	points[1].right_control_point = Vector2(0.62, 0.95)
	points[2].left_control_point = Vector2(0.8, 0.6)
	points[2].right_control_point = Vector2(1.1, 0.85)
	points[0].locked = {"position": true, "left_control_point": false, "right_control_point": true}
	points[1].locked = {"position": false, "left_control_point": true, "right_control_point": false}
	points[2].locked = {"position": true, "left_control_point": true, "right_control_point": false}
	curve.set_point_snapshot(curve.make_point_snapshot(points))
	return curve


func _mode_curve() -> EasingCurve:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var points: Array[EasingCurvePoint] = []
	for position in [
		Vector2(0.0, 0.1),
		Vector2(0.18, 0.24),
		Vector2(0.36, 0.42),
		Vector2(0.54, 0.58),
		Vector2(0.72, 0.76),
		Vector2(1.0, 0.9),
	]:
		var point := EasingCurvePoint.new(position)
		point.left_control_point = position + Vector2(-0.08, -0.05)
		point.right_control_point = position + Vector2(0.12, 0.07)
		points.append(point)

	points[1].set_handle_display_scale(Vector2(1.8, 0.65))
	points[1].handle_mode = EasingCurvePoint.HandleMode.BALANCED
	points[2].handle_mode = EasingCurvePoint.HandleMode.MIRRORED
	points[3].handle_mode = EasingCurvePoint.HandleMode.LINKED
	points[4].handle_mode = EasingCurvePoint.HandleMode.LINEAR
	points[3].set_force_linear_state(true, true)
	points[5].left_force_linear = true
	points[0].locked = {"position": true, "left_control_point": false, "right_control_point": false}
	points[1].locked = {"position": false, "left_control_point": true, "right_control_point": false}
	points[2].locked = {"position": false, "left_control_point": false, "right_control_point": true}
	points[3].locked = {"position": false, "left_control_point": true, "right_control_point": true}
	points[4].locked = {"position": true, "left_control_point": true, "right_control_point": false}
	points[5].locked = {"position": false, "left_control_point": false, "right_control_point": true}
	curve.points = points
	return curve


func _expect_handle_mode_invariants(curve: EasingCurve, label: String) -> void:
	for index in range(curve.points.size()):
		var point := curve.points[index]
		_expect(
			point.position.is_finite()
			and point.left_control_point.is_finite()
			and point.right_control_point.is_finite(),
			"%s point %d has non-finite geometry" % [label, index],
		)
		match point.handle_mode:
			EasingCurvePoint.HandleMode.LINEAR:
				_expect(
					point.left_control_point == point.position
					and point.right_control_point == point.position,
					"%s Linear point %d did not remain collapsed" % [label, index],
				)
			EasingCurvePoint.HandleMode.BALANCED:
				var left := (point.left_control_point - point.position) * point.handle_display_scale
				var right := (point.right_control_point - point.position) * point.handle_display_scale
				_expect(
					is_equal_approx(left.normalized().dot(right.normalized()), -1.0),
					"%s Balanced point %d lost its display-space alignment" % [label, index],
				)
			EasingCurvePoint.HandleMode.MIRRORED:
				_expect(
					point.left_control_point.is_equal_approx(2.0 * point.position - point.right_control_point),
					"%s Mirrored point %d lost reflection symmetry" % [label, index],
				)
			EasingCurvePoint.HandleMode.LINKED:
				_expect(
					point.left_control_point == point.right_control_point,
					"%s Linked point %d lost its shared handle" % [label, index],
				)
			EasingCurvePoint.HandleMode.FREE:
				pass


func _test_handle_mode_transform_state_and_notifications() -> void:
	for property_name: StringName in [&"reverse", &"invert"]:
		var curve := _mode_curve()
		var before := EDITOR_UNDO.capture_state(curve)
		var expected := (
			_expected_reverse(curve.get_point_snapshot())
			if property_name == &"reverse"
			else _expected_invert(curve.get_point_snapshot())
		)
		var notifications := {"changed": 0, "points": 0, "property_list": 0}
		curve.changed.connect(func(): notifications.changed += 1)
		curve.points_changed.connect(func(_points: Array[EasingCurvePoint]): notifications.points += 1)
		curve.property_list_changed.connect(func(): notifications.property_list += 1)

		curve.set(property_name, true)
		var after := EDITOR_UNDO.capture_state(curve)
		_expect_geometry_snapshot(curve.get_point_snapshot(), expected, "%s did not preserve Handle Mode point state" % property_name)
		_expect_handle_mode_invariants(curve, "%s transform" % property_name)
		_expect(notifications.changed == 1 and notifications.points == 1 and notifications.property_list == 1, "%s did not publish one coherent Points-list refresh" % property_name)

		var history := UndoRedo.new()
		_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Toggle %s" % property_name, EasingCurveEditorUndo.ActionContext.new(before, after)), "%s Handle Mode transform did not create an Undo action" % property_name)
		notifications.changed = 0
		notifications.points = 0
		notifications.property_list = 0
		history.undo()
		_expect(curve.get_editor_state_snapshot() == before, "%s Undo did not restore complete Handle Mode state" % property_name)
		_expect_handle_mode_invariants(curve, "%s Undo" % property_name)
		_expect(notifications.changed == 1 and notifications.points == 1 and notifications.property_list == 1, "%s Undo did not refresh the Points list: %s" % [property_name, notifications])
		notifications.changed = 0
		notifications.points = 0
		notifications.property_list = 0
		history.redo()
		_expect(curve.get_editor_state_snapshot() == after, "%s Redo did not restore complete transformed Handle Mode state" % property_name)
		_expect_handle_mode_invariants(curve, "%s Redo" % property_name)
		_expect(notifications.changed == 1 and notifications.points == 1 and notifications.property_list == 1, "%s Redo did not refresh the Points list: %s" % [property_name, notifications])
		history.clear_history(false)
		history.free()


func _expected_reverse(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	var positions: PackedVector2Array = snapshot.positions
	var left_controls: PackedVector2Array = snapshot.left_control_points
	var right_controls: PackedVector2Array = snapshot.right_control_points
	var locks: Array = snapshot.locks
	var out_positions := PackedVector2Array()
	var out_left_controls := PackedVector2Array()
	var out_right_controls := PackedVector2Array()
	var out_locks: Array[Dictionary] = []
	var out_handle_modes := PackedInt32Array()
	var out_left_force_linear := PackedByteArray()
	var out_right_force_linear := PackedByteArray()
	for index in range(positions.size() - 1, -1, -1):
		var position := positions[index]
		position.x = 1.0 - position.x
		out_positions.append(position)
		var left := right_controls[index]
		left.x = 1.0 - left.x
		out_left_controls.append(left)
		var right := left_controls[index]
		right.x = 1.0 - right.x
		out_right_controls.append(right)
		var source_locks: Dictionary = locks[index]
		out_locks.append({
			"position": source_locks.position,
			"left_control_point": source_locks.right_control_point,
			"right_control_point": source_locks.left_control_point,
		})
		out_handle_modes.append(snapshot.handle_modes[index])
		out_left_force_linear.append(snapshot.right_force_linear[index])
		out_right_force_linear.append(snapshot.left_force_linear[index])
	result.positions = out_positions
	result.left_control_points = out_left_controls
	result.right_control_points = out_right_controls
	result.locks = out_locks
	result.handle_modes = out_handle_modes
	result.left_force_linear = out_left_force_linear
	result.right_force_linear = out_right_force_linear
	return result


func _expected_invert(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	for property_name: StringName in [&"positions", &"left_control_points", &"right_control_points"]:
		var source: PackedVector2Array = snapshot[property_name]
		var output := PackedVector2Array()
		for value in source:
			var transformed := value
			transformed.y = 1.0 - transformed.y
			output.append(transformed)
		result[property_name] = output
	return result


func _test_bezier_reverse() -> void:
	var curve := _custom_curve()
	var original := curve.get_point_snapshot()
	var expected := _expected_reverse(original)
	curve.reverse = true
	_expect_geometry_snapshot(curve.get_point_snapshot(), expected, "Reverse did not mirror Custom Bézier geometry")
	_expect(curve.reverse, "Reverse flag was not stored")
	curve.reverse = false
	_expect_geometry_snapshot(curve.get_point_snapshot(), original, "Reverse twice did not restore the Custom snapshot")

	for configuration in [
		[EasingCurve.TRANS.SINE, EasingCurve.EASE.IN],
		[EasingCurve.TRANS.QUAD, EasingCurve.EASE.IN_OUT],
		[EasingCurve.TRANS.QUAD, EasingCurve.EASE.OUT_IN],
	]:
		var preset := EasingCurve.new()
		preset.trans_type = configuration[0]
		preset.ease_type = configuration[1]
		var preset_original := preset.get_point_snapshot()
		preset.reverse = true
		_expect_geometry_snapshot(
			preset.get_point_snapshot(),
			_expected_reverse(preset_original),
			"Reverse did not transform %s/%s" % [EasingCurve.TRANS.keys()[configuration[0]], EasingCurve.EASE.keys()[configuration[1]]],
		)
		preset.reverse = false
		_expect_geometry_snapshot(preset.get_point_snapshot(), preset_original, "Reverse did not round-trip a built-in preset")

	var modified := EasingCurve.new()
	modified.trans_type = EasingCurve.TRANS.SINE
	modified.points[0].right_control_point += Vector2(0.03, -0.02)
	var modified_original := modified.get_point_snapshot()
	modified.reverse = true
	_expect_geometry_snapshot(modified.get_point_snapshot(), _expected_reverse(modified_original), "Reverse did not preserve manually modified geometry")


func _test_bezier_invert() -> void:
	for curve in [_custom_curve(), EasingCurve.new()]:
		if curve.trans_type != EasingCurve.TRANS.CUSTOM:
			curve.trans_type = EasingCurve.TRANS.SINE
		var original: Dictionary = curve.get_point_snapshot()
		curve.invert = true
		_expect_geometry_snapshot(curve.get_point_snapshot(), _expected_invert(original), "Invert did not mirror Bézier Y geometry")
		_expect(curve.get_point_snapshot().locks == original.locks, "Invert changed Bézier lock states")
		curve.invert = false
		_expect_geometry_snapshot(curve.get_point_snapshot(), original, "Invert twice did not restore the Bézier snapshot")


func _test_transform_composition() -> void:
	var reverse_then_invert := _custom_curve()
	reverse_then_invert.reverse = true
	reverse_then_invert.invert = true
	var invert_then_reverse := _custom_curve()
	invert_then_reverse.invert = true
	invert_then_reverse.reverse = true
	_expect_geometry_snapshot(reverse_then_invert.get_point_snapshot(), invert_then_reverse.get_point_snapshot(), "Reverse and Invert did not commute")
	var transformed := reverse_then_invert.get_point_snapshot()
	reverse_then_invert.invert = false
	reverse_then_invert.reverse = false
	_expect_geometry_snapshot(reverse_then_invert.get_point_snapshot(), _custom_curve().get_point_snapshot(), "Combined transforms did not round-trip when disabled")
	_expect(transformed != reverse_then_invert.get_point_snapshot(), "Combined transforms did not change Custom geometry")


func _test_canonical_presets_and_switching() -> void:
	for flags in [[true, false], [false, true], [true, true]]:
		var curve := EasingCurve.new()
		curve.trans_type = EasingCurve.TRANS.QUAD
		curve.ease_type = EasingCurve.EASE.IN_OUT
		curve.reverse = flags[0]
		curve.invert = flags[1]
		_expect(not curve.is_selected_preset_modified(), "Transformed built-in preset was marked modified")
		curve.points[1].right_control_point += Vector2(0.01, 0.02)
		_expect(curve.is_selected_preset_modified(), "Manual edit of transformed preset was not detected")
		curve.reverse = not curve.reverse
		_expect(curve.is_selected_preset_modified(), "Reverse toggle cleared modified state")
		curve.reverse = not curve.reverse
		curve.invert = not curve.invert
		_expect(curve.is_selected_preset_modified(), "Invert toggle cleared modified state")
		curve.invert = not curve.invert
		_expect(curve.reset_selected_preset(), "Transformed modified preset could not reset")
		_expect_snapshot(curve.get_point_snapshot(), curve.get_canonical_preset_point_snapshot(), "Reset ignored active transforms")
		_expect(not curve.is_selected_preset_modified(), "Reset transformed preset stayed modified")

	for ease in EasingCurve.EASE.values():
		var back := EasingCurve.new()
		back.trans_type = EasingCurve.TRANS.BACK
		back.ease_type = ease
		back.overshoot = 3.25
		back.reverse = true
		back.invert = true
		_expect(not back.is_selected_preset_modified(), "Transformed Back/%s with non-default Overshoot was modified" % EasingCurve.EASE.keys()[ease])

	for switch_flags in [[true, false], [false, true], [true, true]]:
		var switched := EasingCurve.new()
		switched.reverse = switch_flags[0]
		switched.invert = switch_flags[1]
		for transition in [EasingCurve.TRANS.SINE, EasingCurve.TRANS.QUAD, EasingCurve.TRANS.BACK]:
			for ease in EasingCurve.EASE.values():
				switched.trans_type = transition
				switched.ease_type = ease
				_expect(
					switched.reverse == switch_flags[0] and switched.invert == switch_flags[1],
					"Preset switching changed transform flags",
				)
				_expect_snapshot(switched.get_point_snapshot(), switched.get_canonical_preset_point_snapshot(), "Preset switching did not regenerate transformed canonical geometry")


func _test_function_mode() -> void:
	var raw := EasingCurve.new()
	raw.trans_type = EasingCurve.TRANS.POWER
	raw.power = 3.0
	var curve := raw.duplicate() as EasingCurve
	var points_before := curve.get_point_snapshot()
	for x in [0.2, 0.63]:
		curve.reverse = false
		curve.invert = false
		curve.reverse = true
		_expect(is_equal_approx(curve.sample(x), raw.sample(1.0 - x)), "Function Reverse did not sample f(1 - x)")
		curve.reverse = false
		curve.invert = true
		_expect(is_equal_approx(curve.sample(x), 1.0 - raw.sample(x)), "Function Invert did not sample 1 - f(x)")
		curve.reverse = true
		_expect(is_equal_approx(curve.sample(x), 1.0 - raw.sample(1.0 - x)), "Function combined transforms sampled incorrectly")
	_expect_snapshot(curve.get_point_snapshot(), points_before, "Function transforms mutated Bézier point data")
	curve.trans_type = EasingCurve.TRANS.QUAD
	_expect(curve.curve_mode == EasingCurve.CurveMode.BEZIER and curve.reverse and curve.invert, "Function to Bézier switch lost transform flags")
	curve.trans_type = EasingCurve.TRANS.POWER
	_expect(curve.curve_mode == EasingCurve.CurveMode.FUNCTION and curve.reverse and curve.invert, "Bézier to Function switch lost transform flags")
	_expect(is_equal_approx(curve.sample(0.2), 1.0 - raw.sample(0.8)), "Function implementation was not restored after mode switch")


func _test_undo_redo() -> void:
	for property_name: StringName in [&"reverse", &"invert"]:
		var curve := _custom_curve()
		var history := UndoRedo.new()
		var before := EDITOR_UNDO.capture_state(curve)
		curve.set(property_name, true)
		var after := EDITOR_UNDO.capture_state(curve)
		_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Toggle %s" % property_name, EasingCurveEditorUndo.ActionContext.new(before, after)), "%s toggle did not create an Undo action" % property_name)
		_expect(history.has_undo(), "%s toggle did not create exactly one Undo action" % property_name)
		history.undo()
		_expect(curve.get_editor_state_snapshot() == before, "%s Undo did not restore flag and geometry atomically" % property_name)
		_expect(not history.has_undo() and history.has_redo(), "%s toggle created more than one Undo action" % property_name)
		history.redo()
		_expect(curve.get_editor_state_snapshot() == after, "%s Redo did not restore transformed state" % property_name)
		history.clear_history(false)
		history.free()


func _test_save_load() -> void:
	for flags in [[true, false], [false, true], [true, true]]:
		var custom := _custom_curve()
		custom.reverse = flags[0]
		custom.invert = flags[1]
		var custom_snapshot := custom.get_point_snapshot()
		_expect(ResourceSaver.save(custom, CUSTOM_SAVE_PATH) == OK, "Transformed Custom curve could not be saved")
		var loaded_custom := ResourceLoader.load(CUSTOM_SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EasingCurve
		_expect(loaded_custom != null, "Transformed Custom curve could not be loaded")
		if loaded_custom != null:
			_expect(loaded_custom.reverse == flags[0] and loaded_custom.invert == flags[1], "Custom save/load lost transform flags")
			_expect_snapshot(loaded_custom.get_point_snapshot(), custom_snapshot, "Custom save/load applied a destructive transform twice")

	var preset := EasingCurve.new()
	preset.trans_type = EasingCurve.TRANS.BACK
	preset.ease_type = EasingCurve.EASE.OUT_IN
	preset.overshoot = 3.25
	preset.reverse = true
	preset.invert = true
	var preset_snapshot := preset.get_point_snapshot()
	_expect(ResourceSaver.save(preset, PRESET_SAVE_PATH) == OK, "Transformed built-in preset could not be saved")
	var loaded_preset := ResourceLoader.load(PRESET_SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EasingCurve
	_expect(loaded_preset != null, "Transformed built-in preset could not be loaded")
	if loaded_preset != null:
		_expect(loaded_preset.reverse and loaded_preset.invert, "Built-in save/load lost transform flags")
		_expect_snapshot(loaded_preset.get_point_snapshot(), preset_snapshot, "Built-in save/load changed transformed geometry")
		_expect(not loaded_preset.is_selected_preset_modified(), "Saved transformed built-in preset was no longer canonical")


func _test_runtime_sampling() -> void:
	var offsets := [0.17, 0.4, 0.83]
	for flags in [[true, false], [false, true], [true, true]]:
		var bezier := _custom_curve()
		bezier.reverse = flags[0]
		bezier.invert = flags[1]
		var stored_geometry := _custom_curve()
		stored_geometry.set_point_snapshot(bezier.get_point_snapshot())
		for x in offsets:
			_expect(is_equal_approx(stored_geometry.sample(x), bezier.sample(x)), "Bézier runtime sampling did not use stored transformed geometry exactly once")

	var function := EasingCurve.new()
	function.trans_type = EasingCurve.TRANS.POWER
	function.power = 2.5
	function.reverse = true
	function.invert = true
	var raw := EasingCurve.new()
	raw.trans_type = EasingCurve.TRANS.POWER
	raw.power = 2.5
	for x in [0.17, 0.4, 0.83]:
		_expect(is_equal_approx(function.sample(x), 1.0 - raw.sample(1.0 - x)), "Function runtime sampling did not reflect global transforms")


func _cleanup_saved_files() -> void:
	for path in [CUSTOM_SAVE_PATH, PRESET_SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

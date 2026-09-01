extends "res://test/scripts/support/test_case.gd"

const EDITOR_UNDO = preload("res://addons/easing_curve/scripts/editor/easing_curve_editor_undo.gd")
const EDITOR_HOST = preload("res://test/scripts/support/editor_host_test_harness.gd")
const EDITOR_DRIVER = preload("res://test/scripts/support/easing_curve_editor_test_driver.gd")
const INSPECTOR_PLUGIN = preload("res://addons/easing_curve/scripts/editor/inspector/easing_curve_editor_inspector_plugin.gd")

func _init() -> void:
	if not EDITOR_HOST.require_editor_host("easing_curve_control_editability_test.gd"):
		quit(1)
		return
	_test_control_editability_constraints()
	_test_handle_mode_undo_redo_refreshes_inputs()
	_test_snapshot_refreshes_bindings_without_input_signals()
	_test_point_input_binding_lifecycle()

	_finish("EasingCurve control editability")


func _register_control_inputs(point: EasingCurvePoint, inspector: Object) -> Dictionary:
	var inputs := {}
	for property_name in ["left_control_point", "right_control_point"]:
		for axis in ["x", "y"]:
			var input := EditorSpinSlider.new()
			input.min_value = -1024.0
			input.max_value = 1024.0
			input.step = 0.001
			EDITOR_DRIVER.register_point_input_binding(
				inspector,
				point,
				StringName(property_name),
				axis,
				input,
			)
			inputs[property_name + axis] = input
	return inputs


func _control_inputs_are_read_only(inputs: Dictionary, property_name: String) -> bool:
	return inputs[property_name + "x"].read_only and inputs[property_name + "y"].read_only


func _control_inputs_match_point(inputs: Dictionary, point: EasingCurvePoint, property_name: String) -> bool:
	var value: Vector2 = point.get(property_name)
	return (
		is_equal_approx(inputs[property_name + "x"].value, value.x)
		and is_equal_approx(inputs[property_name + "y"].value, value.y)
	)


func _free_inputs(inputs: Dictionary) -> void:
	for input in inputs.values():
		if is_instance_valid(input):
			input.free()


func _test_control_editability_constraints() -> void:
	var point := EasingCurvePoint.new(Vector2(0.5, 0.5))
	var inspector := INSPECTOR_PLUGIN.new()
	var inputs := _register_control_inputs(point, inspector)
	_expect(
		not _control_inputs_are_read_only(inputs, "left_control_point")
		and not _control_inputs_are_read_only(inputs, "right_control_point"),
		"Free control positions started read-only",
	)
	point.left_control_point = Vector2(0.2, 0.3)
	point.handle_mode = EasingCurvePoint.HandleMode.BALANCED
	point.left_control_point = Vector2(0.1, 0.7)
	_expect(
		_control_inputs_match_point(inputs, point, "left_control_point")
		and _control_inputs_match_point(inputs, point, "right_control_point"),
		"Balanced control edit did not synchronously refresh both bound inputs",
	)
	point.handle_mode = EasingCurvePoint.HandleMode.MIRRORED
	point.right_control_point = Vector2(0.9, 0.6)
	_expect(
		_control_inputs_match_point(inputs, point, "left_control_point")
		and _control_inputs_match_point(inputs, point, "right_control_point"),
		"Mirrored control edit did not synchronously refresh both bound inputs",
	)
	point.handle_mode = EasingCurvePoint.HandleMode.LINKED
	point.left_control_point = Vector2(0.25, 0.75)
	_expect(
		_control_inputs_match_point(inputs, point, "left_control_point")
		and _control_inputs_match_point(inputs, point, "right_control_point"),
		"Linked control edit did not synchronously refresh both bound inputs",
	)
	point.handle_mode = EasingCurvePoint.HandleMode.FREE
	point.position = Vector2(0.6, 0.4)
	_expect(
		_control_inputs_match_point(inputs, point, "left_control_point")
		and _control_inputs_match_point(inputs, point, "right_control_point"),
		"Position change did not synchronously refresh moved control inputs",
	)

	point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	_expect(
		not _control_inputs_are_read_only(inputs, "left_control_point")
		and not _control_inputs_are_read_only(inputs, "right_control_point"),
		"Linear mode did not keep both control-position inputs editable",
	)
	point.set_locked("left_control_point", true)
	_expect(
		_control_inputs_are_read_only(inputs, "left_control_point")
		and not _control_inputs_are_read_only(inputs, "right_control_point"),
		"Linear mode bypassed the existing left-control lock",
	)
	point.set_locked("left_control_point", false)

	point.handle_mode = EasingCurvePoint.HandleMode.FREE
	_expect(
		not _control_inputs_are_read_only(inputs, "left_control_point")
		and not _control_inputs_are_read_only(inputs, "right_control_point"),
		"Linear-to-Free did not restore editable control-position inputs",
	)

	point.left_force_linear = true
	_expect(_control_inputs_are_read_only(inputs, "left_control_point"), "Left Force Linear did not disable its inputs")
	_expect(not _control_inputs_are_read_only(inputs, "right_control_point"), "Left Force Linear disabled the right inputs")

	point.left_force_linear = false
	point.right_force_linear = true
	_expect(not _control_inputs_are_read_only(inputs, "left_control_point"), "Clearing Left Force Linear did not restore its inputs")
	_expect(_control_inputs_are_read_only(inputs, "right_control_point"), "Right Force Linear did not disable its inputs")

	point.set_locked("left_control_point", true)
	point.right_force_linear = false
	_expect(_control_inputs_are_read_only(inputs, "left_control_point"), "Locked left control became editable")
	point.set_locked("left_control_point", false)
	_expect(not _control_inputs_are_read_only(inputs, "left_control_point"), "Unlocking editable left control did not restore inputs")

	point.handle_mode = EasingCurvePoint.HandleMode.LINKED
	point.left_force_linear = true
	_expect(
		_control_inputs_are_read_only(inputs, "left_control_point")
		and _control_inputs_are_read_only(inputs, "right_control_point"),
		"Linked Force Linear did not disable both shared controls",
	)
	_free_inputs(inputs)


func _test_handle_mode_undo_redo_refreshes_inputs() -> void:
	var point := EasingCurvePoint.new(Vector2(0.5, 0.5))
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [
		EasingCurvePoint.new(Vector2.ZERO),
		point,
		EasingCurvePoint.new(Vector2.ONE),
	]
	var inspector := INSPECTOR_PLUGIN.new()
	var inputs := _register_control_inputs(point, inspector)
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)

	point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	var after := EDITOR_UNDO.capture_state(curve)
	_expect(
		EDITOR_UNDO.commit_applied_action(history, curve, "Change Easing Curve Handle Mode", EasingCurveEditorUndo.ActionContext.new(before, after)),
		"Handle mode change did not create an Undo/Redo action",
	)
	_expect(not _control_inputs_are_read_only(inputs, "left_control_point"), "Linear mode did not keep inputs editable before Undo")
	history.undo()
	_expect(
		not _control_inputs_are_read_only(inputs, "left_control_point"),
		"Undo did not restore control-position editability",
	)
	history.redo()
	_expect(not _control_inputs_are_read_only(inputs, "left_control_point"), "Redo did not restore Linear control-position editability")
	history.clear_history(false)
	history.free()
	_free_inputs(inputs)


func _test_snapshot_refreshes_bindings_without_input_signals() -> void:
	var point := EasingCurvePoint.new(Vector2(0.5, 0.5))
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [
		EasingCurvePoint.new(Vector2.ZERO),
		point,
		EasingCurvePoint.new(Vector2.ONE),
	]
	var inspector := INSPECTOR_PLUGIN.new()
	var inputs := _register_control_inputs(point, inspector)
	var emitted := 0
	inputs["left_control_pointx"].value_changed.connect(
		func(_value: float): emitted += 1
	)
	inputs["right_control_pointx"].value_changed.connect(
		func(_value: float): emitted += 1
	)

	var snapshot := curve.get_point_snapshot()
	var left_controls: PackedVector2Array = snapshot["left_control_points"]
	var right_controls: PackedVector2Array = snapshot["right_control_points"]
	left_controls[1] = Vector2(0.2, 0.3)
	right_controls[1] = Vector2(0.8, 0.7)
	snapshot["left_control_points"] = left_controls
	snapshot["right_control_points"] = right_controls
	snapshot["changing"] = true
	curve.set_point_snapshot(snapshot)

	_expect(
		is_equal_approx(inputs["left_control_pointx"].value, 0.2)
		and is_equal_approx(inputs["right_control_pointx"].value, 0.8),
		"Changing snapshot did not synchronously refresh bound Inspector inputs",
	)
	_expect(emitted == 0, "Bound Inspector refresh emitted a recursive input signal")

	inputs["left_control_pointx"].free()
	point.left_control_point = Vector2(0.3, 0.4)
	_free_inputs(inputs)


func _test_point_input_binding_lifecycle() -> void:
	var point_a := EasingCurvePoint.new(Vector2(0.33, 0.4))
	var point_b := EasingCurvePoint.new(Vector2(0.66, 0.6))
	var inspector := INSPECTOR_PLUGIN.new()
	var inputs_a := _register_control_inputs(point_a, inspector)
	_expect(
		EDITOR_DRIVER.point_input_binding_count(inspector) == 1,
		"One point created more than one binding registry entry",
	)
	_expect(
		EDITOR_DRIVER.point_input_binding_input_count(inspector, point_a) == 4,
		"Point binding did not retain all registered property inputs",
	)
	_expect(
		EDITOR_DRIVER.point_input_binding_is_connected(inspector, point_a),
		"Point binding did not connect its shared changed callback",
	)

	inputs_a["left_control_pointx"].free()
	point_a.left_control_point = Vector2(0.2, 0.3)
	_expect(
		EDITOR_DRIVER.point_input_binding_input_count(inspector, point_a) == 3,
		"Point binding did not prune a freed input",
	)
	_expect(
		EDITOR_DRIVER.point_input_binding_is_connected(inspector, point_a),
		"Point binding disconnected while live inputs remained",
	)

	var point_a_callback := EDITOR_DRIVER.point_input_binding_callback(inspector, point_a)
	_free_inputs(inputs_a)
	point_a.right_control_point = Vector2(0.8, 0.7)
	_expect(
		EDITOR_DRIVER.point_input_binding_count(inspector) == 0
		and not point_a.changed.is_connected(point_a_callback),
		"Point binding remained registered after its final input was freed",
	)

	inputs_a = _register_control_inputs(point_a, inspector)
	var inputs_b := _register_control_inputs(point_b, inspector)
	_expect(
		EDITOR_DRIVER.point_input_binding_count(inspector) == 2,
		"Distinct points did not receive distinct binding registry entries",
	)
	point_a_callback = EDITOR_DRIVER.point_input_binding_callback(inspector, point_a)
	var point_b_callback := EDITOR_DRIVER.point_input_binding_callback(inspector, point_b)
	EDITOR_DRIVER.clear_point_input_bindings(inspector)
	_expect(
		EDITOR_DRIVER.point_input_binding_count(inspector) == 0
		and not point_a.changed.is_connected(point_a_callback)
		and not point_b.changed.is_connected(point_b_callback),
		"Clearing point bindings did not empty the registry and disconnect callbacks",
	)
	_free_inputs(inputs_a)
	_free_inputs(inputs_b)

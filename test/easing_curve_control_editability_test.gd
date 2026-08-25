extends SceneTree

const EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")
const EDITOR_HOST = preload("res://test/editor_host_test_harness.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	if not EDITOR_HOST.require_editor_host("easing_curve_control_editability_test.gd"):
		quit(1)
		return
	_test_control_editability_constraints()
	_test_handle_mode_undo_redo_refreshes_inputs()

	if _failures == 0:
		print("PASS: %d EasingCurve control editability checks" % _checks)
	else:
		push_error("FAIL: %d of %d EasingCurve control editability checks failed" % [_failures, _checks])
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _register_control_inputs(point: EasingCurvePoint) -> Dictionary:
	var inputs := {}
	for property_name in ["left_control_point", "right_control_point"]:
		for axis in ["x", "y"]:
			var input := EditorSpinSlider.new()
			point.set_input_control(property_name, axis, input)
			inputs[property_name + axis] = input
	return inputs


func _control_inputs_are_read_only(inputs: Dictionary, property_name: String) -> bool:
	return inputs[property_name + "x"].read_only and inputs[property_name + "y"].read_only


func _free_inputs(inputs: Dictionary) -> void:
	for input in inputs.values():
		input.free()


func _test_control_editability_constraints() -> void:
	var point := EasingCurvePoint.new(Vector2(0.5, 0.5))
	var inputs := _register_control_inputs(point)
	_expect(
		not _control_inputs_are_read_only(inputs, "left_control_point")
		and not _control_inputs_are_read_only(inputs, "right_control_point"),
		"Free control positions started read-only",
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
	var inputs := _register_control_inputs(point)
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)

	point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	var after := EDITOR_UNDO.capture_state(curve)
	_expect(
		EDITOR_UNDO.commit_applied_action(history, curve, "Change Easing Curve Handle Mode", before, after),
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

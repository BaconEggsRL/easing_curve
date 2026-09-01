extends "res://test/scripts/support/test_case.gd"

const EDITOR_HOST = preload("res://test/scripts/support/editor_host_test_harness.gd")
const EDITOR_DRIVER = preload("res://test/scripts/support/easing_curve_editor_test_driver.gd")
const DRAGGING_META := &"_easing_curve_dragging"

func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("easing_curve_linear_control_alias_test.gd"):
		quit(1)
		return
	_test_linear_control_x_uses_position_reorder()
	_test_linear_control_x_drag_crosses_multiple_points()
	_test_linear_control_y_and_locks()
	_test_linear_control_endpoint_takeover()
	_test_force_linear_control_is_not_aliased()

	_finish("EasingCurve Linear control alias")


func _make_fixture(right_x: float = 0.6) -> Dictionary:
	var a := EasingCurvePoint.new(Vector2(0.2, 0.2))
	var b := EasingCurvePoint.new(Vector2(0.4, 0.5))
	b.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	var c := EasingCurvePoint.new(Vector2(right_x, 0.8))
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [a, b, c]
	var editor_context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = editor_context.editor
	var inspector: EditorInspectorPlugin = editor_context.inspector
	return {
		"curve": curve,
		"editor": editor,
		"inspector": inspector,
		"a": a,
		"b": b,
		"c": c,
	}


func _send_x_edit(
	inspector: Object,
	point: EasingCurvePoint,
	input: EditorSpinSlider,
	reset_btn: Button,
	value: float,
	property_name: String,
) -> void:
	inspector.call(
		"_on_x_input_value_changed",
		value,
		point,
		input,
		reset_btn,
		property_name,
	)


func _send_y_edit(
	inspector: Object,
	point: EasingCurvePoint,
	input: EditorSpinSlider,
	reset_btn: Button,
	value: float,
	property_name: String,
) -> void:
	inspector.call(
		"_on_y_input_value_changed",
		value,
		point,
		input,
		reset_btn,
		property_name,
	)


func _expect_linear_point(point: EasingCurvePoint, expected: Vector2, message: String) -> void:
	_expect(point.position.is_equal_approx(expected), "%s: position did not move" % message)
	_expect(point.left_control_point.is_equal_approx(expected), "%s: left control diverged" % message)
	_expect(point.right_control_point.is_equal_approx(expected), "%s: right control diverged" % message)


func _test_linear_control_x_uses_position_reorder() -> void:
	var fixture := _make_fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var a: EasingCurvePoint = fixture.a
	var b: EasingCurvePoint = fixture.b
	var c: EasingCurvePoint = fixture.c
	var input := EditorSpinSlider.new()
	var reset_btn := Button.new()
	input.set_meta(DRAGGING_META, true)
	editor.selected_index = 1

	_send_x_edit(inspector, b, input, reset_btn, 0.7, "left_control_point")
	var transaction := EDITOR_DRIVER.point_edit_transaction_state(inspector)
	_expect(bool(transaction["active"]), "Linear control drag did not begin an edit transaction")
	_expect(
		transaction["action_name"] == "Move Easing Curve Point",
		"Linear control X alias changed its position Undo action name",
	)
	_expect_linear_point(b, Vector2(0.7, 0.5), "Linear left X edit")
	_expect(curve.points == [a, b, c], "Linear control X edit reordered the list during drag")
	_expect(editor._get_display_points() == [a, c, b], "Linear control X edit did not update live graph order")
	_expect(editor.selected_index == 1, "Linear control X edit changed logical selection during drag")

	_send_x_edit(inspector, b, input, reset_btn, 0.3, "right_control_point")
	_expect_linear_point(b, Vector2(0.3, 0.5), "Linear right X edit")
	_expect(editor._get_display_points() == [a, b, c], "Linear control X edit did not restore graph order")
	_expect(
		EDITOR_DRIVER.point_edit_transaction_state(inspector)["before"] == transaction["before"],
		"Linear control drag opened more than one edit transaction",
	)

	input.remove_meta(DRAGGING_META)
	EDITOR_DRIVER.commit_point_edit(inspector)
	_expect(curve.points == [a, b, c], "Linear control drag commit changed the final sorted order")
	_expect(
		not bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Linear control drag did not close its edit transaction",
	)
	input.free()
	reset_btn.free()
	editor.free()


func _test_linear_control_x_drag_crosses_multiple_points() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var points: Array[EasingCurvePoint] = []
	for x in [0.1, 0.3, 0.5, 0.7, 0.9]:
		points.append(EasingCurvePoint.new(Vector2(x, 0.5)))
	curve.set_point_snapshot(curve.make_point_snapshot(points))
	points = curve.points.duplicate()
	var moved := points[1]
	moved.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	var editor_context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = editor_context.editor
	editor.selected_index = 1
	var inspector: EditorInspectorPlugin = editor_context.inspector
	var input := EditorSpinSlider.new()
	var reset_btn := Button.new()
	input.set_meta(DRAGGING_META, true)
	var values := [0.3, 0.45, 0.6, 0.8, 0.4, 0.2]
	var expected_orders := [
		[points[0], moved, points[2], points[3], points[4]],
		[points[0], moved, points[2], points[3], points[4]],
		[points[0], points[2], moved, points[3], points[4]],
		[points[0], points[2], points[3], moved, points[4]],
		[points[0], moved, points[2], points[3], points[4]],
		[points[0], moved, points[2], points[3], points[4]],
	]
	var transaction_before: Dictionary
	for step in range(values.size()):
		_send_x_edit(
			inspector,
			moved,
			input,
			reset_btn,
			values[step],
			"left_control_point" if step % 2 == 0 else "right_control_point",
		)
		var transaction_state := EDITOR_DRIVER.point_edit_transaction_state(inspector)
		if step == 0:
			transaction_before = transaction_state["before"]
			_expect(bool(transaction_state["active"]), "Linear control X backtracking did not begin an edit transaction")
		else:
			_expect(transaction_state["before"] == transaction_before, "Linear control X backtracking started a second edit transaction")
		_expect_linear_point(moved, Vector2(values[step], 0.5), "Linear control X drag step %d" % step)
		_expect(curve.points == points, "Linear control X drag rebuilt the Points list before commit")
		_expect(editor._get_display_points() == expected_orders[step], "Linear control X drag did not preserve the live graph preview at step %d" % step)
		_expect(editor.selected_index == 1, "Linear control X drag changed selection before commit")
	input.remove_meta(DRAGGING_META)
	EDITOR_DRIVER.commit_point_edit(inspector)
	_expect(curve.points == expected_orders.back(), "Linear control X drag did not commit the final order")
	_expect(curve.points[1] == moved and editor.selected_index == 1, "Linear control X drag lost the logical selected point after commit")
	input.free()
	reset_btn.free()
	editor.free()


func _test_linear_control_y_and_locks() -> void:
	var fixture := _make_fixture()
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var b: EasingCurvePoint = fixture.b
	var input := EditorSpinSlider.new()
	var reset_btn := Button.new()

	_send_y_edit(inspector, b, input, reset_btn, 0.25, "right_control_point")
	_expect_linear_point(b, Vector2(0.4, 0.25), "Linear right Y edit")
	_send_y_edit(inspector, b, input, reset_btn, 0.75, "left_control_point")
	_expect_linear_point(b, Vector2(0.4, 0.75), "Linear left Y edit")

	b.set_locked("left_control_point", true)
	_send_x_edit(inspector, b, input, reset_btn, 0.9, "left_control_point")
	_expect_linear_point(b, Vector2(0.4, 0.75), "Locked Linear control edit")
	input.free()
	reset_btn.free()
	editor.free()


func _test_linear_control_endpoint_takeover() -> void:
	var fixture := _make_fixture(1.0)
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var a: EasingCurvePoint = fixture.a
	var b: EasingCurvePoint = fixture.b
	var input := EditorSpinSlider.new()
	var reset_btn := Button.new()
	input.set_meta(DRAGGING_META, true)

	_send_x_edit(inspector, b, input, reset_btn, 1.0, "left_control_point")
	_expect(editor._get_display_points() == [a, b], "Linear control endpoint edit did not preview takeover")
	input.remove_meta(DRAGGING_META)
	EDITOR_DRIVER.commit_point_edit(inspector)
	_expect(curve.points == [a, b], "Linear control endpoint edit did not commit takeover")
	_expect_linear_point(b, Vector2(1.0, 0.5), "Linear control endpoint edit")
	input.free()
	reset_btn.free()
	editor.free()


func _test_force_linear_control_is_not_aliased() -> void:
	var fixture := _make_fixture()
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var b: EasingCurvePoint = fixture.b
	b.handle_mode = EasingCurvePoint.HandleMode.FREE
	b.left_force_linear = true
	var input := EditorSpinSlider.new()
	var reset_btn := Button.new()

	_send_x_edit(inspector, b, input, reset_btn, 0.9, "left_control_point")
	_expect(b.position.is_equal_approx(Vector2(0.4, 0.5)), "Force Linear control edit moved the point")
	_expect(b.left_control_point.is_equal_approx(b.position), "Force Linear control no longer remained at the point")
	input.free()
	reset_btn.free()
	editor.free()

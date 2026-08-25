extends SceneTree

const INSPECTOR_PLUGIN = preload("res://addons/easing_curve/easing_curve_editor_inspector_plugin.gd")
const DRAGGING_META := &"_easing_curve_dragging"

var _failures := 0
var _checks := 0


func _init() -> void:
	_test_linear_control_x_uses_position_reorder()
	_test_linear_control_x_drag_crosses_multiple_points()
	_test_linear_control_y_and_locks()
	_test_linear_control_endpoint_takeover()
	_test_force_linear_control_is_not_aliased()

	if _failures == 0:
		print("PASS: %d EasingCurve Linear control alias checks" % _checks)
	else:
		push_error("FAIL: %d of %d EasingCurve Linear control alias checks failed" % [_failures, _checks])
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _make_fixture(right_x: float = 0.6) -> Dictionary:
	var a := EasingCurvePoint.new(Vector2(0.2, 0.2))
	var b := EasingCurvePoint.new(Vector2(0.4, 0.5))
	b.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	var c := EasingCurvePoint.new(Vector2(right_x, 0.8))
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [a, b, c]
	var editor := EasingCurveEditor.new()
	editor.size = Vector2(600.0, 300.0)
	editor.set_curve(curve)
	var inspector: EditorInspectorPlugin = INSPECTOR_PLUGIN.new()
	inspector.set("curve", curve)
	inspector.set("easing_curve_editor", editor)
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
		0,
		point,
		input,
		reset_btn,
		0.0,
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
		0,
		point,
		input,
		reset_btn,
		0.0,
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
	var before_state: Dictionary = inspector.get("_point_edit_before_state").duplicate(true)
	_expect_linear_point(b, Vector2(0.7, 0.5), "Linear left X edit")
	_expect(curve.points == [a, b, c], "Linear control X edit reordered the list during drag")
	_expect(editor._get_display_points() == [a, c, b], "Linear control X edit did not update live graph order")
	_expect(editor.selected_index == 1, "Linear control X edit changed logical selection during drag")

	_send_x_edit(inspector, b, input, reset_btn, 0.3, "right_control_point")
	_expect_linear_point(b, Vector2(0.3, 0.5), "Linear right X edit")
	_expect(editor._get_display_points() == [a, b, c], "Linear control X edit did not restore graph order")
	_expect(inspector.get("_point_edit_before_state") == before_state, "Linear control drag opened more than one edit transaction")

	input.remove_meta(DRAGGING_META)
	inspector.call("_commit_point_edit")
	_expect(curve.points == [a, b, c], "Linear control drag commit changed the final sorted order")
	_expect(inspector.get("_point_edit_before_state").is_empty(), "Linear control drag did not close its edit transaction")
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
	var editor := EasingCurveEditor.new()
	editor.size = Vector2(600.0, 300.0)
	editor.set_curve(curve)
	editor.selected_index = 1
	var inspector: EditorInspectorPlugin = INSPECTOR_PLUGIN.new()
	inspector.set("curve", curve)
	inspector.set("easing_curve_editor", editor)
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
	var before_state: Dictionary
	for step in range(values.size()):
		_send_x_edit(
			inspector,
			moved,
			input,
			reset_btn,
			values[step],
			"left_control_point" if step % 2 == 0 else "right_control_point",
		)
		if step == 0:
			before_state = inspector.get("_point_edit_before_state").duplicate(true)
		else:
			_expect(inspector.get("_point_edit_before_state") == before_state, "Linear control X backtracking started a second edit transaction")
		_expect_linear_point(moved, Vector2(values[step], 0.5), "Linear control X drag step %d" % step)
		_expect(curve.points == points, "Linear control X drag rebuilt the Points list before commit")
		_expect(editor._get_display_points() == expected_orders[step], "Linear control X drag did not preserve the live graph preview at step %d" % step)
		_expect(editor.selected_index == 1, "Linear control X drag changed selection before commit")
	input.remove_meta(DRAGGING_META)
	inspector.call("_commit_point_edit")
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
	inspector.call("_commit_point_edit")
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

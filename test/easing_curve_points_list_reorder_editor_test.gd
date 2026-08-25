extends SceneTree

const INSPECTOR_PLUGIN = preload("res://addons/easing_curve/easing_curve_editor_inspector_plugin.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_test_repeated_arrow_moves_keep_the_logical_point_selected()
	_test_committed_drag_reorder_selects_the_dragged_point()

	if _failures == 0:
		print("PASS: %d Points-list submitted reorder checks" % _checks)
	else:
		push_error("FAIL: %d of %d Points-list submitted reorder checks failed" % [_failures, _checks])
		quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _make_fixture() -> Dictionary:
	var points: Array[EasingCurvePoint] = []
	for position in [Vector2(0.1, 0.1), Vector2(0.3, 0.7), Vector2(0.5, 0.4), Vector2(0.7, 0.9)]:
		points.append(EasingCurvePoint.new(position))
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = points
	var editor := EasingCurveEditor.new()
	editor.size = Vector2(600.0, 300.0)
	editor.set_curve(curve)
	var inspector: EditorInspectorPlugin = INSPECTOR_PLUGIN.new()
	inspector.set("curve", curve)
	inspector.set("easing_curve_editor", editor)
	return {"curve": curve, "editor": editor, "inspector": inspector, "points": curve.points.duplicate()}


func _test_repeated_arrow_moves_keep_the_logical_point_selected() -> void:
	var fixture := _make_fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var points: Array[EasingCurvePoint] = fixture.points
	var moved := points[1]
	moved.handle_mode = EasingCurvePoint.HandleMode.FREE
	moved.right_control_point = Vector2(0.4, 0.85)
	moved.right_force_linear = true
	moved.set_locked("position", true)
	editor.selected_index = 1

	inspector.call("_move_point_down", editor.selected_index)
	_expect(curve.points == [points[0], points[2], moved, points[3]], "Move Down did not use X-slot swap order")
	_expect(editor.selected_index == 2 and curve.points[editor.selected_index] == moved, "Move Down did not select the moved logical point")
	_expect(moved.position.is_equal_approx(Vector2(0.5, 0.7)), "Move Down did not preserve the moved point Y")
	_expect(moved.handle_mode == EasingCurvePoint.HandleMode.FREE and moved.right_force_linear, "Move Down lost moved point handle state")

	inspector.call("_move_point_down", editor.selected_index)
	_expect(curve.points == [points[0], points[2], points[3], moved], "Repeated Move Down did not continue moving the selected logical point")
	_expect(editor.selected_index == 3 and curve.points[editor.selected_index] == moved, "Repeated Move Down selected the X-slot inheritor")

	inspector.call("_move_point_up", editor.selected_index)
	_expect(curve.points == [points[0], points[2], moved, points[3]], "Move Up did not reverse the X-slot swap")
	_expect(editor.selected_index == 2 and curve.points[editor.selected_index] == moved, "Move Up did not keep the moved logical point selected")
	editor.free()


func _test_committed_drag_reorder_selects_the_dragged_point() -> void:
	var fixture := _make_fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var points: Array[EasingCurvePoint] = fixture.points
	var moved := points[0]
	moved.handle_mode = EasingCurvePoint.HandleMode.MIRRORED
	moved.left_control_point = Vector2(0.0, 0.2)
	moved.right_control_point = Vector2(0.2, 0.0)
	editor.selected_index = 0

	# PointsListContainer emits this handler only on drop submission, never while hovering.
	inspector.call("_move_point", 0, 2)
	_expect(curve.points == [points[2], points[1], moved, points[3]], "Committed drag reorder did not use X-slot swap order")
	_expect(editor.selected_index == 2 and curve.points[editor.selected_index] == moved, "Committed drag reorder did not select the dragged logical point")
	_expect(moved.handle_mode == EasingCurvePoint.HandleMode.MIRRORED, "Committed drag reorder lost the dragged point mode")
	_expect(moved.position.is_equal_approx(Vector2(0.5, 0.1)), "Committed drag reorder did not translate the dragged point to the destination X slot")

	inspector.call("_move_point", 2, 2)
	_expect(editor.selected_index == 2 and curve.points[2] == moved, "No-op drag reorder changed normal selection")
	editor.free()

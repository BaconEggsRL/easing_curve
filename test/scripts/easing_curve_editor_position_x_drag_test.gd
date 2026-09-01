extends "res://test/scripts/test_case.gd"

const EDITOR_HOST = preload("res://test/scripts/editor_host_test_harness.gd")
const EDITOR_DRIVER = preload("res://test/scripts/easing_curve_editor_test_driver.gd")
const EDITOR_UNDO = preload("res://addons/easing_curve/scripts/editor/easing_curve_editor_undo.gd")

func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("easing_curve_editor_position_x_drag_test.gd"):
		quit(1)
		return
	_test_position_x_drag_defers_list_reorder()
	_test_position_x_reorder_undo_redo_follows_the_selected_resource()
	_test_position_x_drag_crosses_multiple_points()
	_test_position_x_drag_continues_through_backtracking()
	_test_position_x_endpoint_takeover_is_previewed_until_commit()
	_test_position_x_endpoint_takeover_commits_at_both_endpoints()

	_finish("EasingCurveEditor Position X drag")


func _make_fixture(left_x: float = 0.2, right_x: float = 0.6) -> Dictionary:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var points: Array[EasingCurvePoint] = [
		EasingCurvePoint.new(Vector2(left_x, 0.2)),
		EasingCurvePoint.new(Vector2(0.4, 0.5)),
		EasingCurvePoint.new(Vector2(right_x, 0.8)),
	]
	curve.set_point_snapshot(curve.make_point_snapshot(points))

	var editor_context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = editor_context.editor
	var inspector: EditorInspectorPlugin = editor_context.inspector
	return {
		"curve": curve,
		"editor": editor,
		"inspector": inspector,
		"points": curve.points.duplicate(),
	}


func _drag_position_x(
	inspector: Object,
	curve: EasingCurve,
	point: EasingCurvePoint,
	x: float,
) -> void:
	inspector.call(
		"_apply_point_property_change",
		curve.points.find(point),
		&"position",
		Vector2(x, point.position.y),
		true,
		point,
	)


func _finish_position_x(
	inspector: Object,
	curve: EasingCurve,
	point: EasingCurvePoint,
	x: float,
) -> void:
	inspector.call(
		"_apply_point_property_change",
		curve.points.find(point),
		&"position",
		Vector2(x, point.position.y),
		false,
		point,
	)


func _test_position_x_drag_defers_list_reorder() -> void:
	var fixture := _make_fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var points: Array = fixture.points
	var left: EasingCurvePoint = points[0]
	var moved: EasingCurvePoint = points[1]
	var right: EasingCurvePoint = points[2]
	editor.selected_index = 1

	_drag_position_x(inspector, curve, moved, 0.7)
	var before_state: Dictionary = inspector.get("_point_edit_before_state").duplicate(true)
	_expect(
		curve.points == [left, moved, right],
		"Position X drag reordered the Inspector list before the edit finished",
	)
	_expect(
		editor._get_display_points() == [left, right, moved],
		"Graph preview did not reorder the moved point after crossing right",
	)
	_expect(curve.points[1] == moved, "Position X drag lost the active point resource")
	_expect(editor.selected_index == 1, "Position X drag changed selection before list reorder commit")

	_drag_position_x(inspector, curve, moved, 0.6)
	_expect(
		editor._get_display_points() == [left, moved, right],
		"Equal-X Position X preview did not preserve both points in stable order",
	)
	_expect(
		inspector.get("_point_edit_before_state") == before_state,
		"Repeated Position X drag updates started more than one edit transaction",
	)

	_drag_position_x(inspector, curve, moved, 0.8)
	_expect(
		curve.points == [left, moved, right],
		"Multiple Position X crossings rebuilt the Inspector list before commit",
	)
	_expect(
		editor._get_display_points() == [left, right, moved],
		"Graph preview did not track the final Position X crossing",
	)
	_finish_position_x(inspector, curve, moved, 0.8)
	_expect(curve.points == [left, right, moved], "Position X commit did not apply the final point order")
	_expect(editor.selected_index == 2, "Position X commit did not select the moved point at its final index")
	_expect(editor.position_x_order_preview_point == null, "Position X commit left a stale graph-order preview")
	_expect(
		inspector.get("_point_edit_before_state").is_empty(),
		"Final Position X update did not close the drag edit transaction",
	)
	editor.free()


func _test_position_x_reorder_undo_redo_follows_the_selected_resource() -> void:
	var fixture := _make_fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var points: Array[EasingCurvePoint] = fixture.points
	var selected := points[1]
	var property_header := PanelContainer.new()
	var history := UndoRedo.new()
	EDITOR_DRIVER.select_point_property(inspector, property_header, 1, &"position")

	var before := EDITOR_UNDO.capture_state(curve)
	var selection_before := EDITOR_DRIVER.capture_point_selection(inspector)
	var point_resource_ids_before := curve._get_editor_point_resource_ids()
	_drag_position_x(inspector, curve, selected, 0.8)
	_finish_position_x(inspector, curve, selected, 0.8)
	var after := EDITOR_UNDO.capture_state(curve)
	var selection_after := EDITOR_DRIVER.capture_point_selection(inspector)
	var point_resource_ids_after := curve._get_editor_point_resource_ids()
	_expect(
		EDITOR_UNDO.commit_applied_action(
			history,
			curve,
			"Move Easing Curve Point",
			EasingCurveEditorUndo.ActionContext.new(before, after)
				.with_selection(Callable(inspector, "_restore_point_selection_state"), selection_before, selection_after)
				.with_point_resource_ids(point_resource_ids_before, point_resource_ids_after),
		),
		"Position-X reorder did not create an Undo action",
	)
	_expect(curve.points[2] == selected, "Position-X reorder did not move the selected Resource")
	_expect(editor.selected_index == 2, "Position-X reorder did not update the graph selection index")
	history.undo()
	_expect(curve.points[1] == selected, "Position-X Undo did not return the selected Resource to P2")
	_expect(editor.selected_index == 1 and EDITOR_DRIVER.selected_point_index(inspector) == 1, "Position-X Undo did not synchronize graph and Inspector selection")
	_expect(EDITOR_DRIVER.selected_point_resource_id(inspector) == selected.get_instance_id(), "Position-X Undo changed the selected Resource")
	_expect(EDITOR_DRIVER.selected_point_property_name(inspector) == &"position", "Position-X Undo lost the selected property")
	history.redo()
	_expect(curve.points[2] == selected, "Position-X Redo did not return the selected Resource to P3")
	_expect(editor.selected_index == 2 and EDITOR_DRIVER.selected_point_index(inspector) == 2, "Position-X Redo did not synchronize graph and Inspector selection")

	history.clear_history(false)
	history.free()
	property_header.free()
	editor.free()


func _test_position_x_drag_crosses_multiple_points() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var points: Array[EasingCurvePoint] = []
	for x in [0.1, 0.3, 0.5, 0.7, 0.9]:
		points.append(EasingCurvePoint.new(Vector2(x, 0.5)))
	curve.set_point_snapshot(curve.make_point_snapshot(points))
	points = curve.points.duplicate()

	var editor_context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = editor_context.editor
	var inspector: EditorInspectorPlugin = editor_context.inspector
	var moved: EasingCurvePoint = points[1]
	editor.selected_index = 1

	_drag_position_x(inspector, curve, moved, 0.95)
	_expect(
		editor._get_display_points() == [points[0], points[2], points[3], points[4], moved],
		"Position X drag did not preview crossing multiple points to the right",
	)
	_expect(curve.points[1] == moved, "Multi-cross Position X drag changed the active row identity")
	_expect(editor.selected_index == 1, "Multi-cross Position X drag changed selection before commit")

	_drag_position_x(inspector, curve, moved, 0.2)
	_expect(
		editor._get_display_points() == [points[0], moved, points[2], points[3], points[4]],
		"Position X drag did not preview crossing multiple points back to the left",
	)
	_expect(curve.points[1] == moved, "Multi-cross Position X drag stopped editing the original point")

	_drag_position_x(inspector, curve, moved, 0.8)
	_expect(
		editor._get_display_points() == [points[0], points[2], points[3], moved, points[4]],
		"Position X drag did not preview the final multi-cross ordering",
	)
	_expect(curve.points == points, "Multi-cross Position X drag reordered the Points list before commit")
	EDITOR_DRIVER.commit_point_edit(inspector)
	_expect(
		curve.points == [points[0], points[2], points[3], moved, points[4]],
		"Position X commit did not settle the final multi-cross order",
	)
	_expect(editor.selected_index == 3, "Multi-cross Position X commit lost the moved point selection")
	editor.free()


func _test_position_x_drag_continues_through_backtracking() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var points: Array[EasingCurvePoint] = []
	for x in [0.1, 0.3, 0.5, 0.7, 0.9]:
		points.append(EasingCurvePoint.new(Vector2(x, 0.5)))
	curve.set_point_snapshot(curve.make_point_snapshot(points))
	points = curve.points.duplicate()
	var moved := points[1]
	var editor_context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = editor_context.editor
	editor.selected_index = 1
	var inspector: EditorInspectorPlugin = editor_context.inspector
	var expected_orders := [
		[points[0], moved, points[2], points[3], points[4]],
		[points[0], moved, points[2], points[3], points[4]],
		[points[0], points[2], moved, points[3], points[4]],
		[points[0], points[2], points[3], moved, points[4]],
		[points[0], moved, points[2], points[3], points[4]],
		[points[0], moved, points[2], points[3], points[4]],
	]
	var before_state: Dictionary
	for step in range([0.3, 0.45, 0.6, 0.8, 0.4, 0.2].size()):
		_drag_position_x(inspector, curve, moved, [0.3, 0.45, 0.6, 0.8, 0.4, 0.2][step])
		if step == 0:
			before_state = inspector.get("_point_edit_before_state").duplicate(true)
		else:
			_expect(inspector.get("_point_edit_before_state") == before_state, "Position X backtracking started a second edit transaction")
		_expect(curve.points == points, "Position X backtracking rebuilt the Points list before commit")
		_expect(editor._get_display_points() == expected_orders[step], "Position X backtracking did not preserve the live graph preview at step %d" % step)
		_expect(editor.selected_index == 1, "Position X backtracking changed selection before commit")
	_finish_position_x(inspector, curve, moved, 0.2)
	_expect(curve.points == expected_orders.back(), "Position X backtracking did not commit the final order")
	_expect(editor.selected_index == 1 and curve.points[1] == moved, "Position X backtracking did not retain the logical selected point")
	editor.free()


func _test_position_x_endpoint_takeover_is_previewed_until_commit() -> void:
	var fixture := _make_fixture(0.2, 1.0)
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var points: Array = fixture.points
	var left: EasingCurvePoint = points[0]
	var moved: EasingCurvePoint = points[1]
	var old_right_endpoint: EasingCurvePoint = points[2]

	_drag_position_x(inspector, curve, moved, 1.0)
	_expect(curve.points.size() == 3, "Endpoint takeover removed a point before Position X commit")
	_expect(
		editor._get_display_points() == [left, moved],
		"Endpoint takeover was not reflected in the live graph preview",
	)

	_drag_position_x(inspector, curve, moved, 0.8)
	_expect(curve.points.size() == 3 and curve.points.has(old_right_endpoint), "Moving back from endpoint changed source ordering during drag")
	_expect(
		editor._get_display_points() == [left, moved, old_right_endpoint],
		"Moving back from endpoint did not restore the graph preview",
	)
	EDITOR_DRIVER.commit_point_edit(inspector)
	_expect(curve.points == [left, moved, old_right_endpoint], "Position X commit changed endpoint takeover after moving back inward")
	editor.free()

	var left_fixture := _make_fixture(0.0, 0.8)
	var left_curve: EasingCurve = left_fixture.curve
	var left_editor: EasingCurveEditor = left_fixture.editor
	var left_inspector: Object = left_fixture.inspector
	var left_points: Array = left_fixture.points
	var left_moved: EasingCurvePoint = left_points[1]
	var old_left_endpoint: EasingCurvePoint = left_points[0]
	_drag_position_x(left_inspector, left_curve, left_moved, 0.0)
	_expect(left_curve.points.size() == 3, "Left endpoint takeover removed a point before Position X commit")
	_expect(left_editor._get_display_points() == [left_moved, left_points[2]], "Left endpoint takeover was not reflected in the live graph preview")
	_drag_position_x(left_inspector, left_curve, left_moved, 0.2)
	_expect(left_curve.points.size() == 3 and left_curve.points.has(old_left_endpoint), "Moving back from the left endpoint changed source ordering during drag")
	_expect(left_editor._get_display_points() == [old_left_endpoint, left_moved, left_points[2]], "Moving back from the left endpoint did not restore the graph preview")
	EDITOR_DRIVER.commit_point_edit(left_inspector)
	_expect(left_curve.points == [old_left_endpoint, left_moved, left_points[2]], "Left endpoint commit changed takeover after moving back inward")
	left_editor.free()


func _test_position_x_endpoint_takeover_commits_at_both_endpoints() -> void:
	var right_fixture := _make_fixture(0.0, 1.0)
	var right_curve: EasingCurve = right_fixture.curve
	var right_editor: EasingCurveEditor = right_fixture.editor
	var right_inspector: Object = right_fixture.inspector
	var right_points: Array = right_fixture.points
	var right_moved: EasingCurvePoint = right_points[1]
	_drag_position_x(right_inspector, right_curve, right_moved, 1.0)
	EDITOR_DRIVER.commit_point_edit(right_inspector)
	_expect(
		right_curve.points == [right_points[0], right_moved],
		"Position X commit did not replace the occupied right endpoint",
	)
	_expect(right_editor.selected_index == 1, "Right endpoint takeover did not retain selection")
	right_editor.free()

	var left_fixture := _make_fixture(0.0, 1.0)
	var left_curve: EasingCurve = left_fixture.curve
	var left_editor: EasingCurveEditor = left_fixture.editor
	var left_inspector: Object = left_fixture.inspector
	var left_points: Array = left_fixture.points
	var left_moved: EasingCurvePoint = left_points[1]
	_drag_position_x(left_inspector, left_curve, left_moved, 0.0)
	EDITOR_DRIVER.commit_point_edit(left_inspector)
	_expect(
		left_curve.points == [left_moved, left_points[2]],
		"Position X commit did not replace the occupied left endpoint",
	)
	_expect(left_editor.selected_index == 0, "Left endpoint takeover did not retain selection")
	left_editor.free()

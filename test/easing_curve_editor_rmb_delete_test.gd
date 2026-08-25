extends SceneTree

var _failures := 0
var _checks := 0


func _init() -> void:
	_test_click_release_does_not_delete_next_point()
	_test_rmb_cancels_pending_add_without_deleting()
	_test_drag_delete_stops_on_release()
	_test_empty_space_release_does_not_enable_delete()
	_test_press_move_release_does_not_delete_next_point()
	_test_motion_without_rmb_mask_clears_stale_delete_state()

	if _failures == 0:
		print("PASS: %d EasingCurveEditor RMB delete checks" % _checks)
	else:
		push_error("FAIL: %d of %d EasingCurveEditor RMB delete checks failed" % [_failures, _checks])
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _make_editor() -> Dictionary:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var points: Array[EasingCurvePoint] = []
	for x in [0.1, 0.35, 0.6, 0.85]:
		points.append(EasingCurvePoint.new(Vector2(x, 0.5)))
	curve.set_point_snapshot(curve.make_point_snapshot(points))

	var editor := EasingCurveEditor.new()
	editor.size = Vector2(600.0, 300.0)
	editor.set_curve(curve)
	editor.update_view_transform()
	return {"editor": editor, "curve": curve, "points": curve.points.duplicate()}


func _right_button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = position
	return event


func _left_button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event


func _motion(position: Vector2, rmb_held: bool) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	if rmb_held:
		event.button_mask = MOUSE_BUTTON_MASK_RIGHT
	return event


func _point_position(editor: EasingCurveEditor, point: EasingCurvePoint) -> Vector2:
	return editor.get_view_pos(point.position)


func _test_click_release_does_not_delete_next_point() -> void:
	var fixture := _make_editor()
	var editor: EasingCurveEditor = fixture.editor
	var curve: EasingCurve = fixture.curve
	var points: Array = fixture.points
	editor._gui_input(_right_button(_point_position(editor, points[0]), true))
	editor._gui_input(_right_button(_point_position(editor, points[0]), false))
	editor._gui_input(_motion(_point_position(editor, points[1]), false))
	_expect(not curve.points.has(points[0]), "RMB click did not delete the initial point")
	_expect(curve.points.has(points[1]), "Hover after RMB release deleted another point")
	_expect(not editor.is_right_delete_dragging, "RMB release left delete-drag enabled")
	editor.free()


func _test_rmb_cancels_pending_add_without_deleting() -> void:
	var fixture := _make_editor()
	var editor: EasingCurveEditor = fixture.editor
	var curve: EasingCurve = fixture.curve
	var points: Array = fixture.points
	var empty_pos := Vector2(580.0, 280.0)
	editor._gui_input(_left_button(empty_pos, true))
	_expect(editor.pending_add_point != null, "LMB press did not start pending add")
	editor._gui_input(_motion(_point_position(editor, points[1]), false))
	editor._gui_input(_right_button(_point_position(editor, points[1]), true))
	_expect(editor.pending_add_point == null, "RMB did not cancel pending add")
	_expect(curve.points.size() == 4 and curve.points.has(points[1]), "RMB pending-add cancel deleted an existing point")
	_expect(not editor.is_right_delete_dragging, "RMB pending-add cancel started delete-drag")
	editor._gui_input(_motion(_point_position(editor, points[2]), true))
	_expect(curve.points.has(points[2]), "Held RMB after pending-add cancel deleted a point")
	editor._gui_input(_right_button(empty_pos, false))
	editor._gui_input(_left_button(empty_pos, false))
	_expect(curve.points.size() == 4, "LMB release after pending-add cancel committed a point")
	editor.free()


func _test_drag_delete_stops_on_release() -> void:
	var fixture := _make_editor()
	var editor: EasingCurveEditor = fixture.editor
	var curve: EasingCurve = fixture.curve
	var points: Array = fixture.points
	editor._gui_input(_right_button(_point_position(editor, points[0]), true))
	editor._gui_input(_motion(_point_position(editor, points[1]), true))
	editor._gui_input(_motion(_point_position(editor, points[2]), true))
	editor._gui_input(_right_button(_point_position(editor, points[2]), false))
	editor._gui_input(_motion(_point_position(editor, points[3]), false))
	_expect(not curve.points.has(points[0]), "RMB drag did not delete point A")
	_expect(not curve.points.has(points[1]), "RMB drag did not delete point B")
	_expect(not curve.points.has(points[2]), "RMB drag did not delete point C")
	_expect(curve.points.has(points[3]), "Hover after RMB drag release deleted point D")
	editor.free()


func _test_empty_space_release_does_not_enable_delete() -> void:
	var fixture := _make_editor()
	var editor: EasingCurveEditor = fixture.editor
	var curve: EasingCurve = fixture.curve
	var points: Array = fixture.points
	var empty_pos := Vector2(580.0, 280.0)
	editor._gui_input(_right_button(empty_pos, true))
	editor._gui_input(_motion(empty_pos, true))
	editor._gui_input(_right_button(empty_pos, false))
	editor._gui_input(_motion(_point_position(editor, points[0]), false))
	_expect(curve.points.has(points[0]), "Empty-space RMB release enabled later point deletion")
	_expect(not editor.is_right_delete_dragging, "Empty-space RMB release left delete-drag enabled")
	editor.free()


func _test_press_move_release_does_not_delete_next_point() -> void:
	var fixture := _make_editor()
	var editor: EasingCurveEditor = fixture.editor
	var curve: EasingCurve = fixture.curve
	var points: Array = fixture.points
	var empty_pos := Vector2(580.0, 280.0)
	editor._gui_input(_right_button(_point_position(editor, points[0]), true))
	editor._gui_input(_motion(empty_pos, true))
	editor._gui_input(_right_button(empty_pos, false))
	editor._gui_input(_motion(_point_position(editor, points[1]), false))
	_expect(not curve.points.has(points[0]), "RMB press did not delete the initial point")
	_expect(curve.points.has(points[1]), "Hover after press-move-release deleted another point")
	editor.free()


func _test_motion_without_rmb_mask_clears_stale_delete_state() -> void:
	var fixture := _make_editor()
	var editor: EasingCurveEditor = fixture.editor
	var curve: EasingCurve = fixture.curve
	var points: Array = fixture.points
	editor.is_right_delete_dragging = true
	editor._right_delete_requires_exit = true
	editor._right_delete_blocked_position = _point_position(editor, points[0])
	editor._gui_input(_motion(_point_position(editor, points[1]), false))
	_expect(curve.points.has(points[1]), "Motion without RMB mask deleted a point")
	_expect(not editor.is_right_delete_dragging, "Motion without RMB mask did not clear stale delete state")
	_expect(not editor._right_delete_requires_exit, "Stale delete hit tracking was not reset")
	editor.free()

extends SceneTree

const EDITOR_HOST = preload("res://test/editor_host_test_harness.gd")
const EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("easing_curve_points_list_reorder_editor_test.gd"):
		quit(1)
		return
	_test_repeated_arrow_moves_keep_the_logical_point_selected()
	_test_committed_drag_reorder_selects_the_dragged_point()
	_test_handle_mode_reset_uses_the_normal_transition()
	_test_handle_mode_property_cell_layout_selection_and_copy_paste()

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
	var editor_context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = editor_context.editor
	var inspector: EditorInspectorPlugin = editor_context.inspector
	return {"curve": curve, "editor": editor, "inspector": inspector, "points": curve.points.duplicate()}


func _get_handle_mode_row_parts(row: HBoxContainer) -> Dictionary:
	var property_header := row.get_child(0) as PanelContainer
	var header_hbox := property_header.get_child(1) as HBoxContainer
	var reset_margin := header_hbox.get_child(1) as MarginContainer
	var value_panel := row.get_child(1) as PanelContainer
	return {
		"property_header": property_header,
		"context_menu": property_header.get_child(0) as PopupMenu,
		"reset_button": reset_margin.get_child(0) as Button,
		"value_panel": value_panel,
		"option": value_panel.get_child(0) as OptionButton,
	}


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


func _test_handle_mode_reset_uses_the_normal_transition() -> void:
	var fixture := _make_fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var point: EasingCurvePoint = fixture.points[1]
	var free_row: HBoxContainer = inspector.call("_create_handle_mode_property", point, 1)
	var free_reset_btn: Button = _get_handle_mode_row_parts(free_row).reset_button
	_expect(is_zero_approx(free_reset_btn.self_modulate.a), "Free Handle Mode showed its reset action")
	_expect(free_reset_btn.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Free Handle Mode reset action remained enabled")
	free_row.free()

	point.right_force_linear = true
	point.set_locked("position", true)
	point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	var before := EDITOR_UNDO.capture_state(curve)
	var row: HBoxContainer = inspector.call("_create_handle_mode_property", point, 1)
	var row_parts := _get_handle_mode_row_parts(row)
	var reset_btn: Button = row_parts.reset_button
	var option: OptionButton = row_parts.option
	_expect(is_equal_approx(reset_btn.self_modulate.a, 1.0), "Non-Free Handle Mode did not show its reset action")
	_expect(reset_btn.tooltip_text == "Reset to default", "Handle Mode reset tooltip differed from point-property resets")

	reset_btn.emit_signal(&"pressed")
	var after := EDITOR_UNDO.capture_state(curve)
	_expect(point.handle_mode == EasingCurvePoint.HandleMode.FREE, "Handle Mode reset did not select Free")
	_expect(option.get_selected_id() == EasingCurvePoint.HandleMode.FREE, "Handle Mode reset did not update its selector")
	_expect(point.left_control_point.is_equal_approx(point.position + Vector2.LEFT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH), "Linear-to-Free reset did not restore the normal Free left handle")
	_expect(point.right_control_point == point.position and point.right_force_linear, "Handle Mode reset changed Force Linear state instead of applying Free geometry")
	_expect(point.is_lock_active("position") and point.position.is_equal_approx(Vector2(0.3, 0.7)), "Handle Mode reset changed the point position or lock state")
	_expect(is_zero_approx(reset_btn.self_modulate.a) and reset_btn.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Handle Mode reset did not reserve and disable its reset slot")

	var history := UndoRedo.new()
	_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Change Easing Curve Handle Mode", before, after), "Handle Mode reset did not produce an Undo/Redo action")
	history.undo()
	_expect(curve.get_editor_state_snapshot() == before, "Handle Mode reset Undo did not restore the prior mode and geometry")
	history.redo()
	_expect(curve.get_editor_state_snapshot() == after, "Handle Mode reset Redo did not reapply Free geometry")
	history.clear_history(false)
	history.free()
	row.free()
	editor.free()


func _test_handle_mode_property_cell_layout_selection_and_copy_paste() -> void:
	var fixture := _make_fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var source: EasingCurvePoint = fixture.points[1]
	var target: EasingCurvePoint = fixture.points[2]
	var handle_row: HBoxContainer = inspector.call("_create_handle_mode_property", source, 1)
	var handle_parts := _get_handle_mode_row_parts(handle_row)
	var handle_header: PanelContainer = handle_parts.property_header
	var handle_value_panel: PanelContainer = handle_parts.value_panel
	var handle_option: OptionButton = handle_parts.option
	var target_handle_row: HBoxContainer = inspector.call("_create_handle_mode_property", target, 2)
	var target_handle_header: PanelContainer = _get_handle_mode_row_parts(target_handle_row).property_header

	_expect(handle_row.get_child_count() == 2, "Handle Mode row did not use property and value regions")
	_expect(handle_header.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "Handle Mode property cell did not use the shared property-cell width")
	_expect(handle_value_panel.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "Handle Mode value region did not use the shared property-value width")
	_expect(handle_option.clip_text and handle_option.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "Handle Mode dropdown did not use the compact property-value layout")

	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	handle_header.emit_signal(&"gui_input", left_click)
	_expect(inspector.get("_selected_point_property_header") == handle_header, "Clicking Handle Mode did not select its property cell")
	_expect(inspector.get("_selected_point_property_name") == &"handle_mode", "Handle Mode selection did not record its property name")
	target_handle_header.emit_signal(&"gui_input", left_click)
	_expect(inspector.get("_selected_point_property_header") == target_handle_header, "Selecting another Handle Mode cell did not replace the property selection")

	for mode in [
		EasingCurvePoint.HandleMode.LINEAR,
		EasingCurvePoint.HandleMode.BALANCED,
		EasingCurvePoint.HandleMode.MIRRORED,
		EasingCurvePoint.HandleMode.LINKED,
	]:
		source.handle_mode = mode
		target.handle_mode = EasingCurvePoint.HandleMode.FREE
		_expect(inspector.call("_is_point_property_value_compatible", &"handle_mode", mode), "Handle Mode copy value was not accepted for %s" % EasingCurvePoint.HandleMode.keys()[mode])
		inspector.call("_apply_pasted_point_property_value", 2, &"handle_mode", mode)
		_expect(target.handle_mode == mode, "Handle Mode paste did not apply %s" % EasingCurvePoint.HandleMode.keys()[mode])

	var before := EDITOR_UNDO.capture_state(curve)
	source.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	target.handle_mode = EasingCurvePoint.HandleMode.MIRRORED
	inspector.call(
		"_apply_pasted_point_property_value",
		2,
		&"handle_mode",
		source.handle_mode,
	)
	var after := EDITOR_UNDO.capture_state(curve)
	_expect(target.left_control_point == target.position and target.right_control_point == target.position, "Pasting Linear did not use Linear transition geometry")
	var history := UndoRedo.new()
	_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Change Easing Curve Handle Mode", before, after), "Handle Mode paste did not create an Undo/Redo action")
	history.undo()
	_expect(curve.get_editor_state_snapshot() == before, "Handle Mode paste Undo did not restore geometry")
	history.redo()
	_expect(curve.get_editor_state_snapshot() == after, "Handle Mode paste Redo did not reapply geometry")
	history.clear_history(false)
	history.free()
	handle_row.free()
	target_handle_row.free()
	editor.free()

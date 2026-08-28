extends SceneTree

const EDITOR_HOST = preload("res://test/auto/editor_host_test_harness.gd")
const EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")

var _failures := 0
var _checks := 0

var _completed_fixtures := 0

func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("easing_curve_points_list_reorder_editor_test.gd"):
		quit(1)
		return
	call_deferred(&"_run")


func _run() -> void:
	await _test_drop_reorder_waits_for_safe_drag_completion()
	_test_repeated_arrow_moves_keep_the_logical_point_selected()
	_test_committed_drag_reorder_selects_the_dragged_point()
	_test_reorder_undo_redo_follows_the_selected_resource()
	_test_handle_mode_reset_uses_the_normal_transition()
	_test_handle_mode_property_cell_layout_selection_and_copy_paste()

	if _completed_fixtures != 6:
		_failures += 1
		push_error(
			"Only %d of 6 Points-list submitted reorder fixtures completed" % _completed_fixtures
		)
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


func _test_drop_reorder_waits_for_safe_drag_completion() -> void:
	var point_list := EDITOR_HOST.INSPECTOR_PLUGIN.PointsListContainer.new()
	get_root().add_child(point_list)

	var child := Control.new()
	var grandchild := Control.new()

	point_list.mouse_filter = Control.MOUSE_FILTER_STOP
	child.mouse_filter = Control.MOUSE_FILTER_STOP
	grandchild.mouse_filter = Control.MOUSE_FILTER_STOP

	point_list.add_child(child)
	child.add_child(grandchild)

	var request := {
		"count": 0,
		"from": -1,
		"to": -1,
	}

	point_list.point_swap_requested.connect(
		func(from_index: int, to_index: int) -> void:
			request["count"] = int(request["count"]) + 1
			request["from"] = from_index
			request["to"] = to_index
	)

	# A drag end without a submitted reorder must not disable the list.
	point_list.notification(Control.NOTIFICATION_DRAG_END)

	_expect(
		point_list.mouse_filter == Control.MOUSE_FILTER_STOP,
		"Points-list drag end without a pending reorder disabled mouse input",
	)

	point_list._pending_swap_from = 0
	point_list._pending_swap_to = 1

	point_list.notification(Control.NOTIFICATION_DRAG_END)

	_expect(
		int(request["count"]) == 0,
		"Points-list drag end emitted the reorder synchronously",
	)
	_expect(
		point_list.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Points-list drag completion did not disable mouse input on the retiring list",
	)
	_expect(
		child.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Points-list drag completion did not disable mouse input on child controls",
	)
	_expect(
		grandchild.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Points-list drag completion did not disable mouse input recursively",
	)

	# The drag-end handler first defers arming the process-frame callback.
	# Two frames let that asynchronous path settle without depending on
	# exact MessageQueue/process_frame ordering in the editor test host.
	await process_frame
	await process_frame

	_expect(
		int(request["count"]) == 1,
		"Points-list drag completion did not emit exactly one reorder",
	)
	_expect(
		int(request["from"]) == 0 and int(request["to"]) == 1,
		"Points-list drag completion changed the requested reorder indices",
	)
	_expect(
		point_list._pending_swap_from == -1
		and point_list._pending_swap_to == -1,
		"Points-list drag completion did not clear the pending reorder",
	)

	# Make sure the one-shot scheduling cannot emit the same reorder again.
	await process_frame

	_expect(
		int(request["count"]) == 1,
		"Points-list drag completion emitted the reorder more than once",
	)

	point_list.queue_free()
	_completed_fixtures += 1


func _create_handle_mode_fixture(
	inspector: Object,
	point: EasingCurvePoint,
	point_index: int,
) -> Dictionary:
	var property_grid := GridContainer.new()
	property_grid.columns = 2
	inspector.call(
		"_create_handle_mode_property",
		point,
		point_index,
		EasingCurve.get_point_property_definition(&"handle_mode"),
		property_grid,
	)
	if property_grid.get_child_count() != 2:
		return {"property_grid": property_grid}
	var property_header := property_grid.get_child(0) as PanelContainer
	var value_panel := property_grid.get_child(1) as PanelContainer
	if property_header == null or value_panel == null:
		return {"property_grid": property_grid}
	if property_header.get_child_count() < 2 or value_panel.get_child_count() < 1:
		return {"property_grid": property_grid}
	var overlay_root := property_header.get_child(1) as Control
	if overlay_root == null or overlay_root.get_child_count() < 2:
		return {"property_grid": property_grid}
	var reset_clip := overlay_root.get_child(1) as Control
	if reset_clip == null or reset_clip.get_child_count() < 1:
		return {"property_grid": property_grid}
	return {
		"property_grid": property_grid,
		"property_header": property_header,
		"context_menu": property_header.get_child(0) as PopupMenu,
		"reset_button": reset_clip.get_child(0) as Button,
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
	_completed_fixtures += 1
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
	_completed_fixtures += 1
	editor.free()


func _test_reorder_undo_redo_follows_the_selected_resource() -> void:
	var fixture := _make_fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var points: Array[EasingCurvePoint] = fixture.points
	var selected := points[1]
	var property_header := PanelContainer.new()
	var history := UndoRedo.new()
	inspector.call("_select_point_property", property_header, 1, &"position")

	var move_down_before := EDITOR_UNDO.capture_state(curve)
	var move_down_selection_before: Dictionary = inspector.call("_capture_point_selection_state")
	var move_down_point_resource_ids_before := curve._get_editor_point_resource_ids()
	inspector.call("_move_point_down", 1)
	var move_down_after := EDITOR_UNDO.capture_state(curve)
	var move_down_selection_after: Dictionary = inspector.call("_capture_point_selection_state")
	var move_down_point_resource_ids_after := curve._get_editor_point_resource_ids()
	_expect(
		EDITOR_UNDO.commit_applied_action(
			history,
			curve,
			"Reorder Easing Curve Points",
			EasingCurveEditorUndo.ActionContext.new(move_down_before, move_down_after)
				.with_selection(Callable(inspector, "_restore_point_selection_state"), move_down_selection_before, move_down_selection_after)
				.with_point_resource_ids(move_down_point_resource_ids_before, move_down_point_resource_ids_after),
		),
		"Move Down did not create an Undo action",
	)
	_expect(curve.points[2] == selected, "Move Down did not move the selected Resource")
	_expect(editor.selected_index == 2, "Move Down did not update the graph selection index")
	history.undo()
	_expect(curve.points[1] == selected, "Move Down Undo did not return the selected Resource to P2")
	_expect(editor.selected_index == 1, "Move Down Undo did not resolve the graph index from the selected Resource")
	_expect(inspector.get("_selected_point_index") == 1, "Move Down Undo retained a stale Inspector index")
	_expect(inspector.get("_selected_point_resource_id") == selected.get_instance_id(), "Move Down Undo changed the selected Resource")
	_expect(inspector.get("_selected_point_property_name") == &"position", "Move Down Undo lost the selected property")
	history.redo()
	_expect(curve.points[2] == selected, "Move Down Redo did not return the selected Resource to P3")
	_expect(editor.selected_index == 2, "Move Down Redo did not resolve the graph index from the selected Resource")
	_expect(inspector.get("_selected_point_index") == 2, "Move Down Redo retained a stale Inspector index")

	var drag_before := EDITOR_UNDO.capture_state(curve)
	var drag_selection_before: Dictionary = inspector.call("_capture_point_selection_state")
	var drag_point_resource_ids_before := curve._get_editor_point_resource_ids()
	inspector.call("_move_point", 2, 0)
	var drag_after := EDITOR_UNDO.capture_state(curve)
	var drag_selection_after: Dictionary = inspector.call("_capture_point_selection_state")
	var drag_point_resource_ids_after := curve._get_editor_point_resource_ids()
	_expect(
		EDITOR_UNDO.commit_applied_action(
			history,
			curve,
			"Reorder Easing Curve Points",
			EasingCurveEditorUndo.ActionContext.new(drag_before, drag_after)
				.with_selection(Callable(inspector, "_restore_point_selection_state"), drag_selection_before, drag_selection_after)
				.with_point_resource_ids(drag_point_resource_ids_before, drag_point_resource_ids_after),
		),
		"Drag reorder did not create an Undo action",
	)
	_expect(curve.points[0] == selected, "Drag reorder did not move the selected Resource")
	history.undo()
	_expect(curve.points[2] == selected, "Drag reorder Undo did not restore the selected Resource identity")
	_expect(editor.selected_index == 2 and inspector.get("_selected_point_index") == 2, "Drag reorder Undo did not synchronize graph and Inspector selection")
	history.redo()
	_expect(curve.points[0] == selected, "Drag reorder Redo did not restore the selected Resource identity")
	_expect(editor.selected_index == 0 and inspector.get("_selected_point_index") == 0, "Drag reorder Redo did not synchronize graph and Inspector selection")

	history.clear_history(false)
	history.free()
	property_header.free()
	_completed_fixtures += 1
	editor.free()


func _test_handle_mode_reset_uses_the_normal_transition() -> void:
	var fixture := _make_fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var point: EasingCurvePoint = fixture.points[1]
	var free_parts := _create_handle_mode_fixture(inspector, point, 1)
	var free_grid: GridContainer = free_parts.property_grid
	if not free_parts.has("reset_button"):
		free_grid.free()
		editor.free()
		return
	var free_reset_btn: Button = free_parts.reset_button
	_expect(not free_reset_btn.visible, "Free Handle Mode showed its reset action")
	_expect(free_reset_btn.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Free Handle Mode reset action remained enabled")
	free_grid.free()

	point.right_force_linear = true
	point.set_locked("position", true)
	point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	var before := EDITOR_UNDO.capture_state(curve)
	var row_parts := _create_handle_mode_fixture(inspector, point, 1)
	var property_grid: GridContainer = row_parts.property_grid
	if not row_parts.has("reset_button"):
		property_grid.free()
		editor.free()
		return
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
	_expect(not reset_btn.visible and reset_btn.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Handle Mode reset did not reserve and disable its reset slot")

	var history := UndoRedo.new()
	_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Change Easing Curve Handle Mode", EasingCurveEditorUndo.ActionContext.new(before, after)), "Handle Mode reset did not produce an Undo/Redo action")
	history.undo()
	_expect(curve.get_editor_state_snapshot() == before, "Handle Mode reset Undo did not restore the prior mode and geometry")
	history.redo()
	_expect(curve.get_editor_state_snapshot() == after, "Handle Mode reset Redo did not reapply Free geometry")
	history.clear_history(false)
	history.free()
	_completed_fixtures += 1
	property_grid.free()
	editor.free()


func _test_handle_mode_property_cell_layout_selection_and_copy_paste() -> void:
	var fixture := _make_fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var source: EasingCurvePoint = fixture.points[1]
	var target: EasingCurvePoint = fixture.points[2]
	var handle_parts := _create_handle_mode_fixture(inspector, source, 1)
	var handle_grid: GridContainer = handle_parts.property_grid
	if not handle_parts.has("property_header"):
		handle_grid.free()
		editor.free()
		return
	var handle_header: PanelContainer = handle_parts.property_header
	var handle_value_panel: PanelContainer = handle_parts.value_panel
	var handle_option: OptionButton = handle_parts.option
	var target_handle_parts := _create_handle_mode_fixture(inspector, target, 2)
	var target_handle_grid: GridContainer = target_handle_parts.property_grid
	if not target_handle_parts.has("property_header"):
		handle_grid.free()
		target_handle_grid.free()
		editor.free()
		return
	var target_handle_header: PanelContainer = target_handle_parts.property_header

	_expect(handle_grid.get_child_count() == 2, "Handle Mode grid did not use property and value regions")
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
	_expect(inspector.call("_is_point_property_value_compatible", &"position", Vector2(0.25, 0.75)), "Position paste no longer accepts Vector2 values")
	_expect(not inspector.call("_is_point_property_value_compatible", &"handle_mode", 99), "Handle Mode paste accepted an out-of-range integer")

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
	_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Change Easing Curve Handle Mode", EasingCurveEditorUndo.ActionContext.new(before, after)), "Handle Mode paste did not create an Undo/Redo action")
	history.undo()
	_expect(curve.get_editor_state_snapshot() == before, "Handle Mode paste Undo did not restore geometry")
	history.redo()
	_expect(curve.get_editor_state_snapshot() == after, "Handle Mode paste Redo did not reapply geometry")
	history.clear_history(false)
	history.free()
	_completed_fixtures += 1
	handle_grid.free()
	target_handle_grid.free()
	editor.free()

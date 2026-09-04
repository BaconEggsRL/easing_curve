extends "res://test/scripts/support/test_case.gd"

const CURVE_EDITOR := preload(
	"res://addons/easing_curve/scripts/editor/easing_curve_editor.gd"
)
const INSPECTOR_PLUGIN := preload(
	"res://addons/easing_curve/scripts/editor/inspector/easing_curve_editor_inspector_plugin.gd"
)
func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_legacy_selection_path()
	_test_native_selection_and_point_options()
	_test_native_geometry_gestures()
	_test_native_add_delete_and_endpoint_topology()
	_test_native_existing_point_endpoint_takeover()
	_test_native_crossing_and_toolbar_reorder()
	_test_native_point_list_swap_parity()
	_test_native_inspector_path()
	_finish("shared curve editor vertical slice")


func _test_legacy_selection_path() -> void:
	var curve := EasingCurve.new()
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	editor.set_curve(curve)
	root.add_child(editor)
	_expect(editor.get_backend_id() == &"legacy", "Curve Editor did not select the legacy backend")
	_expect(editor.select_point(curve.points[0]), "Curve Editor could not select a legacy point")
	_expect(editor.selected_index == 0, "legacy point selection index changed")
	editor.queue_free()


func _test_native_selection_and_point_options() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		_expect(false, "NativeEasingCurve is unavailable")
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var point := curve.call(&"get_point", 0) as Resource
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	editor.set_curve(curve)
	root.add_child(editor)
	_expect(editor.get_backend_id() == &"native", "Curve Editor did not select the Native backend")
	_expect(editor.select_point(point), "Curve Editor could not select a Native point")
	_expect(editor.selected_index == 0, "Native point selection index changed")

	var change_count := [0]
	curve.changed.connect(func(): change_count[0] += 1)
	editor.call(
		&"_on_point_toolbar_control_state_selected",
		EasingCurvePoint.ControlState.LINEAR,
		EasingCurvePoint.ControlSide.RIGHT,
	)
	_expect(point.get(&"right_force_linear"), "Native Force Linear was not applied from the shared toolbar")
	_expect(change_count[0] == 1, "Native Force Linear amplified curve change signals")

	editor.call(
		&"_on_point_toolbar_control_state_selected",
		EasingCurvePoint.ControlState.LOCKED,
		EasingCurvePoint.ControlSide.RIGHT,
	)
	var locks := point.get(&"locked") as Dictionary
	_expect(locks[&"right_control_point"], "Native lock was not applied from the shared toolbar")
	_expect(not point.get(&"right_force_linear"), "Native lock did not clear Force Linear")
	_expect(change_count[0] == 2, "Native locking amplified curve change signals")

	curve.set(&"transition", 0)
	_expect(not editor.call(&"_is_point_toolbar_hidden"), "Native editable preset hid point options")
	editor.queue_free()


func _test_native_inspector_path() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	var inspector := INSPECTOR_PLUGIN.new()
	_expect(inspector._can_handle(curve), "Inspector plugin rejected NativeEasingCurve")
	var content := inspector.handle_easing_curve_editor(curve)
	_expect(content != null, "Inspector plugin did not build the Native Curve Editor")
	if content != null:
		root.add_child(content)
		var editor := _find_curve_editor(content)
		_expect(editor != null, "Native Inspector content omitted the shared Curve Editor")
		if editor != null:
			_expect(editor.get_backend_id() == &"native", "Native Inspector used the wrong backend")
			var add_button := _find_button(content, "Add Point")
			_expect(add_button != null, "Native Inspector omitted the shared point-list Add control")
			_expect(_find_drag_handle(content) != null, "Native point list omitted the legacy drag handle")
			var first_point := curve.call(&"get_point", 0) as Resource
			var first_panel: Node = inspector.get("_native_points_content").get_child(0)
			var original_position: Vector2 = first_point.get(&"position")
			var preview_position := original_position + Vector2(0.0, 0.2)
			editor.edit_point_property(0, &"position", preview_position, true)
			_expect(
				editor.get("position_x_order_preview_point") == first_point,
				"Native point-list drag did not enable graph-order preview",
			)
			_expect(
				(editor.call(&"_get_display_points") as Array).has(first_point),
				"Native point-list drag omitted the edited point from graph preview",
			)
			editor.finish_point_list_edit(first_point, &"position")
			_expect(
				editor.get("position_x_order_preview_point") == null,
				"Native point-list drag retained stale graph-order preview state",
			)
			_expect(
				not inspector.get("_native_points_refresh_queued")
				and inspector.get("_native_points_content").get_child(0) == first_panel,
				"Native geometry commit rebuilt the entire point list",
			)
			if add_button != null:
				var before_count: int = curve.call(&"get_point_count")
				add_button.pressed.emit()
				_expect(curve.call(&"get_point_count") == before_count + 1, "Native point-list Add did not use the shared backend")
		content.queue_free()


func _test_native_geometry_gestures() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var point := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	point.set(&"position", Vector2(0.5, 0.5))
	point.set(&"left_control_point", Vector2(0.4, 0.45))
	point.set(&"right_control_point", Vector2(0.6, 0.55))
	_expect(bool(curve.call(&"insert_point", 1, point)), "Native interior point fixture was rejected")
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	var live_publications := [0]
	editor.committed_change_publisher = func(): live_publications[0] += 1
	editor.set_curve(curve)
	editor.size = Vector2(520.0, 260.0)
	root.add_child(editor)
	editor.update_view_transform()

	var original_position := point.get(&"position") as Vector2
	var original_left := point.get(&"left_control_point") as Vector2
	var original_right := point.get(&"right_control_point") as Vector2
	point.set(&"right_control_point", Vector2(0.6, 3.5))
	var native_bounds := editor.call(&"_get_autofit_world_bounds") as Rect2
	_expect(native_bounds.end.y >= 3.5, "Native Autofit bounds ignored a visible control handle")
	point.set(&"right_control_point", original_right)
	var target_position := Vector2(0.55, 0.6)
	var position_delta := target_position - original_position
	var start_view := editor.get_view_pos(original_position)
	var intermediate_view := editor.get_view_pos(Vector2(0.525, 0.55))
	var target_view := editor.get_view_pos(target_position)
	var change_count := [0]
	curve.changed.connect(func(): change_count[0] += 1)
	editor._gui_input(_mouse_button(start_view, true))
	editor._gui_input(_mouse_motion(intermediate_view))
	_expect(bool(editor.get("_backend_point_edit_active")), "Native point drag did not open one backend transaction")
	editor._gui_input(_mouse_motion(target_view))
	editor._gui_input(_mouse_button(target_view, false))
	_expect(point.get(&"position").is_equal_approx(target_position), "Native point drag did not update geometry")
	_expect(
		point.get(&"left_control_point").is_equal_approx(original_left + position_delta),
		"Native point drag did not translate its left handle once",
	)
	_expect(
		point.get(&"right_control_point").is_equal_approx(original_right + position_delta),
		"Native point drag did not translate its right handle once",
	)
	_expect(not bool(editor.get("_backend_point_edit_active")), "Native point drag did not close its backend transaction")
	_expect(change_count[0] == 1, "Native point drag did not defer publication to release")
	_expect(live_publications[0] == 1, "Native point drag did not publish one live-edit snapshot")
	_expect(history.has_undo(), "Native point drag did not create an Undo action")
	history.undo()
	_expect(point.get(&"position").is_equal_approx(original_position), "Native point drag Undo did not restore geometry")
	_expect(live_publications[0] == 2, "Native point drag Undo did not publish one live-edit snapshot")
	_expect(not history.has_undo() and history.has_redo(), "Native point drag created more than one Undo action")
	history.redo()
	_expect(point.get(&"position").is_equal_approx(target_position), "Native point drag Redo did not restore geometry")
	_expect(live_publications[0] == 3, "Native point drag Redo did not publish one live-edit snapshot")

	history.clear_history()
	var original_control := point.get(&"right_control_point") as Vector2
	var target_control := target_position + Vector2(0.25, 0.2)
	start_view = editor.get_view_pos(original_control)
	target_view = editor.get_view_pos(target_control)
	editor._gui_input(_mouse_button(start_view, true))
	editor._gui_input(_mouse_motion(target_view))
	editor._gui_input(_mouse_button(target_view, false))
	_expect(point.get(&"right_control_point").is_equal_approx(target_control), "Native handle drag did not update geometry")
	_expect(history.has_undo(), "Native handle drag did not create an Undo action")
	history.undo()
	_expect(point.get(&"right_control_point").is_equal_approx(original_control), "Native handle drag Undo did not restore geometry")
	_expect(not history.has_undo() and history.has_redo(), "Native handle drag created more than one Undo action")
	history.redo()
	_expect(point.get(&"right_control_point").is_equal_approx(target_control), "Native handle drag Redo did not restore geometry")

	point.call(&"set_locked", &"position", true)
	history.clear_history()
	start_view = editor.get_view_pos(target_position)
	target_view = editor.get_view_pos(Vector2(0.4, 0.4))
	editor._gui_input(_mouse_button(start_view, true))
	editor._gui_input(_mouse_motion(target_view))
	editor._gui_input(_mouse_button(target_view, false))
	_expect(point.get(&"position").is_equal_approx(target_position), "Native position lock did not block graph dragging")
	_expect(not history.has_undo(), "Blocked Native point drag created an Undo action")
	editor.queue_free()


func _test_native_existing_point_endpoint_takeover() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var middle := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	middle.set(&"position", Vector2(0.5, 0.5))
	middle.set(&"left_control_point", Vector2(0.4, 0.5))
	middle.set(&"right_control_point", Vector2(0.6, 0.5))
	curve.call(&"insert_point", 1, middle)
	var old_right := curve.call(&"get_point", 2) as Resource
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	editor.set_curve(curve)
	editor.size = Vector2(520.0, 260.0)
	root.add_child(editor)
	editor.update_view_transform()
	var start_view := editor.get_view_pos(middle.get(&"position"))
	var endpoint_view := editor.get_view_pos(Vector2(1.0, 0.75))
	editor._gui_input(_mouse_button(start_view, true))
	editor._gui_input(_mouse_motion(endpoint_view))
	editor._gui_input(_mouse_button(endpoint_view, false))
	_expect(curve.call(&"get_point_count") == 2, "Native point drag to x=1 retained the old endpoint")
	_expect(curve.call(&"get_point", 1) == middle, "Native point drag endpoint takeover lost point identity")
	_expect((curve.call(&"get_points") as Array).find(old_right) == -1, "Native point drag did not detach the displaced endpoint")
	_expect(editor.selected_index == 1, "Native point drag endpoint takeover lost selection")
	_expect(history.has_undo(), "Native point drag endpoint takeover omitted Undo history")
	history.undo()
	_expect(curve.call(&"get_point_count") == 3, "Native endpoint takeover Undo did not restore the displaced endpoint")
	_expect(curve.call(&"get_point", 1) == middle and curve.call(&"get_point", 2) == old_right, "Native endpoint takeover Undo lost resource identity")
	history.redo()
	_expect(curve.call(&"get_point_count") == 2 and curve.call(&"get_point", 1) == middle, "Native endpoint takeover Redo failed")
	editor.queue_free()


func _test_native_add_delete_and_endpoint_topology() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	editor.set_curve(curve)
	editor.size = Vector2(520.0, 260.0)
	root.add_child(editor)
	editor.update_view_transform()

	var add_world := Vector2(0.35, 0.4)
	var add_view := editor.get_view_pos(add_world)
	editor._gui_input(_mouse_button(add_view, true))
	var cancelled_point := editor.get(&"pending_add_point") as Resource
	_expect(cancelled_point != null, "Native pending add did not create a backend point")
	_expect(curve.call(&"get_point_count") == 2, "Native pending add mutated topology before release")
	editor.notification(Control.NOTIFICATION_FOCUS_EXIT)
	_expect(editor.get(&"pending_add_point") == null, "Native focus exit retained a stale pending point")
	editor._gui_input(_mouse_button(add_view, true))
	cancelled_point = editor.get(&"pending_add_point") as Resource
	_expect(cancelled_point != null, "Native pending add could not restart after focus exit")
	editor._gui_input(_mouse_button(add_view, true, MOUSE_BUTTON_RIGHT))
	_expect(editor.get(&"pending_add_point") == null, "Native RMB did not cancel pending add")
	_expect(not history.has_undo(), "Native pending-add cancellation created Undo history")

	var changes := [0]
	curve.changed.connect(func() -> void: changes[0] += 1)
	editor._gui_input(_mouse_button(add_view, true))
	var added_point := editor.get(&"pending_add_point") as Resource
	editor._gui_input(_mouse_button(add_view, false))
	_expect(curve.call(&"get_point_count") == 3, "Native click add did not commit topology")
	_expect(editor.selected_index == 1 and curve.call(&"get_point", 1) == added_point, "Native click add lost point identity or selection")
	_expect(changes[0] == 1, "Native click add published more than once")
	_expect(history.has_undo(), "Native click add did not create Undo history")
	history.undo()
	_expect(curve.call(&"get_point_count") == 2, "Native click-add Undo did not remove the point")
	_expect(editor.selected_index == -1, "Native click-add Undo did not restore selection")
	_expect(not history.has_undo() and history.has_redo(), "Native click add created more than one Undo action")
	history.redo()
	_expect(curve.call(&"get_point", 1) == added_point, "Native click-add Redo recreated point identity")
	_expect(editor.selected_index == 1, "Native click-add Redo did not restore point selection")

	history.clear_history()
	add_view = editor.get_view_pos(added_point.get(&"position"))
	editor._gui_input(_mouse_button(add_view, true))
	editor._gui_input(_mouse_button(add_view, false))
	_expect(not history.has_undo(), "Native no-op point release created Undo history")

	var old_left := curve.call(&"get_point", 0) as Resource
	var endpoint_start_view := editor.get_view_pos(Vector2(0.2, 0.7))
	var endpoint_view := editor.get_view_pos(Vector2(0.0, 0.7))
	history.clear_history()
	editor._gui_input(_mouse_button(endpoint_start_view, true))
	var replacement := editor.get(&"pending_add_point") as Resource
	editor._gui_input(_mouse_motion(endpoint_view))
	changes[0] = 0
	editor._gui_input(_mouse_button(endpoint_view, false))
	_expect(curve.call(&"get_point_count") == 3, "Native endpoint takeover changed the point count")
	_expect(curve.call(&"get_point", 0) == replacement, "Native endpoint takeover lost the replacement resource")
	_expect(curve.call(&"get_points").find(old_left) == -1, "Native endpoint takeover retained the displaced endpoint")
	_expect(changes[0] == 1, "Native endpoint takeover published more than once")

	var selected_point := curve.call(&"get_point", 2) as Resource
	editor.select_point(selected_point)
	var delete_point := curve.call(&"get_point", 1) as Resource
	var delete_view := editor.get_view_pos(delete_point.get(&"position"))
	history.clear_history()
	changes[0] = 0
	editor.set_position_x_order_preview(delete_point)
	editor._gui_input(_mouse_button(delete_view, true, MOUSE_BUTTON_RIGHT))
	editor._gui_input(_mouse_button(delete_view, false, MOUSE_BUTTON_RIGHT))
	_expect(curve.call(&"get_point_count") == 2, "Native RMB delete did not remove the point")
	_expect(editor.get("position_x_order_preview_point") == null, "Native deletion retained a detached preview point")
	_expect(not (editor.call(&"_get_display_points") as Array).has(delete_point), "Native graph retained a deleted point")
	_expect(editor.selected_index == 1 and curve.call(&"get_point", 1) == selected_point, "Native RMB delete did not preserve shifted selection identity")
	_expect(changes[0] == 1, "Native RMB delete published more than once")
	_expect(not editor.is_right_delete_dragging, "Native RMB release retained stale drag state")
	history.undo()
	_expect(curve.call(&"get_point", 1) == delete_point, "Native RMB-delete Undo recreated point identity")
	_expect(editor.selected_index == 2 and curve.call(&"get_point", 2) == selected_point, "Native RMB-delete Undo lost selection identity")
	history.redo()
	_expect(editor.selected_index == 1 and curve.call(&"get_point", 1) == selected_point, "Native RMB-delete Redo lost selection identity")

	history.clear_history()
	delete_view = editor.get_view_pos(selected_point.get(&"position"))
	editor._gui_input(_mouse_button(delete_view, true, MOUSE_BUTTON_RIGHT))
	editor._gui_input(_mouse_button(delete_view, false, MOUSE_BUTTON_RIGHT))
	_expect(editor.selected_index == -1, "Deleting the selected Native point did not clear selection")
	history.undo()
	_expect(editor.selected_index == 1 and curve.call(&"get_point", 1) == selected_point, "Selected-point delete Undo lost selection identity")
	history.redo()
	_expect(editor.selected_index == -1, "Selected-point delete Redo did not clear selection")
	editor.queue_free()


func _test_native_point_list_swap_parity() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var first := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	first.set(&"position", Vector2(0.25, 0.3))
	first.set(&"left_control_point", Vector2(0.15, 0.2))
	first.set(&"right_control_point", Vector2(0.35, 0.4))
	first.call(&"set_locked", &"left_control_point", true)
	first.call(&"set_locked", &"right_control_point", true)
	var middle := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	middle.set(&"position", Vector2(0.5, 0.5))
	var last := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	last.set(&"position", Vector2(0.75, 0.7))
	last.set(&"left_control_point", Vector2(0.65, 0.6))
	last.set(&"right_control_point", Vector2(0.85, 0.8))
	curve.call(&"insert_point", 1, first)
	curve.call(&"insert_point", 2, middle)
	curve.call(&"insert_point", 3, last)
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	editor.set_curve(curve)
	root.add_child(editor)
	var first_state := first.call(&"capture_state") as Dictionary
	var last_state := last.call(&"capture_state") as Dictionary
	editor.move_point_from_list(1, 3)
	_expect(curve.call(&"get_point", 1) == last, "Native list swap did not move the target resource to the source slot")
	_expect(curve.call(&"get_point", 2) == middle, "Native list swap shifted an unrelated point")
	_expect(curve.call(&"get_point", 3) == first, "Native list swap lost the dragged resource")
	_expect(editor.get_selected_point_resource() == first, "Native list swap lost selection identity")
	_expect(_state_was_horizontally_translated(first, first_state, 0.75), "Native list swap did not translate the dragged point and handles")
	_expect(_state_was_horizontally_translated(last, last_state, 0.25), "Native list swap did not translate the target point and handles")
	history.undo()
	_expect(curve.call(&"get_point", 1) == first and curve.call(&"get_point", 3) == last, "Native list-swap Undo lost point identity")
	_expect(first.call(&"capture_state") == first_state and last.call(&"capture_state") == last_state, "Native list-swap Undo lost point state")
	history.redo()
	_expect(curve.call(&"get_point", 3) == first and editor.get_selected_point_resource() == first, "Native list-swap Redo lost point identity or selection")
	editor.queue_free()


func _state_was_horizontally_translated(
	point: Resource,
	original: Dictionary,
	target_x: float,
) -> bool:
	var current := point.call(&"capture_state") as Dictionary
	var delta_x := target_x - (original[&"position"] as Vector2).x
	for property_name: StringName in [&"position", &"left_control_point", &"right_control_point"]:
		var expected := original[property_name] as Vector2
		expected.x += delta_x
		if not (current[property_name] as Vector2).is_equal_approx(expected):
			return false
	return true


func _test_native_crossing_and_toolbar_reorder() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var first := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	first.set(&"position", Vector2(0.35, 0.35))
	first.set(&"left_control_point", Vector2(0.25, 0.35))
	first.set(&"right_control_point", Vector2(0.45, 0.35))
	var second := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	second.set(&"position", Vector2(0.65, 0.65))
	second.set(&"left_control_point", Vector2(0.55, 0.65))
	second.set(&"right_control_point", Vector2(0.75, 0.65))
	curve.call(&"insert_point", 1, first)
	curve.call(&"insert_point", 2, second)
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	editor.set_curve(curve)
	editor.size = Vector2(520.0, 260.0)
	root.add_child(editor)
	editor.update_view_transform()

	var start_view := editor.get_view_pos(first.get(&"position"))
	var target_position := Vector2(0.8, 0.45)
	var target_view := editor.get_view_pos(target_position)
	var changes := [0]
	curve.changed.connect(func() -> void: changes[0] += 1)
	editor._gui_input(_mouse_button(start_view, true))
	_expect(editor.selected_index == 1, "Native crossing press did not select the dragged point")
	editor._gui_input(_mouse_motion(target_view))
	_expect(editor.get("_backend_point_edit_selected_before") == first, "Native crossing transaction did not capture selected resource identity")
	var changes_before_release: int = changes[0]
	editor._gui_input(_mouse_button(target_view, false))
	_expect(curve.call(&"get_point", 2) == first, "Native right crossing did not commit point order")
	_expect(editor.selected_index == 2, "Native right crossing lost selected point identity")
	_expect(changes[0] == changes_before_release + 1, "Native crossing release did not publish exactly once")
	_expect(history.has_undo(), "Native crossing did not create Undo history")
	history.undo()
	_expect(curve.call(&"get_point", 1) == first, "Native crossing Undo lost point identity")
	_expect(
		editor.selected_index == 1,
		"Native crossing Undo lost selection identity (index=%d, resolved=%d)"
		% [editor.selected_index, (curve.call(&"get_points") as Array).find(first)],
	)
	_expect(not history.has_undo() and history.has_redo(), "Native crossing created more than one Undo action")
	history.redo()
	_expect(curve.call(&"get_point", 2) == first and editor.selected_index == 2, "Native crossing Redo lost identity or selection")

	history.clear_history()
	start_view = editor.get_view_pos(first.get(&"position"))
	target_position = Vector2(0.2, 0.45)
	target_view = editor.get_view_pos(target_position)
	editor._gui_input(_mouse_button(start_view, true))
	editor._gui_input(_mouse_motion(target_view))
	editor._gui_input(_mouse_button(target_view, false))
	_expect(curve.call(&"get_point", 1) == first and editor.selected_index == 1, "Native left crossing lost identity or selection")
	history.undo()
	_expect(curve.call(&"get_point", 2) == first and editor.selected_index == 2, "Native left-crossing Undo lost identity or selection")
	history.redo()
	_expect(curve.call(&"get_point", 1) == first and editor.selected_index == 1, "Native left-crossing Redo lost identity or selection")
	history.undo()

	history.clear_history()
	editor.point_move_buttons_reorder_points = true
	editor.call(&"_request_point_move_up")
	_expect(curve.call(&"get_point", 1) == first and editor.selected_index == 1, "Native toolbar reorder lost identity or selection")
	_expect(history.has_undo(), "Native toolbar reorder did not create Undo history")
	history.undo()
	_expect(curve.call(&"get_point", 2) == first and editor.selected_index == 2, "Native toolbar reorder Undo lost identity or selection")
	history.redo()
	_expect(curve.call(&"get_point", 1) == first and editor.selected_index == 1, "Native toolbar reorder Redo lost identity or selection")
	editor.queue_free()


func _mouse_button(
	position: Vector2,
	pressed: bool,
	button_index: MouseButton = MOUSE_BUTTON_LEFT,
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.position = position
	event.pressed = pressed
	return event


func _mouse_motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event


func _find_curve_editor(node: Node) -> EasingCurveEditor:
	if node is EasingCurveEditor:
		return node
	for child in node.get_children():
		var result := _find_curve_editor(child)
		if result != null:
			return result
	return null


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var result := _find_button(child, text)
		if result != null:
			return result
	return null


func _find_drag_handle(node: Node) -> EasingCurveDragHandle:
	if node is EasingCurveDragHandle:
		return node
	for child in node.get_children():
		var result := _find_drag_handle(child)
		if result != null:
			return result
	return null

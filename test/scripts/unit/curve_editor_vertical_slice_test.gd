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
	_expect(editor.call(&"_is_point_toolbar_hidden"), "Native standard transition exposed point options")
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
	editor.set_curve(curve)
	editor.size = Vector2(520.0, 260.0)
	root.add_child(editor)
	editor.update_view_transform()

	var original_position := point.get(&"position") as Vector2
	var original_left := point.get(&"left_control_point") as Vector2
	var original_right := point.get(&"right_control_point") as Vector2
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
	_expect(change_count[0] == 2, "Native point drag amplified curve change signals")
	_expect(history.has_undo(), "Native point drag did not create an Undo action")
	history.undo()
	_expect(point.get(&"position").is_equal_approx(original_position), "Native point drag Undo did not restore geometry")
	_expect(not history.has_undo() and history.has_redo(), "Native point drag created more than one Undo action")
	history.redo()
	_expect(point.get(&"position").is_equal_approx(target_position), "Native point drag Redo did not restore geometry")

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


func _mouse_button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
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

extends "res://test/scripts/support/test_case.gd"


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(Engine.is_editor_hint() and ClassDB.class_exists(&"NativeEasingCurve"), "Requires Editor host and Native extension")
	if not Engine.is_editor_hint() or not ClassDB.class_exists(&"NativeEasingCurve"):
		_finish("drag coordinates")
		return
	for native: bool in [false, true]:
		for reverse: bool in [false, true]:
			for invert: bool in [false, true]:
				_test_gestures(native, reverse, invert)
		_test_lifecycle(native)
		_test_constraints(native)
	_test_format_and_placement()
	await _test_rendered()
	_finish("drag coordinates")


func _fixture(native: bool, reverse := false, invert := false) -> EasingCurveEditor:
	var curve: Resource
	if native:
		curve = ClassDB.instantiate(&"NativeEasingCurve")
		curve.set(&"transition", 100)
		var point := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
		point.set(&"position", Vector2(0.35, 0.4))
		point.set(&"left_control_point", Vector2(0.2, 0.25))
		point.set(&"right_control_point", Vector2(0.55, 0.65))
		curve.call(&"insert_point", 1, point)
	else:
		var legacy := EasingCurve.new()
		legacy.trans_type = EasingCurve.TRANS.CUSTOM
		legacy.points = [EasingCurvePoint.new(Vector2.ZERO), EasingCurvePoint.new(Vector2(0.35, 0.4)), EasingCurvePoint.new(Vector2.ONE)]
		legacy.points[1].left_control_point = Vector2(0.2, 0.25)
		legacy.points[1].right_control_point = Vector2(0.55, 0.65)
		curve = legacy
	curve.set(&"reverse", reverse)
	curve.set(&"invert", invert)
	var editor := EasingCurveEditor.new()
	editor.presentation_owned = true
	editor.editor_undo_redo = UndoRedo.new()
	editor.set_curve(curve)
	editor.size = Vector2(600, 300)
	root.add_child(editor)
	editor.update_view_transform()
	return editor


func _press(editor: EasingCurveEditor, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = editor.get_view_pos(position)
	editor._gui_input(event)


func _motion(editor: EasingCurveEditor, position: Vector2, shift := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = editor.get_view_pos(position)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.shift_pressed = shift
	editor._gui_input(event)


func _resolved(editor: EasingCurveEditor, property: StringName) -> Vector2:
	return editor._backend.curve_to_display_position(editor._point(1).get(property) as Vector2)


func _test_gestures(native: bool, reverse: bool, invert: bool) -> void:
	for property: StringName in [&"position", &"left_control_point", &"right_control_point"]:
		var editor := _fixture(native, reverse, invert)
		var start := _resolved(editor, property)
		_expect(not editor._get_drag_coordinate_position().is_finite(), "Idle graph showed coordinates")
		_press(editor, start)
		_expect(editor._get_drag_coordinate_position().is_equal_approx(start), "Press readout mismatched visible element")
		if property != &"position":
			var expected_side := EasingCurveEditor.ControlIndex.LEFT if property == &"left_control_point" else EasingCurveEditor.ControlIndex.RIGHT
			_expect(editor.dragging_control == expected_side, "Reverse swapped underlying handle twice")
		_motion(editor, start + Vector2(0.03, 0.04))
		_expect(editor._get_drag_coordinate_position().is_equal_approx(_resolved(editor, property)), "Motion readout mismatched resolved geometry")
		var snapshot: Variant = editor._backend.capture_snapshot()
		var changes := [0]
		editor.get_curve().changed.connect(func(): changes[0] += 1)
		var history: UndoRedo = editor.editor_undo_redo
		var history_count := history.get_history_count()
		for index in range(20):
			editor._format_drag_coordinates(editor._get_drag_coordinate_position())
			editor.queue_redraw()
		_expect(editor._backend.capture_snapshot() == snapshot and changes[0] == 0, "Overlay mutated resource or published changes")
		_expect(history.get_history_count() == history_count, "Overlay recorded history")
		var graph_position := editor._get_drag_coordinate_position()
		var view_position := editor.get_view_pos(graph_position)
		editor.pan_offset += Vector2(15, -12)
		editor._zoom_x = 1.5
		editor.update_view_transform()
		_expect(editor._get_drag_coordinate_position().is_equal_approx(graph_position), "Pan/zoom changed coordinate value")
		_expect(not editor.get_view_pos(graph_position).is_equal_approx(view_position), "Pan/zoom failed to move anchor")
		editor._handle_left_released()
		_expect(not editor._get_drag_coordinate_position().is_finite(), "Release left readout visible")
		_expect(history.get_history_count() == history_count + 1, "Drag did not create exactly one action")
		_dispose(editor)
	var editor := _fixture(native, reverse, invert)
	var target := Vector2(0.73, 0.18)
	_press(editor, target)
	_expect(editor.pending_add_point != null, "Pending-add fixture missed empty graph")
	_expect(editor._get_drag_coordinate_position().is_equal_approx(target), "Pending point transformed twice on press")
	_motion(editor, target + Vector2(0.02, 0.03))
	_expect(editor._get_drag_coordinate_position().is_equal_approx(target + Vector2(0.02, 0.03)), "Pending point transformed twice on motion")
	editor._cancel_pending_add()
	_expect(not editor._get_drag_coordinate_position().is_finite(), "Cancelled pending point remained visible")
	_press(editor, target)
	editor._handle_left_released()
	_expect(not editor._get_drag_coordinate_position().is_finite(), "Committed pending point remained visible")
	_dispose(editor)


func _test_lifecycle(native: bool) -> void:
	var editor := _fixture(native)
	for notification: int in [Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_press(editor, _resolved(editor, &"position"))
		var snapshot: Variant = editor._backend.capture_snapshot()
		editor.notification(notification)
		_expect(not editor._get_drag_coordinate_position().is_finite(), "Focus loss did not dismiss readout")
		_expect(editor.dragging_point == 1 and editor._backend.capture_snapshot() == snapshot, "Focus loss altered drag")
		editor._handle_left_released()
	_press(editor, _resolved(editor, &"position"))
	editor.hide()
	editor.show()
	_expect(not editor._get_drag_coordinate_position().is_finite(), "Hide/show revived readout")
	editor._handle_left_released()
	_press(editor, _resolved(editor, &"position"))
	_expect(editor._get_drag_coordinate_position().is_finite(), "New gesture did not rearm")
	var sibling := _fixture(not native)
	_expect(not sibling._get_drag_coordinate_position().is_finite(), "Sibling inherited overlay")
	editor.set_curve(sibling.get_curve())
	_expect(not editor._get_drag_coordinate_position().is_finite(), "Resource replacement revived readout")
	_dispose(editor)
	_dispose(sibling)
	var rebuilt := _fixture(native)
	_expect(not rebuilt._get_drag_coordinate_position().is_finite(), "Reconstruction inherited overlay")
	_press(rebuilt, _resolved(rebuilt, &"position"))
	root.remove_child(rebuilt)
	_expect(not rebuilt._get_drag_coordinate_position().is_finite(), "Tree exit retained readout")
	_dispose(rebuilt)


func _test_constraints(native: bool) -> void:
	for property: StringName in [&"position", &"left_control_point", &"right_control_point"]:
		var editor := _fixture(native)
		editor._point(1).call(&"set_locked", property, true)
		_press(editor, _resolved(editor, property))
		_expect(not editor._get_drag_coordinate_position().is_finite(), "Locked element showed drag readout")
		_dispose(editor)
	for mode: int in [EasingCurvePoint.HandleMode.FREE, EasingCurvePoint.HandleMode.BALANCED, EasingCurvePoint.HandleMode.MIRRORED]:
		var editor := _fixture(native)
		editor._point(1).set(&"handle_mode", mode)
		var start := _resolved(editor, &"left_control_point")
		_press(editor, start)
		_motion(editor, start + Vector2(-0.08, 0.01), true)
		_expect(editor._get_drag_coordinate_position().is_equal_approx(_resolved(editor, &"left_control_point")), "Handle mode/axis constraint readout used cursor")
		_expect(is_equal_approx(editor._get_drag_coordinate_position().y, start.y), "Axis constrained readout moved Y")
		editor._handle_left_released()
		_dispose(editor)
	var editor := _fixture(native)
	editor._point(1).set(&"left_force_linear", true)
	_press(editor, _resolved(editor, &"position"))
	_motion(editor, Vector2(1.2, 0.8))
	_expect(editor._get_drag_coordinate_position().is_equal_approx(_resolved(editor, &"position")), "Crossing/clamped point readout used cursor")
	_expect(editor._get_drag_coordinate_position().x <= 1.0, "Endpoint clamp was not reflected")
	editor._handle_left_released()
	var endpoint := editor._point(0).get(&"position") as Vector2
	editor._point(0).call(&"set_locked", &"right_control_point", true)
	_press(editor, endpoint)
	if editor.dragging_point != -1:
		_motion(editor, Vector2(-0.3, 0.2))
		_expect(editor._get_drag_coordinate_position().x >= 0.0, "Endpoint readout escaped constraints")
	editor._handle_left_released()
	_dispose(editor)


func _test_format_and_placement() -> void:
	var editor := _fixture(false)
	_expect(editor._format_drag_coordinates(Vector2(0.5, 0.91)) == "(0.50, 0.91)", "Precision/trailing zeros")
	_expect(editor._format_drag_coordinates(Vector2(-0.0001, -0.004)) == "(0.00, 0.00)", "Negative zero")
	_expect(editor._format_drag_coordinates(Vector2(-0.02, 1.25)) == "(-0.02, 1.25)", "Out-of-range formatting")
	for scale: float in [1.0, 2.0]:
		editor._editor_scale = scale
		var text_size := Vector2(100, 20) * scale
		for anchor: Vector2 in [Vector2.ZERO, Vector2(600, 0), Vector2(0, 300), Vector2(600, 300), Vector2(-300, 800)]:
			var position := editor._get_drag_coordinate_label_position(anchor, text_size)
			_expect(position.x >= 4 * scale and position.y >= 36 * scale, "Label escaped top/left bounds")
			_expect(position.x + text_size.x <= editor.size.x - 4 * scale and position.y + text_size.y <= editor.size.y - 4 * scale, "Label escaped bottom/right bounds")
	_expect(not editor._get_drag_coordinate_label_position(Vector2.ZERO, Vector2(900, 900)).is_finite(), "Oversized label was not omitted")
	_dispose(editor)


func _test_rendered() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: rendered drag-coordinate smoke requires display support")
		return
	var canvas := Control.new()
	canvas.z_index = 100
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = root.size
	root.add_child(canvas)
	var background := ColorRect.new()
	background.size = root.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	var editors: Array[EasingCurveEditor] = []
	for native: bool in [false, true]:
		var editor := _fixture(native)
		editor.reparent(canvas)
		editor.position = Vector2(20, 20 if not native else 330)
		_press(editor, _resolved(editor, &"position"))
		editors.append(editor)
	for scale: float in [1.0, 1.5]:
		for light: bool in [false, true]:
			background.color = Color(0.85, 0.85, 0.85) if light else Color(0.12, 0.12, 0.12)
			for editor: EasingCurveEditor in editors:
				editor._editor_scale = scale
				var theme := Theme.new()
				theme.set_font_size(&"font_size", &"Label", roundi(16 * scale))
				theme.set_color(&"font_color", &"Label", Color.BLACK if light else Color.WHITE)
				editor.theme = theme
				_press(editor, _resolved(editor, &"position"))
				editor.queue_redraw()
			editors[1].position.y = editors[0].position.y + editors[0].size.y + 30
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://test/_temp/drag-coordinates-%s-%s.png" % [scale, "light" if light else "dark"])
			for editor: EasingCurveEditor in editors:
				_expect(editor._get_drag_coordinate_position().is_finite(), "Rendered overlay disappeared")
	for editor: EasingCurveEditor in editors:
		editor._handle_left_released()
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = editor.position + editor.get_view_pos(_resolved(editor, &"position"))
		press.global_position = press.position
		root.push_input(press)
		_expect(editor._get_drag_coordinate_position().is_finite(), "Viewport press did not start overlay")
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = Vector2(900, 900)
		release.global_position = release.position
		root.push_input(release)
		_expect(not editor._get_drag_coordinate_position().is_finite(), "Outside-graph viewport release retained overlay")
		_dispose(editor)
	canvas.free()


func _dispose(editor: EasingCurveEditor) -> void:
	editor.finish_active_point_edit()
	(editor.editor_undo_redo as UndoRedo).clear_history()
	editor.free()

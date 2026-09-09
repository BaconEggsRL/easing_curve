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
	await _test_format_and_placement()
	for native: bool in [false, true]:
		await _test_coordinate_tracking_and_minimum_gap(native)
	_test_display_space_handle_parity()
	_test_grid_snapping()
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
	var handoff := _fixture(native)
	var input := EditorSpinSlider.new()
	root.add_child(input)
	handoff.begin_point_list_coordinate_drag(input, handoff._point(1), &"position")
	handoff.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_press(handoff, Vector2(0.73, 0.18))
	_expect(handoff.pending_add_point != null, "List-to-graph handoff did not create pending point")
	_expect(handoff._get_drag_coordinate_position().is_equal_approx(Vector2(0.73, 0.18)), "Pending point inherited stale list coordinate source")
	input.free()
	handoff._cancel_pending_add()
	_dispose(handoff)


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
	await process_frame
	await process_frame
	_expect(editor._format_drag_coordinates(Vector2(0.5, 0.91)) == "(0.50, 0.91)", "Precision/trailing zeros")
	_expect(editor._format_drag_coordinates(Vector2(-0.0001, -0.004)) == "(0.00, 0.00)", "Negative zero")
	_expect(editor._format_drag_coordinates(Vector2(-0.02, 1.25)) == "(-0.02, 1.25)", "Out-of-range formatting")
	for scale: float in [1.0, 2.0]:
		editor._editor_scale = scale
		editor.set_zoom(Vector2.ONE * editor.step_to_zoom(EasingCurveEditor.DEFAULT_SLIDER_VALUE))
		editor.update_view_transform()
		var font := editor.get_theme_font(&"font", &"Label")
		var font_size := editor.get_theme_font_size(&"font_size", &"Label")
		var top_anchor := editor.get_view_pos(Vector2(0.5, 1.0))
		var actual_text_size := Vector2(100, font.get_height(font_size))
		var top_label := editor._get_drag_coordinate_label_position(top_anchor, actual_text_size)
		var top_controls_bottom := editor._snap_button.position.y + editor._snap_button.size.y
		var snap_to_overlay := editor._coordinate_overlay.get_global_transform().affine_inverse() * editor._snap_button.get_global_transform()
		top_controls_bottom = (snap_to_overlay * Vector2(0, editor._snap_button.size.y)).y
		_expect(top_label.y >= top_controls_bottom + 8.0 * scale, "Top-edge label overlapped the visible overlay controls")
		_expect(is_equal_approx(editor._get_graph_view_rect().position.y, 4.0 * scale), "Readout clamp reserved graph height")
		var text_size := Vector2(100, 20) * scale
		for anchor: Vector2 in [Vector2.ZERO, Vector2(600, 0), Vector2(0, 300), Vector2(600, 300), Vector2(-300, 800)]:
			var position := editor._get_drag_coordinate_label_position(anchor, text_size)
			_expect(position.x >= 4 * scale and position.y >= 36 * scale, "Label escaped top/left bounds")
			_expect(position.x + text_size.x <= editor.size.x - 4 * scale and position.y + text_size.y <= editor.size.y - 4 * scale, "Label escaped bottom/right bounds")
	_expect(not editor._get_drag_coordinate_label_position(Vector2.ZERO, Vector2(900, 900)).is_finite(), "Oversized label was not omitted")
	_dispose(editor)


func _label_bounds(editor: EasingCurveEditor) -> Rect2:
	var font := editor.get_theme_font(&"font", &"Label")
	var font_size := editor.get_theme_font_size(&"font_size", &"Label")
	var coordinate := editor._get_drag_coordinate_position()
	var text_size := font.get_string_size(editor._format_drag_coordinates(coordinate), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	text_size.y = font.get_height(font_size)
	return Rect2(editor._get_drag_coordinate_label_position(editor.get_view_pos(coordinate), text_size), text_size)


func _expect_coordinate_placement(editor: EasingCurveEditor, expected_coordinate: Vector2, radius := -1.0) -> void:
	var bounds := _label_bounds(editor)
	var label_top := editor._coordinate_overlay.get_global_transform() * bounds.position
	var button_bottom := editor._snap_button.get_global_transform() * Vector2(0, editor._snap_button.size.y)
	var canvas_scale := editor._coordinate_overlay.get_global_transform().get_scale().y
	var minimum_gap := EasingCurveEditor.GRID_SNAP_COORDINATE_LABEL_MIN_GAP * editor._editor_scale
	_expect((label_top.y - button_bottom.y) / canvas_scale >= minimum_gap - 0.01, "Coordinate line crossed the Grid Snap minimum gap")
	_expect(editor._get_drag_coordinate_position().is_equal_approx(expected_coordinate), "Layout/navigation changed the coordinate value")
	var margin := 4.0 * editor._editor_scale
	var expected_x := clampf(editor.get_view_pos(expected_coordinate).x - bounds.size.x * 0.5, margin, editor.size.x - margin - bounds.size.x)
	_expect(is_equal_approx(bounds.position.x, expected_x), "Y-only fix changed horizontal placement")
	var minimum_y := (editor._coordinate_overlay.get_global_transform().affine_inverse() * button_bottom).y + minimum_gap
	var item_radius := float(editor.point_radius) if radius < 0 else radius
	var candidate_y := editor.get_view_pos(expected_coordinate).y - item_radius - 6.0 * editor._editor_scale - bounds.size.y
	var expected_y := clampf(candidate_y, minimum_y, editor.size.y - margin - bounds.size.y)
	_expect(is_equal_approx(bounds.position.y, expected_y), "Coordinate Y lost its original anchor/radius offset or edge clamp")


func _coordinate_view_cases() -> Array[Dictionary]:
	return [
		{ "name": "default", "width": 414.0, "zoom": EasingCurveEditor.DEFAULT_SLIDER_VALUE },
		{ "name": "zoom-out-narrow", "width": 320.0, "zoom": 0 },
		{ "name": "zoom-in-wide", "width": 640.0, "zoom": 21 },
		{ "name": "pan-up", "width": 414.0, "zoom": 21, "pan": Vector2(160, -120) },
		{ "name": "pan-down", "width": 414.0, "zoom": 0, "pan": Vector2(-160, 120) },
		{ "name": "autofit", "width": 414.0 },
		{ "name": "reset", "width": 414.0, "zoom": EasingCurveEditor.DEFAULT_SLIDER_VALUE },
	]


func _apply_coordinate_view(editor: EasingCurveEditor, view: Dictionary) -> void:
	if view.name == "autofit":
		editor.autofit()
	else:
		editor.slider_value = view.zoom
		editor.pan_offset = view.get("pan", Vector2.ZERO)
	editor.update_view_transform()
	editor.queue_redraw()


func _test_coordinate_tracking_and_minimum_gap(native: bool) -> void:
	var editor := _fixture(native)
	editor.position = Vector2(23, 17)
	var slider := EasingCurveEditor.ZOOM_SLIDER_CONTAINER.instantiate() as EasingCurveZoomSliderContainer
	root.add_child(slider)
	slider.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	editor.set_slider_container(slider)
	_press(editor, _resolved(editor, &"position"))
	var coordinate := editor._get_drag_coordinate_position()
	for view: Dictionary in _coordinate_view_cases():
		editor.size = Vector2(view.width, 300)
		await process_frame
		await process_frame
		var graph_rect := editor._get_graph_view_rect()
		var button_rect := editor._snap_button.get_global_rect()
		var slider_rect := slider.get_global_rect()
		_apply_coordinate_view(editor, view)
		await process_frame
		_expect_coordinate_placement(editor, coordinate)
		_expect(editor._get_graph_view_rect() == graph_rect, "Coordinate layout/navigation changed graph rectangle")
		_expect(editor._snap_button.get_global_rect() == button_rect, "Coordinate layout/navigation moved Grid Snap")
		_expect(slider.get_global_rect() == slider_rect, "Coordinate layout/navigation moved zoom controls")
	_test_leaving_top_clamp(editor)
	# The same placement applies to handles, pending points, and Inspector inputs.
	editor._handle_left_released()
	for property: StringName in [&"left_control_point", &"right_control_point"]:
		_press(editor, _resolved(editor, property))
		_expect_coordinate_placement(editor, _resolved(editor, property), editor.control_radius)
		editor._handle_left_released()
	_press(editor, Vector2(0.73, 0.18))
	_expect(editor.pending_add_point != null, "Layout fixture did not start pending add")
	_expect_coordinate_placement(editor, Vector2(0.73, 0.18))
	editor._cancel_pending_add()
	var input := EditorSpinSlider.new()
	root.add_child(input)
	editor.begin_point_list_coordinate_drag(input, editor._point(1), &"position")
	_expect_coordinate_placement(editor, _resolved(editor, &"position"))
	editor.begin_point_list_coordinate_drag(input, editor._point(1), &"left_control_point")
	_expect_coordinate_placement(editor, _resolved(editor, &"left_control_point"), editor.control_radius)
	editor.begin_point_list_coordinate_drag(input, editor._point(1), &"position")
	# Put the label on its top clamp before testing toolbar-only relayout.
	editor.pan_offset.y = -1000
	editor.queue_redraw()
	var draws := [0]
	editor._coordinate_overlay.draw.connect(func(): draws[0] += 1)
	await process_frame
	await process_frame
	var previous_draws: int = draws[0]
	var previous_top := _label_bounds(editor).position.y
	var separation := editor._point_toolbar_panel.get_theme_constant(&"separation")
	editor._point_toolbar_panel.add_theme_constant_override(&"separation", separation - 2)
	await process_frame
	await process_frame
	await process_frame
	_expect(draws[0] > previous_draws, "Toolbar-only relayout did not redraw the coordinate overlay")
	_expect(is_equal_approx(_label_bounds(editor).position.y, previous_top - 2), "Coordinate label did not follow the actual toolbar bottom")
	# Canvas scaling must not be applied twice when converting the button bounds.
	editor.scale = Vector2(1.5, 1.5)
	_expect_coordinate_placement(editor, _resolved(editor, &"position"))
	editor._editor_scale = 2.0
	_expect_coordinate_placement(editor, _resolved(editor, &"position"))
	editor.end_point_list_coordinate_drag()
	input.free()
	slider.free()
	_dispose(editor)


func _test_leaving_top_clamp(editor: EasingCurveEditor) -> void:
	var coordinate := editor._get_drag_coordinate_position()
	var original_top := _label_bounds(editor).position.y
	var original_anchor := editor.get_view_pos(coordinate)
	_motion(editor, coordinate + Vector2(0, -0.1))
	coordinate = editor._get_drag_coordinate_position()
	var moved_top := _label_bounds(editor).position.y
	var anchor_delta := editor.get_view_pos(coordinate).y - original_anchor.y
	_expect(anchor_delta > 1.0 and is_equal_approx(moved_top - original_top, anchor_delta), "Unclamped point movement did not move the readout vertically")
	_expect_coordinate_placement(editor, coordinate)
	var minimum_y := editor._get_drag_coordinate_label_position(Vector2(0, -1000), _label_bounds(editor).size).y
	editor.pan_offset.y += minimum_y - moved_top - 20.0
	_expect(is_equal_approx(_label_bounds(editor).position.y, minimum_y), "Readout did not enter the top clamp")
	_expect_coordinate_placement(editor, coordinate)
	editor.pan_offset.y += 40.0
	_expect(is_equal_approx(_label_bounds(editor).position.y, minimum_y + 20.0), "Readout did not immediately leave the top clamp")
	_expect_coordinate_placement(editor, coordinate)
	editor.pan_offset = Vector2.ZERO


func _test_display_space_handle_parity() -> void:
	for mode: int in [EasingCurvePoint.HandleMode.BALANCED, EasingCurvePoint.HandleMode.MIRRORED]:
		for property_name: StringName in [&"left_control_point", &"right_control_point"]:
			for graph_size: Vector2 in [Vector2(900, 320), Vector2(480, 520)]:
				var legacy_trace: Array[Vector2] = []
				for native: bool in [false, true]:
					var editor := _fixture(native)
					editor.size = graph_size
					editor._zoom_x = 1.3
					editor._zoom_y = 0.8
					editor.update_view_transform()
					var point := editor._point(1)
					point.set(&"handle_mode", mode)
					var opposite := &"right_control_point" if property_name == &"left_control_point" else &"left_control_point"
					var center := editor.get_view_pos(point.get(&"position"))
					var opposite_length := center.distance_to(editor.get_view_pos(point.get(opposite)))
					_press(editor, _resolved(editor, property_name))
					for angle: float in [0.2, 0.6, 1.0, 1.4, 2.0]:
						var target := editor.get_world_pos(center + Vector2.from_angle(angle) * 55.0)
						_motion(editor, target)
						var moved := editor.get_view_pos(point.get(property_name)) - center
						var other := editor.get_view_pos(point.get(opposite)) - center
						_expect(absf(moved.normalized().cross(other.normalized())) < 0.0001 and moved.dot(other) < 0, "Handles lost opposite screen-space alignment")
						var expected_length := opposite_length if mode == EasingCurvePoint.HandleMode.BALANCED else moved.length()
						_expect(absf(other.length() - expected_length) < 0.01, "Rotation changed opposite screen-space radius")
						for property: StringName in [&"left_control_point", &"right_control_point"]:
							var result: Vector2 = point.get(property)
							if native:
								_expect(result.distance_to(legacy_trace.pop_front()) < 0.0001, "Native display-space rotation differs from Legacy")
							else:
								legacy_trace.append(result)
					editor._handle_left_released()
					_expect((editor.editor_undo_redo as UndoRedo).get_history_count() == 1, "Display-space drag changed Undo transaction count")
					_dispose(editor)


func _test_grid_snapping() -> void:
	for native: bool in [false, true]:
		for reverse: bool in [false, true]:
			for invert: bool in [false, true]:
				for count: int in [2, 10, 100]:
					var editor := _fixture(native, reverse, invert)
					var before: Variant = editor._backend.capture_snapshot()
					_expect(not editor._snap_count_input.visible, "Disabled snapping showed count")
					editor._snap_button.button_pressed = true
					editor._snap_count_input.value = count
					_expect(editor.snap_count == count and editor._snap_count_input.visible, "Snap controls did not synchronize")
					_expect(editor._backend.capture_snapshot() == before, "Snap setting changed curve geometry")
					var target := Vector2(0.637, 0.823)
					var expected := target.snapped(Vector2.ONE / float(count))
					_press(editor, _resolved(editor, &"position"))
					_motion(editor, target)
					_expect(editor._get_drag_coordinate_position().distance_to(expected) < 0.0001, "Point snap did not match visible graph grid")
					editor._handle_left_released()
					_expect((editor.editor_undo_redo as UndoRedo).get_history_count() == 1, "Snapped drag changed Undo count")
					var resource := editor.get_curve()
					var replacement := EasingCurveEditor.new()
					replacement.set_curve(resource)
					_expect(replacement.snap_enabled and replacement.snap_count == count, "Graph rebuild lost snap preferences")
					replacement.free()
					_dispose(editor)
		var editor := _fixture(native)
		editor.snap_enabled = true
		editor.snap_count = 10
		_press(editor, _resolved(editor, &"left_control_point"))
		_motion(editor, Vector2(0.233, 0.317))
		_expect(editor._get_drag_coordinate_position().distance_to(Vector2(0.233, 0.317)) < 0.0001, "Grid snapping affected a handle")
		editor._handle_left_released()
		_press(editor, Vector2(0.731, 0.183))
		_expect(editor.pending_add_point != null and editor._get_drag_coordinate_position().distance_to(Vector2(0.7, 0.2)) < 0.0001, "New point did not snap on press")
		_motion(editor, Vector2(0.812, 0.287))
		_expect(editor._get_drag_coordinate_position().distance_to(Vector2(0.8, 0.3)) < 0.0001, "Pending point did not snap on motion")
		editor._cancel_pending_add()
		editor.snap_enabled = false
		var origin := _resolved(editor, &"position")
		_press(editor, origin)
		var motion := InputEventMouseMotion.new()
		motion.position = editor.get_view_pos(Vector2(0.637, 0.823))
		motion.ctrl_pressed = OS.get_name() != "macOS"
		motion.meta_pressed = OS.get_name() == "macOS"
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		editor._gui_input(motion)
		_expect(editor._get_drag_coordinate_position().distance_to(Vector2(0.6, 0.8)) < 0.0001, "Temporary Ctrl/Cmd snapping failed")
		editor._handle_left_released()
		(editor.editor_undo_redo as UndoRedo).undo()
		editor.snap_enabled = true
		_press(editor, origin)
		_motion(editor, origin + Vector2(0.21, 0.01), true)
		_expect(is_equal_approx(editor._get_drag_coordinate_position().y, origin.y), "Snapping overrode Shift axis constraint")
		editor._handle_left_released()
		editor.snap_count = 1
		_expect(editor.snap_count == 2, "Snap count accepted less than 2")
		editor.snap_count = 200
		_expect(editor.snap_count == 100, "Snap count accepted more than 100")
		_expect(editor._coordinate_overlay.z_index > 0 and editor._coordinate_overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Readout is not a foreground input-transparent overlay")
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
		editor._point(1).set(&"position", Vector2(0.35, 1.0))
		_press(editor, _resolved(editor, &"position"))
		editor.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test/_temp/drag-coordinates-top-inset.png")
	for editor: EasingCurveEditor in editors:
		editor._snap_button.button_pressed = true
		editor._snap_count_input.value = 100
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test/_temp/drag-coordinates-snapping.png")
	await _capture_coordinate_views(editors, canvas)
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


func _capture_coordinate_views(editors: Array[EasingCurveEditor], canvas: Control) -> void:
	var input := EditorSpinSlider.new()
	canvas.add_child(input)
	input.hide()
	var sliders: Array[EasingCurveZoomSliderContainer] = []
	for editor: EasingCurveEditor in editors:
		editor._handle_left_released()
		editor.theme = null
		editor._editor_scale = EditorInterface.get_editor_scale()
		editor.snap_enabled = false
		editor._point(0).set(&"position", Vector2(0, 1))
		editor._point(2).set(&"position", Vector2(1, 1))
		editor.selected_index = 0
		var slider := EasingCurveEditor.ZOOM_SLIDER_CONTAINER.instantiate() as EasingCurveZoomSliderContainer
		canvas.add_child(slider)
		slider.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		editor.set_slider_container(slider)
		sliders.append(slider)
	for view: Dictionary in _coordinate_view_cases():
		for index in range(editors.size()):
			var editor := editors[index]
			editor.size = Vector2(view.width, 300)
			_apply_coordinate_view(editor, view)
			editor.begin_point_list_coordinate_drag(input, editor._point(0), &"position")
		await process_frame
		await process_frame
		editors[1].position.y = editors[0].position.y + editors[0].size.y + 55
		for index in range(editors.size()):
			sliders[index].position = editors[index].position + Vector2(0, editors[index].size.y + 8)
			sliders[index].size = Vector2(editors[index].size.x, 32.0 * editors[index]._editor_scale)
		await process_frame
		await RenderingServer.frame_post_draw
		_expect_coordinate_placement(editors[0], Vector2(0, 1))
		_expect_coordinate_placement(editors[1], Vector2(0, 1))
		_expect(is_equal_approx(_label_bounds(editors[0]).position.y, _label_bounds(editors[1]).position.y), "Legacy/Native coordinate rows differ")
		var capture_size := Vector2i(int(view.width) + 40, int(editors[1].position.y + editors[1].size.y + 45))
		var capture := root.get_texture().get_image().get_region(Rect2i(Vector2i.ZERO, capture_size))
		_expect(capture.save_png("res://test/_temp/coordinate-gap-%s.png" % view.name) == OK, "Coordinate layout capture failed")
	for editor: EasingCurveEditor in editors:
		editor.end_point_list_coordinate_drag()
	for slider: EasingCurveZoomSliderContainer in sliders:
		slider.free()
	input.free()


func _dispose(editor: EasingCurveEditor) -> void:
	editor.finish_active_point_edit()
	(editor.editor_undo_redo as UndoRedo).clear_history()
	editor.free()

extends "res://test/scripts/support/test_case.gd"


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(Engine.is_editor_hint(), "Grid suite requires an Editor host")
	_expect(ClassDB.class_exists(&"NativeEasingCurve"), "Grid suite requires Native extension")
	if not Engine.is_editor_hint() or not ClassDB.class_exists(&"NativeEasingCurve"):
		_finish("fixed graph grid")
		return
	for native: bool in [false, true]:
		_test_ticks(native)
		_test_box(native)
		_test_labels(native)
		await _test_drawing_is_read_only(native)
	_test_formatting()
	await _capture_views()
	_finish("fixed graph grid")


func _fixture(native: bool) -> EasingCurveEditor:
	var curve: Resource
	if native:
		curve = ClassDB.instantiate(&"NativeEasingCurve")
		curve.set(&"transition", 100)
	else:
		var legacy := EasingCurve.new()
		legacy.trans_type = EasingCurve.TRANS.CUSTOM
		legacy.points = [EasingCurvePoint.new(Vector2.ZERO), EasingCurvePoint.new(Vector2.ONE)]
		curve = legacy
	var editor := EasingCurveEditor.new()
	editor.presentation_owned = true
	editor.editor_undo_redo = UndoRedo.new()
	editor.set_curve(curve)
	editor.size = Vector2(600, 320)
	root.add_child(editor)
	editor.update_view_transform()
	return editor


func _test_ticks(native: bool) -> void:
	var editor := _fixture(native)
	var rect := editor._get_graph_view_rect()
	var margin := 4.0 * editor._editor_scale
	_expect(rect.is_equal_approx(Rect2(Vector2.ONE * margin, editor.size - Vector2.ONE * margin * 2.0)), "Graph viewport does not fill the editor")
	editor.selected_index = 0
	editor._point_toolbar_panel.hide()
	_expect(editor._get_graph_view_rect() == rect, "Toolbar visibility or selection changed graph dimensions")
	editor._point_toolbar_panel.show()
	for zoom: Vector2 in [Vector2.ONE, Vector2(0.1, 0.1), Vector2(10, 10), Vector2(0.3, 7.0)]:
		for pan: Vector2 in [Vector2.ZERO, Vector2(-123, 91), Vector2(817, -651)]:
			editor.set_zoom(zoom)
			editor.pan_offset = pan
			editor.update_view_transform()
			_expect(editor._get_graph_view_rect() == rect, "Pan/zoom moved the canonical graph rectangle")
			for axis in [Vector2.AXIS_X, Vector2.AXIS_Y]:
				var divisions := 4 if axis == Vector2.AXIS_X else 2
				var previous := -INF
				for index in range(divisions + 1):
					var anchor := editor._get_grid_tick_position(axis, index, rect)
					var fraction := float(index) / divisions
					var expected := Vector2(rect.position.x + rect.size.x * fraction, rect.end.y) if axis == 0 else Vector2(rect.position.x, rect.end.y - rect.size.y * fraction)
					_expect(anchor.is_equal_approx(expected), "Fixed tick anchor moved during navigation")
					var world := editor.get_world_pos(anchor)
					_expect(editor.get_view_pos(world).distance_to(anchor) < 0.01, "Tick failed canonical transform round trip")
					var value := world[axis]
					var text := editor._format_grid_label(value)
					_expect(absf(text.to_float() - value) <= 0.05001, "Label rounding exceeded half a tenth")
					_expect(text.to_float() >= previous, "Rounded tick labels lost coordinate order")
					previous = text.to_float()
	# Reference labels are display coordinates, unaffected by backend Reverse/Invert.
	var anchor := editor._get_grid_tick_position(0, 1, rect)
	var coordinate := editor.get_world_pos(anchor)
	editor.get_curve().set(&"reverse", true)
	editor.get_curve().set(&"invert", true)
	editor.update_view_transform()
	_expect(editor.get_world_pos(anchor).is_equal_approx(coordinate), "Backend transform was applied to tick values twice")
	editor.size = Vector2(830, 430)
	editor.update_view_transform()
	var resized := editor._get_graph_view_rect()
	_expect(not resized.is_equal_approx(rect), "Resize fixture did not resize plot")
	_expect(editor._get_grid_tick_position(0, 2, resized).x == resized.get_center().x, "Resize lost proportional divisions")
	editor.size = Vector2(320, 900)
	editor.update_view_transform()
	var square := editor._get_graph_view_rect()
	_expect(square.size.is_equal_approx(Vector2.ONE * (320.0 - margin * 2.0)), "An externally tall editor escaped the square graph cap")
	var square_tick := editor._get_grid_tick_position(1, 1, square)
	_expect(is_equal_approx(square_tick.y, square.get_center().y), "Height cap moved proportional grid ticks")
	_expect(editor.get_view_pos(editor.get_world_pos(square_tick)).distance_to(square_tick) < 0.01, "Height cap broke canonical transform round trip")
	_dispose(editor)


func _test_box(native: bool) -> void:
	var editor := _fixture(native)
	var rect := editor._get_graph_view_rect()
	var lines := editor._get_reference_box_lines(rect)
	_expect(lines.size() == 8, "Default reference box should have four edges")
	editor.pan_offset = rect.size * 0.5
	lines = editor._get_reference_box_lines(rect)
	_expect(lines.size() == 4, "Partial box must contain only its two visible original edges")
	var corner := editor.get_view_pos(Vector2(0, 1))
	for index in range(0, lines.size(), 2):
		_expect(is_equal_approx(lines[index].x, corner.x) or is_equal_approx(lines[index].y, corner.y), "Clipping introduced a false box edge")
		_expect(rect.grow(0.001).has_point(lines[index]) and rect.grow(0.001).has_point(lines[index + 1]), "Reference edge escaped plot")
	editor.pan_offset = rect.size * 2.0
	_expect(editor._get_reference_box_lines(rect).is_empty(), "Fully offscreen box still drew edges")
	editor.pan_offset = Vector2.ZERO
	editor.set_zoom(Vector2(10, 10))
	editor.update_view_transform()
	_expect(editor._get_reference_box_lines(rect).is_empty(), "Enclosing world box manufactured a viewport outline")
	editor.set_zoom(Vector2(0.1, 0.1))
	editor.update_view_transform()
	lines = editor._get_reference_box_lines(rect)
	_expect(lines.size() == 8, "Zoomed-out box lost edges")
	_expect(is_equal_approx(lines[1].y - lines[0].y, rect.size.y * 0.1), "Reference box failed to scale with world transform")
	_dispose(editor)


func _test_labels(native: bool) -> void:
	var editor := _fixture(native)
	for scale: float in [1.0, 1.5]:
		editor._editor_scale = scale
		var theme := Theme.new()
		theme.set_font_size(&"font_size", &"Label", roundi(16 * scale))
		editor.theme = theme
		for dimensions: Vector2 in [Vector2(600, 320), Vector2(140, 220), Vector2(64, 180)]:
			editor.size = dimensions
			editor.update_view_transform()
			var rect := editor._get_graph_view_rect().intersection(Rect2(Vector2.ZERO, editor.size))
			var labels := editor._get_grid_labels(rect, editor.get_theme_font(&"font", &"Label"), editor.get_theme_font_size(&"font_size", &"Label"))
			_expect(labels.size() <= 8, "Fixed grid generated too many labels")
			for index in range(labels.size()):
				var label: Dictionary = labels[index]
				_expect(rect.encloses(label.bounds), "Label escaped plot bounds")
				for previous in range(index):
					_expect(not label.bounds.intersects(labels[previous].bounds), "Grid labels overlap")
			if dimensions.x == 600:
				_expect(labels.size() >= 6, "Normal plot suppressed too many labels")
				_expect(labels[0].axis == 0 and labels[0].index == 0, "X origin label lost collision priority")
	var font := editor.get_theme_font(&"font", &"Label")
	_expect(editor._get_grid_labels(Rect2(0, 0, 2, 2), font, 16).is_empty(), "Tiny plot should suppress labels")
	_dispose(editor)


func _test_formatting() -> void:
	var editor := EasingCurveEditor.new()
	for pair: Array in [[0.0, "0.0"], [0.26, "0.3"], [0.5, "0.5"], [0.74, "0.7"], [1.0, "1.0"], [-0.5, "-0.5"], [1.5, "1.5"], [0.30000004, "0.3"], [-0.049, "0.0"]]:
		_expect(editor._format_grid_label(pair[0]) == pair[1], "Unexpected one-decimal grid formatting: %s" % pair[0])
	_expect(editor._format_grid_label(0.000125) == "0.0", "Zoom must retain tenth-resolution labels")
	editor.free()


func _test_drawing_is_read_only(native: bool) -> void:
	var editor := _fixture(native)
	var changes := [0]
	editor.get_curve().changed.connect(func(): changes[0] += 1)
	var before: Variant = editor._backend.capture_snapshot()
	var history := editor.editor_undo_redo as UndoRedo
	var history_count := history.get_history_count()
	for index in range(3):
		editor.hide_graph_background = index % 2 == 1
		editor.pan_offset += Vector2(13, -21)
		editor.queue_redraw()
		await process_frame
	_expect(before == editor._backend.capture_snapshot(), "Drawing changed curve resource")
	_expect(changes[0] == 0, "Drawing emitted curve change signals")
	_expect(history.get_history_count() == history_count, "Drawing modified Undo/Redo history")
	_dispose(editor)


func _capture_views() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: grid screenshots require display support")
		return
	root.size = Vector2i(1000, 650)
	var canvas := Control.new()
	canvas.z_index = 100
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("20252d")
	background.size = Vector2(1000, 650)
	canvas.add_child(background)
	var editors: Array[EasingCurveEditor] = []
	for native: bool in [false, true]:
		var editor := _fixture(native)
		editor.reparent(canvas)
		editor.size = Vector2(460, 290)
		editor.position = Vector2(20 if not native else 510, 45)
		var caption := Label.new()
		caption.text = "Legacy" if not native else "Native"
		caption.position = editor.position - Vector2(0, 25)
		canvas.add_child(caption)
		editors.append(editor)
	for scenario: String in ["default", "panned", "zoomed_out", "hidden", "zoomed_in", "resized", "dragging", "light"]:
		for editor: EasingCurveEditor in editors:
			editor.hide_graph_background = scenario == "hidden"
			editor.set_zoom(Vector2.ONE)
			editor.pan_offset = Vector2.ZERO
			match scenario:
				"panned": editor.pan_offset = Vector2(83, -47)
				"zoomed_out": editor.set_zoom(Vector2(0.2, 0.2))
				"hidden": editor.set_zoom(Vector2(0.2, 0.2))
				"zoomed_in": editor.set_zoom(Vector2(8, 5))
				"resized": editor.size = Vector2(240, 360)
				"dragging":
					editor.size = Vector2(460, 290)
					editor.update_view_transform()
					var press := InputEventMouseButton.new()
					press.button_index = MOUSE_BUTTON_LEFT
					press.pressed = true
					press.position = editor.get_view_pos(Vector2.ZERO)
					editor._gui_input(press)
					var motion := InputEventMouseMotion.new()
					motion.button_mask = MOUSE_BUTTON_MASK_LEFT
					motion.position = press.position + Vector2(12, -18)
					editor._gui_input(motion)
				"light":
					editor._handle_left_released()
					var theme := Theme.new()
					theme.set_color(&"font_color", &"Label", Color("20252d"))
					theme.set_font_size(&"font_size", &"Label", 24)
					editor.theme = theme
					editor._editor_scale = 1.5
					background.color = Color("e0e3e8")
			editor.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test/_temp/fixed-grid-%s.png" % scenario)
	for editor: EasingCurveEditor in editors:
		_dispose(editor)
	canvas.free()


func _dispose(editor: EasingCurveEditor) -> void:
	editor.finish_active_point_edit()
	(editor.editor_undo_redo as UndoRedo).clear_history()
	editor.free()

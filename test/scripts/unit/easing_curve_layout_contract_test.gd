extends "res://test/scripts/support/test_case.gd"

const HOST = preload("res://test/scripts/support/editor_host_test_harness.gd")


class CaptureProbe:
	extends Control
	var events: Array[InputEvent] = []

	func _gui_input(event: InputEvent) -> void:
		events.append(event)
		accept_event()


func _init() -> void:
	if not HOST.require_inspector_host("easing_curve_layout_contract_test.gd"):
		quit(1)
		return
	call_deferred(&"_run")


func _run() -> void:
	_test_free_mode_preserves_overrides()
	await _test_grouped_toolbar()
	await _test_sibling_capture()
	await _test_graph_dimensions()
	_finish("curve layout contract")


func _test_free_mode_preserves_overrides() -> void:
	for native: bool in [false, true]:
		for mode: int in EasingCurvePoint.HandleMode.values():
			for flags in range(16):
				var curve: Resource = ClassDB.instantiate(&"NativeEasingCurve") if native else EasingCurve.new()
				if native:
					curve.set(&"transition", 100)
				else:
					curve.set(&"trans_type", EasingCurve.TRANS.CUSTOM)
				var backend = EasingCurveEditor.BackendFactory.create(curve)
				var point: Resource = backend.get_point(0)
				point.set(&"left_force_linear", bool(flags & 1))
				point.set(&"right_force_linear", bool(flags & 2))
				point.call(&"set_locked", &"left_control_point", bool(flags & 4))
				point.call(&"set_locked", &"right_control_point", bool(flags & 8))
				point.set(&"handle_mode", mode)
				var before := _stored_overrides(point)
				_expect(backend.apply_point_property(0, &"handle_mode", EasingCurvePoint.HandleMode.FREE, false), "Free mode edit was rejected")
				_expect(_stored_overrides(backend.get_point(0)) == before, "Free mode changed stored flags: native=%s mode=%s flags=%s" % [native, mode, flags])
		print("FREE_MODE_GATE backend=%s preserved overrides for all modes and flag combinations" % ["native" if native else "legacy"])


func _stored_overrides(point: Resource) -> Array:
	return [point.get(&"left_force_linear"), point.get(&"right_force_linear"), point.get(&"locked").duplicate(true)]


func _settle() -> void:
	for frame in range(5):
		await process_frame


func _test_grouped_toolbar() -> void:
	for native: bool in [false, true]:
		var curve: Resource
		if native:
			curve = ClassDB.instantiate(&"NativeEasingCurve")
			curve.set(&"transition", 100)
			var point: Resource = ClassDB.instantiate(&"NativeEasingCurvePoint")
			point.set(&"position", Vector2(0.5, 0.5))
			curve.call(&"insert_point", 1, point)
		else:
			var legacy := EasingCurve.new()
			legacy.trans_type = EasingCurve.TRANS.CUSTOM
			legacy.points = [EasingCurvePoint.new(Vector2.ZERO), EasingCurvePoint.new(Vector2(0.5, 0.5)), EasingCurvePoint.new(Vector2.ONE)]
			curve = legacy
		var context := HOST.INSPECTOR_PLUGIN.new()
		var presentation: Control = context.handle_easing_curve_editor(curve)
		root.add_child(presentation)
		var editor: EasingCurveEditor = context.easing_curve_editor
		editor.selected_index = 1
		editor._point(1).set(&"left_force_linear", true)
		editor._point(1).call(&"set_locked", &"right_control_point", true)
		await _settle()
		var flow := editor._point_toolbar
		_expect(flow is HFlowContainer, "Toolbar lost its characterized native wrapping container")
		_expect(editor._point_left_state.get_parent() == editor._point_left_state_label.get_parent(), "Left label split from its field")
		_expect(editor._point_right_state.get_parent() == editor._point_right_state_label.get_parent(), "Right label split from its field")
		for scale_value: float in [1.0, 1.5, 2.0]:
			var theme := Theme.new()
			theme.default_font_size = roundi(16.0 * scale_value)
			presentation.theme = theme
			editor._editor_scale = scale_value
			await _settle()
			var baseline_width := presentation.get_combined_minimum_size().x
			var arrangements := {}
			for width: float in [150.0, 180.0, 220.0, 270.0, 359.0, 360.0, 361.0, 600.0, 220.0, 180.0, 150.0]:
				presentation.size.x = width * scale_value
				await _settle()
				var positions: Array[Vector2] = []
				for group: Control in flow.get_children():
					positions.append(group.position)
					if group.visible:
						_expect(group.position.x >= 0 and group.get_rect().end.x <= flow.size.x + 0.01, "Toolbar group overflowed allocated width")
				await _settle()
				for index in range(flow.get_child_count()):
					_expect(flow.get_child(index).position == positions[index], "Toolbar layout oscillated at fixed width")
				if arrangements.has(width):
					_expect(arrangements[width] == positions, "Returning to a width changed row arrangement")
				arrangements[width] = positions
				_expect(presentation.get_combined_minimum_size().x == baseline_width, "Toolbar wrapping changed presentation minimum width")
				_expect(editor._graph_canvas.size.x == editor.size.x, "Control minimum widened the graph canvas")
				_expect(editor._snap_toolbar_margin.get_parent() == editor._graph_canvas.get_parent(), "Grid Snap is not a graph sibling")
				_expect(editor._snap_toolbar_margin.get_rect().end.y <= editor._graph_canvas.position.y, "Grid Snap overlaps graph")
				_expect(editor._slider.get_global_rect().end.x <= editor.get_global_rect().end.x + 0.01, "Zoom row overflowed Inspector width")
				for option: OptionButton in [editor._point_handle_mode, editor._point_left_state, editor._point_right_state]:
					var font := option.get_theme_font(&"font")
					var extent := font.get_string_size(option.get_item_text(option.selected), HORIZONTAL_ALIGNMENT_LEFT, -1, option.get_theme_font_size(&"font_size"))
					_expect(option.size.x >= extent.x + option.get_theme_icon(&"arrow").get_width(), "Flow collapsed a state field to its arrow")
				editor.autofit()
				var graph := editor._get_graph_view_rect()
				_expect(editor._get_autofit_view_rect() == graph, "Auto Fit still subtracts control obstructions")
				var bounds := editor._get_autofit_world_bounds()
				_expect(graph.has_point(editor.get_view_pos(bounds.position)) and graph.has_point(editor.get_view_pos(bounds.end)), "Auto Fit clipped world bounds")
				var fitted_pan := editor.pan_offset
				editor.autofit()
				_expect(editor.pan_offset.is_equal_approx(fitted_pan), "Repeated Auto Fit drifted")
				for anchor: Vector2 in [graph.position - Vector2(100, 100), graph.end + Vector2(100, 100)]:
					var extent := Vector2(50, 20)
					var label := editor._get_drag_coordinate_label_position(anchor, extent)
					_expect(graph.encloses(Rect2(label, extent)), "Transient readout escaped the graph")
			print("WRAP_GATE backend=%s scale=%s presentation_min=%s" % ["native" if native else "legacy", scale_value, baseline_width])
		presentation.free()
		await _settle()


func _test_sibling_capture() -> void:
	for button: MouseButton in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(500, 400)
		root.add_child(viewport)
		var graph := CaptureProbe.new()
		graph.position = Vector2(0, 80)
		graph.size = Vector2(400, 240)
		viewport.add_child(graph)
		var toolbar := Button.new()
		toolbar.size = Vector2(400, 60)
		viewport.add_child(toolbar)
		var clicks := [0]
		toolbar.pressed.connect(func(): clicks[0] += 1)
		await _settle()
		var press := InputEventMouseButton.new()
		press.button_index = button
		press.pressed = true
		press.position = Vector2(100, 180)
		viewport.push_input(press, true)
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(100, 30)
		motion.button_mask = 1 << (int(button) - 1)
		viewport.push_input(motion, true)
		var release := press.duplicate() as InputEventMouseButton
		release.pressed = false
		release.position = motion.position
		viewport.push_input(release, true)
		_expect(graph.events.size() == 3, "Sibling capture failed for mouse button %s" % button)
		_expect(clicks[0] == 0, "Graph-owned release activated sibling button")
		if graph.events.size() == 3:
			_expect((graph.events[1] as InputEventMouseMotion).position.y < 0, "Captured motion did not retain graph-local coordinates outside canvas")
		graph.events.clear()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = Vector2(100, 30)
		release.button_index = MOUSE_BUTTON_LEFT
		viewport.push_input(press, true)
		viewport.push_input(release, true)
		_expect(graph.events.is_empty() and clicks[0] == 1, "Sibling button did not own its own interaction")
		viewport.free()


func _test_graph_dimensions() -> void:
	var editor := EasingCurveEditor.new()
	root.add_child(editor)
	editor.setup_zoom_row()
	for scale_value: float in [1.0, 1.5, 2.0]:
		editor._editor_scale = scale_value
		for width: float in [150.0, 179.0, 180.0, 181.0, 220.0, 359.0, 360.0, 361.0, 600.0]:
			editor.size.x = (width + 8.0) * scale_value
			editor._update_layout()
			await _settle()
			var graph := editor._get_graph_view_rect()
			var expected := Vector2(width, clampf(180.0, width / 2.0, width)) * scale_value
			_expect(graph.size.is_equal_approx(expected), "Canonical graph size applied padding or scale twice")
			_expect(graph.size.x >= graph.size.y and graph.size.x <= graph.size.y * 2.0, "Graph aspect escaped 1:1 to 2:1")
			var shown_height := editor.get_combined_minimum_size().y
			editor._point_toolbar_panel.hide()
			await _settle()
			_expect(editor._get_graph_view_rect().size == graph.size, "Toolbar visibility changed fixed-width graph dimensions")
			_expect(editor.get_combined_minimum_size().y < shown_height, "Hidden toolbar retained persistent height")
			editor._point_toolbar_panel.show()
			await _settle()
			_expect(editor.get_combined_minimum_size().x == 64.0 * scale_value, "Graph height preference raised horizontal minimum")
			_expect(editor._point_toolbar_panel.get_rect().end.y <= editor._graph_canvas.position.y, "Point controls overlap graph")
			_expect(editor._graph_canvas.get_rect().end.y <= editor._zoom_row.position.y, "Zoom controls overlap graph")
	editor.free()

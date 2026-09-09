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
	await _characterize_grouped_flow()
	await _test_sibling_capture()
	await _test_graph_dimensions()
	_finish("curve layout contract")


func _settle() -> void:
	for frame in range(5):
		await process_frame


func _characterize_grouped_flow() -> void:
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
		await _settle()
		var baseline_width := presentation.get_combined_minimum_size().x
		var flow := HFlowContainer.new()
		root.add_child(flow)
		editor._point_reorder_buttons.reparent(flow)
		editor._point_handle_mode.reparent(flow)
		for pair: Array in [[editor._point_left_state_label, editor._point_left_state], [editor._point_right_state_label, editor._point_right_state]]:
			var group := HBoxContainer.new()
			flow.add_child(group)
			for control: Control in pair:
				control.reparent(group)
		editor._point_reset_button.reparent(flow)
		editor._point_reset_button.show()
		var largest_width := 0.0
		for group: Control in flow.get_children():
			largest_width = maxf(largest_width, group.get_combined_minimum_size().x)
		for width: float in [150.0, 220.0, 360.0, 600.0, 220.0]:
			flow.size = Vector2(width, 1.0)
			await _settle()
			var positions: Array[Vector2] = []
			for group: Control in flow.get_children():
				positions.append(group.position)
			await _settle()
			for index in range(flow.get_child_count()):
				_expect(flow.get_child(index).position == positions[index], "Native flow layout did not settle")
		_expect(flow.get_combined_minimum_size().x >= largest_width, "Flow minimum did not include largest actual group")
		print("FLOW_GATE backend=%s presentation_min=%s graph_min=%s flow_min=%s largest_group=%s" % ["native" if native else "legacy", baseline_width, editor.get_combined_minimum_size().x, flow.get_combined_minimum_size().x, largest_width])
		# Probe whether adding the candidate can raise the existing presentation minimum.
		flow.reparent(presentation)
		await _settle()
		print("FLOW_GATE wrapped_presentation_min=%s baseline=%s" % [presentation.get_combined_minimum_size().x, baseline_width])
		_expect(presentation.get_combined_minimum_size().x == baseline_width, "Grouped flow raised the presentation minimum")
		for scale_value: float in [1.0, 1.5, 2.0]:
			var theme := Theme.new()
			theme.default_font_size = roundi(16.0 * scale_value)
			presentation.theme = theme
			flow.reparent(root)
			await _settle()
			var reference_width := presentation.get_combined_minimum_size().x
			flow.reparent(presentation)
			await _settle()
			_expect(presentation.get_combined_minimum_size().x == reference_width, "Scaled grouped flow raised the presentation minimum")
			print("FLOW_SCALE scale=%s presentation_min=%s flow_min=%s" % [scale_value, reference_width, flow.get_combined_minimum_size().x])
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
	editor.setup_zoom_overlay()
	for scale_value: float in [1.0, 1.5, 2.0]:
		editor._editor_scale = scale_value
		for width: float in [150.0, 179.0, 180.0, 181.0, 220.0, 359.0, 360.0, 361.0, 600.0]:
			editor.size.x = (width + 8.0) * scale_value
			editor._update_overlay_layout()
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
			_expect(editor._graph_canvas.get_rect().end.y <= editor._zoom_overlay.position.y, "Zoom controls overlap graph")
	editor.free()

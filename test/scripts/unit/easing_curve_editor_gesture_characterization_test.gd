extends "res://test/scripts/support/test_case.gd"

const EDITOR_HOST = preload("res://test/scripts/support/editor_host_test_harness.gd")
const EDITOR_DRIVER = preload("res://test/scripts/support/easing_curve_editor_test_driver.gd")
const ZOOM_SLIDER = preload("res://addons/easing_curve/scripts/editor/widgets/zoom_slider_container.tscn")

func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("easing_curve_editor_gesture_characterization_test.gd"):
		quit(1)
		return
	call_deferred(&"_run")


func _run() -> void:
	await _test_overlay_section_geometry()
	await _test_overlay_gesture_ownership()
	await _test_overlay_input_routing()
	await _test_overlay_resize_and_theme()
	await _test_autofit_avoids_overlays()
	await _test_autofit_limits_overlay_shrinkage()
	_test_zoom_metadata_contract()
	_test_loaded_resource_initial_autofit_gate()
	_test_view_state_update_ownership()
	_test_view_state_restore_and_rebuild_order()
	await _test_autofit_request_lifecycle()
	await _test_autofit_waits_for_function_toolbar_layout()
	await _test_automatic_autofit_suppresses_intermediate_render()
	await _test_folded_curve_editor_defers_autofit_until_expand()
	_test_zoom_behavioral_invariants()
	await _test_zoom_slider_wheel_scope()
	_test_bezier_draw_clipping_and_tessellation()
	_test_pending_add_cancel_and_no_op_release()
	_test_modifier_capable_drag_baseline()
	_test_point_axis_constraint_behavior()
	_test_handle_axis_constraint_behavior()
	_test_preheld_shift_drag_constraints()
	_test_shift_reference_recapture()
	_test_snapped_shift_cursor_reference()
	_test_axis_constraint_downstream_control_semantics()
	_test_axis_constraint_view_and_order_geometry()
	_test_axis_constraint_request_and_input_boundaries()
	await _test_inspector_input_transaction_finish_boundaries()
	_test_point_and_control_drag_boundaries()
	_test_zoom_and_pan_interactions()
	_finish("graph gesture characterization")


func _test_overlay_section_geometry() -> void:
	var measurements: Array[Dictionary] = []
	for native: bool in [false, true]:
		for function_mode: bool in [false, true]:
			for width: float in [320.0, 450.0, 700.0]:
				var curve: Resource
				if native:
					curve = ClassDB.instantiate(&"NativeEasingCurve")
					curve.set(&"transition", 6 if function_mode else 100)
				else:
					var legacy := EasingCurve.new()
					legacy.trans_type = EasingCurve.TRANS.ELASTIC if function_mode else EasingCurve.TRANS.CUSTOM
					curve = legacy
				var inspector := EDITOR_HOST.INSPECTOR_PLUGIN.new()
				var content := inspector.handle_easing_curve_editor(curve)
				var viewport := SubViewport.new()
				viewport.size = Vector2i(1000, 1000)
				root.add_child(viewport)
				viewport.add_child(content)
				content.size = Vector2(width, 0)
				for frame in range(6):
					await process_frame
				var editor := inspector.easing_curve_editor
				var graph_content := editor.get_parent() as VBoxContainer
				var zoom_row := editor._slider.get_parent() as HBoxContainer
				var separation := graph_content.get_theme_constant(&"separation")
				var graph_rect := editor._get_graph_view_rect()
				var measurement := {
					"native": native, "function": function_mode, "width": editor.size.x,
					"scale": editor._editor_scale,
					"outer_height": inspector._curve_editor_section.size.y,
					"content_height": graph_content.size.y, "editor_height": editor.size.y,
					"graph_height": graph_rect.size.y, "top_reservation": graph_rect.position.y - 4.0 * editor._editor_scale,
					"zoom_minimum": zoom_row.get_combined_minimum_size().y, "separation": separation,
				}
				measurements.append(measurement)
				print("OVERLAY_LAYOUT: ", JSON.stringify(measurement))
				# Recorded before migration, for both backends and both modes at 1x.
				var old_heights := {320.0: Vector3(270, 212, 109), 450.0: Vector3(330, 272, 169), 700.0: Vector3(446, 388, 285)}
				var baseline: Vector3 = old_heights[width]
				if is_equal_approx(editor._editor_scale, 1.0):
					_expect(absf(inspector._curve_editor_section.size.y - baseline.x) <= 1.0, "Overlay migration changed the measured outer section height")
					_expect(absf(editor.size.y - baseline.y - 34.0) <= 1.0, "Zoom row height was not transferred to the graph")
					var old_graph_height := baseline.y - 8.0 if function_mode else baseline.z
					_expect(graph_rect.size.y > old_graph_height + 33.0, "Overlay migration did not recover graph height")
				_expect(is_equal_approx(graph_content.size.y, editor.size.y), "An external row still reserves graph section height")
				_expect(is_zero_approx(graph_rect.position.y - 4.0 * editor._editor_scale), "Graph still reserves top overlay height")
				var zoom_before := editor._slider
				var minimum_before := editor.get_combined_minimum_size()
				editor.setup_zoom_overlay()
				_expect(editor._slider == zoom_before and editor.get_combined_minimum_size() == minimum_before, "Repeated overlay setup changed controls or height")
				_expect(editor._slider.slider_changed.get_connections().size() == 1 and editor._slider.autofit_pressed.get_connections().size() == 1, "Repeated overlay setup duplicated callbacks")
				editor.autofit()
				var fit := editor._get_autofit_view_rect()
				var bounds := editor._get_autofit_world_bounds()
				_expect(graph_rect.grow(0.01).has_point(editor.get_view_pos(bounds.position)) and graph_rect.grow(0.01).has_point(editor.get_view_pos(bounds.end)), "Inspector Autofit clipped Custom/Elastic bounds against canvas edges")
				if function_mode:
					_expect(is_equal_approx(fit.position.y, graph_rect.position.y), "Function Autofit reserved hidden top controls")
				if DisplayServer.get_name() != "headless":
					viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
					await RenderingServer.frame_post_draw
					var capture := viewport.get_texture().get_image().get_region(Rect2i(Vector2i.ZERO, Vector2i(ceili(content.size.x), ceili(content.size.y))))
					capture.save_png("res://test/_temp/overlay-%s-%s-%d.png" % ["native" if native else "legacy", "function" if function_mode else "custom", width])
				viewport.free()
	var output := FileAccess.open("res://test/_temp/overlay-layout.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(measurements, "\t"))


func _overlay_input_fixture(native: bool) -> Dictionary:
	var curve: Resource
	var point: Resource
	if native:
		curve = ClassDB.instantiate(&"NativeEasingCurve")
		curve.set(&"transition", 100)
		point = ClassDB.instantiate(&"NativeEasingCurvePoint")
		point.set(&"position", Vector2(0.5, 0.4))
		curve.call(&"insert_point", 1, point)
	else:
		var legacy := EasingCurve.new()
		legacy.trans_type = EasingCurve.TRANS.CUSTOM
		point = EasingCurvePoint.new(Vector2(0.5, 0.4))
		legacy.points = [EasingCurvePoint.new(Vector2.ZERO), point, EasingCurvePoint.new(Vector2.ONE)]
		curve = legacy
	point.set(&"left_control_point", Vector2(0.3, 0.3))
	point.set(&"right_control_point", Vector2(0.7, 0.6))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 800)
	root.add_child(viewport)
	var editor := EasingCurveEditor.new()
	editor.presentation_owned = true
	editor.editor_undo_redo = UndoRedo.new()
	editor.set_curve(curve)
	editor.size = Vector2(600, 360)
	viewport.add_child(editor)
	editor.setup_zoom_overlay()
	editor.selected_index = 1
	editor.update_view_transform()
	return {"viewport": viewport, "editor": editor, "point": point}


func _push_graph_input(viewport: SubViewport, event: InputEventMouse) -> void:
	event.global_position = event.position
	viewport.push_input(event, true)


func _dispose_overlay_fixture(fixture: Dictionary) -> void:
	fixture.editor.finish_active_point_edit()
	fixture.editor.editor_undo_redo.clear_history()
	fixture.viewport.free()


func _test_overlay_gesture_ownership() -> void:
	for native: bool in [false, true]:
		for gesture: String in ["point", "left", "right", "pan", "pending", "delete", "immediate"]:
			var fixture := _overlay_input_fixture(native)
			var editor: EasingCurveEditor = fixture.editor
			var viewport: SubViewport = fixture.viewport
			for frame in range(3):
				await process_frame
			var start := Vector2(250, 200)
			if gesture in ["point", "left", "right"]:
				var property := &"position" if gesture == "point" else StringName(gesture + "_control_point")
				start = editor.get_view_pos(fixture.point.get(property))
			if gesture == "immediate":
				editor.use_pending_add = false
			var button := MOUSE_BUTTON_MIDDLE if gesture == "pan" else (MOUSE_BUTTON_RIGHT if gesture == "delete" else MOUSE_BUTTON_LEFT)
			var mask := MOUSE_BUTTON_MASK_MIDDLE if gesture == "pan" else (MOUSE_BUTTON_MASK_RIGHT if gesture == "delete" else MOUSE_BUTTON_MASK_LEFT)
			_push_graph_input(viewport, _motion(start))
			_push_graph_input(viewport, _button(button, start, true))
			var expected_drag := editor.dragging_point
			var expected_control := editor.dragging_control
			var pending := editor.pending_add_point
			_expect(editor.is_panning or editor.is_right_delete_dragging or expected_drag >= 0 or pending != null, "Viewport press did not begin graph " + gesture)
			var target := editor._snap_button.get_global_rect().get_center()
			var snap_before := editor.snap_enabled
			var zoom_before := editor._zoom_step
			var slider_inputs := [0]
			editor._slider.slider.gui_input.connect(func(_event): slider_inputs[0] += 1)
			for control: Control in [editor._snap_button, editor._point_handle_mode, editor._slider.slider, editor._slider.autofit_btn]:
				target = control.get_global_rect().get_center()
				_push_graph_input(viewport, _motion(target, mask))
				_expect(editor.dragging_point == expected_drag and editor.dragging_control == expected_control and editor.pending_add_point == pending, "Control crossing stole graph " + gesture)
			_expect(slider_inputs[0] == 0 and editor._zoom_step == zoom_before, "Slider received a graph-owned drag")
			_expect(editor.dragging_point == expected_drag and editor.dragging_control == expected_control and editor.pending_add_point == pending, "Overlay stole graph " + gesture)
			if gesture == "pan":
				_expect(editor.is_panning and editor.pan_offset.is_equal_approx(target - start), "Pan stopped when crossing overlay")
			elif gesture == "delete":
				_expect(editor.is_right_delete_dragging, "Overlay cancelled RMB delete gesture")
			else:
				_expect(editor._get_drag_coordinate_position().is_finite(), "Overlay dismissed active drag readout")
				var expected_position := editor.get_world_pos(target)
				if gesture not in ["left", "right"]:
					expected_position = expected_position.clamp(Vector2.ZERO, Vector2.ONE)
				_expect(editor._get_drag_coordinate_position().is_equal_approx(expected_position), "Graph geometry stopped following the pointer over a control")
			_push_graph_input(viewport, _button(button, target, false))
			_expect(not editor.is_panning and not editor.is_right_delete_dragging and editor.dragging_point == -1 and editor.pending_add_point == null, "Release over overlay did not finish graph " + gesture)
			_expect(editor.snap_enabled == snap_before, "Graph release activated Grid Snap")
			_expect(editor._zoom_step == zoom_before, "Graph release activated Autofit")
			# A new interaction originating on the button must belong to it.
			target = editor._snap_button.get_global_rect().get_center()
			_push_graph_input(viewport, _button(MOUSE_BUTTON_LEFT, target, true))
			_push_graph_input(viewport, _button(MOUSE_BUTTON_LEFT, target, false))
			_expect(editor.snap_enabled != snap_before and editor.dragging_point == -1 and editor.pending_add_point == null, "Grid Snap did not own a fresh button click")
			_dispose_overlay_fixture(fixture)


func _test_overlay_input_routing() -> void:
	for native: bool in [false, true]:
		var fixture := _overlay_input_fixture(native)
		var editor: EasingCurveEditor = fixture.editor
		var viewport: SubViewport = fixture.viewport
		editor.selected_index = -1
		for frame in range(3):
			await process_frame
		var separator := editor._snap_button.get_parent().get_child(1) as Control
		var empty_positions: Array[Vector2] = [
			editor._point_label.get_global_rect().get_center(),
			editor._point_move_left_button.get_global_rect().get_center(),
			editor._point_handle_mode.get_global_rect().get_center(),
			separator.get_global_rect().get_center(),
			Vector2(450, editor._snap_button.get_global_rect().get_center().y),
			Vector2(100, editor._slider.get_global_rect().get_center().y),
		]
		for position: Vector2 in empty_positions:
			_push_graph_input(viewport, _motion(position))
			_push_graph_input(viewport, _button(MOUSE_BUTTON_MIDDLE, position, true))
			_expect(editor.is_panning, "Empty overlay space blocked a graph press")
			_push_graph_input(viewport, _motion(position + Vector2(3, 4), MOUSE_BUTTON_MASK_MIDDLE))
			_push_graph_input(viewport, _button(MOUSE_BUTTON_MIDDLE, position + Vector2(3, 4), false))
			_expect(not editor.is_panning, "Empty overlay space blocked graph release")
			editor.pan_offset = Vector2.ZERO
			var zoom_before := editor._zoom_step
			_push_graph_input(viewport, _button(MOUSE_BUTTON_WHEEL_UP, position, true))
			_expect(editor._zoom_step == zoom_before, "Plain wheel in empty overlay space zoomed graph")
			var world_before := editor.get_world_pos(position)
			_push_graph_input(viewport, _button(MOUSE_BUTTON_WHEEL_UP, position, true, false, true))
			_expect(editor._zoom_step == zoom_before + 1 and editor.get_world_pos(position).is_equal_approx(world_before), "Empty overlay space blocked pointer-anchored zoom")
			_push_graph_input(viewport, _button(MOUSE_BUTTON_LEFT, position, true))
			_expect(editor.pending_add_point != null, "Empty overlay space blocked pending point addition")
			_push_graph_input(viewport, _button(MOUSE_BUTTON_RIGHT, position, true))
			_push_graph_input(viewport, _button(MOUSE_BUTTON_RIGHT, position, false))
			_push_graph_input(viewport, _button(MOUSE_BUTTON_LEFT, position, false))
			_expect(editor.pending_add_point == null, "Pending addition could not be cancelled in empty overlay space")
		# Numeric control and slider own presses; their parents and gaps do not.
		editor.snap_enabled = true
		await process_frame
		await process_frame
		for control: Control in [editor._snap_count_input, editor._slider.slider]:
			var position := control.get_global_rect().get_center()
			_push_graph_input(viewport, _motion(position))
			var hovered := viewport.gui_get_hovered_control()
			_expect(hovered == control or (hovered != null and control.is_ancestor_of(hovered)), "Viewport did not target the overlay field")
			_push_graph_input(viewport, _button(MOUSE_BUTTON_LEFT, position, true))
			_push_graph_input(viewport, _button(MOUSE_BUTTON_LEFT, position, false))
			_expect(editor.pending_add_point == null and editor.dragging_point == -1, "Overlay field click reached graph editing")
		var slider_position := editor._slider.slider.get_global_rect().get_center()
		editor.set_slider_value(4)
		_push_graph_input(viewport, _button(MOUSE_BUTTON_WHEEL_UP, slider_position, true))
		_expect(editor._zoom_step == 5, "Plain wheel over embedded slider did not zoom")
		_dispose_overlay_fixture(fixture)
		# EditorSpinSlider can open a text-entry popup, so verify a fresh Autofit
		# click in its own viewport rather than clicking through that popup.
		fixture = _overlay_input_fixture(native)
		editor = fixture.editor
		viewport = fixture.viewport
		for frame in range(3):
			await process_frame
		editor.set_slider_value(4)
		var fit_position := editor._slider.autofit_btn.get_global_rect().get_center()
		_push_graph_input(viewport, _motion(fit_position))
		_push_graph_input(viewport, _button(MOUSE_BUTTON_LEFT, fit_position, true))
		_push_graph_input(viewport, _button(MOUSE_BUTTON_LEFT, fit_position, false))
		var fitted_step := editor._zoom_step
		var fitted_pan := editor.pan_offset
		editor.autofit()
		_expect(editor._zoom_step == fitted_step and editor.pan_offset.is_equal_approx(fitted_pan) and editor.dragging_point == -1 and editor.pending_add_point == null, "Fresh Autofit click did not belong to the overlay")
		_dispose_overlay_fixture(fixture)


func _test_overlay_resize_and_theme() -> void:
	for native: bool in [false, true]:
		var fixture := _overlay_input_fixture(native)
		var editor: EasingCurveEditor = fixture.editor
		for scale_value: float in [1.0, 1.5, 2.0]:
			editor._editor_scale = scale_value
			var theme := Theme.new()
			theme.set_font_size(&"font_size", &"Label", roundi(16 * scale_value))
			theme.set_font_size(&"font_size", &"Button", roundi(16 * scale_value))
			editor.theme = theme
			for logical_width: float in [320.0, 450.0, 700.0]:
				editor.size = Vector2(logical_width, 360) * scale_value
				for frame in range(4):
					await process_frame
				var inset := 8.0 * scale_value
				var top := editor._point_toolbar_panel.get_rect()
				var bottom := editor._zoom_overlay.get_rect()
				_expect(top.position.is_equal_approx(Vector2.ONE * inset), "Top overlay lost logical insets after resize/theme change")
				_expect(is_equal_approx(top.end.x, editor.size.x - inset), "Top overlay width did not follow resize")
				_expect(is_equal_approx(bottom.position.x, inset) and is_equal_approx(bottom.end.x, editor.size.x - inset) and is_equal_approx(bottom.end.y, editor.size.y - inset), "Bottom overlay lost logical insets after resize/theme change")
				_expect(is_equal_approx(bottom.size.y, editor._zoom_overlay.get_combined_minimum_size().y), "Bottom overlay height ignored widget minimum size")
				var graph := editor._get_graph_view_rect()
				var canvas_size := Vector2(editor.size.x, minf(editor.size.x, editor.size.y))
				_expect(graph.is_equal_approx(Rect2(Vector2.ONE * 4.0 * scale_value, canvas_size - Vector2.ONE * 8.0 * scale_value)), "Scaled graph lost its edge margins or square height cap")
				_expect(graph.size.y <= graph.size.x and editor.get_combined_minimum_size().y <= editor.size.x, "Graph became taller than wide")
				var minimum := editor.get_combined_minimum_size()
				editor.selected_index = -1
				editor._point_toolbar_panel.hide()
				_expect(editor._get_graph_view_rect() == graph and editor.get_combined_minimum_size() == minimum, "Hidden top controls changed graph or section height")
				_expect(is_equal_approx(editor._get_coordinate_minimum_y(), 4.0 * scale_value), "Hidden top controls retained the readout clamp")
				editor._point_toolbar_panel.show()
				editor.selected_index = 1
		# A taller numeric field must participate in the top clamp independently
		# of the Snap button; changing only chrome must not change the viewport.
		editor.snap_enabled = true
		editor._snap_count_input.custom_minimum_size.y = 100
		for frame in range(4):
			await process_frame
		var graph_before := editor._get_graph_view_rect()
		var count_bottom := editor._snap_count_input.get_global_rect().end.y
		_expect(editor._get_coordinate_minimum_y() >= count_bottom + 8.0 * editor._editor_scale, "Readout clamp ignored the numeric Snap field")
		editor._point_toolbar_panel.add_theme_constant_override(&"separation", 10)
		for frame in range(4):
			await process_frame
		_expect(editor._get_graph_view_rect() == graph_before, "Toolbar-only relayout changed graph coordinates")
		_dispose_overlay_fixture(fixture)


func _test_autofit_avoids_overlays() -> void:
	for native: bool in [false, true]:
		var fixture := _overlay_input_fixture(native)
		var editor: EasingCurveEditor = fixture.editor
		# Fit bounds must continue to include handles outside the reference box.
		fixture.point.set(&"left_control_point", Vector2(0.15, -0.25))
		fixture.point.set(&"right_control_point", Vector2(0.85, 1.25))
		for scale_value: float in [1.0, 1.5, 2.0]:
			editor._editor_scale = scale_value
			for width: float in [320.0, 450.0, 700.0]:
				editor.size = Vector2(width, width * 0.8) * scale_value
				for frame in range(4):
					await process_frame
				var graph := editor._get_graph_view_rect()
				editor.autofit()
				var fit := editor._get_autofit_view_rect()
				_expect(fit.position.y >= editor._snap_button.get_global_rect().end.y + 8.0 * scale_value, "Autofit ignored visible top controls")
				_expect(fit.end.y <= editor._zoom_overlay.position.y - 8.0 * scale_value, "Autofit ignored the zoom overlay")
				var bounds := editor._get_autofit_world_bounds()
				for world: Vector2 in [bounds.position, bounds.end, Vector2(bounds.position.x, bounds.end.y), Vector2(bounds.end.x, bounds.position.y)]:
					_expect(graph.grow(0.01).has_point(editor.get_view_pos(world)), "Autofit left curve or handle bounds outside the canvas")
				_expect(editor.get_view_pos(bounds.get_center()).is_equal_approx(fit.get_center()), "Autofit did not center in the clear area")
				var pan := editor.pan_offset
				var step := editor._zoom_step
				editor.autofit()
				_expect(editor.pan_offset.is_equal_approx(pan) and editor._zoom_step == step, "Repeated Autofit drifted")
				editor.pan_offset += Vector2(0, -fit.position.y)
				_expect(editor.get_view_pos(bounds.get_center()).y < fit.get_center().y and editor._get_graph_view_rect() == graph, "Preferred fit area constrained manual pan or graph geometry")
				var pointer := editor._snap_button.get_global_rect().get_center()
				var world_before := editor.get_world_pos(pointer)
				editor._zoom_at_view_pos(1, pointer)
				_expect(editor.get_world_pos(pointer).is_equal_approx(world_before), "Preferred fit area broke pointer-anchored zoom under controls")
		# Actual minimum size changes must affect the preference, not the canvas.
		editor.snap_enabled = true
		editor._snap_count_input.custom_minimum_size.y = 100
		for frame in range(4):
			await process_frame
		_expect(editor._get_autofit_view_rect().position.y >= editor._snap_count_input.get_global_rect().end.y + 8.0 * editor._editor_scale, "Autofit ignored the taller Snap field")
		editor._point_toolbar_panel.hide()
		_expect(is_equal_approx(editor._get_autofit_view_rect().position.y, editor._get_graph_view_rect().position.y), "Hidden top controls still reduced Autofit space")
		editor._zoom_overlay.hide()
		_expect(editor._get_autofit_view_rect() == editor._get_graph_view_rect(), "Hidden overlays still reduced Autofit space")
		editor._point_toolbar_panel.show()
		editor._zoom_overlay.show()
		editor._snap_count_input.custom_minimum_size.y = editor.size.y * 2.0
		for frame in range(4):
			await process_frame
		_expect(editor._get_autofit_view_rect() == editor._get_graph_view_rect(), "Controls filling the canvas did not fall back to a usable Autofit")
		editor.autofit()
		_expect(editor.pan_offset.is_finite(), "Crowded Autofit produced invalid coordinates")
		_dispose_overlay_fixture(fixture)


func _test_autofit_limits_overlay_shrinkage() -> void:
	for native: bool in [false, true]:
		var fixture := _overlay_input_fixture(native)
		var editor: EasingCurveEditor = fixture.editor
		# Match the narrow Inspector and flat curve from the reported regression.
		for index in range(editor._point_count()):
			var point := editor._point(index)
			var position: Vector2 = point.get(&"position")
			position.y = 1.0
			point.set(&"position", position)
			point.set(&"left_control_point", position)
			point.set(&"right_control_point", position)
		editor.size = Vector2(400, 280)
		for frame in range(4):
			await process_frame
		var graph := editor._get_graph_view_rect()
		editor._point_toolbar_panel.hide()
		editor._zoom_overlay.hide()
		editor.autofit()
		var full_step := editor._zoom_step
		editor._point_toolbar_panel.show()
		editor._zoom_overlay.show()
		editor.autofit()
		_expect(editor._zoom_step == full_step - 2, "Narrow Inspector Autofit did not retain the requested larger framing")
		var plot_width := absf(editor.get_view_pos(Vector2.ONE).x - editor.get_view_pos(Vector2(0, 1)).x)
		_expect(plot_width >= graph.size.x * 0.60, "Overlay avoidance shrank the reference plot below 60 percent of canvas width")
		_expect(editor._zoom_step < full_step, "Autofit stopped considering visible controls")
		# A tall Snap field may push the preferred center down, but must neither
		# force more zoom-out nor push the fitted bounds past the canvas edge.
		editor.snap_enabled = true
		editor._snap_count_input.custom_minimum_size.y = 150
		for frame in range(4):
			await process_frame
		editor.autofit()
		_expect(editor._zoom_step >= full_step - 2, "Taller controls exceeded the overlay zoom penalty")
		var bounds := editor._get_autofit_world_bounds()
		_expect(graph.grow(0.01).has_point(editor.get_view_pos(bounds.position)) and graph.grow(0.01).has_point(editor.get_view_pos(bounds.end)), "Preferred center pushed a larger fit outside the graph")
		var pan := editor.pan_offset
		editor.autofit()
		_expect(editor.pan_offset.is_equal_approx(pan), "Soft overlay fitting drifted on repeat")
		_dispose_overlay_fixture(fixture)


func _fixture() -> Dictionary:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [
		EasingCurvePoint.new(Vector2(0.1, 0.1)),
		EasingCurvePoint.new(Vector2(0.5, 0.5)),
		EasingCurvePoint.new(Vector2(0.9, 0.9)),
	]
	curve.points[1].left_control_point = Vector2(0.4, 0.3)
	curve.points[1].right_control_point = Vector2(0.6, 0.7)
	var context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = context.editor
	var inspector: Object = context.inspector
	EDITOR_DRIVER.connect_curve_editor(editor, inspector)
	editor._slider = ZOOM_SLIDER.instantiate()
	editor.update_view_transform()
	return {"curve": curve, "editor": editor, "inspector": inspector}


func _button(
	button: MouseButton,
	position: Vector2,
	pressed: bool,
	shift_pressed := false,
	command_or_control_pressed := false,
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	if command_or_control_pressed:
		if OS.get_name() == "macOS":
			event.meta_pressed = true
		else:
			event.ctrl_pressed = true
	return event


func _motion(
	position: Vector2,
	buttons := 0,
	shift_pressed := false,
) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = buttons
	event.shift_pressed = shift_pressed
	return event


func _point_view(editor: EasingCurveEditor, point: EasingCurvePoint) -> Vector2:
	return editor.get_view_pos(point.position)


func _view_state(curve: EasingCurve) -> Dictionary:
	return curve._get_curve_editor_view_state()


func _handles_are_opposite_in_display_space(point: EasingCurvePoint) -> bool:
	var left_delta := (point.left_control_point - point.position) * point.handle_display_scale
	var right_delta := (point.right_control_point - point.position) * point.handle_display_scale
	if left_delta.is_zero_approx() or right_delta.is_zero_approx():
		return false
	return left_delta.normalized().is_equal_approx(-right_delta.normalized())


func _test_zoom_metadata_contract() -> void:
	_expect(EasingCurve.ZOOM_MIN == 0.1, "EasingCurve ZOOM_MIN changed")
	_expect(EasingCurve.ZOOM_MAX == 10.0, "EasingCurve ZOOM_MAX changed")
	_expect(EasingCurve.ZOOM_FACTOR == 1.2, "EasingCurve ZOOM_FACTOR changed")
	_expect(EasingCurve.ZOOM_STEPS == 25, "EasingCurve ZOOM_STEPS changed")
	_expect(EasingCurve.DEFAULT_SLIDER_VALUE == 12.0, "EasingCurve DEFAULT_SLIDER_VALUE changed")

	for value_pair in [
		[EasingCurveEditor.ZOOM_MIN, EasingCurveZoomSliderContainer.ZOOM_MIN],
		[EasingCurveEditor.ZOOM_MAX, EasingCurveZoomSliderContainer.ZOOM_MAX],
		[EasingCurveEditor.ZOOM_FACTOR, EasingCurveZoomSliderContainer.ZOOM_FACTOR],
		[EasingCurveEditor.ZOOM_STEPS, EasingCurveZoomSliderContainer.ZOOM_STEPS],
		[EasingCurveEditor.DEFAULT_SLIDER_VALUE, EasingCurveZoomSliderContainer.DEFAULT_SLIDER_VALUE],
	]:
		_expect(value_pair[0] == value_pair[1], "Editor and zoom slider zoom metadata diverged")

	_expect(EasingCurveEditor.ZOOM_MIN == EasingCurve.ZOOM_MIN, "Editor ZOOM_MIN diverged from EasingCurve")
	_expect(EasingCurveEditor.ZOOM_MAX == EasingCurve.ZOOM_MAX, "Editor ZOOM_MAX diverged from EasingCurve")
	_expect(EasingCurveEditor.ZOOM_FACTOR == EasingCurve.ZOOM_FACTOR, "Editor ZOOM_FACTOR diverged from EasingCurve")
	_expect(EasingCurveEditor.ZOOM_STEPS == EasingCurve.ZOOM_STEPS, "Editor ZOOM_STEPS diverged from EasingCurve")
	_expect(EasingCurveEditor.DEFAULT_SLIDER_VALUE == EasingCurve.DEFAULT_SLIDER_VALUE, "Editor DEFAULT_SLIDER_VALUE diverged from EasingCurve")

	_expect(
		EasingCurve.ZOOM_STEPS == int(round(log(EasingCurve.ZOOM_MAX / EasingCurve.ZOOM_MIN) / log(EasingCurve.ZOOM_FACTOR))),
		"Zoom step count no longer matches the public zoom range/factor",
	)
	_expect(
		EasingCurve.DEFAULT_SLIDER_VALUE == floor(EasingCurve.ZOOM_STEPS / 2.0),
		"Default slider value is no longer the midpoint of the zoom-step range",
	)

	var editor := EasingCurveEditor.new()
	var default_step := int(EasingCurve.DEFAULT_SLIDER_VALUE)
	_expect(is_equal_approx(editor.step_to_zoom(0), EasingCurve.ZOOM_MIN), "Zoom step zero no longer maps to ZOOM_MIN")
	_expect(editor.zoom_to_step(editor.step_to_zoom(default_step)) == default_step, "Default zoom step no longer round-trips through the zoom conversion")
	editor.free()


func _test_loaded_resource_initial_autofit_gate() -> void:
	var unsaved_curve := EasingCurve.new()
	var unsaved_context := EDITOR_HOST.create_inspector_context(unsaved_curve)
	var unsaved_editor: EasingCurveEditor = unsaved_context.editor
	var unsaved_inspector: Object = unsaved_context.inspector
	_expect(
		not bool(
			unsaved_inspector.call(
				"_consume_initial_autofit_for_loaded_resource",
				unsaved_curve,
			)
		),
		"Unsaved EasingCurve unexpectedly requested initial Autofit",
	)
	unsaved_editor.free()

	var temp_dir := "res://test/_temp"
	var temp_path := temp_dir.path_join("loaded_resource_autofit_gate.tres")
	var make_dir_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(temp_dir)
	)
	_expect(
		make_dir_error in [OK, ERR_ALREADY_EXISTS],
		"Could not create temp directory for loaded-resource Autofit characterization",
	)
	var saved_curve := EasingCurve.new()
	var save_error := ResourceSaver.save(saved_curve, temp_path)
	_expect(save_error == OK, "Could not save EasingCurve Autofit characterization resource")
	var loaded_curve := ResourceLoader.load(
		temp_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE,
	) as EasingCurve
	_expect(loaded_curve != null, "Could not reload saved EasingCurve Autofit characterization resource")
	if loaded_curve != null:
		var loaded_context := EDITOR_HOST.create_inspector_context(loaded_curve)
		var loaded_editor: EasingCurveEditor = loaded_context.editor
		var loaded_inspector: Object = loaded_context.inspector
		_expect(
			bool(
				loaded_inspector.call(
					"_consume_initial_autofit_for_loaded_resource",
					loaded_curve,
				)
			),
			"First Inspector load of a saved EasingCurve did not request Autofit",
		)
		_expect(
			not bool(
				loaded_inspector.call(
					"_consume_initial_autofit_for_loaded_resource",
					loaded_curve,
				)
			),
			"Inspector rebuild requested Autofit twice for the same loaded EasingCurve instance",
		)
		loaded_editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))


func _test_view_state_update_ownership() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var inspector := EDITOR_HOST.INSPECTOR_PLUGIN.new()
	var content := EDITOR_DRIVER.create_curve_editor(inspector, curve)
	get_root().add_child(content)
	var editor := EDITOR_DRIVER.curve_editor(inspector)
	editor.size = Vector2(600.0, 300.0)
	editor.update_view_transform()

	var zoom_step_before := editor._zoom_step
	var zoom_anchor := Vector2(220.0, 140.0)
	editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, zoom_anchor, true, false, true))
	var expected_step := mini(zoom_step_before + 1, EasingCurve.ZOOM_STEPS)
	var expected_zoom := editor.step_to_zoom(expected_step)
	var view_state := _view_state(curve)
	_expect(
		int(view_state[EasingCurve.CURVE_EDITOR_VIEW_SLIDER_VALUE]) == expected_step,
		"Wheel zoom did not update the owning EasingCurve slider view state",
	)
	_expect(
		(view_state[EasingCurve.CURVE_EDITOR_VIEW_ZOOM] as Vector2).is_equal_approx(
			Vector2(expected_zoom, expected_zoom)
		),
		"Wheel zoom did not update the owning EasingCurve zoom view state",
	)
	_expect(
		(view_state[EasingCurve.CURVE_EDITOR_VIEW_PAN] as Vector2).is_equal_approx(
			editor.pan_offset
		),
		"Pointer-anchored wheel zoom did not publish its pan adjustment to the owning EasingCurve",
	)

	var pan_before := editor.pan_offset
	var pan_start := Vector2(100.0, 100.0)
	var pan_end := Vector2(132.0, 119.0)
	editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, pan_start, true))
	editor._gui_input(_motion(pan_end, MOUSE_BUTTON_MASK_MIDDLE))
	editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, pan_end, false))
	view_state = _view_state(curve)
	var stored_pan: Vector2 = view_state[EasingCurve.CURVE_EDITOR_VIEW_PAN]
	_expect(
		stored_pan.is_equal_approx(pan_before + (pan_end - pan_start))
		and stored_pan.is_equal_approx(editor.pan_offset),
		"Middle-mouse pan did not update the owning EasingCurve pan view state",
	)

	var other_curve := EasingCurve.new()
	var other_view_state := _view_state(other_curve)
	_expect(
		is_equal_approx(
			float(other_view_state[EasingCurve.CURVE_EDITOR_VIEW_SLIDER_VALUE]),
			EasingCurve.DEFAULT_SLIDER_VALUE,
		)
		and other_view_state[EasingCurve.CURVE_EDITOR_VIEW_ZOOM] == Vector2.ONE
		and other_view_state[EasingCurve.CURVE_EDITOR_VIEW_PAN] == Vector2.ZERO,
		"Graph navigation state leaked from one EasingCurve resource to another",
	)

	get_root().remove_child(content)
	content.free()


func _test_view_state_restore_and_rebuild_order() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var saved_step := mini(
		int(EasingCurve.DEFAULT_SLIDER_VALUE) + 3,
		EasingCurve.ZOOM_STEPS,
	)
	var pre_slider_zoom := Vector2(3.0, 2.0)
	var saved_pan := Vector2(37.0, -21.0)
	curve._on_curve_editor_slider_value_changed(saved_step)
	curve._on_curve_editor_zoom_changed(pre_slider_zoom)
	curve._on_curve_editor_pan_changed(saved_pan)

	var inspector := EDITOR_HOST.INSPECTOR_PLUGIN.new()
	var content := EDITOR_DRIVER.create_curve_editor(inspector, curve)
	get_root().add_child(content)
	var editor := EDITOR_DRIVER.curve_editor(inspector)
	var expected_zoom_value := editor.step_to_zoom(saved_step)
	var expected_zoom := Vector2(expected_zoom_value, expected_zoom_value)
	var restored_view_state := _view_state(curve)

	_expect(
		editor._zoom_step == saved_step
		and is_equal_approx(editor._zoom_x, expected_zoom_value)
		and is_equal_approx(editor._zoom_y, expected_zoom_value),
		"Inspector rebuild no longer restores zoom from the saved slider step after passive zoom restore",
	)
	var restored_zoom: Vector2 = restored_view_state[EasingCurve.CURVE_EDITOR_VIEW_ZOOM]
	_expect(
		restored_zoom.is_equal_approx(expected_zoom)
		and not restored_zoom.is_equal_approx(pre_slider_zoom),
		"Inspector slider initialization no longer re-publishes the canonical slider-derived zoom",
	)
	var restored_pan: Vector2 = restored_view_state[EasingCurve.CURVE_EDITOR_VIEW_PAN]
	_expect(
		editor.pan_offset.is_equal_approx(saved_pan)
		and restored_pan.is_equal_approx(saved_pan),
		"Inspector rebuild no longer restores pan without changing the stored pan value",
	)

	var next_step := mini(saved_step + 1, EasingCurve.ZOOM_STEPS)
	editor.set_slider_value(next_step)
	var pan_start := Vector2(140.0, 120.0)
	var pan_end := Vector2(161.0, 107.0)
	editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, pan_start, true))
	editor._gui_input(_motion(pan_end, MOUSE_BUTTON_MASK_MIDDLE))
	editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, pan_end, false))
	var persisted_view_state := _view_state(curve)
	var persisted_slider: float = persisted_view_state[
		EasingCurve.CURVE_EDITOR_VIEW_SLIDER_VALUE
	]
	var persisted_zoom: Vector2 = persisted_view_state[EasingCurve.CURVE_EDITOR_VIEW_ZOOM]
	var persisted_pan: Vector2 = persisted_view_state[EasingCurve.CURVE_EDITOR_VIEW_PAN]

	get_root().remove_child(content)
	content.free()
	var replacement_content := EDITOR_DRIVER.create_curve_editor(inspector, curve)
	get_root().add_child(replacement_content)
	var replacement_editor := EDITOR_DRIVER.curve_editor(inspector)

	_expect(
		is_equal_approx(replacement_editor._zoom_step, persisted_slider)
		and Vector2(replacement_editor._zoom_x, replacement_editor._zoom_y).is_equal_approx(
			persisted_zoom
		),
		"Inspector rebuild did not restore the same resource's in-session slider/zoom state",
	)
	_expect(
		replacement_editor.pan_offset.is_equal_approx(persisted_pan),
		"Inspector rebuild did not restore the same resource's in-session pan state",
	)

	get_root().remove_child(replacement_content)
	replacement_content.free()


func _test_autofit_waits_for_function_toolbar_layout() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var inspector := EDITOR_HOST.INSPECTOR_PLUGIN.new()
	var content := EDITOR_DRIVER.create_curve_editor(inspector, curve)
	get_root().add_child(content)
	var editor := EDITOR_DRIVER.curve_editor(inspector)
	editor.size = Vector2(600.0, 300.0)
	await process_frame
	_expect(editor.is_autofit_ready(), "Inspector curve editor was not ready for Autofit after setup")

	curve.trans_type = EasingCurve.TRANS.ELASTIC
	editor.size = Vector2(600.0, 300.0)
	EDITOR_DRIVER.request_autofit(inspector)
	await process_frame
	await process_frame
	await process_frame

	var toolbar_panel: VBoxContainer = editor.get("_point_toolbar_panel")
	_expect(
		toolbar_panel.visible != editor.hide_selection_toolbar_for_functions,
		"Function preset toolbar visibility did not match the production hide-selection-toolbar setting before Autofit",
	)
	var fitted_step := editor._zoom_step
	var fitted_pan := editor.pan_offset
	editor.autofit()
	_expect(
		editor._zoom_step == fitted_step,
		"Second Autofit changed the Function preset zoom after layout settled",
	)
	_expect(
		editor.pan_offset.is_equal_approx(fitted_pan),
		"Second Autofit shifted the Function preset after layout settled",
	)

	get_root().remove_child(content)
	content.free()


func _test_autofit_request_lifecycle() -> void:
	var missing_slider_context := EDITOR_HOST.create_inspector_context(EasingCurve.new())
	var missing_slider_editor: EasingCurveEditor = missing_slider_context.editor
	var missing_slider_inspector: Object = missing_slider_context.inspector
	_expect(
		not missing_slider_editor.is_autofit_ready(),
		"Curve editor without a slider unexpectedly reported Autofit readiness",
	)
	missing_slider_inspector.call("_queue_autofit_curve_editor")
	_expect(
		bool(missing_slider_inspector.call("_is_autofit_pending"))
		and missing_slider_editor.is_graph_render_suppressed(),
		"Autofit request did not acquire pending render suppression",
	)
	await process_frame
	await process_frame
	await process_frame
	_expect(
		not bool(missing_slider_inspector.call("_is_autofit_pending"))
		and not missing_slider_editor.is_graph_render_suppressed(),
		"Missing-slider Autofit did not cancel and release render suppression",
	)
	missing_slider_editor.free()

	var stale_context := EDITOR_HOST.create_inspector_context(EasingCurve.new())
	var stale_editor: EasingCurveEditor = stale_context.editor
	var stale_inspector: Object = stale_context.inspector
	var stale_request_id := int(stale_inspector.call("_request_autofit"))
	var current_request_id := int(stale_inspector.call("_request_autofit"))
	stale_inspector.call("_cancel_autofit", stale_request_id)
	_expect(
		bool(stale_inspector.call("_is_autofit_pending"))
		and stale_editor.is_graph_render_suppressed(),
		"Stale Autofit cancellation released the current request's suppression",
	)
	stale_inspector.call("_cancel_autofit", current_request_id)
	_expect(
		not bool(stale_inspector.call("_is_autofit_pending"))
		and not stale_editor.is_graph_render_suppressed(),
		"Current Autofit cancellation did not release render suppression",
	)
	stale_editor.free()

	var destruction_context := EDITOR_HOST.create_inspector_context(EasingCurve.new())
	var destroyed_editor: EasingCurveEditor = destruction_context.editor
	var destruction_inspector: Object = destruction_context.inspector
	destruction_inspector.call("_queue_autofit_curve_editor")
	destroyed_editor.free()
	await process_frame
	await process_frame
	await process_frame
	_expect(
		not bool(destruction_inspector.call("_is_autofit_pending")),
		"Destroyed curve editor left its Autofit request pending",
	)


func _test_automatic_autofit_suppresses_intermediate_render() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.LINEAR
	var inspector := EDITOR_HOST.INSPECTOR_PLUGIN.new()
	var initial_content := EDITOR_DRIVER.create_curve_editor(inspector, curve)
	get_root().add_child(initial_content)
	var initial_editor := EDITOR_DRIVER.curve_editor(inspector)

	inspector.call("_queue_autofit_curve_editor")
	_expect(
		initial_editor.is_graph_render_suppressed(),
		"Automatic Autofit did not suppress graph rendering immediately",
	)

	# Simulate the Inspector rebuild caused by switching to a Function preset.
	curve.trans_type = EasingCurve.TRANS.ELASTIC
	get_root().remove_child(initial_content)
	initial_content.free()
	var replacement_content := EDITOR_DRIVER.create_curve_editor(inspector, curve)
	get_root().add_child(replacement_content)
	var replacement_editor := EDITOR_DRIVER.curve_editor(inspector)
	_expect(
		replacement_editor.is_graph_render_suppressed(),
		"Inspector rebuild did not inherit pending Autofit render suppression",
	)
	var replacement_toolbar_panel: VBoxContainer = replacement_editor.get("_point_toolbar_panel")
	_expect(
		replacement_toolbar_panel.visible != replacement_editor.hide_selection_toolbar_for_functions,
		"Elastic rebuild toolbar visibility did not match the production hide-selection-toolbar setting before Autofit",
	)

	await process_frame
	_expect(
		replacement_editor.is_graph_render_suppressed(),
		"Automatic Autofit revealed the graph before the layout-settle window completed",
	)
	await process_frame
	await process_frame
	_expect(
		not replacement_editor.is_graph_render_suppressed(),
		"Automatic Autofit did not reveal the graph after fitting completed",
	)
	_expect(
		not bool(inspector.call("_is_autofit_pending")),
		"Completed automatic Autofit remained pending",
	)

	var fitted_zoom := Vector2(replacement_editor._zoom_x, replacement_editor._zoom_y)
	var fitted_pan := replacement_editor.pan_offset
	replacement_editor.autofit()
	_expect(
		Vector2(replacement_editor._zoom_x, replacement_editor._zoom_y).is_equal_approx(fitted_zoom),
		"Manual Autofit changed zoom after the automatic fitted graph was revealed",
	)
	_expect(
		replacement_editor.pan_offset.is_equal_approx(fitted_pan),
		"Manual Autofit shifted pan after the automatic fitted graph was revealed",
	)

	get_root().remove_child(replacement_content)
	replacement_content.free()


func _test_folded_curve_editor_defers_autofit_until_expand() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.LINEAR
	var inspector := EDITOR_HOST.INSPECTOR_PLUGIN.new()
	var initial_content := EDITOR_DRIVER.create_curve_editor(inspector, curve)
	get_root().add_child(initial_content)
	var initial_section: Control = inspector.get("_curve_editor_section")
	var initial_editor := EDITOR_DRIVER.curve_editor(inspector)

	initial_section.call("fold")
	await process_frame
	await process_frame
	_expect(
		bool(initial_section.get("folded")),
		"Curve Editor fixture did not fold before preset change",
	)

	inspector.call("_queue_autofit_curve_editor")
	curve.trans_type = EasingCurve.TRANS.ELASTIC

	# Simulate the Inspector rebuild caused by the preset switch while the
	# Curve Editor section remains folded.
	get_root().remove_child(initial_content)
	initial_content.free()
	var replacement_content := EDITOR_DRIVER.create_curve_editor(inspector, curve)
	get_root().add_child(replacement_content)
	var replacement_section: Control = inspector.get("_curve_editor_section")
	var replacement_editor := EDITOR_DRIVER.curve_editor(inspector)

	await process_frame
	await process_frame
	await process_frame
	_expect(
		bool(replacement_section.get("folded")),
		"Curve Editor fold state was not preserved across the Elastic rebuild",
	)
	_expect(
		bool(inspector.call("_is_autofit_pending")),
		"Automatic Autofit completed while the Curve Editor was folded",
	)
	_expect(
		replacement_editor.is_graph_render_suppressed(),
		"Folded Curve Editor revealed the graph before pending Autofit could use expanded layout",
	)

	replacement_section.call("expand")
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	_expect(
		not bool(inspector.call("_is_autofit_pending")),
		"Opening the Curve Editor did not complete the pending Autofit",
	)
	_expect(
		not replacement_editor.is_graph_render_suppressed(),
		"Curve Editor graph remained suppressed after expanded-layout Autofit",
	)

	var fitted_zoom := Vector2(replacement_editor._zoom_x, replacement_editor._zoom_y)
	var fitted_pan := replacement_editor.pan_offset
	replacement_editor.autofit()
	_expect(
		Vector2(replacement_editor._zoom_x, replacement_editor._zoom_y).is_equal_approx(fitted_zoom),
		"Manual Autofit changed zoom after folded Elastic preset was opened",
	)
	_expect(
		replacement_editor.pan_offset.is_equal_approx(fitted_pan),
		"Manual Autofit shifted pan after folded Elastic preset was opened",
	)

	get_root().remove_child(replacement_content)
	replacement_content.free()


func _test_zoom_behavioral_invariants() -> void:
	var fixture := _fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var default_step := int(EasingCurve.DEFAULT_SLIDER_VALUE)
	var default_zoom := editor.step_to_zoom(default_step)

	var default_view_state := _view_state(curve)
	_expect(
		is_equal_approx(
			float(default_view_state[EasingCurve.CURVE_EDITOR_VIEW_SLIDER_VALUE]),
			EasingCurve.DEFAULT_SLIDER_VALUE,
		),
		"New EasingCurve resource no longer starts at the canonical slider value",
	)

	editor.set_slider_value(default_step)
	_expect(editor._zoom_step == default_step, "Applying the default slider value did not select the canonical zoom step")
	_expect(
		is_equal_approx(editor._zoom_x, default_zoom) and is_equal_approx(editor._zoom_y, default_zoom),
		"Default slider value no longer maps to the canonical zoom",
	)
	_expect(editor._slider.slider.value == default_step, "Editor and slider value diverged at the canonical zoom step")

	var slider_step := mini(default_step + 2, EasingCurve.ZOOM_STEPS)
	editor.set_slider_value(slider_step)
	var slider_zoom := editor.step_to_zoom(slider_step)
	_expect(editor._zoom_step == slider_step, "Slider-driven zoom did not update the editor zoom step")
	_expect(
		is_equal_approx(editor._zoom_x, slider_zoom) and is_equal_approx(editor._zoom_y, slider_zoom),
		"Slider-driven zoom no longer uses step_to_zoom() consistently",
	)

	editor.update_view_transform()
	var wheel_anchor := Vector2(137.0, 113.0)
	var plain_step := editor._zoom_step
	var plain_pan := editor.pan_offset
	var plain_state := _view_state(curve).duplicate(true)
	editor.selected_index = 1
	editor.dragging_point = 1
	editor.dragging_control = EasingCurveEditor.ControlIndex.RIGHT
	editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, wheel_anchor, true))
	_expect(editor._zoom_step == plain_step, "Plain graph wheel input unexpectedly changed zoom")
	_expect(editor.pan_offset == plain_pan, "Plain graph wheel input unexpectedly changed pan")
	_expect(_view_state(curve) == plain_state, "Plain graph wheel input unexpectedly changed view-state metadata")
	_expect(
		editor.selected_index == 1
		and editor.dragging_point == 1
		and editor.dragging_control == EasingCurveEditor.ControlIndex.RIGHT,
		"Plain graph wheel input changed selection or active drag state",
	)
	editor.dragging_point = -1
	editor.dragging_control = EasingCurveEditor.ControlIndex.NONE
	var world_before := editor.get_world_pos(wheel_anchor)
	var wheel_step_before := editor._zoom_step
	editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, wheel_anchor, true, false, true))
	var expected_wheel_step := mini(wheel_step_before + 1, EasingCurve.ZOOM_STEPS)
	var wheel_zoom := editor.step_to_zoom(expected_wheel_step)
	_expect(editor._zoom_step == expected_wheel_step, "Wheel zoom did not advance exactly one zoom step")
	_expect(
		is_equal_approx(editor._zoom_x, wheel_zoom) and is_equal_approx(editor._zoom_y, wheel_zoom),
		"Wheel zoom no longer uses the same step-to-zoom conversion as slider zoom",
	)
	var world_after := editor.get_world_pos(wheel_anchor)
	_expect(
		world_after.is_equal_approx(world_before),
		"Zoom around an off-center pointer no longer preserves the world point under the cursor",
	)

	editor.pan_offset = Vector2(23.0, -17.0)
	editor.set_slider_value(mini(default_step + 3, EasingCurve.ZOOM_STEPS))
	editor._on_autofit_pressed()
	_expect(editor._zoom_step == default_step, "Autofit no longer restores the canonical default zoom step")
	_expect(editor._slider.slider.value == default_step, "Autofit left the slider out of sync with the canonical default step")
	_expect(editor.pan_offset == Vector2.ZERO, "Autofit no longer clears graph pan")
	_expect(
		is_equal_approx(editor._zoom_x, default_zoom) and is_equal_approx(editor._zoom_y, default_zoom),
		"Autofit changed the canonical fit for geometry already inside the base graph",
	)

	editor.size = Vector2(600.0, 300.0)
	curve.points[1].left_control_point = Vector2(-0.6, 1.5)
	curve.points[1].right_control_point = Vector2(1.5, -0.4)
	editor.set_slider_value(mini(default_step + 3, EasingCurve.ZOOM_STEPS))
	editor.pan_offset = Vector2(47.0, -31.0)
	editor._on_autofit_pressed()
	editor.update_view_transform()
	var fit_rect := editor._get_graph_view_rect()
	for world_point in [
		Vector2(0.0, curve.min_value),
		Vector2(1.0, curve.max_value),
		curve.points[1].left_control_point,
		curve.points[1].right_control_point,
	]:
		_expect(
			fit_rect.has_point(editor.get_view_pos(world_point)),
			"Autofit left graph/control geometry outside the drawable graph rect",
		)
	_expect(
		editor._zoom_step < default_step,
		"Autofit did not zoom out for controls outside the base graph",
	)
	_expect(
		editor._slider.slider.value == editor._zoom_step,
		"Autofit left the zoom slider out of sync with the fitted zoom step",
	)

	editor._slider.free()
	editor.free()


func _test_zoom_slider_wheel_scope() -> void:
	var zoom_controls := ZOOM_SLIDER.instantiate() as EasingCurveZoomSliderContainer
	get_root().add_child(zoom_controls)
	await process_frame
	var slider := zoom_controls.slider
	var initial_value := slider.value
	zoom_controls._on_slider_gui_input(
		_button(MOUSE_BUTTON_WHEEL_UP, slider.size * 0.5, true)
	)
	_expect(
		is_equal_approx(slider.value, initial_value + slider.step),
		"Unmodified wheel input over the zoom slider did not advance one step",
	)

	slider.value = slider.max_value
	zoom_controls._on_slider_gui_input(
		_button(MOUSE_BUTTON_WHEEL_UP, slider.size * 0.5, true)
	)
	_expect(
		is_equal_approx(slider.value, slider.max_value),
		"Wheel input over the zoom slider exceeded its maximum",
	)
	slider.value = slider.min_value
	zoom_controls._on_slider_gui_input(
		_button(MOUSE_BUTTON_WHEEL_DOWN, slider.size * 0.5, true)
	)
	_expect(
		is_equal_approx(slider.value, slider.min_value),
		"Wheel input over the zoom slider exceeded its minimum",
	)

	var slider_wheel_handler := Callable(zoom_controls, &"_on_slider_gui_input")
	_expect(
		not zoom_controls.zoom_icon.gui_input.is_connected(slider_wheel_handler),
		"Zoom icon unexpectedly routes wheel input to the slider",
	)
	_expect(
		not zoom_controls.autofit_btn.gui_input.is_connected(slider_wheel_handler),
		"Autofit button unexpectedly routes wheel input to the slider",
	)
	zoom_controls.queue_free()
	await process_frame


func _test_bezier_draw_clipping_and_tessellation() -> void:
	var editor := EasingCurveEditor.new()
	editor.size = Vector2(600.0, 300.0)
	editor.update_view_transform()
	var default_bounds := editor._get_visible_world_x_bounds()
	editor.set_zoom(Vector2(10.0, 10.0))
	editor.update_view_transform()
	var zoomed_bounds := editor._get_visible_world_x_bounds()
	_expect(
		zoomed_bounds.y - zoomed_bounds.x < default_bounds.y - default_bounds.x,
		"Visible world-X clipping bounds did not narrow under horizontal zoom",
	)

	var a := EasingCurvePoint.new(Vector2.ZERO)
	var b := EasingCurvePoint.new(Vector2.ONE)
	var curved_out_control := Vector2(0.1, 1.0)
	var curved_in_control := Vector2(0.9, 0.0)
	var start_view := editor.get_view_pos(a.position)
	var end_view := editor.get_view_pos(b.position)
	var curved_polyline := PackedVector2Array([start_view])
	editor._append_adaptive_bezier_points(
		start_view,
		editor.get_view_pos(curved_out_control),
		editor.get_view_pos(curved_in_control),
		end_view,
		0,
		curved_polyline,
	)
	_expect(
		curved_polyline.size() > 2 and curved_polyline.size() < int(editor.size.x),
		"Adaptive Bézier tessellation did not reduce the curved segment below per-pixel sampling",
	)

	var straight_out_control := Vector2.ONE / 3.0
	var straight_in_control := Vector2.ONE * 2.0 / 3.0
	var straight_polyline := PackedVector2Array([start_view])
	editor._append_adaptive_bezier_points(
		start_view,
		editor.get_view_pos(straight_out_control),
		editor.get_view_pos(straight_in_control),
		end_view,
		0,
		straight_polyline,
	)
	_expect(
		straight_polyline.size() == 2,
		"Adaptive Bézier tessellation produced %d points for a straight segment"
		% straight_polyline.size(),
	)
	editor.free()


func _test_pending_add_cancel_and_no_op_release() -> void:
	var fixture := _fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var empty := Vector2(580.0, 280.0)
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, empty, true))
	_expect(editor.pending_add_point != null, "Graph press did not begin a pending add")
	editor._gui_input(_button(MOUSE_BUTTON_RIGHT, empty, true))
	_expect(editor.pending_add_point == null and not editor.is_right_delete_dragging, "RMB pending-add cancel leaked graph delete/add state")
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, empty, false))
	_expect(curve.points.size() == 3, "Canceled pending add committed on the later LMB release")

	var point_position := _point_view(editor, curve.points[1])
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_position, true))
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_position, false))
	_expect(
		not bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"No-op point click created an edit transaction",
	)
	_expect(editor.dragging_point == -1 and editor.dragging_control == EasingCurveEditor.ControlIndex.NONE, "No-op point release leaked drag state")
	editor.free()


func _test_modifier_capable_drag_baseline() -> void:
	var point_fixture := _fixture()
	var point_curve: EasingCurve = point_fixture.curve
	var point_editor: EasingCurveEditor = point_fixture.editor
	var point := point_curve.points[1]
	var point_start := _point_view(point_editor, point)
	var point_target_view := point_start + Vector2(26.0, -17.0)
	var expected_point_target := point_editor.get_world_pos(point_target_view).clamp(
		Vector2(0, point_curve.min_value),
		Vector2(1.0, point_curve.max_value),
	)
	expected_point_target.y = point.position.y
	point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_start, true, true))
	_expect(point_editor.dragging_point == 1, "Pre-held Shift prevented the ordinary point drag from starting")
	point_editor._gui_input(_motion(point_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(point.position.is_equal_approx(expected_point_target), "Pre-held Shift did not constrain the point target")
	point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_target_view, false, true))
	_expect(point_editor.dragging_point == -1, "Pre-held Shift point drag did not clear drag state on release")
	point_editor._slider.free()
	point_editor.free()

	var left_fixture := _fixture()
	var left_curve: EasingCurve = left_fixture.curve
	var left_editor: EasingCurveEditor = left_fixture.editor
	var left_point := left_curve.points[1]
	var left_start := left_editor.get_view_pos(left_point.left_control_point)
	var left_target_view := left_start + Vector2(-18.0, 12.0)
	var expected_left_target := left_editor.get_world_pos(left_target_view)
	left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, left_start, true))
	_expect(left_editor.dragging_control == EasingCurveEditor.ControlIndex.LEFT, "Ordinary left-handle drag did not start on the left control")
	left_editor._gui_input(_motion(left_target_view, MOUSE_BUTTON_MASK_LEFT))
	_expect(left_point.left_control_point.is_equal_approx(expected_left_target), "Ordinary left-handle drag no longer follows the unconstrained mouse target")
	left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, left_target_view, false))
	left_editor._slider.free()
	left_editor.free()

	var right_fixture := _fixture()
	var right_curve: EasingCurve = right_fixture.curve
	var right_editor: EasingCurveEditor = right_fixture.editor
	var right_point := right_curve.points[1]
	var right_start := right_editor.get_view_pos(right_point.right_control_point)
	var right_target_view := right_start + Vector2(18.0, -12.0)
	var expected_right_target := right_editor.get_world_pos(right_target_view)
	right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, right_start, true))
	_expect(right_editor.dragging_control == EasingCurveEditor.ControlIndex.RIGHT, "Ordinary right-handle drag did not start on the right control")
	right_editor._gui_input(_motion(right_target_view, MOUSE_BUTTON_MASK_LEFT))
	_expect(right_point.right_control_point.is_equal_approx(expected_right_target), "Ordinary right-handle drag no longer follows the unconstrained mouse target")
	right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, right_target_view, false))
	right_editor._slider.free()
	right_editor.free()


func _test_point_axis_constraint_behavior() -> void:
	var fixture := _fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var point := curve.points[1]
	var origin := point.position
	var start := _point_view(editor, point)

	editor._gui_input(_button(MOUSE_BUTTON_LEFT, start, true))
	editor._gui_input(_motion(start + Vector2(8.0, -5.0), MOUSE_BUTTON_MASK_LEFT))

	var horizontal_view := start + Vector2(54.0, 14.0)
	var horizontal_world := editor.get_world_pos(horizontal_view)
	origin = point.position
	var expected_horizontal := Vector2(horizontal_world.x, origin.y).clamp(
		Vector2(0, curve.min_value),
		Vector2(1.0, curve.max_value),
	)
	editor._gui_input(_motion(horizontal_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		point.position.is_equal_approx(expected_horizontal),
		"Mid-drag Shift did not constrain the point to the horizontal axis from the current drag position",
	)

	var vertical_view := start + Vector2(14.0, -54.0)
	var vertical_world := editor.get_world_pos(vertical_view)
	var expected_vertical := Vector2(origin.x, vertical_world.y).clamp(
		Vector2(0, curve.min_value),
		Vector2(1.0, curve.max_value),
	)
	editor._gui_input(_motion(vertical_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		point.position.is_equal_approx(expected_vertical),
		"Held Shift did not switch to the vertical axis when total view displacement became Y-dominant",
	)

	var free_view := start + Vector2(42.0, -30.0)
	var expected_free := editor.get_world_pos(free_view).clamp(
		Vector2(0, curve.min_value),
		Vector2(1.0, curve.max_value),
	)
	editor._gui_input(_motion(free_view, MOUSE_BUTTON_MASK_LEFT, false))
	_expect(
		point.position.is_equal_approx(expected_free),
		"Releasing Shift did not immediately restore ordinary unconstrained point dragging",
	)
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, free_view, false))
	_expect(editor.dragging_point == -1, "Constrained point drag did not clear drag state on release")
	editor._slider.free()
	editor.free()

	var preheld_fixture := _fixture()
	var preheld_curve: EasingCurve = preheld_fixture.curve
	var preheld_editor: EasingCurveEditor = preheld_fixture.editor
	var preheld_point := preheld_curve.points[1]
	var preheld_origin := preheld_point.position
	var preheld_start := _point_view(preheld_editor, preheld_point)
	preheld_editor._gui_input(_button(MOUSE_BUTTON_LEFT, preheld_start, true, true))

	var held_view := preheld_start + Vector2(40.0, -12.0)
	var expected_held := preheld_editor.get_world_pos(held_view).clamp(
		Vector2(0, preheld_curve.min_value),
		Vector2(1.0, preheld_curve.max_value),
	)
	expected_held.y = preheld_origin.y
	preheld_editor._gui_input(_motion(held_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		preheld_point.position.is_equal_approx(expected_held),
		"Pre-held Shift did not activate point axis constraint",
	)

	var released_shift_view := preheld_start + Vector2(45.0, -20.0)
	var expected_released_shift := preheld_editor.get_world_pos(released_shift_view).clamp(
		Vector2(0, preheld_curve.min_value),
		Vector2(1.0, preheld_curve.max_value),
	)
	preheld_editor._gui_input(_motion(released_shift_view, MOUSE_BUTTON_MASK_LEFT, false))
	_expect(
		preheld_point.position.is_equal_approx(expected_released_shift),
		"Releasing a pre-held Shift did not preserve the ordinary point drag target",
	)

	var repress_view := preheld_start + Vector2(52.0, 10.0)
	var repress_world := preheld_editor.get_world_pos(repress_view)
	var expected_repress := Vector2(preheld_point.position.x, repress_world.y).clamp(
		Vector2(0, preheld_curve.min_value),
		Vector2(1.0, preheld_curve.max_value),
	)
	preheld_editor._gui_input(_motion(repress_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		preheld_point.position.is_equal_approx(expected_repress),
		"Shift did not become eligible after a pre-held Shift was released and pressed again during the same drag",
	)
	preheld_editor._gui_input(_button(MOUSE_BUTTON_LEFT, repress_view, false, true))
	preheld_editor._slider.free()
	preheld_editor.free()


func _test_handle_axis_constraint_behavior() -> void:
	var left_fixture := _fixture()
	var left_curve: EasingCurve = left_fixture.curve
	var left_editor: EasingCurveEditor = left_fixture.editor
	var left_point := left_curve.points[1]
	var left_origin := left_point.left_control_point
	var left_start := left_editor.get_view_pos(left_origin)
	left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, left_start, true))

	var left_horizontal_view := left_start + Vector2(-52.0, 12.0)
	var left_horizontal_world := left_editor.get_world_pos(left_horizontal_view)
	var expected_left_horizontal := Vector2(left_horizontal_world.x, left_origin.y)
	left_editor._gui_input(_motion(left_horizontal_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		left_point.left_control_point.is_equal_approx(expected_left_horizontal),
		"Shift did not constrain the left handle to the horizontal axis from its original drag position",
	)

	var left_vertical_view := left_start + Vector2(-12.0, -52.0)
	var left_vertical_world := left_editor.get_world_pos(left_vertical_view)
	var expected_left_vertical := Vector2(left_origin.x, left_vertical_world.y)
	left_editor._gui_input(_motion(left_vertical_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		left_point.left_control_point.is_equal_approx(expected_left_vertical),
		"Held Shift did not constrain the left handle to the vertical axis when Y became dominant",
	)

	var left_free_view := left_start + Vector2(-30.0, -24.0)
	var expected_left_free := left_editor.get_world_pos(left_free_view)
	left_editor._gui_input(_motion(left_free_view, MOUSE_BUTTON_MASK_LEFT, false))
	_expect(
		left_point.left_control_point.is_equal_approx(expected_left_free),
		"Releasing Shift did not immediately restore ordinary unconstrained left-handle dragging",
	)
	left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, left_free_view, false))
	left_editor._slider.free()
	left_editor.free()

	var right_fixture := _fixture()
	var right_curve: EasingCurve = right_fixture.curve
	var right_editor: EasingCurveEditor = right_fixture.editor
	var right_point := right_curve.points[1]
	var right_origin := right_point.right_control_point
	var right_start := right_editor.get_view_pos(right_origin)
	right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, right_start, true))

	var right_horizontal_view := right_start + Vector2(52.0, -12.0)
	var right_horizontal_world := right_editor.get_world_pos(right_horizontal_view)
	var expected_right_horizontal := Vector2(right_horizontal_world.x, right_origin.y)
	right_editor._gui_input(_motion(right_horizontal_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		right_point.right_control_point.is_equal_approx(expected_right_horizontal),
		"Shift did not constrain the right handle to the horizontal axis from its original drag position",
	)

	var right_vertical_view := right_start + Vector2(12.0, 52.0)
	var right_vertical_world := right_editor.get_world_pos(right_vertical_view)
	var expected_right_vertical := Vector2(right_origin.x, right_vertical_world.y)
	right_editor._gui_input(_motion(right_vertical_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		right_point.right_control_point.is_equal_approx(expected_right_vertical),
		"Held Shift did not constrain the right handle to the vertical axis when Y became dominant",
	)
	right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, right_vertical_view, false, true))
	right_editor._slider.free()
	right_editor.free()


func _test_preheld_shift_drag_constraints() -> void:
	for property_name: StringName in [&"position", &"left_control_point", &"right_control_point"]:
		var fixture := _fixture()
		var editor: EasingCurveEditor = fixture.editor
		root.add_child(editor)
		editor.update_view_transform()
		var point: EasingCurvePoint = fixture.curve.points[1]
		var origin: Vector2 = point.get(property_name)
		var start := editor.get_view_pos(origin)
		var shift := InputEventKey.new()
		shift.keycode = KEY_SHIFT
		shift.pressed = true
		shift.shift_pressed = true
		Input.parse_input_event(shift)
		Input.flush_buffered_events()
		editor._gui_input(_button(MOUSE_BUTTON_LEFT, start, true, Input.is_key_pressed(KEY_SHIFT)))
		for delta: Vector2 in [Vector2(52, -12), Vector2(12, -52)]:
			var target := start + delta
			var expected := editor.get_world_pos(target)
			if absf(delta.x) > absf(delta.y):
				expected.y = origin.y
			else:
				expected.x = origin.x
			editor._gui_input(_motion(target, MOUSE_BUTTON_MASK_LEFT, Input.is_key_pressed(KEY_SHIFT)))
			_expect((point.get(property_name) as Vector2).is_equal_approx(expected), "Pre-held Shift axis constraint failed for %s at %s" % [property_name, delta])
		# Key release/repress has no intervening mouse motion to clear a latch.
		for pressed: bool in [false, true]:
			var key := InputEventKey.new()
			key.keycode = KEY_SHIFT
			key.pressed = pressed
			key.shift_pressed = pressed
			Input.parse_input_event(key)
			Input.flush_buffered_events()
		var repress_target := start + Vector2(48, -10)
		var repress_expected := editor.get_world_pos(repress_target)
		var anchor: Vector2 = point.get(property_name)
		_expect(editor._axis_drag_origin_world == anchor, "Input Shift repress did not capture current target")
		var cursor_delta := repress_target - editor._axis_drag_origin_view
		if absf(cursor_delta.x) > absf(cursor_delta.y):
			repress_expected.y = anchor.y
		else:
			repress_expected.x = anchor.x
		editor._gui_input(_motion(repress_target, MOUSE_BUTTON_MASK_LEFT, Input.is_key_pressed(KEY_SHIFT)))
		_expect((point.get(property_name) as Vector2).is_equal_approx(repress_expected), "Stationary Shift release/repress failed for %s" % property_name)
		var release := InputEventKey.new()
		release.keycode = KEY_SHIFT
		Input.parse_input_event(release)
		Input.flush_buffered_events()
		var free_target := start + Vector2(30, -24)
		editor._gui_input(_motion(free_target, MOUSE_BUTTON_MASK_LEFT, Input.is_key_pressed(KEY_SHIFT)))
		_expect((point.get(property_name) as Vector2).is_equal_approx(editor.get_world_pos(free_target)), "Shift release did not restore free dragging for %s" % property_name)
		editor._gui_input(_button(MOUSE_BUTTON_LEFT, free_target, false))
		editor._slider.free()
		editor.free()


func _test_shift_reference_recapture() -> void:
	for property_name: StringName in [&"position", &"left_control_point", &"right_control_point", &"pending"]:
		var fixture := _fixture()
		var editor: EasingCurveEditor = fixture.editor
		var curve: EasingCurve = fixture.curve
		var point := curve.points[1]
		var pending := property_name == &"pending"
		var property := &"position" if pending else property_name
		var start := editor.get_view_pos(Vector2(0.7, 0.3) if pending else point.get(property))
		editor._gui_input(_button(MOUSE_BUTTON_LEFT, start, true))
		if pending:
			point = editor.pending_add_point
		var resource_count := curve.points.size()
		for free_delta: Vector2 in [Vector2(15, -18), Vector2(35, 12)]:
			var cursor := start + free_delta
			editor._gui_input(_motion(cursor, MOUSE_BUTTON_MASK_LEFT))
			var anchor: Vector2 = point.get(property)
			# A separate cursor anchor must win even when the target is elsewhere.
			var cursor_anchor := cursor + Vector2(30, 0)
			editor._update_axis_drag_reference(true, cursor_anchor)
			_expect((point.get(property) as Vector2).is_equal_approx(anchor), "Shift capture moved %s" % property_name)
			editor._update_axis_drag_reference(true, cursor_anchor + Vector2(99, 99))
			_expect(editor._axis_drag_origin_view == cursor_anchor, "Held Shift recaptured %s" % property_name)
			var target := cursor_anchor + Vector2(2, -6)
			editor._gui_input(_motion(target, MOUSE_BUTTON_MASK_LEFT, true))
			var expected := editor.get_world_pos(target)
			expected.x = anchor.x
			_expect((point.get(property) as Vector2).is_equal_approx(expected), "Cursor-relative vertical axis or fresh target anchor failed for %s" % property_name)
			editor._update_axis_drag_reference(false, target)
			var before_repress: Vector2 = point.get(property)
			editor._update_axis_drag_reference(true, target)
			var next := target + Vector2(6, -2)
			editor._gui_input(_motion(next, MOUSE_BUTTON_MASK_LEFT, true))
			expected = editor.get_world_pos(next)
			expected.y = before_repress.y
			_expect((point.get(property) as Vector2).is_equal_approx(expected), "Stationary recapture failed for %s" % property_name)
			if pending:
				_expect(curve.points.size() == resource_count, "Pending constraint committed the preview")
			editor._update_axis_drag_reference(false, next)
		editor._gui_input(_button(MOUSE_BUTTON_LEFT, start, false))
		_expect(not editor._axis_drag_reference_active, "Release leaked axis reference for %s" % property_name)
		if pending:
			_expect(curve.points.size() == resource_count + 1, "Pending release did not commit once")
		editor._slider.free()
		editor.free()


func _test_snapped_shift_cursor_reference() -> void:
	for pending: bool in [false, true]:
		var fixture := _fixture()
		var editor: EasingCurveEditor = fixture.editor
		var point: EasingCurvePoint = fixture.curve.points[1]
		editor.snap_enabled = true
		var start := editor.get_view_pos(Vector2(0.7, 0.3) if pending else point.position)
		editor._gui_input(_button(MOUSE_BUTTON_LEFT, start, true))
		if pending:
			point = editor.pending_add_point
		var cursor := editor.get_view_pos(Vector2(0.549, 0.5))
		editor._gui_input(_motion(cursor, MOUSE_BUTTON_MASK_LEFT))
		var anchor := point.position
		_expect(anchor.is_equal_approx(Vector2(0.5, 0.5)), "Snapped Shift fixture did not establish offset")
		editor._update_axis_drag_reference(true, cursor)
		var target := cursor + Vector2(2, -18)
		var expected := editor._snap_graph_position(editor.get_world_pos(target))
		expected.x = anchor.x
		editor._gui_input(_motion(target, MOUSE_BUTTON_MASK_LEFT, true))
		_expect(point.position.is_equal_approx(expected) and not point.position.is_equal_approx(anchor), "Snapped target offset biased cursor-relative axis choice")
		editor._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		_expect(not editor._axis_drag_reference_active, "Focus loss retained Shift reference")
		editor._update_axis_drag_reference(true, target)
		_expect(editor._axis_drag_origin_world == point.position, "Focus recovery reused old target anchor")
		if pending:
			editor._cancel_pending_add()
		else:
			editor._gui_input(_button(MOUSE_BUTTON_LEFT, target, false))
		_expect(not editor._axis_drag_reference_active, "Gesture cleanup retained Shift reference")
		editor._slider.free()
		editor.free()


func _test_axis_constraint_downstream_control_semantics() -> void:
	var locked_point_fixture := _fixture()
	var locked_point_curve: EasingCurve = locked_point_fixture.curve
	var locked_point_editor: EasingCurveEditor = locked_point_fixture.editor
	var locked_point := locked_point_curve.points[1]
	var locked_point_origin := locked_point.position
	var locked_point_start := _point_view(locked_point_editor, locked_point)
	locked_point.set_locked("position", true)
	locked_point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_point_start, true))
	_expect(locked_point_editor.dragging_point == -1, "Locked point position unexpectedly started a graph drag")
	locked_point_editor._gui_input(_motion(locked_point_start + Vector2(50.0, 10.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(locked_point.position == locked_point_origin, "Shift motion moved a locked point position")
	locked_point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_point_start + Vector2(50.0, 10.0), false, true))
	locked_point_editor._slider.free()
	locked_point_editor.free()

	var locked_left_fixture := _fixture()
	var locked_left_curve: EasingCurve = locked_left_fixture.curve
	var locked_left_editor: EasingCurveEditor = locked_left_fixture.editor
	var locked_left_point := locked_left_curve.points[1]
	var locked_left_origin := locked_left_point.left_control_point
	var locked_left_start := locked_left_editor.get_view_pos(locked_left_origin)
	locked_left_point.set_locked("left_control_point", true)
	locked_left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_left_start, true))
	_expect(locked_left_editor.dragging_point == -1, "Locked left control unexpectedly started a graph drag")
	locked_left_editor._gui_input(_motion(locked_left_start + Vector2(-50.0, 10.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(locked_left_point.left_control_point == locked_left_origin, "Shift motion moved a locked left control")
	locked_left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_left_start + Vector2(-50.0, 10.0), false, true))
	locked_left_editor._slider.free()
	locked_left_editor.free()

	var locked_right_fixture := _fixture()
	var locked_right_curve: EasingCurve = locked_right_fixture.curve
	var locked_right_editor: EasingCurveEditor = locked_right_fixture.editor
	var locked_right_point := locked_right_curve.points[1]
	var locked_right_origin := locked_right_point.right_control_point
	var locked_right_start := locked_right_editor.get_view_pos(locked_right_origin)
	locked_right_point.set_locked("right_control_point", true)
	locked_right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_right_start, true))
	_expect(locked_right_editor.dragging_point == -1, "Locked right control unexpectedly started a graph drag")
	locked_right_editor._gui_input(_motion(locked_right_start + Vector2(50.0, -10.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(locked_right_point.right_control_point == locked_right_origin, "Shift motion moved a locked right control")
	locked_right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_right_start + Vector2(50.0, -10.0), false, true))
	locked_right_editor._slider.free()
	locked_right_editor.free()

	var free_fixture := _fixture()
	var free_curve: EasingCurve = free_fixture.curve
	var free_editor: EasingCurveEditor = free_fixture.editor
	var free_point := free_curve.points[1]
	var free_left_origin := free_point.left_control_point
	var free_right_origin := free_point.right_control_point
	var free_start := free_editor.get_view_pos(free_left_origin)
	free_editor._gui_input(_button(MOUSE_BUTTON_LEFT, free_start, true))
	var free_target_view := free_start + Vector2(-48.0, 10.0)
	var free_target_world := free_editor.get_world_pos(free_target_view)
	var expected_free_left := Vector2(free_target_world.x, free_left_origin.y)
	free_editor._gui_input(_motion(free_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(free_point.left_control_point.is_equal_approx(expected_free_left), "Free Shift drag did not preserve the constrained requested handle target")
	_expect(free_point.right_control_point == free_right_origin, "Free Shift drag unexpectedly changed the opposite handle")
	free_editor._gui_input(_button(MOUSE_BUTTON_LEFT, free_target_view, false, true))
	free_editor._slider.free()
	free_editor.free()

	var force_fixture := _fixture()
	var force_curve: EasingCurve = force_fixture.curve
	var force_editor: EasingCurveEditor = force_fixture.editor
	var force_point := force_curve.points[1]
	force_point.left_force_linear = true
	var force_origin := force_point.position
	var force_start := _point_view(force_editor, force_point)
	force_editor._gui_input(_button(MOUSE_BUTTON_LEFT, force_start, true))
	var force_target_view := force_start + Vector2(50.0, 10.0)
	var force_target_world := force_editor.get_world_pos(force_target_view)
	var expected_force_position := Vector2(force_target_world.x, force_origin.y).clamp(
		Vector2(0, force_curve.min_value),
		Vector2(1.0, force_curve.max_value),
	)
	force_editor._gui_input(_motion(force_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(force_point.position.is_equal_approx(expected_force_position), "Force Linear point did not receive the constrained point target")
	_expect(force_point.left_control_point == force_point.position, "Constrained point drag bypassed downstream Force Linear geometry")
	force_editor._gui_input(_button(MOUSE_BUTTON_LEFT, force_target_view, false, true))
	force_editor._slider.free()
	force_editor.free()

	var balanced_fixture := _fixture()
	var balanced_curve: EasingCurve = balanced_fixture.curve
	var balanced_editor: EasingCurveEditor = balanced_fixture.editor
	var balanced_point := balanced_curve.points[1]
	balanced_point.set_handle_display_scale(balanced_editor.get_world_to_view_scale())
	balanced_point.handle_mode = EasingCurvePoint.HandleMode.BALANCED
	var balanced_left_origin := balanced_point.left_control_point
	var balanced_right_display_length := (
		(balanced_point.right_control_point - balanced_point.position)
		* balanced_point.handle_display_scale
	).length()
	var balanced_start := balanced_editor.get_view_pos(balanced_left_origin)
	balanced_editor._gui_input(_button(MOUSE_BUTTON_LEFT, balanced_start, true))
	var balanced_target_view := balanced_start + Vector2(-50.0, 10.0)
	var balanced_target_world := balanced_editor.get_world_pos(balanced_target_view)
	var expected_balanced_left := Vector2(balanced_target_world.x, balanced_left_origin.y)
	balanced_editor._gui_input(_motion(balanced_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(balanced_point.left_control_point.is_equal_approx(expected_balanced_left), "Balanced Shift drag did not preserve the constrained requested handle target")
	_expect(_handles_are_opposite_in_display_space(balanced_point), "Balanced Shift drag bypassed downstream opposite-direction geometry")
	_expect(
		is_equal_approx(
			((balanced_point.right_control_point - balanced_point.position) * balanced_point.handle_display_scale).length(),
			balanced_right_display_length,
		),
		"Balanced Shift drag did not preserve the downstream opposite display-space length",
	)
	balanced_editor._gui_input(_button(MOUSE_BUTTON_LEFT, balanced_target_view, false, true))
	balanced_editor._slider.free()
	balanced_editor.free()

	var mirrored_fixture := _fixture()
	var mirrored_curve: EasingCurve = mirrored_fixture.curve
	var mirrored_editor: EasingCurveEditor = mirrored_fixture.editor
	var mirrored_point := mirrored_curve.points[1]
	mirrored_point.set_handle_display_scale(mirrored_editor.get_world_to_view_scale())
	mirrored_point.handle_mode = EasingCurvePoint.HandleMode.MIRRORED
	var mirrored_right_origin := mirrored_point.right_control_point
	var mirrored_start := mirrored_editor.get_view_pos(mirrored_right_origin)
	mirrored_editor._gui_input(_button(MOUSE_BUTTON_LEFT, mirrored_start, true))
	var mirrored_target_view := mirrored_start + Vector2(10.0, 50.0)
	var mirrored_target_world := mirrored_editor.get_world_pos(mirrored_target_view)
	var expected_mirrored_right := Vector2(mirrored_right_origin.x, mirrored_target_world.y)
	mirrored_editor._gui_input(_motion(mirrored_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(mirrored_point.right_control_point.is_equal_approx(expected_mirrored_right), "Mirrored Shift drag did not preserve the constrained requested handle target")
	_expect(
		((mirrored_point.left_control_point - mirrored_point.position) * mirrored_point.handle_display_scale).is_equal_approx(
			-((mirrored_point.right_control_point - mirrored_point.position) * mirrored_point.handle_display_scale)
		),
		"Mirrored Shift drag bypassed downstream mirrored display-space geometry",
	)
	mirrored_editor._gui_input(_button(MOUSE_BUTTON_LEFT, mirrored_target_view, false, true))
	mirrored_editor._slider.free()
	mirrored_editor.free()

	var linked_fixture := _fixture()
	var linked_curve: EasingCurve = linked_fixture.curve
	var linked_editor: EasingCurveEditor = linked_fixture.editor
	var linked_point := linked_curve.points[1]
	linked_point.handle_mode = EasingCurvePoint.HandleMode.LINKED
	var linked_origin := linked_point.left_control_point
	var linked_start := linked_editor.get_view_pos(linked_origin)
	linked_editor._gui_input(_button(MOUSE_BUTTON_LEFT, linked_start, true))
	_expect(linked_editor.dragging_control == EasingCurveEditor.ControlIndex.LEFT, "Linked shared handle did not enter the existing left-control graph path")
	var linked_target_view := linked_start + Vector2(50.0, 10.0)
	var linked_target_world := linked_editor.get_world_pos(linked_target_view)
	var expected_linked := Vector2(linked_target_world.x, linked_origin.y)
	linked_editor._gui_input(_motion(linked_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		linked_point.left_control_point.is_equal_approx(expected_linked)
		and linked_point.right_control_point.is_equal_approx(expected_linked),
		"Linked Shift drag did not keep both controls synchronized to the constrained request",
	)
	linked_editor._gui_input(_button(MOUSE_BUTTON_LEFT, linked_target_view, false, true))
	linked_editor._slider.free()
	linked_editor.free()

	var linear_fixture := _fixture()
	var linear_curve: EasingCurve = linear_fixture.curve
	var linear_editor: EasingCurveEditor = linear_fixture.editor
	var linear_point := linear_curve.points[1]
	linear_point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	var linear_origin := linear_point.position
	var linear_start := linear_editor.get_view_pos(linear_point.left_control_point)
	linear_editor._gui_input(_button(MOUSE_BUTTON_LEFT, linear_start, true))
	_expect(
		linear_editor.dragging_point == 1 and linear_editor.dragging_control == EasingCurveEditor.ControlIndex.NONE,
		"Linear collapsed handle did not fall back to the existing point drag path",
	)
	var linear_target_view := linear_start + Vector2(50.0, 10.0)
	var linear_target_world := linear_editor.get_world_pos(linear_target_view)
	var expected_linear_position := Vector2(linear_target_world.x, linear_origin.y).clamp(
		Vector2(0, linear_curve.min_value),
		Vector2(1.0, linear_curve.max_value),
	)
	linear_editor._gui_input(_motion(linear_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(linear_point.position.is_equal_approx(expected_linear_position), "Linear fallback point drag did not receive the constrained point target")
	_expect(
		linear_point.left_control_point == linear_point.position
		and linear_point.right_control_point == linear_point.position,
		"Linear fallback point drag did not retain collapsed downstream controls",
	)
	linear_editor._gui_input(_button(MOUSE_BUTTON_LEFT, linear_target_view, false, true))
	linear_editor._slider.free()
	linear_editor.free()


func _test_axis_constraint_view_and_order_geometry() -> void:
	var view_fixture := _fixture()
	var view_curve: EasingCurve = view_fixture.curve
	var view_editor: EasingCurveEditor = view_fixture.editor
	var view_point := view_curve.points[1]
	var view_origin := view_point.position
	var view_start := _point_view(view_editor, view_point)
	var disagreement_view := view_start + Vector2(40.0, 30.0)
	var disagreement_world := view_editor.get_world_pos(disagreement_view)
	var disagreement_world_delta := disagreement_world - view_origin
	_expect(
		absf(disagreement_world_delta.y) > absf(disagreement_world_delta.x),
		"View-space dominance fixture no longer disagrees with world-space dominance",
	)
	view_editor._gui_input(_button(MOUSE_BUTTON_LEFT, view_start, true))
	view_editor._gui_input(_motion(disagreement_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		view_point.position.is_equal_approx(
			Vector2(disagreement_world.x, view_origin.y).clamp(
				Vector2(0, view_curve.min_value),
				Vector2(1.0, view_curve.max_value),
			)
		),
		"Shift axis choice followed world-space magnitude instead of view-space pixel displacement",
	)

	var equal_view := view_start + Vector2(32.0, 32.0)
	var equal_world := view_editor.get_world_pos(equal_view)
	view_editor._gui_input(_motion(equal_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		view_point.position.is_equal_approx(
			Vector2(view_origin.x, equal_world.y).clamp(
				Vector2(0, view_curve.min_value),
				Vector2(1.0, view_curve.max_value),
			)
		),
		"Equal view-space displacement no longer resolves to the Y axis",
	)

	var x_side_view := view_start + Vector2(33.0, 32.0)
	var x_side_world := view_editor.get_world_pos(x_side_view)
	view_editor._gui_input(_motion(x_side_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		view_point.position.is_equal_approx(
			Vector2(x_side_world.x, view_origin.y).clamp(
				Vector2(0, view_curve.min_value),
				Vector2(1.0, view_curve.max_value),
			)
		),
		"X side of the view-space diagonal did not constrain horizontally",
	)

	var y_side_view := view_start + Vector2(32.0, 33.0)
	var y_side_world := view_editor.get_world_pos(y_side_view)
	view_editor._gui_input(_motion(y_side_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		view_point.position.is_equal_approx(
			Vector2(view_origin.x, y_side_world.y).clamp(
				Vector2(0, view_curve.min_value),
				Vector2(1.0, view_curve.max_value),
			)
		),
		"Y side of the view-space diagonal did not constrain vertically",
	)
	view_editor._gui_input(_button(MOUSE_BUTTON_LEFT, y_side_view, false, true))
	view_editor._slider.free()
	view_editor.free()

	var zoom_fixture := _fixture()
	var zoom_curve: EasingCurve = zoom_fixture.curve
	var zoom_editor: EasingCurveEditor = zoom_fixture.editor
	zoom_editor.set_slider_value(
		mini(int(EasingCurve.DEFAULT_SLIDER_VALUE) + 3, EasingCurve.ZOOM_STEPS)
	)
	zoom_editor.update_view_transform()
	zoom_editor.pan_offset = Vector2(37.0, -21.0)
	var zoom_point := zoom_curve.points[1]
	var zoom_origin := zoom_point.position
	var zoom_start := _point_view(zoom_editor, zoom_point)
	zoom_editor._gui_input(_button(MOUSE_BUTTON_LEFT, zoom_start, true))
	var zoom_target_view := zoom_start + Vector2(44.0, 20.0)
	var zoom_target_world := zoom_editor.get_world_pos(zoom_target_view)
	zoom_editor._gui_input(_motion(zoom_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		zoom_point.position.is_equal_approx(
			Vector2(zoom_target_world.x, zoom_origin.y).clamp(
				Vector2(0, zoom_curve.min_value),
				Vector2(1.0, zoom_curve.max_value),
			)
		),
		"Shift constraint did not preserve view-space axis behavior under zoom and pan",
	)
	var zoom_step_before_wheel := zoom_editor._zoom_step
	zoom_editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, zoom_target_view, true, true, true))
	_expect(
		zoom_editor.dragging_point == 1
		and zoom_editor._zoom_step == mini(zoom_step_before_wheel + 1, EasingCurve.ZOOM_STEPS),
		"Wheel zoom during a constrained drag canceled the drag or failed to advance zoom",
	)
	var post_wheel_view := zoom_start + Vector2(56.0, 18.0)
	var post_wheel_world := zoom_editor.get_world_pos(post_wheel_view)
	zoom_editor._gui_input(_motion(post_wheel_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		zoom_point.position.is_equal_approx(
			Vector2(post_wheel_world.x, zoom_origin.y).clamp(
				Vector2(0, zoom_curve.min_value),
				Vector2(1.0, zoom_curve.max_value),
			)
		),
		"Constrained drag after wheel zoom stopped using the original view-space drag axis",
	)
	zoom_editor._gui_input(_button(MOUSE_BUTTON_LEFT, post_wheel_view, false, true))
	zoom_editor._slider.free()
	zoom_editor.free()

	var endpoint_fixture := _fixture()
	var endpoint_curve: EasingCurve = endpoint_fixture.curve
	var endpoint_editor: EasingCurveEditor = endpoint_fixture.editor
	endpoint_curve.points[2].position = Vector2(1.0, endpoint_curve.points[2].position.y)
	var endpoint_points: Array[EasingCurvePoint] = endpoint_curve.points.duplicate()
	var endpoint_moved := endpoint_points[1]
	var endpoint_origin := endpoint_moved.position
	var endpoint_start := _point_view(endpoint_editor, endpoint_moved)
	endpoint_editor._gui_input(_button(MOUSE_BUTTON_LEFT, endpoint_start, true))
	var endpoint_target_view := endpoint_start + Vector2(1000.0, 5.0)
	endpoint_editor._gui_input(_motion(endpoint_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		endpoint_moved.position.is_equal_approx(Vector2(1.0, endpoint_origin.y)),
		"Horizontal constrained point drag did not clamp to the right X endpoint",
	)
	_expect(
		endpoint_curve.points == endpoint_points
		and endpoint_editor._get_display_points() == [endpoint_points[0], endpoint_moved],
		"Horizontal constrained endpoint takeover changed source order or failed to update the live preview",
	)
	endpoint_editor._gui_input(_button(MOUSE_BUTTON_LEFT, endpoint_target_view, false, true))
	_expect(
		endpoint_curve.points == [endpoint_points[0], endpoint_moved]
		and endpoint_editor.selected_index == 1,
		"Horizontal constrained endpoint takeover did not commit through the existing ordering path",
	)
	endpoint_editor._slider.free()
	endpoint_editor.free()

	var vertical_fixture := _fixture()
	var vertical_curve: EasingCurve = vertical_fixture.curve
	var vertical_editor: EasingCurveEditor = vertical_fixture.editor
	var vertical_points: Array[EasingCurvePoint] = vertical_curve.points.duplicate()
	var vertical_moved := vertical_points[1]
	var vertical_origin := vertical_moved.position
	var vertical_start := _point_view(vertical_editor, vertical_moved)
	vertical_editor._gui_input(_button(MOUSE_BUTTON_LEFT, vertical_start, true))
	var vertical_target_view := vertical_start + Vector2(5.0, -1000.0)
	vertical_editor._gui_input(_motion(vertical_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		vertical_moved.position.is_equal_approx(
			Vector2(vertical_origin.x, vertical_curve.max_value)
		),
		"Vertical constrained point drag did not clamp Y while preserving the original X",
	)
	_expect(
		vertical_curve.points == vertical_points
		and vertical_editor._get_display_points() == vertical_points,
		"Vertical constrained movement changed point ordering during the live preview",
	)
	vertical_editor._gui_input(_button(MOUSE_BUTTON_LEFT, vertical_target_view, false, true))
	_expect(
		vertical_curve.points == vertical_points
		and vertical_editor.selected_index == 1,
		"Vertical constrained movement changed committed point ordering",
	)
	vertical_editor._slider.free()
	vertical_editor.free()


func _test_axis_constraint_request_and_input_boundaries() -> void:
	var point_fixture := _fixture()
	var point_curve: EasingCurve = point_fixture.curve
	var point_editor: EasingCurveEditor = point_fixture.editor
	var point_inspector: Object = point_fixture.inspector
	var point_requests: Array = []
	var point_finish := {"count": 0}
	point_editor.point_property_change_requested.connect(
		func(_index: int, property_name: StringName, _value: Variant, changing: bool) -> void:
			point_requests.append({"name": property_name, "changing": changing})
	)
	point_editor.point_edit_finished.connect(
		func(_point_order: Array[EasingCurvePoint]) -> void:
			point_finish["count"] += 1
	)
	var point := point_curve.points[1]
	var point_start := _point_view(point_editor, point)
	point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_start, true))
	var point_selection_before := EDITOR_DRIVER.capture_point_selection(point_inspector)
	var point_resource_ids_before := point_curve._get_editor_point_resource_ids()
	point_editor._gui_input(_motion(point_start + Vector2(48.0, 10.0), MOUSE_BUTTON_MASK_LEFT, true))
	var point_transaction := EDITOR_DRIVER.point_edit_transaction_state(point_inspector)
	_expect(bool(point_transaction["active"]), "Constrained point drag did not start an edit transaction")
	_expect(point_transaction["action_name"] == "Move Easing Curve Point", "Constrained point drag changed its Undo action name")
	_expect(
		point_transaction["selection_before"] == point_selection_before,
		"Constrained point drag did not capture selection at the transaction boundary",
	)
	_expect(
		point_transaction["point_resource_ids_before"] == point_resource_ids_before,
		"Constrained point drag did not capture point Resource identity order at the transaction boundary",
	)
	point_editor._gui_input(_motion(point_start + Vector2(56.0, 12.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		EDITOR_DRIVER.point_edit_transaction_state(point_inspector)["before"] == point_transaction["before"],
		"Repeated constrained point motion started a second edit transaction",
	)
	var point_request_names := []
	var point_requests_all_changing := true
	for request: Dictionary in point_requests:
		point_request_names.append(request["name"])
		point_requests_all_changing = point_requests_all_changing and bool(request["changing"])
	_expect(
		point_request_names == [
			&"position", &"left_control_point", &"right_control_point",
			&"position", &"left_control_point", &"right_control_point",
		],
		"Constrained point drag changed the existing point/control request sequence",
	)
	_expect(point_requests_all_changing, "Constrained point drag emitted a non-changing motion request")
	var point_request_count_before_release := point_requests.size()
	point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_start + Vector2(56.0, 12.0), false, true))
	_expect(point_requests.size() == point_request_count_before_release, "Constrained point release emitted an extra point-property request")
	_expect(int(point_finish["count"]) == 1, "Constrained point drag emitted the wrong number of edit-finished boundaries")
	_expect(
		not bool(EDITOR_DRIVER.point_edit_transaction_state(point_inspector)["active"]),
		"Constrained point drag left the Inspector transaction open after release",
	)
	point_editor._slider.free()
	point_editor.free()

	var handle_fixture := _fixture()
	var handle_curve: EasingCurve = handle_fixture.curve
	var handle_editor: EasingCurveEditor = handle_fixture.editor
	var handle_inspector: Object = handle_fixture.inspector
	var handle_requests: Array = []
	var handle_finish := {"count": 0}
	handle_editor.point_property_change_requested.connect(
		func(_index: int, property_name: StringName, _value: Variant, changing: bool) -> void:
			handle_requests.append({"name": property_name, "changing": changing})
	)
	handle_editor.point_edit_finished.connect(
		func(_point_order: Array[EasingCurvePoint]) -> void:
			handle_finish["count"] += 1
	)
	var handle_point := handle_curve.points[1]
	var handle_start := handle_editor.get_view_pos(handle_point.right_control_point)
	handle_editor._gui_input(_button(MOUSE_BUTTON_LEFT, handle_start, true))
	var handle_selection_before := EDITOR_DRIVER.capture_point_selection(handle_inspector)
	var handle_resource_ids_before := handle_curve._get_editor_point_resource_ids()
	handle_editor._gui_input(_motion(handle_start + Vector2(46.0, -8.0), MOUSE_BUTTON_MASK_LEFT, true))
	var handle_transaction := EDITOR_DRIVER.point_edit_transaction_state(handle_inspector)
	_expect(bool(handle_transaction["active"]), "Constrained handle drag did not start an edit transaction")
	_expect(handle_transaction["action_name"] == "Move Easing Curve Handle", "Constrained handle drag changed its Undo action name")
	_expect(
		handle_transaction["selection_before"] == handle_selection_before,
		"Constrained handle drag did not capture selection at the transaction boundary",
	)
	_expect(
		handle_transaction["point_resource_ids_before"] == handle_resource_ids_before,
		"Constrained handle drag did not capture point Resource identity order at the transaction boundary",
	)
	handle_editor._gui_input(_motion(handle_start + Vector2(54.0, -10.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		EDITOR_DRIVER.point_edit_transaction_state(handle_inspector)["before"] == handle_transaction["before"],
		"Repeated constrained handle motion started a second edit transaction",
	)
	var handle_request_names := []
	var handle_requests_all_changing := true
	for request: Dictionary in handle_requests:
		handle_request_names.append(request["name"])
		handle_requests_all_changing = handle_requests_all_changing and bool(request["changing"])
	_expect(handle_request_names == [&"right_control_point", &"right_control_point"], "Constrained handle drag changed the existing handle request sequence")
	_expect(handle_requests_all_changing, "Constrained handle drag emitted a non-changing motion request")
	handle_editor._gui_input(_button(MOUSE_BUTTON_LEFT, handle_start + Vector2(54.0, -10.0), false, true))
	_expect(int(handle_finish["count"]) == 1, "Constrained handle drag emitted the wrong number of edit-finished boundaries")
	_expect(
		not bool(EDITOR_DRIVER.point_edit_transaction_state(handle_inspector)["active"]),
		"Constrained handle drag left the Inspector transaction open after release",
	)
	handle_editor._slider.free()
	handle_editor.free()

	var noop_fixture := _fixture()
	var noop_curve: EasingCurve = noop_fixture.curve
	var noop_editor: EasingCurveEditor = noop_fixture.editor
	var noop_inspector: Object = noop_fixture.inspector
	var noop_point := noop_curve.points[1]
	var noop_position := noop_point.position
	var noop_left := noop_point.left_control_point
	var noop_right := noop_point.right_control_point
	var noop_start := _point_view(noop_editor, noop_point)
	noop_editor._gui_input(_button(MOUSE_BUTTON_LEFT, noop_start, true))
	noop_editor._gui_input(_motion(noop_start, MOUSE_BUTTON_MASK_LEFT, true))
	noop_editor._gui_input(_button(MOUSE_BUTTON_LEFT, noop_start, false, true))
	_expect(
		noop_point.position.is_equal_approx(noop_position)
		and noop_point.left_control_point.is_equal_approx(noop_left)
		and noop_point.right_control_point.is_equal_approx(noop_right),
		"Zero-displacement constrained drag changed point geometry",
	)
	_expect(
		not bool(EDITOR_DRIVER.point_edit_transaction_state(noop_inspector)["active"]),
		"Zero-displacement constrained drag left a transaction open",
	)
	noop_editor._slider.free()
	noop_editor.free()

	var pending_fixture := _fixture()
	var pending_curve: EasingCurve = pending_fixture.curve
	var pending_editor: EasingCurveEditor = pending_fixture.editor
	var pending_count := pending_curve.points.size()
	var pending_start := Vector2(580.0, 280.0)
	var pending_target := Vector2(540.0, 250.0)
	pending_editor._gui_input(_button(MOUSE_BUTTON_LEFT, pending_start, true, true))
	_expect(pending_editor.pending_add_point != null, "Pre-held Shift prevented ordinary pending-add start")
	pending_editor._gui_input(_motion(pending_target, MOUSE_BUTTON_MASK_LEFT, true))
	var expected_pending := Vector2(pending_editor.get_world_pos(pending_target).x, pending_editor.get_world_pos(pending_start).y).clamp(
		Vector2(0, pending_curve.min_value),
		Vector2(1.0, pending_curve.max_value),
	)
	_expect(pending_editor.pending_add_point.position.is_equal_approx(expected_pending), "Shift did not constrain pending-add mouse tracking")
	pending_editor._gui_input(_button(MOUSE_BUTTON_RIGHT, pending_target, true, true))
	_expect(pending_editor.pending_add_point == null and pending_curve.points.size() == pending_count and not pending_editor.is_right_delete_dragging, "Shift changed RMB pending-add cancel semantics")
	pending_editor._gui_input(_button(MOUSE_BUTTON_RIGHT, pending_target, false, true))
	pending_editor._gui_input(_button(MOUSE_BUTTON_LEFT, pending_target, false, true))
	pending_editor._slider.free()
	pending_editor.free()

	var delete_fixture := _fixture()
	var delete_curve: EasingCurve = delete_fixture.curve
	var delete_editor: EasingCurveEditor = delete_fixture.editor
	var deleted_point := delete_curve.points[1]
	var delete_view := delete_editor.get_view_pos(deleted_point.position)
	delete_editor._gui_input(_button(MOUSE_BUTTON_RIGHT, delete_view, true, true))
	_expect(not delete_curve.points.has(deleted_point), "Shift changed RMB point deletion")
	delete_editor._gui_input(_button(MOUSE_BUTTON_RIGHT, delete_view, false, true))
	_expect(not delete_editor.is_right_delete_dragging, "Shift+RMB release left delete-drag active")
	delete_editor._slider.free()
	delete_editor.free()

	var navigation_fixture := _fixture()
	var navigation_editor: EasingCurveEditor = navigation_fixture.editor
	get_root().add_child(navigation_editor)
	var pan_before := navigation_editor.pan_offset
	navigation_editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, Vector2(100.0, 100.0), true, true))
	navigation_editor._gui_input(_motion(Vector2(125.0, 115.0), MOUSE_BUTTON_MASK_MIDDLE, true))
	navigation_editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, Vector2(125.0, 115.0), false, true))
	_expect(navigation_editor.pan_offset == pan_before + Vector2(25.0, 15.0) and not navigation_editor.is_panning, "Shift changed MMB pan semantics")
	var zoom_before := navigation_editor._zoom_step
	navigation_editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, Vector2(200.0, 150.0), true, true))
	_expect(navigation_editor._zoom_step == zoom_before, "Shift-only wheel input unexpectedly zoomed the graph")
	navigation_editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, Vector2(200.0, 150.0), true, true, true))
	_expect(navigation_editor._zoom_step == mini(zoom_before + 1, EasingCurve.ZOOM_STEPS), "Shift+Ctrl/Cmd wheel did not zoom the graph")
	var hover_view := navigation_editor.get_view_pos(navigation_fixture.curve.points[1].position)
	navigation_editor._gui_input(_motion(hover_view, 0, true))
	_expect(navigation_editor.hovered_index == 1, "Shift changed ordinary graph hover detection")
	navigation_editor.get_parent().remove_child(navigation_editor)
	navigation_editor._slider.free()
	navigation_editor.free()

	var function_fixture := _fixture()
	var function_curve: EasingCurve = function_fixture.curve
	var function_editor: EasingCurveEditor = function_fixture.editor
	function_curve.curve_mode = EasingCurve.CurveMode.FUNCTION
	function_editor.hovered_index = -1
	function_editor._gui_input(_button(MOUSE_BUTTON_LEFT, Vector2(500.0, 250.0), true, true))
	function_editor._gui_input(_motion(Vector2(300.0, 160.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(function_editor.pending_add_point == null and function_editor.dragging_point == -1 and function_editor.hovered_index == -1, "Shift activated graph point input in Function mode")
	function_editor._slider.free()
	function_editor.free()


func _test_inspector_input_transaction_finish_boundaries() -> void:
	var fixture := _fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var point := curve.points[1]
	var input := EditorSpinSlider.new()
	var reset_btn := Button.new()
	var property_header := PanelContainer.new()
	inspector.call("_connect_point_input_drag_signals", input)
	EDITOR_DRIVER.select_point_property(
		inspector,
		property_header,
		1,
		&"right_control_point",
	)

	var selection_before := EDITOR_DRIVER.capture_point_selection(inspector)
	var point_resource_ids_before := curve._get_editor_point_resource_ids()
	input.emit_signal(&"grabbed")
	inspector.call(
		"_on_y_input_value_changed",
		0.82,
		point,
		input,
		reset_btn,
		"right_control_point",
	)
	var drag_transaction := EDITOR_DRIVER.point_edit_transaction_state(inspector)
	_expect(bool(drag_transaction["active"]), "Inspector slider drag did not begin an edit transaction")
	_expect(
		drag_transaction["action_name"] == "Move Easing Curve Handle",
		"Inspector slider drag changed its Undo action name",
	)
	_expect(
		drag_transaction["selection_before"] == selection_before,
		"Inspector slider drag did not capture the selected property at transaction start",
	)
	_expect(
		drag_transaction["point_resource_ids_before"] == point_resource_ids_before,
		"Inspector slider drag did not capture point Resource identity order",
	)
	input.emit_signal(&"ungrabbed")
	_expect(
		bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Inspector slider ungrab committed synchronously instead of at its deferred boundary",
	)
	await process_frame
	_expect(
		not bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Inspector slider ungrab did not finish its deferred edit transaction",
	)

	input.emit_signal(&"grabbed")
	inspector.call(
		"_on_y_input_value_changed",
		0.76,
		point,
		input,
		reset_btn,
		"right_control_point",
	)
	_expect(
		bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Second Inspector slider drag did not begin an edit transaction",
	)
	input.emit_signal(&"value_focus_entered")
	_expect(
		not bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Inspector slider-to-value-focus handoff did not finish the active drag synchronously",
	)

	var position_input := EditorSpinSlider.new()
	inspector.call("_on_position_x_input_focus_entered", position_input)
	inspector.call(
		"_on_x_input_value_changed",
		0.75,
		point,
		position_input,
		reset_btn,
		"position",
	)
	var position_transaction := EDITOR_DRIVER.point_edit_transaction_state(inspector)
	_expect(bool(position_transaction["active"]), "Position X focus edit did not begin an edit transaction")
	_expect(
		position_transaction["action_name"] == "Move Easing Curve Point",
		"Position X focus edit changed its Undo action name",
	)
	_expect(
		editor.position_x_order_preview_point == point,
		"Position X focus edit did not defer list order behind the graph preview",
	)
	inspector.call("_on_position_x_input_focus_exited", position_input)
	_expect(
		bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Position X focus exit committed synchronously instead of at its deferred boundary",
	)
	await process_frame
	_expect(
		not bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Position X focus exit did not finish its deferred edit transaction",
	)
	_expect(
		editor.position_x_order_preview_point == null,
		"Position X focus completion left a stale graph-order preview",
	)

	var typed_input := EditorSpinSlider.new()
	inspector.call("_connect_point_input_drag_signals", typed_input)
	var publications := [0]
	curve.changed.connect(func() -> void: publications[0] += 1)
	var publications_before: int = publications[0]
	typed_input.emit_signal(&"value_focus_entered")
	inspector.call(
		"_on_y_input_value_changed",
		0.71,
		point,
		typed_input,
		reset_btn,
		"right_control_point",
	)
	_expect(
		bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Typed Legacy point value did not begin an accepted-value transaction",
	)
	_expect(
		publications[0] == publications_before,
		"Typed Legacy point value published before entry was accepted",
	)
	typed_input.emit_signal(&"value_focus_exited")
	await process_frame
	_expect(
		publications[0] == publications_before + 1,
		"Typed Legacy point value did not publish once after entry was accepted",
	)

	point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	var linear_input := EditorSpinSlider.new()
	inspector.call("_on_linear_control_x_input_focus_entered", linear_input, point)
	inspector.call(
		"_on_x_input_value_changed",
		0.65,
		point,
		linear_input,
		reset_btn,
		"left_control_point",
	)
	var linear_transaction := EDITOR_DRIVER.point_edit_transaction_state(inspector)
	_expect(bool(linear_transaction["active"]), "Linear control X focus did not begin a position edit transaction")
	_expect(
		linear_transaction["action_name"] == "Move Easing Curve Point",
		"Linear control X focus did not retain the position Undo action name",
	)
	_expect(
		editor.position_x_order_preview_point == point,
		"Linear control X focus did not use the Position X order preview",
	)
	inspector.call("_on_linear_control_x_input_focus_exited", linear_input, point)
	_expect(
		bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Linear control X focus exit committed synchronously instead of at its deferred boundary",
	)
	await process_frame
	_expect(
		not bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Linear control X focus exit did not finish its deferred edit transaction",
	)
	_expect(
		editor.position_x_order_preview_point == null,
		"Linear control X focus completion left a stale graph-order preview",
	)

	property_header.free()
	reset_btn.free()
	input.free()
	position_input.free()
	linear_input.free()
	editor.free()


func _test_point_and_control_drag_boundaries() -> void:
	var fixture := _fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var point := curve.points[1]
	var start := _point_view(editor, point)
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, start, true))
	editor._gui_input(_motion(start + Vector2(30.0, -20.0), MOUSE_BUTTON_MASK_LEFT))
	_expect(
		bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Point drag did not begin one edit transaction",
	)
	editor._gui_input(_motion(start + Vector2(45.0, -25.0), MOUSE_BUTTON_MASK_LEFT))
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, start + Vector2(45.0, -25.0), false))
	_expect(
		not bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Point drag release did not complete its transaction",
	)
	_expect(editor.dragging_point == -1 and editor.dragging_control == EasingCurveEditor.ControlIndex.NONE, "Point drag release leaked graph state")

	point = curve.points[editor.selected_index]
	var control_view := editor.get_view_pos(point.right_control_point)
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, control_view, true))
	editor._gui_input(_motion(control_view + Vector2(20.0, 15.0), MOUSE_BUTTON_MASK_LEFT))
	_expect(
		bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Control drag did not begin one edit transaction",
	)
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, control_view + Vector2(20.0, 15.0), false))
	_expect(
		not bool(EDITOR_DRIVER.point_edit_transaction_state(inspector)["active"]),
		"Control drag release did not complete its transaction",
	)
	editor.free()


func _test_zoom_and_pan_interactions() -> void:
	var fixture := _fixture()
	var editor: EasingCurveEditor = fixture.editor
	var point_view := _point_view(editor, fixture.curve.points[1])
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_view, true))
	var zoom_before := editor._zoom_step
	editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, point_view, true))
	_expect(editor.dragging_point != -1, "Plain wheel input during a point drag canceled the active drag")
	_expect(editor._zoom_step == zoom_before, "Plain wheel input unexpectedly zoomed during a point drag")
	editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, point_view, true, false, true))
	_expect(editor.dragging_point != -1, "Modified zoom during a point drag canceled the active drag")
	_expect(editor._zoom_step != zoom_before, "Modified zoom during a point drag did not update the view")
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_view, false))

	get_root().add_child(editor)
	var pan_before := editor.pan_offset
	editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, Vector2(100.0, 100.0), true))
	editor._gui_input(_motion(Vector2(125.0, 115.0), MOUSE_BUTTON_MASK_MIDDLE))
	editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, Vector2(125.0, 115.0), false))
	_expect(editor.pan_offset != pan_before and not editor.is_panning, "Pan gesture did not move the view and clear panning state")
	editor.get_parent().remove_child(editor)
	editor._slider.free()
	editor.free()

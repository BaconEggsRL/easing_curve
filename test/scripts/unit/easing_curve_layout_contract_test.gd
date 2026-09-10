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
	await _test_independent_resets()
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
		# Keep full-editor captures free of the host's scene-tree/start-page text.
		var backdrop := ColorRect.new()
		backdrop.color = Color(0.16, 0.16, 0.16)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop.size = Vector2(root.size)
		root.add_child(backdrop)
		root.add_child(presentation)
		var editor: EasingCurveEditor = context.easing_curve_editor
		editor.selected_index = 1
		editor._point(1).set(&"left_force_linear", true)
		editor._point(1).call(&"set_locked", &"right_control_point", true)
		await _settle()
		var toolbar := editor._point_toolbar
		var preset_reset := presentation.get_child(0).get_child(5) as Button
		_expect(toolbar is VBoxContainer and toolbar.get_child_count() == 3, "Toolbar must contain mode, left/shared and right rows")
		_expect(editor._point_left_state.get_parent().get_parent() == editor._point_left_state_label.get_parent(), "Left label split from its field")
		_expect(editor._point_right_state.get_parent().get_parent() == editor._point_right_state_label.get_parent(), "Right label split from its field")
		for scale_value: float in [1.0, 1.5, 2.0]:
			var theme := Theme.new()
			theme.default_font_size = roundi(16.0 * scale_value)
			presentation.theme = theme
			editor._editor_scale = scale_value
			await _settle()
			var baseline_width := presentation.get_combined_minimum_size().x
			var arrangements := {}
			for width: float in [150.0, 180.0, 220.0, 270.0, 359.0, 360.0, 361.0, 600.0, 220.0, 180.0, 150.0]:
				editor._point(1).set(&"handle_mode", EasingCurvePoint.HandleMode.FREE)
				editor._update_point_toolbar()
				presentation.size.x = width * scale_value
				await _settle()
				var positions: Array[Vector2] = []
				for group: Control in toolbar.get_children():
					positions.append(group.position)
					if group.visible:
						_expect(group.position.x >= 0 and group.get_rect().end.x <= toolbar.size.x + 0.01, "Toolbar group overflowed allocated width")
				var minimum_changes := [0]
				var record_change := func(): minimum_changes[0] += 1
				toolbar.minimum_size_changed.connect(record_change)
				await _settle()
				toolbar.minimum_size_changed.disconnect(record_change)
				_expect(minimum_changes[0] == 0, "Settled toolbar kept invalidating minimum size")
				for index in range(toolbar.get_child_count()):
					_expect(toolbar.get_child(index).position == positions[index], "Toolbar layout oscillated at fixed width")
				if arrangements.has(width):
					_expect(arrangements[width] == positions, "Returning to a width changed row arrangement")
				arrangements[width] = positions
				_expect(presentation.get_combined_minimum_size().x == baseline_width, "Toolbar wrapping changed presentation minimum width")
				_expect(editor._graph_canvas.size.x == editor.size.x, "Control minimum widened the graph canvas")
				_expect(editor._snap_toolbar_margin.get_parent() == editor._graph_canvas.get_parent(), "Grid Snap is not a graph sibling")
				_expect(editor._snap_toolbar_margin.get_rect().end.y <= editor._graph_canvas.position.y, "Grid Snap overlaps graph")
				_expect(editor._slider.get_global_rect().end.x <= editor.get_global_rect().end.x + 0.01, "Zoom row overflowed Inspector width")
				_assert_fixed_rows(editor, preset_reset)
				var dimensions := editor._get_graph_view_rect().size
				var row_height := toolbar.size.y
				for mode: int in [0, 1, 2, 3, 4, 0, 4, 0]:
					editor._point(1).set(&"handle_mode", mode)
					editor._update_point_toolbar()
					await _settle()
					_assert_fixed_rows(editor, preset_reset)
					_expect(toolbar.size.y < row_height if mode == 4 else is_equal_approx(toolbar.size.y, row_height), "Linked must remove exactly the unused side row")
					_expect(editor._get_graph_view_rect().size == dimensions, "Point state changed graph dimensions")
					_expect(editor._point_left_state.disabled == (mode not in [0, 4]), "Left state availability does not match mode")
					_expect(editor._point_right_state.disabled == (mode != 0), "Right state availability does not match mode")
					_expect(presentation.get_combined_minimum_size().x == baseline_width, "Long mode text increased Inspector minimum width")
					if scale_value == 1.0 and width in [150.0, 220.0, 600.0] and mode in [0, 4] and DisplayServer.get_name() != "headless":
						await RenderingServer.frame_post_draw
						var capture := root.get_texture().get_image().get_region(Rect2i(presentation.get_global_rect()))
						capture.save_png("res://test/_temp/point-toolbar-%s-%s-%s.png" % ["native" if native else "legacy", "linked" if mode == 4 else "separate", int(width)])
				if width == 150.0:
					for option: OptionButton in [editor._point_handle_mode, editor._point_left_state, editor._point_right_state]:
						var original := option.get_item_text(option.selected)
						var allocation: Vector2 = option.get_parent().size
						option.set_item_text(option.selected, "Long localized control state description")
						await _settle()
						_expect(option.get_parent().size == allocation, "Long text changed field allocation")
						_expect(toolbar.size.y == row_height and editor._get_graph_view_rect().size == dimensions, "Long text wrapped or resized the graph")
						_expect(presentation.get_combined_minimum_size().x == baseline_width, "Long text raised Inspector minimum width")
						option.set_item_text(option.selected, original)
					await _settle()
					print("TOOLBAR_METRICS backend=%s scale=%s width=%s mode=%s left=%s right=%s reset_x=%s preset_x=%s graph=%s" % ["native" if native else "legacy", scale_value, editor.size.x, editor._point_handle_mode.size.x, editor._point_left_state.size.x, editor._point_right_state.size.x, editor._point_reset_button.global_position.x, preset_reset.global_position.x, dimensions])
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
		for index: int in [0, 2]:
			editor.selected_index = index
			editor._update_point_toolbar()
			await _settle()
			_assert_fixed_rows(editor, preset_reset)
			_expect(editor._point_left_state.disabled if index == 0 else editor._point_right_state.disabled, "Missing endpoint side accepts input")
			editor._point(index).set(&"handle_mode", EasingCurvePoint.HandleMode.LINKED)
			editor._update_point_toolbar()
			await _settle()
			_assert_fixed_rows(editor, preset_reset)
			_expect(not editor._point_left_state.disabled, "Linked endpoint lost its available side")
		editor.selected_index = -1
		editor._update_point_toolbar()
		await _settle()
		_expect(not editor._point_left_state_row.visible and not editor._point_right_state_row.visible, "No selection reserves state rows")
		presentation.free()
		backdrop.free()
		await _settle()


func _assert_fixed_rows(editor: EasingCurveEditor, preset_reset: Button) -> void:
	var first := editor._point_mode_row
	var second := editor._point_left_state_row
	var third := editor._point_right_state_row
	var linked := int(editor._point(editor.selected_index).get(&"handle_mode")) == EasingCurvePoint.HandleMode.LINKED
	_expect(first.visible and second.visible and third.visible == not linked, "Mode has the wrong visible row count")
	_expect(first.get_rect().end.y <= second.position.y, "Logical rows overlap")
	_expect(editor._point_left_state_label.text == ("LR" if linked else "L"), "Shared state label does not match mode")
	_expect(editor._point_handle_mode.get_parent().get_parent() == first, "Handle Mode left Row 1")
	_expect(editor._point_reorder_buttons.get_parent().get_parent() == first, "Navigation left Row 1")
	_expect(editor._point_left_group.get_parent() == second and editor._point_right_group.get_parent() == third, "Side controls must have their own rows")
	if linked:
		_expect(editor._point_left_state.get_selected_id() == editor._get_point_toolbar_control_state(editor.selected_index, EasingCurvePoint.ControlSide.RIGHT), "LR does not show the shared backend state")
	else:
		_expect(second.get_rect().end.y <= third.position.y, "Side rows overlap")
		_expect(editor._point_left_state.global_position.x == editor._point_right_state.global_position.x, "L/R fields do not align")
		_expect(absf(editor._point_left_state.size.x - editor._point_right_state.size.x) <= 1.0, "Side fields have different allocations")
	for row: HBoxContainer in [first, second, third]:
		if not row.visible:
			continue
		var previous_end := 0.0
		for child: Control in row.get_children():
			_expect(child.position.x >= previous_end - 0.01 and child.get_rect().end.x <= row.size.x + 0.01, "Row contents overlap or overflow")
			previous_end = child.get_rect().end.x
	for button: Button in [editor._point_reset_button, editor._point_left_state_reset_button, editor._point_right_state_reset_button]:
		if not button.is_visible_in_tree():
			continue
		_expect(button.visible, "Inactive reset removed its slot")
		_expect(absf(button.global_position.x - preset_reset.global_position.x) <= 1.0, "Reset column left edge differs from Ease/Trans")
		_expect(absf(button.get_global_rect().end.x - preset_reset.get_global_rect().end.x) <= 1.0, "Reset column right edge differs from Ease/Trans")
	for option: OptionButton in [editor._point_handle_mode, editor._point_left_state, editor._point_right_state]:
		if not option.is_visible_in_tree():
			continue
		_expect(option.visible and option.clip_text and option.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "State field must remain visible with ellipsis")
		_expect(option.size.x > 0 and option.size.x <= option.get_parent().size.x + 0.01, "Dropdown cannot shrink into its slot")
		_expect(not option.tooltip_text.is_empty(), "Clipped state lost its tooltip")
		if option.disabled:
			_expect(option.mouse_filter == Control.MOUSE_FILTER_IGNORE and option.focus_mode == Control.FOCUS_NONE, "Unavailable field still accepts input")


func _test_independent_resets() -> void:
	var plugin := EditorPlugin.new()
	var manager := plugin.get_undo_redo()
	for native: bool in [false, true]:
		for reverse_sides: bool in [false, true]:
			var viewport := SubViewport.new()
			viewport.size = Vector2i(600, 900)
			root.add_child(viewport)
			var curve: Resource = ClassDB.instantiate(&"NativeEasingCurve") if native else EasingCurve.new()
			curve.set(&"transition" if native else &"trans_type", 100 if native else EasingCurve.TRANS.CUSTOM)
			var context := HOST.INSPECTOR_PLUGIN.new()
			curve.set(&"reverse", reverse_sides)
			curve.set(&"ease_type", 1 if reverse_sides else 0)
			context.editor_undo_redo = manager
			var presentation: Control = context.handle_easing_curve_editor(curve)
			viewport.add_child(presentation)
			presentation.size.x = 220.0
			var editor: EasingCurveEditor = context.easing_curve_editor
			editor.selected_index = 0
			await _settle()
			var history := manager.get_history_undo_redo(manager.get_object_history_id(curve))
			for mode: int in EasingCurvePoint.HandleMode.values():
				for reset_target: int in [0, 1, 2]:
					if mode == 4 and reset_target == 2:
						continue
					var reset_states := reset_target != 0
					var point := editor._point(0)
					point.set(&"handle_mode", EasingCurvePoint.HandleMode.FREE)
					point.set(&"left_force_linear", true)
					point.call(&"set_locked", &"right_control_point", true)
					point.call(&"set_locked", &"position", true)
					point.set(&"handle_mode", mode)
					editor._update_point_toolbar()
					await _settle()
					manager.clear_history()
					var before: Variant = editor._backend.capture_snapshot()
					var overrides := _stored_overrides(editor._point(0))
					var geometry := [point.get(&"position"), point.get(&"left_control_point"), point.get(&"right_control_point")]
					var dimensions := editor._get_graph_view_rect().size
					var buttons: Array[Button] = [editor._point_reset_button, editor._point_left_state_reset_button, editor._point_right_state_reset_button]
					var button := buttons[reset_target]
					var reset_rect := button.get_global_rect()
					_click(viewport, reset_rect.get_center())
					await _settle()
					if mode == EasingCurvePoint.HandleMode.FREE and not reset_states:
						_expect(history.get_history_count() == 0, "Inactive mode reset created an action")
						_expect(editor._backend.capture_snapshot() == before, "Inactive mode reset mutated flags")
						continue
					_expect(history.get_history_count() == 1, "Reset did not create exactly one Undo action")
					point = editor._point(0)
					if reset_states:
						_expect(int(point.get(&"handle_mode")) == mode, "State reset changed Handle Mode")
						if mode == 4:
							_expect(editor._point_control_states_are_default(point), "LR reset left hidden overrides")
						else:
							var display_side: int = EasingCurvePoint.ControlSide.LEFT if reset_target == 1 else EasingCurvePoint.ControlSide.RIGHT
							_expect(editor._point_control_side_is_default(point, display_side), "Side reset left hidden overrides")
							var opposite_side: int = editor._backend.display_control_side_to_curve(1 - display_side)
							var force_property := &"left_force_linear" if opposite_side == 0 else &"right_force_linear"
							var lock_property := &"left_control_point" if opposite_side == 0 else &"right_control_point"
							_expect(point.get(force_property) == overrides[opposite_side] and point.get(&"locked").get(lock_property) == overrides[2].get(lock_property), "Side reset changed the opposite side")
						_expect(point.get(&"locked").get(&"position"), "State reset cleared position lock")
						_expect([point.get(&"position"), point.get(&"left_control_point"), point.get(&"right_control_point")] == geometry, "State reset changed handle geometry")
					else:
						_expect(int(point.get(&"handle_mode")) == EasingCurvePoint.HandleMode.FREE, "Mode reset did not select Free")
						_expect(_stored_overrides(point) == overrides, "Mode reset changed stored L/R flags")
					var after: Variant = editor._backend.capture_snapshot()
					_expect(button.disabled and button.get_global_rect() == reset_rect, "Reset availability shifted its slot")
					_expect(editor._get_graph_view_rect().size == dimensions, "Reset changed graph dimensions")
					_expect(history.undo(), "Reset Undo failed")
					_expect(editor._backend.capture_snapshot() == before, "Reset Undo did not restore complete snapshot")
					_expect(not history.has_undo(), "Reset created multiple Undo actions")
					_expect(history.redo(), "Reset Redo failed")
					_expect(editor._backend.capture_snapshot() == after, "Reset Redo did not restore complete snapshot")
			for shared: bool in [false, true]:
				await _test_state_dropdown_edit(editor, manager, history, shared)
			print("RESET_GATE backend=%s reverse=%s mode, separate side and LR edits preserve independent state and Undo/Redo" % ["native" if native else "legacy", reverse_sides])
			manager.clear_history()
			viewport.free()
	plugin.free()


func _test_state_dropdown_edit(editor: EasingCurveEditor, manager: EditorUndoRedoManager, history: UndoRedo, shared: bool) -> void:
	editor._backend.apply_point_property(0, &"toolbar_options_reset", true, false)
	editor._backend.apply_point_property(0, &"handle_mode", 4 if shared else 0, false)
	editor._update_point_toolbar()
	await _settle()
	manager.clear_history()
	var option := editor._point_left_state if shared else editor._point_right_state
	_expect(not option.disabled and option.is_visible_in_tree(), "State-edit fixture selected an unavailable dropdown")
	var before: Variant = editor._backend.capture_snapshot()
	var item := option.get_item_index(EasingCurvePoint.ControlState.LINEAR)
	option.select(item)
	option.item_selected.emit(item)
	await _settle()
	_expect(history.get_history_count() == 1, "Dropdown edit did not create one Undo action")
	_expect(editor._get_point_toolbar_control_state(0, EasingCurvePoint.ControlSide.RIGHT) == EasingCurvePoint.ControlState.LINEAR, "Dropdown edit missed the displayed side")
	_expect(editor._get_point_toolbar_control_state(0, EasingCurvePoint.ControlSide.LEFT) == (EasingCurvePoint.ControlState.LINEAR if shared else EasingCurvePoint.ControlState.FREE), "Dropdown edit changed the wrong set of sides")
	var after: Variant = editor._backend.capture_snapshot()
	_expect(history.undo() and editor._backend.capture_snapshot() == before, "Dropdown Undo did not restore complete snapshot")
	_expect(not history.has_undo(), "Dropdown edit created multiple actions")
	_expect(history.redo() and editor._backend.capture_snapshot() == after, "Dropdown Redo did not restore complete snapshot")


func _click(viewport: SubViewport, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = true
	viewport.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)


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

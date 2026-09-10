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
	_test_mode_override_transitions()
	_test_locked_handle_precedence()
	await _test_grouped_toolbar()
	await _test_independent_resets()
	await _test_layout_variants()
	await _test_variant_resets()
	await _test_sibling_capture()
	await _test_graph_dimensions()
	_finish("curve layout contract")


func _test_mode_override_transitions() -> void:
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
				point = backend.get_point(0)
				var locked_position: Vector2 = point.get(&"left_control_point" if flags & 4 else &"right_control_point")
				_expect(backend.apply_point_property(0, &"handle_mode", EasingCurvePoint.HandleMode.LINKED, false), "Linked mode edit was rejected")
				point = backend.get_point(0)
				var locks: Dictionary = point.get(&"locked")
				var shared_locked := bool(flags & 12)
				var shared_linear := bool(flags & 3) and not shared_locked
				_expect(bool(locks[&"left_control_point"]) == shared_locked and bool(locks[&"right_control_point"]) == shared_locked, "Entering Linked did not combine stored locks: native=%s flags=%s" % [native, flags])
				_expect(bool(point.get(&"left_force_linear")) == shared_linear and bool(point.get(&"right_force_linear")) == shared_linear, "Entering Linked did not combine stored Force Linear: native=%s flags=%s" % [native, flags])
				_expect(locks[&"position"] == before[2][&"position"], "Entering Linked changed position lock")
				if (flags & 12) in [4, 8]:
					_expect(point.get(&"left_control_point") == locked_position and point.get(&"right_control_point") == locked_position, "Linked ignored the uniquely locked handle position")
		print("FREE_MODE_GATE backend=%s preserved overrides for all modes and flag combinations" % ["native" if native else "legacy"])


func _test_locked_handle_precedence() -> void:
	for native: bool in [false, true]:
		for locked_side: int in [0, 1]:
			for opposite_state: int in EasingCurvePoint.ControlState.values():
				var curve: Resource = ClassDB.instantiate(&"NativeEasingCurve") if native else EasingCurve.new()
				curve.set(&"transition" if native else &"trans_type", 100 if native else EasingCurve.TRANS.CUSTOM)
				var backend = EasingCurveEditor.BackendFactory.create(curve)
				var point: Resource = backend.get_point(0)
				var locked_property := &"left_control_point" if locked_side == 0 else &"right_control_point"
				var opposite_property := &"right_control_point" if locked_side == 0 else &"left_control_point"
				var short_handle := Vector2(0.1, 0.1)
				var long_handle := Vector2(0.8, 0.2)
				point.set(locked_property, short_handle)
				point.set(opposite_property, long_handle)
				point.call(&"set_locked", locked_property, true)
				point.call(&"set_locked", opposite_property, opposite_state == EasingCurvePoint.ControlState.LOCKED)
				point.set(&"right_force_linear" if locked_side == 0 else &"left_force_linear", opposite_state == EasingCurvePoint.ControlState.LINEAR)
				_expect(backend.apply_point_property(0, &"handle_mode", EasingCurvePoint.HandleMode.LINKED, false), "Linked precedence edit failed")
				point = backend.get_point(0)
				var expected := long_handle if opposite_state == EasingCurvePoint.ControlState.LOCKED else short_handle
				_expect(point.get(&"left_control_point") == expected and point.get(&"right_control_point") == expected, "Linked chose a longer unlocked control over the locked control, or lost the both-locked tie rule")
				_expect(not point.get(&"left_force_linear") and not point.get(&"right_force_linear"), "Locked precedence left stale Linear flags")


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
		var presentation: Control = context.handle_easing_curve_editor(curve, EasingCurveEditor.ControlsLayout.CURRENT_TWO_ROW)
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
		_expect(toolbar is VBoxContainer and toolbar.get_child_count() == 2, "Toolbar must contain mode and shared state rows")
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
					_expect(is_equal_approx(toolbar.size.y, row_height), "Linked must retain the shared toolbar row height")
					_expect(editor._get_graph_view_rect().size == dimensions, "Point state changed graph dimensions")
					_expect(editor._point_left_state.disabled == (mode not in [0, 4]), "Left state availability does not match mode")
					_expect(editor._point_right_state.disabled == (mode not in [0, 4]), "Right state availability does not match mode")
					if native and mode not in [0, 4]:
						_expect(editor._point_left_state.get_selected_id() == EasingCurvePoint.ControlState.LINEAR, "Disabled Left field hid its stored Linear state")
						_expect(editor._point_right_state.get_selected_id() == EasingCurvePoint.ControlState.LOCKED, "Disabled Right field hid its stored Lock state")
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
			_expect(editor._point_left_state.disabled if index == 0 else editor._point_right_state.disabled, "Linked missing endpoint side accepts input")
			_expect(not editor._point_right_state.disabled if index == 0 else not editor._point_left_state.disabled, "Linked endpoint lost its available side")
		editor.selected_index = -1
		editor._update_point_toolbar()
		await _settle()
		_expect(not editor._point_states_row.visible, "No selection reserves state rows")
		presentation.free()
		backdrop.free()
		await _settle()


func _assert_fixed_rows(editor: EasingCurveEditor, preset_reset: Button) -> void:
	var first := editor._point_mode_row
	var second := editor._point_states_row
	var linked := int(editor._point(editor.selected_index).get(&"handle_mode")) == EasingCurvePoint.HandleMode.LINKED
	_expect(first.visible and second.visible and editor._point_left_group.visible and editor._point_right_group.visible, "Mode has the wrong visible rows or side controls")
	_expect(first.get_rect().end.y <= second.position.y, "Logical rows overlap")
	_expect(editor._point_left_state_label.text == "L" and editor._point_right_state_label.text == "R", "Side labels changed with mode")
	_expect(editor._point_handle_mode.get_parent().get_parent() == first, "Handle Mode left Row 1")
	_expect(editor._point_reorder_buttons.get_parent().get_parent() == first, "Navigation left Row 1")
	_expect(editor._point_left_group.get_parent() == second and editor._point_right_group.get_parent() == second, "Side controls must share a row")
	if linked:
		_expect(editor._point_left_state.get_selected_id() == editor._get_point_toolbar_control_state(editor.selected_index, EasingCurvePoint.ControlSide.RIGHT), "Left field does not show the shared Linked state")
		_expect(editor._point_left_state.get_selected_id() == editor._point_right_state.get_selected_id(), "Linked fields disagree")
	_expect(editor._point_left_state.global_position.y == editor._point_right_state.global_position.y, "L/R fields do not share a row")
	_expect(absf(editor._point_left_state.size.x - editor._point_right_state.size.x) <= 1.0, "Side fields have different allocations")
	for row: HBoxContainer in [first, second]:
		if not row.visible:
			continue
		var previous_end := 0.0
		for child: Control in row.get_children():
			if not child.visible:
				continue
			_expect(child.position.x >= previous_end - 0.01 and child.get_rect().end.x <= row.size.x + 0.01, "Row contents overlap or overflow")
			previous_end = child.get_rect().end.x
	for button: Button in [editor._point_reset_button, editor._point_states_reset_button]:
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
			var presentation: Control = context.handle_easing_curve_editor(curve, EasingCurveEditor.ControlsLayout.CURRENT_TWO_ROW)
			viewport.add_child(presentation)
			presentation.size.x = 220.0
			var editor: EasingCurveEditor = context.easing_curve_editor
			editor.selected_index = 0
			await _settle()
			var history := manager.get_history_undo_redo(manager.get_object_history_id(curve))
			for mode: int in EasingCurvePoint.HandleMode.values():
				for reset_target: int in [0, 1]:
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
					var buttons: Array[Button] = [editor._point_reset_button, editor._point_states_reset_button]
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
						_expect(editor._point_control_states_are_default(point), "Shared reset left hidden overrides")
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
				for point_index: int in [0, 1]:
					for control_state: int in EasingCurvePoint.ControlState.values():
						await _test_state_dropdown_edit(editor, manager, history, shared, point_index, control_state)
			for point_index: int in [0, 1]:
				for locked_side: StringName in [&"left_control_point", &"right_control_point"]:
					await _test_enter_linked_with_one_lock(editor, manager, history, point_index, locked_side)
			print("RESET_GATE backend=%s reverse=%s mode/shared resets and Linked side edits preserve state and Undo/Redo" % ["native" if native else "legacy", reverse_sides])
			await _test_inactive_override_drags(editor, manager, history)
			manager.clear_history()
			viewport.free()
	plugin.free()


func _test_inactive_override_drags(editor: EasingCurveEditor, manager: EditorUndoRedoManager, history: UndoRedo) -> void:
	var point: Resource = editor._backend.create_point(Vector2(0.5, 0.5))
	var point_index: int = editor._backend.add_point(point)
	editor.selected_index = point_index
	point.set(&"left_force_linear", true)
	point.call(&"set_locked", &"right_control_point", true)
	var stored := _stored_overrides(point)
	for mode: int in [3, 2, 1, 3, 0, 3]:
		editor._backend.apply_point_property(point_index, &"handle_mode", mode, false)
		editor._update_point_toolbar()
		await _settle()
		_expect(_stored_overrides(editor._point(point_index)) == stored, "Mode transition changed inactive L/R overrides")
		if mode not in [EasingCurvePoint.HandleMode.MIRRORED, EasingCurvePoint.HandleMode.BALANCED]:
			continue
		for display_side: int in [EasingCurvePoint.ControlSide.LEFT, EasingCurvePoint.ControlSide.RIGHT]:
			editor.autofit()
			await _settle()
			manager.clear_history()
			point = editor._point(point_index)
			var before: Variant = editor._backend.capture_snapshot()
			var start := editor.get_view_pos(editor._backend.get_display_control_point(point, display_side))
			_expect(editor.get_control_at(start)[0] == point_index, "Inactive override drag missed its interior handle")
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = editor.global_position + start
			editor.get_viewport().push_input(press, true)
			_expect(editor.dragging_point == point_index, "Inactive Lock blocked a handle drag")
			var motion := InputEventMouseMotion.new()
			motion.relative = Vector2(12.0, -18.0)
			motion.position = press.position + motion.relative
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			editor.get_viewport().push_input(motion, true)
			var release := press.duplicate() as InputEventMouseButton
			release.pressed = false
			release.position = motion.position
			editor.get_viewport().push_input(release, true)
			await _settle()
			point = editor._point(point_index)
			_expect(_stored_overrides(point) == stored, "Viewport drag rewrote inactive overrides")
			for property_name: StringName in [&"left_control_point", &"right_control_point"]:
				_expect(not (point.get(property_name) as Vector2).is_equal_approx(point.get(&"position")), "Inactive Force Linear collapsed a handle during viewport drag")
			var after: Variant = editor._backend.capture_snapshot()
			_expect(after != before and history.get_history_count() == 1, "Handle drag did not commit one geometry edit")
			_expect(history.undo() and _drag_snapshots_match(editor._backend.capture_snapshot(), before), "Handle drag Undo lost geometry or inactive overrides")
			_expect(history.redo() and _drag_snapshots_match(editor._backend.capture_snapshot(), after), "Handle drag Redo lost geometry or inactive overrides")


func _drag_snapshots_match(actual: Dictionary, expected: Dictionary) -> bool:
	if actual == expected:
		return true
	if actual[&"point_states"] is not Dictionary:
		return false
	# Legacy restores modes through float32 geometry setters. Permit only tiny
	# handle rounding; resource order, positions, modes and overrides stay exact.
	var normalized := actual.duplicate()
	var states: Dictionary = actual[&"point_states"].duplicate()
	for property_name: StringName in [&"left_control_points", &"right_control_points"]:
		var values: PackedVector2Array = states[property_name]
		var target: PackedVector2Array = expected[&"point_states"][property_name]
		if values.size() != target.size():
			return false
		for index in range(values.size()):
			if values[index].distance_to(target[index]) > 0.000001:
				return false
		states[property_name] = target
	normalized[&"point_states"] = states
	return normalized == expected


func _test_enter_linked_with_one_lock(editor: EasingCurveEditor, manager: EditorUndoRedoManager, history: UndoRedo, point_index: int, locked_side: StringName) -> void:
	editor.selected_index = point_index
	editor._backend.apply_point_property(point_index, &"toolbar_options_reset", true, false)
	var point := editor._point(point_index)
	var opposite_force := &"right_force_linear" if locked_side == &"left_control_point" else &"left_force_linear"
	point.set(opposite_force, true)
	point.call(&"set_locked", locked_side, true)
	var locked_position: Vector2 = point.get(locked_side)
	editor._update_point_toolbar()
	await _settle()
	manager.clear_history()
	var before: Variant = editor._backend.capture_snapshot()
	var option := editor._point_handle_mode
	var item := option.get_item_index(EasingCurvePoint.HandleMode.LINKED)
	option.select(item)
	option.item_selected.emit(item)
	await _settle()
	_expect(history.get_history_count() == 1, "Entering Linked did not create one Undo action")
	for property_name: StringName in [&"left_control_point", &"right_control_point"]:
		_expect(editor._backend.is_point_property_locked(point_index, property_name), "Entering Linked displays Locked but leaves a movable handle")
	_expect(editor._point_left_state.get_selected_id() == EasingCurvePoint.ControlState.LOCKED and editor._point_right_state.get_selected_id() == EasingCurvePoint.ControlState.LOCKED, "Entering Linked did not refresh both Locked dropdowns")
	point = editor._point(point_index)
	_expect(not point.get(&"left_force_linear") and not point.get(&"right_force_linear"), "Linked Locked retained a competing Linear override")
	_expect(point.get(&"left_control_point") == locked_position and point.get(&"right_control_point") == locked_position, "Linked Locked moved away from the locked handle position")
	var after: Variant = editor._backend.capture_snapshot()
	await _assert_linked_handle_cannot_drag(editor, point_index)
	_expect(editor._backend.capture_snapshot() == after, "Viewport drag moved a handle after entering Linked with one lock")
	_expect(history.undo() and editor._backend.capture_snapshot() == before, "Linked Undo did not restore the asymmetric Free state")
	_expect(not history.has_undo(), "Entering Linked created multiple Undo actions")
	_expect(history.redo() and editor._backend.capture_snapshot() == after, "Linked Redo did not restore shared locks")
	editor._backend.apply_point_property(point_index, &"handle_mode", EasingCurvePoint.HandleMode.FREE, false)
	point = editor._point(point_index)
	_expect(point.get(&"left_control_point") == locked_position and point.get(&"right_control_point") == locked_position, "Returning to Free reapplied a discarded Linear override")
	editor._backend.apply_point_property(point_index, &"handle_mode", EasingCurvePoint.HandleMode.LINEAR, false)
	point = editor._point(point_index)
	_expect(point.get(&"left_control_point") == point.get(&"position") and point.get(&"right_control_point") == point.get(&"position"), "Explicit Linear Handle Mode no longer collapses both controls")


func _test_state_dropdown_edit(editor: EasingCurveEditor, manager: EditorUndoRedoManager, history: UndoRedo, shared: bool, point_index: int, control_state: int) -> void:
	editor.selected_index = point_index
	editor._backend.apply_point_property(point_index, &"toolbar_options_reset", true, false)
	editor._backend.apply_point_property(point_index, &"handle_mode", 4 if shared else 0, false)
	var side := EasingCurvePoint.ControlSide.RIGHT if point_index == 0 else EasingCurvePoint.ControlSide.LEFT
	var curve_side: int = editor._backend.display_control_side_to_curve(side)
	var point := editor._point(point_index)
	for stored_side: int in [EasingCurvePoint.ControlSide.LEFT, EasingCurvePoint.ControlSide.RIGHT] if shared else [curve_side]:
		if control_state == EasingCurvePoint.ControlState.LOCKED:
			point.set(&"left_force_linear" if stored_side == EasingCurvePoint.ControlSide.LEFT else &"right_force_linear", true)
		else:
			point.call(&"set_locked", &"left_control_point" if stored_side == EasingCurvePoint.ControlSide.LEFT else &"right_control_point", true)
	editor._update_point_toolbar()
	await _settle()
	manager.clear_history()
	var option := editor._point_right_state if point_index == 0 else editor._point_left_state
	_expect(not option.disabled and option.is_visible_in_tree(), "State-edit fixture selected an unavailable dropdown")
	var before: Variant = editor._backend.capture_snapshot()
	var item := option.get_item_index(control_state)
	option.select(item)
	option.item_selected.emit(item)
	await _settle()
	_expect(history.get_history_count() == 1, "Dropdown edit did not create one Undo action")
	for display_side: int in [EasingCurvePoint.ControlSide.LEFT, EasingCurvePoint.ControlSide.RIGHT]:
		var expected_state := control_state if shared or display_side == side else EasingCurvePoint.ControlState.FREE
		_expect(editor._get_point_toolbar_control_state(point_index, display_side) == expected_state, "Dropdown edit changed the wrong set of sides")
		var stored_side: int = editor._backend.display_control_side_to_curve(display_side)
		var lock_property := &"left_control_point" if stored_side == EasingCurvePoint.ControlSide.LEFT else &"right_control_point"
		var force_property := &"left_force_linear" if stored_side == EasingCurvePoint.ControlSide.LEFT else &"right_force_linear"
		_expect(editor._backend.is_point_property_locked(point_index, lock_property) == (expected_state == EasingCurvePoint.ControlState.LOCKED), "Displayed lock state differs from actual handle drag lock")
		_expect(bool(point.get(force_property)) == (expected_state == EasingCurvePoint.ControlState.LINEAR), "Dropdown edit left a stale stored Force Linear flag")
	var after: Variant = editor._backend.capture_snapshot()
	if shared and control_state == EasingCurvePoint.ControlState.LOCKED:
		await _assert_linked_handle_cannot_drag(editor, point_index)
		_expect(editor._backend.capture_snapshot() == after, "Viewport drag moved a locked Linked handle")
	_expect(history.undo() and editor._backend.capture_snapshot() == before, "Dropdown Undo did not restore complete snapshot")
	_expect(not history.has_undo(), "Dropdown edit created multiple actions")
	_expect(history.redo() and editor._backend.capture_snapshot() == after, "Dropdown Redo did not restore complete snapshot")


func _assert_linked_handle_cannot_drag(editor: EasingCurveEditor, point_index: int) -> void:
	editor.autofit()
	await _settle()
	var point := editor._point(point_index)
	var display_side := EasingCurvePoint.ControlSide.RIGHT if editor._get_display_points().find(point) == 0 else EasingCurvePoint.ControlSide.LEFT
	var local_position := editor.get_view_pos(editor._backend.get_display_control_point(point, display_side))
	_expect(editor.get_control_at(local_position)[0] == point_index, "Locked drag fixture missed the visible handle")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = editor.global_position + local_position
	editor.get_viewport().push_input(press, true)
	_expect(editor.dragging_point == -1, "Locked Linked handle started a viewport drag")
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(20.0, -15.0)
	motion.relative = Vector2(20.0, -15.0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	editor.get_viewport().push_input(motion, true)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.position = motion.position
	editor.get_viewport().push_input(release, true)
	_expect(editor.dragging_point == -1, "Locked Linked handle retained a gesture")


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


func _comparison_curve(native: bool) -> Resource:
	var curve: Resource = ClassDB.instantiate(&"NativeEasingCurve") if native else EasingCurve.new()
	curve.set(&"transition" if native else &"trans_type", 100 if native else EasingCurve.TRANS.CUSTOM)
	if native:
		var point: Resource = ClassDB.instantiate(&"NativeEasingCurvePoint")
		point.set(&"position", Vector2(0.5, 0.5))
		curve.call(&"insert_point", 1, point)
	else:
		curve.set(&"points", [EasingCurvePoint.new(Vector2.ZERO), EasingCurvePoint.new(Vector2(0.5, 0.5)), EasingCurvePoint.new(Vector2.ONE)] as Array[EasingCurvePoint])
	return curve


func _test_layout_variants() -> void:
	for native: bool in [false, true]:
		var baseline_width := -1.0
		for layout: int in EasingCurveEditor.ControlsLayout.values():
			var compact := layout == EasingCurveEditor.ControlsLayout.COMPACT_TWO_ROW
			var single_row := layout == EasingCurveEditor.ControlsLayout.DEV_SINGLE_ROW
			var curve := _comparison_curve(native)
			var context := HOST.INSPECTOR_PLUGIN.new()
			var presentation := context.handle_easing_curve_editor(curve, layout)
			var editor: EasingCurveEditor = context.easing_curve_editor
			_expect(editor.controls_layout == layout, "Construction override did not select layout")
			var backdrop := ColorRect.new()
			backdrop.color = Color(0.16, 0.16, 0.16)
			backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
			backdrop.size = Vector2(root.size)
			root.add_child(backdrop)
			root.add_child(presentation)
			await _settle()
			if baseline_width < 0:
				baseline_width = presentation.get_combined_minimum_size().x
			_expect(presentation.get_combined_minimum_size().x == baseline_width, "Layout variant changed Inspector minimum width")
			for hide_unused: bool in [true, false]:
				editor.hide_unused_controls = hide_unused
				var hide_groups := single_row or (compact and hide_unused)
				for point_index: int in [0, 1, 2]:
					editor.selected_index = point_index
					for mode: int in EasingCurvePoint.HandleMode.values():
						editor._backend.apply_point_property(point_index, &"toolbar_options_reset", true, false)
						editor._backend.apply_point_property(point_index, &"handle_mode", mode, false)
						editor._update_point_toolbar()
						var supports := mode in [EasingCurvePoint.HandleMode.FREE, EasingCurvePoint.HandleMode.LINKED]
						var left_available := supports and point_index > 0
						var right_available := supports and point_index < 2
						_expect(editor._point_left_state.disabled == not left_available, "Left availability changed across layouts")
						_expect(editor._point_right_state.disabled == not right_available, "Right availability changed across layouts")
						_expect(editor._point_left_group.visible == (left_available or not hide_groups), "Left group visibility ignored layout policy")
						_expect(editor._point_right_group.visible == (right_available or not hide_groups), "Right group visibility ignored layout policy")
						for group: HBoxContainer in [editor._point_left_group, editor._point_right_group]:
							_expect(group.get_child(0).visible == group.visible, "Side label did not hide atomically")
						_expect(editor._point_states_row.visible == (not single_row and (not compact or supports)), "Empty state row retained space or applicable row disappeared")
						_expect(editor._point_reset_button.visible and editor._point_states_reset_button.visible, "Reset slot visibility changed")
					editor._backend.apply_point_property(point_index, &"toolbar_options_reset", true, false)
					editor._update_point_toolbar()
					editor._set_point_toolbar_reorder_available(false)
					_expect(editor._point_move_left_button.visible == not hide_groups, "Unavailable navigation ignored layout policy")
					editor._update_point_toolbar()
					editor.selected_index = -1
					await _settle()
					_expect(editor._point_toolbar_panel.visible == not compact, "No-selection empty panel did not follow layout policy")
					editor.selected_index = 1
					await _settle()
					_expect(editor._point_toolbar_panel.visible, "Selection failed to restore toolbar")
				for scale_value: float in [1.0, 1.5, 2.0]:
					var theme := Theme.new()
					theme.default_font_size = roundi(16.0 * scale_value)
					presentation.theme = theme
					editor._editor_scale = scale_value
					for width: float in [150.0, 220.0, 600.0]:
						presentation.size.x = width * scale_value
						editor._backend.apply_point_property(1, &"toolbar_options_reset", true, false)
						editor._update_point_toolbar()
						await _settle()
						var graph_size := editor._get_graph_view_rect().size
						var expanded_height := editor.get_combined_minimum_size().y
						var reset_rect := editor._point_states_reset_button.get_global_rect()
						_expect(editor._graph_canvas.size.x == editor.size.x, "Variant widened graph beyond Inspector")
						_expect(editor.get_combined_minimum_size().x == 64.0 * scale_value, "Variant propagated control minimum width")
						if single_row:
							_expect(editor._point_mode_row.get_parent().clip_contents, "Single row lost right-edge clipping")
							_expect(editor._point_left_group.get_parent() == editor._point_mode_row and editor._point_right_group.get_parent() == editor._point_mode_row, "Single-row controls wrapped")
							_expect(not editor._point_states_reset_button.is_visible_in_tree(), "Single row shows a second reset")
						else:
							_assert_fixed_rows(editor, presentation.get_child(0).get_child(5) as Button)
						if scale_value == 1.0 and DisplayServer.get_name() != "headless":
							await _capture_layout(presentation, "layout-%s-%s-hide-%s-%s" % [native, layout, hide_unused, int(width)])
							editor.selected_index = 0
							await _capture_layout(presentation, "layout-endpoint-%s-%s-hide-%s-%s" % [native, layout, hide_unused, int(width)])
							editor.selected_index = 1
						editor._backend.apply_point_property(1, &"handle_mode", EasingCurvePoint.HandleMode.BALANCED, false)
						editor._update_point_toolbar()
						await _settle()
						_expect(editor._get_graph_view_rect().size == graph_size, "Row collapse changed graph dimensions")
						_expect((editor.get_combined_minimum_size().y < expanded_height) == compact, "Empty row did not collapse with its separation")
						if scale_value == 1.0 and DisplayServer.get_name() != "headless":
							await _capture_layout(presentation, "layout-balanced-%s-%s-hide-%s-%s" % [native, layout, hide_unused, int(width)])
						editor._point(1).set(&"left_force_linear", true)
						editor._update_point_toolbar()
						await _settle()
						if compact:
							_expect(editor._point_states_row.visible, "Active reset became inaccessible with hidden overrides")
							_expect(editor._point_states_reset_button.get_global_rect() == reset_rect, "Reset slot shifted when side groups hid")
						editor._backend.apply_point_property(1, &"toolbar_options_reset", true, false)
						editor._update_point_toolbar()
						await _settle()
						_expect(editor.get_combined_minimum_size().y == expanded_height, "Restored controls changed layout height")
						var minimum_width := presentation.get_combined_minimum_size().x
						var original_text := editor._point_handle_mode.get_item_text(editor._point_handle_mode.selected)
						editor._point_handle_mode.set_item_text(editor._point_handle_mode.selected, "Long localized handle mode description")
						await _settle()
						_expect(presentation.get_combined_minimum_size().x == minimum_width and editor._get_graph_view_rect().size == graph_size, "Preferred text width escaped variant clipping")
						editor._point_handle_mode.set_item_text(editor._point_handle_mode.selected, original_text)
				editor.selected_index = 1
				presentation.theme = null
				editor._editor_scale = 1.0
				await _settle()
			curve.set(&"transition" if native else &"trans_type", 6 if native else EasingCurve.TRANS.ELASTIC)
			editor._update_point_toolbar()
			_expect(not editor._point_toolbar_panel.visible and not editor._snap_toolbar_margin.visible, "Function mode exposed point controls")
			print("WRAP_GATE layout=%s native=%s comparison policies and widths verified" % [layout, native])
			presentation.free()
			backdrop.free()


func _capture_layout(presentation: Control, capture_name: String) -> void:
	await _settle()
	presentation.size.y = presentation.get_combined_minimum_size().y
	await _settle()
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image().get_region(Rect2i(presentation.get_global_rect()))
	capture.save_png("res://test/_temp/%s.png" % capture_name)


func _test_variant_resets() -> void:
	var plugin := EditorPlugin.new()
	var manager := plugin.get_undo_redo()
	for native: bool in [false, true]:
		for layout: int in [EasingCurveEditor.ControlsLayout.COMPACT_TWO_ROW, EasingCurveEditor.ControlsLayout.DEV_SINGLE_ROW]:
			var curve := _comparison_curve(native)
			var context := HOST.INSPECTOR_PLUGIN.new()
			context.editor_undo_redo = manager
			var presentation := context.handle_easing_curve_editor(curve, layout)
			var viewport := SubViewport.new()
			viewport.size = Vector2i(600, 900)
			root.add_child(viewport)
			viewport.add_child(presentation)
			presentation.size.x = 600
			var editor: EasingCurveEditor = context.easing_curve_editor
			editor.selected_index = 1
			await _settle()
			var history := manager.get_history_undo_redo(manager.get_object_history_id(curve))
			var single_row := layout == EasingCurveEditor.ControlsLayout.DEV_SINGLE_ROW
			for reset_states: bool in [false, true]:
				editor._backend.apply_point_property(1, &"toolbar_options_reset", true, false)
				var point := editor._point(1)
				point.set(&"left_force_linear", true)
				point.call(&"set_locked", &"right_control_point", true)
				point.call(&"set_locked", &"position", true)
				point.set(&"handle_mode", EasingCurvePoint.HandleMode.BALANCED)
				editor._update_point_toolbar()
				await _settle()
				manager.clear_history()
				var before: Variant = editor._backend.capture_snapshot()
				var button := editor._point_states_reset_button if reset_states and not single_row else editor._point_reset_button
				_click(viewport, button.get_global_rect().get_center())
				await _settle()
				point = editor._point(1)
				_expect(history.get_history_count() == 1, "Variant reset did not create one transaction")
				_expect(int(point.get(&"handle_mode")) == (EasingCurvePoint.HandleMode.BALANCED if reset_states and not single_row else EasingCurvePoint.HandleMode.FREE), "Variant reset changed wrong mode")
				_expect(editor._point_control_states_are_default(point) == (single_row or reset_states), "Variant reset changed wrong control states")
				_expect(point.get(&"locked").get(&"position"), "Variant reset cleared position lock")
				var after: Variant = editor._backend.capture_snapshot()
				_expect(history.undo() and editor._backend.capture_snapshot() == before, "Variant reset Undo lost state")
				await _settle()
				_expect(not button.disabled and button.is_visible_in_tree(), "Undo did not restore reset control")
				_expect(history.redo() and editor._backend.capture_snapshot() == after, "Variant reset Redo lost state")
			manager.clear_history()
			viewport.free()
	plugin.free()


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

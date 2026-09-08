extends "res://test/scripts/support/test_case.gd"


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(Engine.is_editor_hint() and ClassDB.class_exists(&"NativeEasingCurve"), "Requires Editor host and Native extension")
	if not Engine.is_editor_hint() or not ClassDB.class_exists(&"NativeEasingCurve"):
		_finish("graph add selection")
		return
	for native: bool in [false, true]:
		await _test_graph_gesture_selection(native)
		await _test_graph_gesture_selection(native, false)
	await _test_legacy_drag_selection_survives_context_rebuild()
	_finish("graph add selection")


func _test_graph_gesture_selection(native: bool, pending_add := true) -> void:
	var host := EditorPlugin.new()
	var manager := host.get_undo_redo()
	var resource: Resource
	if native:
		resource = ClassDB.instantiate(&"NativeEasingCurve")
		resource.set(&"transition", 100)
	else:
		var legacy := EasingCurve.new()
		legacy.trans_type = EasingCurve.TRANS.CUSTOM
		legacy.points = [EasingCurvePoint.new(Vector2.ZERO), EasingCurvePoint.new(Vector2.ONE)]
		resource = legacy
	var legacy_selection_registry: Dictionary[int, Dictionary] = {}
	var context := InspectorCurveContext.new()
	context.editor_undo_redo = manager
	if not native:
		context._legacy_selection_by_resource = legacy_selection_registry
	context._parse_begin(resource)
	var graph := context.handle_easing_curve_editor(resource)
	root.add_child(graph)
	var list: Control = context._handle_native_points(resource) if native else context._create_points_section(context.handle_points(resource), resource)
	root.add_child(list)
	await process_frame
	var editor := context.easing_curve_editor
	editor.use_pending_add = pending_add
	editor.selected_index = 0
	var publications := [0]
	resource.changed.connect(func() -> void: publications[0] += 1)
	var selections := [0]
	editor.point_selection_changed.connect(func(_point: Resource) -> void: selections[0] += 1)
	for position: Vector2 in [Vector2(0.5, 0.7), Vector2(0.08, 0.8), Vector2(0.92, 0.65), Vector2(0.3, 0.45)]:
		manager.clear_history()
		var before: Dictionary = resource.call(&"get_editor_state_snapshot")
		var selected_before := editor.get_selected_point_resource()
		var selected_position: Vector2 = selected_before.get(&"position") if selected_before != null else Vector2.INF
		var count_before := editor._point_count()
		editor.size = Vector2(600, 350)
		editor.update_view_transform()
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = editor.get_view_pos(position)
		var publications_before: int = publications[0]
		var selections_before: int = selections[0]
		editor._gui_input(press)
		var pending := editor.pending_add_point
		_expect((pending != null and editor._point_count() == count_before) if pending_add else (pending == null and editor._point_count() == count_before + 1), "Graph press changed pending-add semantics")
		if pending_add and pending == null:
			break
		var requested_position: Vector2 = pending.get(&"position") if pending_add else position
		if pending_add:
			for cycle in range(2):
				var shift := InputEventKey.new()
				shift.keycode = KEY_SHIFT
				shift.pressed = true
				shift.shift_pressed = true
				Input.parse_input_event(shift)
				Input.flush_buffered_events()
				_expect(editor._axis_drag_reference_active, "Input Shift press did not capture pending reference")
				_expect(editor._axis_drag_origin_world.is_equal_approx(requested_position), "Shift press did not capture current pending position")
				var cursor_anchor := editor._axis_drag_origin_view
				var echo := shift.duplicate() as InputEventKey
				echo.echo = true
				Input.parse_input_event(echo)
				Input.flush_buffered_events()
				_expect(editor._axis_drag_origin_view == cursor_anchor, "Shift echo recaptured pending cursor anchor")
				var motion := InputEventMouseMotion.new()
				motion.position = press.position + Vector2(12, -8) * (cycle + 1)
				motion.button_mask = MOUSE_BUTTON_MASK_LEFT
				motion.shift_pressed = true
				var expected: Vector2 = editor._backend.display_to_curve_position(editor.get_world_pos(motion.position))
				var delta := motion.position - cursor_anchor
				if absf(delta.x) > absf(delta.y):
					expected.y = requested_position.y
				else:
					expected.x = requested_position.x
				expected = expected.clamp(Vector2.ZERO, Vector2.ONE)
				editor._gui_input(motion)
				requested_position = pending.get(&"position")
				_expect(requested_position.is_equal_approx(expected), "Pending Shift motion used incorrect anchors")
				var shift_release := InputEventKey.new()
				shift_release.keycode = KEY_SHIFT
				Input.parse_input_event(shift_release)
				Input.flush_buffered_events()
				_expect(not editor._axis_drag_reference_active, "Stationary Shift release retained pending reference")
				_expect((pending.get(&"position") as Vector2).is_equal_approx(requested_position), "Shift release moved pending point")
				_expect(resource.call(&"get_editor_state_snapshot") == before, "Pending Shift changed resource before commit")
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = press.position
		editor._gui_input(release)
		var actual := _point_at_position(editor, requested_position)
		_expect(editor._point_count() == count_before + 1, "Graph add did not insert one point")
		_expect(actual != null, "Graph add lost requested position")
		_expect(editor.pending_add_point == null, "Graph add retained pending point")
		_expect_graph_add_selection(context, editor, actual, native, "immediate add")
		if not native:
			_expect(actual != pending, "Legacy fixture no longer exercises snapshot reconstruction")
		_expect(publications[0] == publications_before + 1, "Graph add published extra resource changes")
		var maximum_selections := (3 if pending_add else 4) if native else 2
		_expect(selections[0] - selections_before <= maximum_selections, "Graph add caused a selection loop")
		var after: Dictionary = resource.call(&"get_editor_state_snapshot")
		for frame in range(3):
			await process_frame
		_expect_graph_add_selection(context, editor, actual, native, "after refresh")
		var settled_selections: int = selections[0]
		await process_frame
		_expect(selections[0] == settled_selections, "Selection kept changing after add refresh settled")
		_expect(resource.call(&"get_editor_state_snapshot") == after and publications[0] == publications_before + 1, "Refresh mutated the added point")
		# The graph keeps the context alive while the list is rebuilt.
		list.free()
		var replacement: Control = context._handle_native_points(resource) if native else context._create_points_section(context.handle_points(resource), resource)
		root.add_child(replacement)
		list = replacement
		_expect_graph_add_selection(context, editor, actual, native, "rebuilt list")
		var history := manager.get_history_undo_redo(manager.get_object_history_id(resource))
		_expect(history.get_current_action_name() == "Add Easing Curve Point", "Graph add changed action name")
		_expect(history.undo(), "Graph add missing Undo")
		_expect(not history.has_undo(), "One graph add created multiple Undo actions")
		_expect(resource.call(&"get_editor_state_snapshot") == before, "Undo did not restore pre-add curve")
		var restored := editor.get_selected_point_resource()
		_expect(restored != null and restored.get(&"position") == selected_position, "Undo lost previous logical selection")
		_expect(history.redo(), "Graph add missing Redo")
		_expect(resource.call(&"get_editor_state_snapshot") == after, "Redo changed added point state")
		actual = _point_at_position(editor, requested_position)
		_expect_graph_add_selection(context, editor, actual, native, "Redo")
		await process_frame
		_expect_graph_add_selection(context, editor, actual, native, "Redo refresh")
		if not native:
			# Simulate the real Inspector property-list refresh: the plugin creates a
			# brand-new context and graph, while only plugin-owned transient state survives.
			graph.free()
			list.free()
			await process_frame
			var replacement_context := InspectorCurveContext.new()
			replacement_context.editor_undo_redo = manager
			replacement_context._legacy_selection_by_resource = legacy_selection_registry
			replacement_context._parse_begin(resource)
			var replacement_graph := replacement_context.handle_easing_curve_editor(resource)
			root.add_child(replacement_graph)
			var replacement_list := replacement_context._create_points_section(
				replacement_context.handle_points(resource), resource
			)
			root.add_child(replacement_list)
			context = replacement_context
			graph = replacement_graph
			list = replacement_list
			editor = context.easing_curve_editor
			editor.use_pending_add = pending_add
			editor.point_selection_changed.connect(func(_point: Resource) -> void: selections[0] += 1)
			actual = _point_at_position(editor, requested_position)
			_expect_graph_add_selection(context, editor, actual, native, "rebuilt Legacy context")
			await process_frame
			_expect_graph_add_selection(context, editor, actual, native, "rebuilt Legacy context refresh")
	list.free()
	graph.free()
	manager.clear_history()
	host.free()
	await process_frame


func _test_legacy_drag_selection_survives_context_rebuild() -> void:
	var host := EditorPlugin.new()
	var manager := host.get_undo_redo()
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [
		EasingCurvePoint.new(Vector2.ZERO),
		EasingCurvePoint.new(Vector2(0.25, 0.35)),
		EasingCurvePoint.new(Vector2(0.75, 0.7)),
		EasingCurvePoint.new(Vector2.ONE),
	]
	var selection_registry: Dictionary[int, Dictionary] = {}
	var context := InspectorCurveContext.new()
	context.editor_undo_redo = manager
	context._legacy_selection_by_resource = selection_registry
	context._parse_begin(curve)
	var graph := context.handle_easing_curve_editor(curve)
	root.add_child(graph)
	var list := context._create_points_section(context.handle_points(curve), curve)
	root.add_child(list)
	await process_frame
	var editor := context.easing_curve_editor
	editor.size = Vector2(600, 350)
	editor.update_view_transform()
	var dragged_point := curve.points[1]
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = editor.get_view_pos(dragged_point.position)
	editor._gui_input(press)
	_expect(editor.get_selected_point_resource() == dragged_point, "Legacy drag press did not select the point")
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = editor.get_view_pos(Vector2(0.85, 0.45))
	editor._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	editor._gui_input(release)
	var selected_after_drag := editor.get_selected_point_resource()
	_expect(selected_after_drag != null, "Legacy drag release cleared graph selection before rebuild")
	var selected_position: Vector2 = selected_after_drag.position if selected_after_drag != null else Vector2.INF
	var selected_index := editor.selected_index
	_expect(editor._point_label.text != "No Selection", "Legacy drag release reset the point toolbar before rebuild")

	graph.free()
	list.free()
	await process_frame
	var replacement_context := InspectorCurveContext.new()
	replacement_context.editor_undo_redo = manager
	replacement_context._legacy_selection_by_resource = selection_registry
	replacement_context._parse_begin(curve)
	var replacement_graph := replacement_context.handle_easing_curve_editor(curve)
	root.add_child(replacement_graph)
	var replacement_list := replacement_context._create_points_section(
		replacement_context.handle_points(curve), curve
	)
	root.add_child(replacement_list)
	await process_frame
	var replacement_editor := replacement_context.easing_curve_editor
	var restored := replacement_editor.get_selected_point_resource()
	_expect(restored != null, "Legacy Inspector context rebuild lost dragged-point selection")
	_expect(restored != null and restored.position.is_equal_approx(selected_position), "Legacy Inspector context rebuild selected the wrong dragged point")
	_expect(replacement_editor.selected_index == selected_index, "Legacy Inspector context rebuild lost the dragged point's final index")
	_expect(replacement_editor._point_label.text != "No Selection", "Legacy point toolbar returned to No Selection after drag rebuild")

	replacement_list.free()
	replacement_graph.free()
	manager.clear_history()
	host.free()
	await process_frame


func _point_at_position(editor: EasingCurveEditor, position: Vector2) -> Resource:
	for point: Resource in editor._points():
		if (point.get(&"position") as Vector2).is_equal_approx(position):
			return point
	return null


func _expect_graph_add_selection(context: InspectorCurveContext, editor: EasingCurveEditor, point: Resource, native: bool, label: String) -> void:
	_expect(point != null and editor.get_selected_point_resource() == point, "%s selected a missing/neighboring graph point (native=%s)" % [label, native])
	var selection := context._capture_point_selection_state()
	_expect(point != null and int(selection.get("point_resource_id", 0)) == point.get_instance_id(), "%s Inspector disagrees with graph (native=%s)" % [label, native])
	if not native:
		_expect(point != null and context._point_list_controller.selected_point_resource_id == point.get_instance_id(), "%s lost Legacy logical resource identity" % label)

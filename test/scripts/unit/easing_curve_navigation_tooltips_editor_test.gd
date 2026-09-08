extends "res://test/scripts/support/test_case.gd"

const CONTEXT = preload("res://addons/easing_curve/scripts/editor/inspector/inspector_curve_context.gd")

var _host: EditorPlugin
var _manager: EditorUndoRedoManager


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(Engine.is_editor_hint() and ClassDB.class_exists(&"NativeEasingCurve"), "Requires Editor host and Native extension")
	if not Engine.is_editor_hint() or not ClassDB.class_exists(&"NativeEasingCurve"):
		_finish("navigation tooltips")
		return
	_host = EditorPlugin.new()
	_manager = _host.get_undo_redo()
	_shift(false)
	for native: bool in [false, true]:
		await _test_tooltip_lifecycle(native)
		for count: int in [2, 4]:
			for reverse: bool in [false, true]:
				for index: int in range(count):
					for offset: int in [-1, 1]:
						await _test_swap_equivalence(native, count, reverse, index, offset)
		await _test_ownership(native)
		await _test_fixed_and_repeated_actions(native)
		await _test_swap_equivalence(native, 4, false, 1, -1, true)
	_shift(false)
	_manager.clear_history()
	_host.free()
	_finish("navigation tooltips and Shift swap")


func _shift(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	event.pressed = pressed
	event.shift_pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_expect(Input.is_key_pressed(KEY_SHIFT) == pressed, "Injected Shift state was not applied")


func _fixture(native: bool, count := 4, reverse := false) -> Dictionary:
	var curve: Resource
	if native:
		curve = ClassDB.instantiate(&"NativeEasingCurve")
		curve.set(&"transition", 100)
		for index in range(1, count - 1):
			var point := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
			point.set(&"position", Vector2(float(index) / (count - 1), 0.2 * index))
			curve.call(&"insert_point", index, point)
	else:
		var legacy := EasingCurve.new()
		legacy.trans_type = EasingCurve.TRANS.CUSTOM
		var points: Array[EasingCurvePoint] = []
		for index in range(count):
			points.append(EasingCurvePoint.new(Vector2(float(index) / (count - 1), 0.2 * index)))
		legacy.points = points
		curve = legacy
	curve.set(&"reverse", reverse)
	var context := CONTEXT.new()
	context.editor_undo_redo = _manager
	context._parse_begin(curve)
	var graph := context.handle_easing_curve_editor(curve)
	root.add_child(graph)
	var list: Control = context._handle_native_points(curve) if native else context._create_points_section(context.handle_points(curve), curve)
	root.add_child(list)
	return {"curve": curve, "context": context, "graph": graph, "list": list, "editor": context.easing_curve_editor}


func _free_fixture(fixture: Dictionary) -> void:
	_shift(false)
	fixture.list.free()
	fixture.graph.free()
	_manager.clear_history()


func _buttons(node: Node, tooltip: String) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button and node.tooltip_text == tooltip:
		result.append(node)
	for child in node.get_children():
		result.append_array(_buttons(child, tooltip))
	return result


func _expect_labels(editor: EasingCurveEditor, swap: bool) -> void:
	var prefix := "Swap" if swap else "Select"
	_expect(editor._point_move_left_button.tooltip_text == prefix + " Previous Point", "Incorrect Previous tooltip")
	_expect(editor._point_move_right_button.tooltip_text == prefix + " Next Point", "Incorrect Next tooltip")
	# get_tooltip is the public text source used when Godot creates a popup.
	_expect(editor._point_move_left_button.get_tooltip() == prefix + " Previous Point", "New tooltip source has stale text")
	_expect(editor._point_move_right_button.get_tooltip() == prefix + " Next Point", "New Next tooltip source has stale text")


func _test_tooltip_lifecycle(native: bool) -> void:
	var fixture := _fixture(native)
	var editor: EasingCurveEditor = fixture.editor
	editor.selected_index = 1
	var before: Dictionary = fixture.curve.call(&"get_editor_state_snapshot")
	_manager.clear_history()
	var changes := [0]
	fixture.curve.changed.connect(func() -> void: changes[0] += 1)
	var selections := [0]
	editor.point_selection_changed.connect(func(_point: Resource) -> void: selections[0] += 1)
	var left := editor._point_move_left_button
	var right := editor._point_move_right_button
	var properties := [left.icon, right.icon, left.disabled, right.disabled, left.get_index(), right.get_index(), left.visible, right.visible, left.pressed.get_connections(), right.pressed.get_connections()]
	_expect_labels(editor, false)
	_shift(true)
	_expect_labels(editor, true)
	_shift(false)
	_expect_labels(editor, false)
	_expect(properties == [left.icon, right.icon, left.disabled, right.disabled, left.get_index(), right.get_index(), left.visible, right.visible, left.pressed.get_connections(), right.pressed.get_connections()], "Modifier changed button structure or behavior")
	_expect(editor._point_move_left_button == left and editor._point_move_right_button == right, "Modifier recreated buttons")
	for notification: int in [Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_shift(true)
		editor.notification(notification)
		_expect_labels(editor, false)
		editor.hide()
		_shift(false) # No visible graph observer receives the release.
		editor.show()
		editor.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
		await process_frame
		_expect_labels(editor, false)
	_shift(true)
	editor.hide()
	_expect_labels(editor, false)
	left.tooltip_text = "hidden sentinel"
	_shift(false)
	_expect(left.tooltip_text == "hidden sentinel", "Hidden graph observed input")
	editor.show()
	_expect_labels(editor, false)
	_shift(true)
	editor.set_curve(null)
	editor.set_curve(fixture.curve)
	_expect_labels(editor, true)
	_shift(false)
	editor.selected_index = 1
	editor.point_move_buttons_reorder_points = true
	editor._update_point_toolbar()
	_expect_labels(editor, true)
	editor.point_move_buttons_reorder_points = false
	editor._update_point_toolbar()
	_expect_labels(editor, false)
	_expect(fixture.curve.call(&"get_editor_state_snapshot") == before and changes[0] == 0, "Tooltip lifecycle mutated resource")
	_expect(not _manager.get_history_undo_redo(_manager.get_object_history_id(fixture.curve)).has_undo(), "Tooltip lifecycle created Undo")
	# set_curve/selected_index intentionally publish selection; modifier-only checks below do not.
	selections[0] = 0
	_shift(true)
	_shift(false)
	_expect(selections[0] == 0, "Modifier emitted selection")
	_expect(_buttons(fixture.list, "Swap Previous Point").size() == 4, "List Previous labels missing")
	_expect(_buttons(fixture.list, "Swap Next Point").size() == 4, "List Next labels missing")
	for pressed: bool in [false, true]:
		_shift(pressed)
		var rebuilt := EasingCurveEditor.new()
		rebuilt.set_curve(fixture.curve)
		root.add_child(rebuilt)
		_expect_labels(rebuilt, pressed)
		root.remove_child(rebuilt)
		rebuilt._point_move_left_button.tooltip_text = "detached sentinel"
		rebuilt._input(InputEventKey.new())
		_expect(rebuilt._point_move_left_button.tooltip_text == "detached sentinel", "Detached graph observed input")
		rebuilt.free()
	_free_fixture(fixture)
	await process_frame


func _test_swap_equivalence(native: bool, count: int, reverse: bool, index: int, offset: int, preview := false) -> void:
	var fixture := _fixture(native, count, reverse)
	var editor: EasingCurveEditor = fixture.editor
	var context: InspectorCurveContext = fixture.context
	var curve: Resource = fixture.curve
	if preview:
		var preview_point: Resource = editor._points()[2]
		preview_point.set(&"position", Vector2(0.2, 0.4))
		editor.position_x_order_preview_point = preview_point
		_expect(editor._get_display_points() != editor._points(), "Preview fixture did not differ from resource order")
	editor.selected_index = index
	var selected := editor.get_selected_point_resource()
	var before: Dictionary = curve.call(&"get_editor_state_snapshot")
	var before_order := editor._points().duplicate()
	var history := _manager.get_history_undo_redo(_manager.get_object_history_id(curve))
	_manager.clear_history()
	var list_buttons := _buttons(fixture.list, "Swap Previous Point" if offset < 0 else "Swap Next Point")
	_expect(list_buttons.size() == count, "List button count differs from point count")
	list_buttons[index].pressed.emit()
	var after: Dictionary = curve.call(&"get_editor_state_snapshot")
	var after_order := editor._points().duplicate()
	var after_index := editor.selected_index
	_expect(after_index == wrapi(index + offset, 0, count), "List wrapping changed")
	_expect(editor.get_selected_point_resource() == selected, "List lost selected identity")
	_expect(history.undo(), "List swap missing Undo")
	_expect(not history.has_undo(), "List swap created multiple actions")
	_expect(curve.call(&"get_editor_state_snapshot") == before, "List Undo lost point state")
	_manager.clear_history()
	editor.selected_index = index
	_shift(true)
	# Deliberately lie in the presentation: activation must still use Input.
	editor._point_move_left_button.tooltip_text = "Select Previous Point"
	editor._point_move_right_button.tooltip_text = "Select Next Point"
	var button := editor._point_move_left_button if offset < 0 else editor._point_move_right_button
	button.pressed.emit()
	_expect(curve.call(&"get_editor_state_snapshot") == after and editor._points() == after_order, "Shift swap differs from list state/order")
	_expect(editor.selected_index == after_index and editor.get_selected_point_resource() == selected, "Shift swap differs from list selection")
	_expect(history.undo(), "Shift swap missing Undo")
	_expect(not history.has_undo(), "Shift swap created multiple actions")
	_expect(curve.call(&"get_editor_state_snapshot") == before and editor._points() == before_order, "Shift Undo differs from list Undo")
	_expect(history.redo(), "Shift swap missing Redo")
	_expect(curve.call(&"get_editor_state_snapshot") == after and editor.get_selected_point_resource() == selected, "Shift Redo lost state/selection")
	history.undo()
	_manager.clear_history()
	_shift(false)
	editor.selected_index = index
	var display_target := editor._get_display_neighbor_index(offset)
	editor._point_move_left_button.tooltip_text = "Swap Previous Point"
	editor._point_move_right_button.tooltip_text = "Swap Next Point"
	button.pressed.emit()
	_expect(editor.selected_index == display_target and editor._points() == before_order, "Normal navigation lost display ordering")
	_expect(not history.has_undo(), "Normal navigation created Undo")
	# Disconnect the Inspector adapter to verify the standalone operation on the same resources.
	context._disconnect_graph_swap_request()
	editor.selected_index = index
	_shift(true)
	button.pressed.emit()
	_expect(curve.call(&"get_editor_state_snapshot") == after and editor._points() == after_order, "Standalone swap differs from list")
	_expect(editor.get_selected_point_resource() == selected, "Standalone swap lost identity")
	_expect(history.undo(), "Standalone swap missing Undo")
	_expect(not history.has_undo() and curve.call(&"get_editor_state_snapshot") == before, "Standalone Undo differs from list")
	_manager.clear_history()
	# Native fixed mode intentionally follows the old display-neighbor path.
	if native:
		editor.selected_index = index
		editor.point_move_buttons_reorder_points = true
		button.pressed.emit()
		_expect(editor.selected_index == display_target, "Fixed Native mode changed neighbor semantics")
		history.undo()
		editor.point_move_buttons_reorder_points = false
	_manager.clear_history()
	editor.selected_index = -1
	button.pressed.emit()
	_expect(not history.has_undo() and editor._points() == before_order, "Invalid selection performed a swap")
	_free_fixture(fixture)
	await process_frame


func _test_ownership(native: bool) -> void:
	var fixture := _fixture(native)
	var old: InspectorCurveContext = fixture.context
	var editor: EasingCurveEditor = fixture.editor
	var replacement := CONTEXT.new()
	replacement.editor_undo_redo = _manager
	replacement._parse_begin(fixture.curve)
	replacement.easing_curve_editor = editor
	replacement._connect_graph_swap_request()
	replacement._connect_graph_swap_request()
	_expect(not editor.point_swap_requested.is_connected(old._on_graph_point_swap_requested), "Old Inspector adapter retained")
	_expect(editor.point_swap_requested.get_connections().size() == 1, "Reconnection duplicated adapter")
	_expect(old._swap_request_graph == null, "Old context retained graph ownership")
	editor.selected_index = 1
	var selected := editor.get_selected_point_resource()
	var before: Dictionary = fixture.curve.call(&"get_editor_state_snapshot")
	_manager.clear_history()
	_shift(true)
	editor._point_move_right_button.pressed.emit()
	_expect(editor.selected_index == 2 and editor.get_selected_point_resource() == selected, "Reassigned graph did not swap exactly once")
	var history := _manager.get_history_undo_redo(_manager.get_object_history_id(fixture.curve))
	_expect(history.undo(), "Reassigned swap missing Undo")
	_expect(not history.has_undo() and fixture.curve.call(&"get_editor_state_snapshot") == before, "Reassigned swap created duplicate history")
	replacement._dispose_presentation()
	_expect(editor.point_swap_requested.get_connections().is_empty(), "Disposed context retained adapter")
	# Rebuild the complete Inspector graph/list, then exercise its new binding.
	fixture.list.free()
	fixture.graph.free()
	_manager.clear_history()
	var rebuilt := CONTEXT.new()
	rebuilt.editor_undo_redo = _manager
	rebuilt._parse_begin(fixture.curve)
	fixture.context = rebuilt
	fixture.graph = rebuilt.handle_easing_curve_editor(fixture.curve)
	root.add_child(fixture.graph)
	fixture.list = rebuilt._handle_native_points(fixture.curve) if native else rebuilt._create_points_section(rebuilt.handle_points(fixture.curve), fixture.curve)
	root.add_child(fixture.list)
	editor = rebuilt.easing_curve_editor
	editor.selected_index = 1
	_expect_labels(editor, true)
	editor._point_move_right_button.pressed.emit()
	_expect(editor.selected_index == 2, "Rebuilt graph swapped more or less than once")
	_expect(history.undo() and not history.has_undo(), "Rebuilt graph did not create exactly one Undo action")
	_expect(fixture.curve.call(&"get_editor_state_snapshot") == before, "Rebuilt graph Undo lost state")
	_free_fixture(fixture)
	await process_frame


func _test_fixed_and_repeated_actions(native: bool) -> void:
	var fixture := _fixture(native, 4, true)
	var editor: EasingCurveEditor = fixture.editor
	var curve: Resource = fixture.curve
	var history := _manager.get_history_undo_redo(_manager.get_object_history_id(curve))
	editor.selected_index = 1
	var selected := editor.get_selected_point_resource()
	var before: Dictionary = curve.call(&"get_editor_state_snapshot")
	editor.point_move_buttons_reorder_points = true
	_shift(false)
	editor._point_move_right_button.pressed.emit()
	var fixed_after: Dictionary = curve.call(&"get_editor_state_snapshot")
	var fixed_index := editor.selected_index
	_expect(history.undo(), "Fixed mode missing Undo")
	_manager.clear_history()
	editor.selected_index = 1
	_shift(true)
	editor._point_move_right_button.pressed.emit()
	_expect(curve.call(&"get_editor_state_snapshot") == fixed_after and editor.selected_index == fixed_index, "Shift changed fixed mode")
	_expect(history.undo() and not history.has_undo(), "Fixed mode did not create one action")
	_manager.clear_history()
	editor.point_move_buttons_reorder_points = false
	editor.selected_index = 1
	for expected: int in [2, 3, 0]:
		editor._point_move_right_button.pressed.emit()
		_expect(editor.selected_index == expected and editor.get_selected_point_resource() == selected, "Repeated Shift swap lost wrapping/identity")
	for step in range(3):
		_expect(history.undo(), "Repeated swap lost Undo action")
	_expect(not history.has_undo() and curve.call(&"get_editor_state_snapshot") == before, "Repeated Undo did not restore original state")
	_free_fixture(fixture)
	await process_frame

extends "res://test/scripts/support/test_case.gd"

const Context = preload("res://addons/easing_curve/scripts/editor/inspector/inspector_curve_context.gd")
const Factory = preload("res://addons/easing_curve/scripts/editor/backend/curve_editor_backend_factory.gd")

class CountingContext extends Context:
	var constructed := 0

	func _create_native_point_panel(point: Resource, index: int, count: int) -> Control:
		constructed += 1
		return super(point, index, count)

	func _create_foldable_section(title: String, content: Control, target: Resource) -> Control:
		if DisplayServer.get_name() != "headless":
			return super(title, content, target)
		var section := PointsFoldableSection.new()
		section.title = title
		section.add_child(content)
		return section

	func _create_inspector_section(title: String, content: Control, target: Resource) -> Control:
		return _create_foldable_section(title, content, target)

var _undo_plugin: EditorPlugin
var _undo: EditorUndoRedoManager

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	_expect(Engine.is_editor_hint() and ClassDB.class_exists(&"NativeEasingCurve"), "Native editor host required")
	if _failures:
		_finish("Native reconciliation")
		return
	_undo_plugin = EditorPlugin.new()
	_undo = _undo_plugin.get_undo_redo()
	for count in [9, 65, 129, 257]:
		await _test_scaling(count)
	for detached in [false, true]:
		await _test_history(detached)
	await _test_endpoints_and_transforms()
	await _test_callbacks_and_disposal()
	await _test_selection_and_active_edit()
	await _test_deferred_drag()
	_undo_plugin.free()
	_finish("Native reconciliation")

func _fixture(count: int) -> Dictionary:
	var curve: Resource = ClassDB.instantiate(&"NativeEasingCurve")
	curve.set(&"transition", 100)
	var backend := Factory.create(curve)
	var points: Array[Resource] = []
	for index in range(count):
		points.append(backend.create_point(Vector2(float(index) / maxi(count - 1, 1), 0.5)))
	curve.set(&"points", points)
	# Empty and singleton arrays are accepted by Native set_points/topology snapshots.
	_expect(backend.get_point_count() == count, "Native boundary fixture rejected count %d" % count)
	var context := CountingContext.new()
	context.editor_undo_redo = _undo
	context._parse_begin(curve)
	var host := VBoxContainer.new()
	root.add_child(host)
	host.add_child(context.handle_easing_curve_editor(curve))
	host.add_child(context._handle_native_points(curve))
	return {"curve": curve, "backend": backend, "context": context, "host": host}

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _panels(f: Dictionary) -> Dictionary:
	var result := {}
	for panel in f.context._native_points_content.get_children():
		result[panel.get_meta(&"point_resource").get_instance_id()] = panel
	return result

func _ids(f: Dictionary) -> Dictionary:
	var result := {}
	var panels := _panels(f)
	for id in panels:
		result[id] = panels[id].get_instance_id()
	return result

func _assert_order(f: Dictionary) -> void:
	var actual: Array[Resource] = []
	for panel in f.context._native_points_content.get_children():
		actual.append(panel.get_meta(&"point_resource"))
	_expect(actual == f.backend.get_display_points(), "Panels do not follow final display identity order")
	for index in range(actual.size()):
		var panel: Control = f.context._native_points_content.get_child(index)
		_expect(panel.get_meta(&"point_shape") == Vector2i(int(index > 0), int(index < actual.size() - 1)), "Endpoint shape mismatch")
		var drag: EasingCurveDragHandle = panel.get_meta(&"point_drag_handle")
		_expect(drag.index == index, "Drag index was not refreshed")
		var properties: Array[StringName] = []
		for header in panel.get_meta(&"point_headers"):
			var property: StringName = header.get_meta(&"point_property_name")
			properties.append(property)
			_expect(header.tooltip_text == "points/%d/%s" % [f.backend.find_point(actual[index]), property], "Stale storage-index tooltip")
		var expected: Array[StringName] = [&"position", &"handle_mode"]
		var reverse := bool(f.curve.get(&"reverse"))
		if index > 0:
			expected.append(&"right_control_point" if reverse else &"left_control_point")
		if index < actual.size() - 1:
			expected.append(&"left_control_point" if reverse else &"right_control_point")
		_expect(properties == expected, "Endpoint Controls bind the wrong stored handle side")

func _assert_retained(f: Dictionary, before: Dictionary, excluded: Array = []) -> void:
	var after := _ids(f)
	for id in before:
		if after.has(id) and id not in excluded:
			_expect(before[id] == after[id], "Unaffected panel was reconstructed")

func _close(f: Dictionary) -> void:
	f.host.free()
	_undo.clear_history()

func _test_scaling(count: int) -> void:
	var f := _fixture(count)
	await _settle()
	var context: CountingContext = f.context
	var graph := context.easing_curve_editor
	var points_root: Control = context.points_root_ref.get_ref()
	var graph_root: Control = context.graph_root_ref.get_ref()
	var point_list := context._native_points_content
	var before := _ids(f)
	var constructed := context.constructed
	var point: Resource = f.backend.create_point(Vector2((count / 2 + 0.5) / float(count - 1), 0.6))
	context.easing_curve_editor._request_point_add(point)
	await _settle()
	_expect(context.constructed - constructed == 1, "Middle Add must construct exactly one panel at %d" % count)
	_assert_retained(f, before)
	_assert_order(f)
	before = _ids(f)
	constructed = context.constructed
	context._remove_native_point(point)
	await _settle()
	_expect(context.constructed == constructed, "Middle Remove must construct zero panels at %d" % count)
	_assert_retained(f, before)
	_assert_order(f)
	before = _ids(f)
	context._move_point_relative(f.backend.get_point(count / 2), 1)
	await _settle()
	_expect(context.constructed == constructed, "Interior reorder must construct zero panels at %d" % count)
	_assert_retained(f, before)
	_assert_order(f)
	context._refresh_native_point_list(f.curve)
	_expect(context.constructed == constructed, "Reconciliation is not idempotent")
	_expect(context.easing_curve_editor == graph and context.graph_root_ref.get_ref() == graph_root, "Topology replaced graph/toolbar presentation")
	_expect(context.points_root_ref.get_ref() == points_root and context._native_points_content == point_list, "Topology replaced Points/Add presentation")
	_close(f)

func _test_history(detached: bool) -> void:
	var f := _fixture(9)
	await _settle()
	if detached:
		f.context.graph_root_ref.get_ref().free()
	var history: UndoRedo = _undo.get_history_undo_redo(_undo.get_object_history_id(f.curve))
	var originals: Array[Resource] = f.backend.get_points()
	var original_panels := _ids(f)
	f.context._on_add_point_btn_pressed()
	await _settle()
	var added_order: Array[Resource] = f.backend.get_points()
	history.undo()
	await _settle()
	_expect(f.backend.get_points() == originals, "Undo Add replaced surviving resource identities")
	_assert_retained(f, original_panels)
	history.redo()
	await _settle()
	_expect(f.backend.get_points() == added_order, "Redo Add replaced resource identities")
	_assert_retained(f, original_panels)
	var removed: Resource = f.backend.get_point(4)
	f.context._remove_native_point(removed)
	await _settle()
	var removed_order: Array[Resource] = f.backend.get_points()
	history.undo()
	await _settle()
	_expect(f.backend.get_points() == added_order, "Undo Remove replaced resource identities")
	history.redo()
	await _settle()
	_expect(f.backend.get_points() == removed_order, "Redo Remove replaced resource identities")
	f.context._move_point_relative(f.backend.get_point(3), 1)
	await _settle()
	var swapped: Array[Resource] = f.backend.get_points()
	history.undo()
	await _settle()
	_expect(f.backend.get_points() == removed_order, "Undo reorder replaced identities")
	history.redo()
	await _settle()
	_expect(f.backend.get_points() == swapped, "Redo reorder replaced identities")
	_assert_order(f)
	_close(f)

func _test_endpoints_and_transforms() -> void:
	var f := _fixture(5)
	await _settle()
	for index in [0, 3]:
		var before := _ids(f)
		var points: Array[Resource] = f.backend.get_points()
		var removed: Resource = points[mini(index, points.size() - 1)]
		var neighbor: Resource = points[1] if index == 0 else points[points.size() - 2]
		f.context._remove_native_point(removed)
		await _settle()
		_assert_retained(f, before, [neighbor.get_instance_id()])
		_assert_order(f)
	# Missing endpoint insertion makes the previous first/last interior.
	for x in [0.0, 1.0]:
		f.context.easing_curve_editor._request_point_add(f.backend.create_point(Vector2(x, 0.4)))
		await _settle()
		_assert_order(f)
	# Endpoint takeover has equal count and changes resource identity.
	var before := _ids(f)
	f.context.easing_curve_editor._request_point_add(f.backend.create_point(Vector2(0, 0.7)))
	await _settle()
	_assert_retained(f, before)
	_assert_order(f)
	var selected: Resource = f.backend.get_point(1)
	var header: PanelContainer = _panels(f)[selected.get_instance_id()].get_meta(&"point_headers")[0]
	f.context._select_native_point_property(header, selected, &"position")
	before = _ids(f)
	f.curve.set(&"invert", true)
	await _settle()
	_assert_retained(f, before)
	f.curve.set(&"reverse", true)
	await _settle()
	_assert_order(f)
	_expect(f.context._selected_point_property_header.get_meta(&"point_resource_id") == selected.get_instance_id(), "Reverse lost selected property identity")
	# Replacement snapshots must never reuse controls bound to old resources.
	before = _ids(f)
	var snapshot: Dictionary = f.curve.call(&"get_editor_state_snapshot")
	snapshot.point_states[1].position.y = 0.77
	f.curve.call(&"set_editor_state_snapshot", snapshot)
	await _settle()
	for id in _ids(f):
		_expect(not before.has(id), "Replacement snapshot unexpectedly retained resource identity")
	_assert_order(f)
	_close(f)
	for count in [0, 1]:
		f = _fixture(count)
		await _settle()
		f.context._on_add_point_btn_pressed()
		await _settle()
		_assert_order(f)
		while f.backend.get_point_count() > 0:
			f.context._remove_native_point(f.backend.get_point(0))
			await _settle()
			_assert_order(f)
		_close(f)

func _test_callbacks_and_disposal() -> void:
	var f := _fixture(9)
	await _settle()
	var point: Resource = f.backend.get_point(4)
	var connections: int = point.changed.get_connections().size()
	var unattached := f.context._create_native_point_panel(point, 4, 9) as Control
	f.context._remove_native_point_panel(unattached)
	_expect(point.changed.get_connections().size() == connections, "Never-attached panel leaked callbacks")
	for iteration in range(4):
		f.context._refresh_native_point_list(f.curve)
	_expect(point.changed.get_connections().size() == connections, "Reconciliation duplicated callbacks")
	var panel: Control = _panels(f)[point.get_instance_id()]
	var panel_id := panel.get_instance_id()
	f.context._remove_native_point(point)
	await _settle()
	_expect(not is_instance_id_valid(panel_id), "Removed panel was retained")
	_expect(point.changed.get_connections().is_empty(), "Removed point retained UI/model callbacks")
	point.emit_changed()
	# A queued update after disposal must not touch released Controls.
	f.backend.add_point(f.backend.create_point(Vector2(0.44, 0.3)))
	_close(f)
	await _settle()

func _test_deferred_drag() -> void:
	var f := _fixture(5)
	await _settle()
	var list: Control = f.context._native_points_content
	var source: Resource = f.backend.get_point(1)
	var target: Resource = f.backend.get_point(3)
	var panel: Control = _panels(f)[source.get_instance_id()]
	var original_filter := panel.mouse_filter
	list._pending_swap_from = 1
	list._pending_swap_to = 3
	list._pending_source = source
	list._pending_target = target
	list._disable_mouse_for_subtree(list)
	# Insert before the pending source; cached numeric indices are now stale.
	f.backend.add_point(f.backend.create_point(Vector2(0.1, 0.3)))
	await _settle()
	list._emit_pending_point_swap(list._debug_drag_id)
	await _settle()
	_expect(panel.mouse_filter == original_filter, "Drag quarantine did not restore surviving Controls")
	_expect(f.backend.find_point(source) == 4, "Deferred drag used stale numeric source/target")
	_assert_order(f)
	# A second completed drag targets the same identities at their new indices.
	list._pending_source = source
	list._pending_target = target
	list._pending_swap_from = 4
	list._pending_swap_to = 2
	list._disable_mouse_for_subtree(list)
	list._emit_pending_point_swap(list._debug_drag_id)
	await _settle()
	_expect(f.backend.find_point(source) == 2, "Second drag did not route the reused panel")
	var header: PanelContainer = panel.get_meta(&"point_headers")[0]
	_expect(header.mouse_filter != Control.MOUSE_FILTER_IGNORE, "Reused header cannot receive clicks")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	header.gui_input.emit(click)
	_expect(f.context.easing_curve_editor.get_selected_point_resource() == source, "Reused header click selected a stale index")
	# Removed deferred target cancels and still restores input.
	list._pending_source = source
	list._pending_target = target
	list._pending_swap_from = 4
	list._pending_swap_to = 2
	list._disable_mouse_for_subtree(list)
	f.backend.remove_point(f.backend.find_point(target))
	await _settle()
	var order: Array[Resource] = f.backend.get_points()
	list._emit_pending_point_swap(list._debug_drag_id)
	await _settle()
	_expect(f.backend.get_points() == order, "Missing deferred target did not cancel swap")
	_expect(panel.mouse_filter == original_filter, "Cancelled drag did not restore input")
	# A later drag generation cancels stale queued work without quarantining the new list.
	list._pending_swap_from = 1
	list._pending_swap_to = 2
	list._disable_mouse_for_subtree(list)
	list._emit_pending_point_swap(list._debug_drag_id - 1)
	_expect(list._pending_swap_from == -1 and list._pending_swap_to == -1, "Stale drag generation retained pending swap")
	_expect(panel.mouse_filter == original_filter, "Stale drag generation retained quarantine")
	_close(f)


func _test_selection_and_active_edit() -> void:
	var f := _fixture(5)
	await _settle()
	var point: Resource = f.backend.get_point(2)
	var panel: Control = _panels(f)[point.get_instance_id()]
	var header: PanelContainer = panel.get_meta(&"point_headers")[0]
	f.context._select_native_point_property(header, point, &"position")
	f.backend.add_point(f.backend.create_point(Vector2(0.1, 0.3)))
	await _settle()
	_expect(f.context.easing_curve_editor.get_selected_point_resource() == point, "External insertion lost selected point identity")
	_expect(f.context._selected_point_property_header == header, "External insertion replaced selected header")
	var before := _ids(f)
	f.context._edit_native_point_property(f.backend.find_point(point), &"position", Vector2(0.6, 0.7), true)
	f.context._refresh_native_point_list(f.curve)
	await _settle()
	_expect(f.context.easing_curve_editor._backend_point_edit_active, "Queued reconciliation ended active edit")
	_assert_retained(f, before)
	f.context.easing_curve_editor.finish_active_point_edit()
	await _settle()
	_expect(not f.context._native_points_refresh_queued, "Finished edit left reconciliation queued")
	_assert_order(f)
	f.context._edit_native_point_property(f.backend.find_point(point), &"position", Vector2(0.61, 0.72), true)
	f.curve.set(&"reverse", true)
	await _settle()
	_expect(not f.context.easing_curve_editor._backend_point_edit_active, "Reverse did not finish the edit before replacing stored-side bindings")
	_assert_order(f)
	f.curve.set(&"reverse", false)
	await _settle()
	# Endpoint swap replaces the selected endpoint header, preserving logical property.
	point = f.backend.get_point(0)
	panel = _panels(f)[point.get_instance_id()]
	header = panel.get_meta(&"point_headers")[0]
	f.context._select_native_point_property(header, point, &"position")
	f.context._move_point_relative(point, 1)
	await _settle()
	_expect(f.context.easing_curve_editor.get_selected_point_resource() == point, "Endpoint swap lost selected point")
	_expect(f.context._selected_point_property_header.get_meta(&"point_property_name") == &"position", "Endpoint replacement lost selected property")
	_assert_order(f)
	_close(f)

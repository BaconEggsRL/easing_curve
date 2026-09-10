extends "res://test/scripts/support/test_case.gd"

const Context = preload("res://addons/easing_curve/scripts/editor/inspector/inspector_curve_context.gd")
const Factory = preload("res://addons/easing_curve/scripts/editor/backend/curve_editor_backend_factory.gd")
const Plugin = preload("res://addons/easing_curve/scripts/editor/inspector/easing_curve_editor_inspector_plugin.gd")

# Godot 4.7 cannot construct FoldableContainer under the headless display server.
# Only section chrome is substituted; all graph/list controls and callbacks are real.
class HeadlessContext extends Context:
	func _create_foldable_section(title: String, content: Control, target: Resource) -> Control:
		var section := PointsFoldableSection.new()
		section.title = title
		section.add_child(content)
		return section

	func _create_inspector_section(title: String, content: Control, target: Resource) -> Control:
		return _create_foldable_section(title, content, target)

var _undo: EditorUndoRedoManager
var _undo_plugin: EditorPlugin
var _host: HBoxContainer
var _test_window: Window


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(Engine.is_editor_hint(), "Ownership suite requires an editor host")
	_expect(ClassDB.class_exists(&"NativeEasingCurve"), "Ownership suite requires Native")
	if _failures:
		_finish("inspector ownership")
		return
	_host = HBoxContainer.new()
	_undo_plugin = EditorPlugin.new()
	_undo = _undo_plugin.get_undo_redo()
	_host.size = Vector2(1280, 900)
	_test_window = Window.new()
	_test_window.title = "Easing Curve ownership regression tests"
	_test_window.size = Vector2i(1280, 900)
	root.add_child(_test_window)
	_test_window.add_child(_host)
	if "--rendered-only" in OS.get_cmdline_user_args():
		await _test_rendered_inspectors()
		_host.free()
		_test_window.queue_free()
		await process_frame
		_undo_plugin.free()
		_finish("rendered inspector ownership")
		return
	for kinds in [[false, false], [true, true], [false, true], [true, false]]:
		await _test_mutations(kinds[0], kinds[1])
	for native in [false, true]:
		await _test_same_resource(native)
		for graph_first in [false, true]:
			await _test_teardown(native, graph_first)
		for queued in [false, true]:
			await _test_pending_disposal(native, queued)
		await _test_graph_survives_points_teardown(native)
		await _test_point_list_coordinates(native)
		await _test_clipboard(native)
	await _test_original_reproduction()
	await _test_native_point_position_limits()
	if DisplayServer.get_name() != "headless":
		await _test_rendered_inspectors()
	_host.free()
	_test_window.queue_free()
	await process_frame
	_undo_plugin.free()
	_finish("inspector ownership")


func _curve(native: bool) -> Resource:
	var target: Resource = ClassDB.instantiate(&"NativeEasingCurve") if native else EasingCurve.new()
	target.set(&"transition" if native else &"trans_type", 100 if native else EasingCurve.TRANS.CUSTOM)
	var backend := Factory.create(target)
	var points: Array[Resource] = []
	for position in [Vector2.ZERO, Vector2(0.35, 0.4), Vector2(0.7, 0.8), Vector2.ONE]:
		points.append(backend.create_point(position))
	if native:
		target.set(&"points", points)
	else:
		var legacy_points: Array[EasingCurvePoint] = []
		legacy_points.assign(points)
		target.set(&"points", legacy_points)
	_expect(backend.get_point_count() == 4, "Fixture did not install four points")
	return target


func _presentation(target: Resource) -> Dictionary:
	var context: Context = HeadlessContext.new() if DisplayServer.get_name() == "headless" else Context.new()
	context.editor_undo_redo = _undo
	context._parse_begin(target)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 560
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.add_child(column)
	var graph_name := &"easing_curve_editor" if target is EasingCurve else &"_editor_state_snapshot"
	context._parse_property(target, TYPE_NIL, graph_name, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR, false)
	context._parse_property(target, TYPE_ARRAY, &"points", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR, false)
	var graph_root: Control
	var points_root: Control
	for registration: Dictionary in context.registrations:
		var control: Control = registration.control
		column.add_child(control)
		if registration.has("name"):
			graph_root = control
		else:
			points_root = control
	context.registrations.clear()
	return {"context": context, "curve": target, "graph": context.easing_curve_editor,
		"graph_root": graph_root, "points_root": points_root, "column": column}


func _close(presentation: Dictionary) -> void:
	presentation.column.free()
	presentation.clear()


func _history(target: Resource) -> UndoRedo:
	return _undo.get_history_undo_redo(_undo.get_object_history_id(target))


func _input(presentation: Dictionary, point: Resource, axis := 1, property_name := "position") -> EditorSpinSlider:
	if point is EasingCurvePoint:
		var bindings: Dictionary = presentation.context._point_list_controller.get_input_bindings()
		return bindings[point.get_instance_id()].inputs[property_name + ("x" if axis == 0 else "y")].input.get_ref()
	var panel: Control
	for child in presentation.context._native_points_content.get_children():
		if child.get_meta(&"point_resource", null) == point:
			panel = child
	var inputs: Array[EditorSpinSlider] = []
	_collect_inputs(panel, inputs)
	var property_offset := 0 if property_name == "position" else (2 if property_name == "left_control_point" else 4)
	return inputs[property_offset + axis]


func _test_point_list_coordinates(native: bool) -> void:
	for linear: bool in [false, true]:
		for property_name: String in ["position", "left_control_point", "right_control_point"]:
			for axis in range(2):
				var target := _curve(native)
				var backend := Factory.create(target)
				var point: Resource = backend.get_point(1)
				if linear:
					point.set(&"handle_mode", EasingCurvePoint.HandleMode.LINEAR)
				var p := _presentation(target)
				for frame in range(8):
					await process_frame
					if not p.graph._graph_render_suppressed:
						break
				p.graph.update_view_transform()
				var input := _input(p, point, axis, property_name)
				var history := _history(target)
				history.clear_history()
				var before: Vector2 = point.get(&"position")
				input.grabbed.emit()
				_expect(p.graph._get_drag_coordinate_position().is_finite(), "Points drag did not show coordinates")
				_expect(p.graph.dragging_point == -1, "List readout changed graph drag state")
				input.value = 0.85 if axis == 0 else 0.61
				var edit_property := "position" if linear else property_name
				var resolved: Vector2 = backend.curve_to_display_position(point.get(edit_property))
				_expect(p.graph._get_drag_coordinate_position().is_equal_approx(resolved), "Points readout did not follow resolved property")
				if linear:
					_expect(is_equal_approx((point.get(&"position") as Vector2)[axis], input.value), "Linear control did not move point")
					_expect(point.get(&"left_control_point") == point.get(&"position") and point.get(&"right_control_point") == point.get(&"position"), "Linear controls diverged from point")
				input.ungrabbed.emit()
				_expect(not p.graph._get_drag_coordinate_position().is_finite(), "Points release retained readout")
				await process_frame
				_expect(history.get_history_count() == 1, "Points gesture did not commit exactly one action")
				history.undo()
				_expect(point.get(&"position") == before, "Points gesture Undo did not restore position")
				history.redo()
				if linear and axis == 0:
					_expect(backend.find_point(point) == 2, "Linear control X did not follow position ordering")
				_close(p)
				history.clear_history()
				await process_frame
	var target := _curve(native)
	var backend := Factory.create(target)
	var point: Resource = backend.get_point(1)
	point.set(&"handle_mode", EasingCurvePoint.HandleMode.LINEAR)
	var p := _presentation(target)
	for frame in range(8):
		await process_frame
		if not p.graph._graph_render_suppressed:
			break
	var input := _input(p, point, 1, "left_control_point")
	input.value_focus_entered.emit()
	input.value = 0.57
	input.value_focus_exited.emit()
	await process_frame
	_expect(is_equal_approx((point.get(&"position") as Vector2).y, 0.57), "Typed Linear control did not move point")
	_expect(not p.graph._get_drag_coordinate_position().is_finite(), "Typing showed drag coordinates")
	point.call(&"set_locked", &"left_control_point", true)
	var before: Vector2 = point.get(&"position")
	input.value = 0.91
	_expect(point.get(&"position") == before, "Locked Linear list control moved point")
	point.call(&"set_locked", &"left_control_point", false)
	input.grabbed.emit()
	_expect(p.graph._get_drag_coordinate_position().is_finite(), "List gesture did not rearm after typing")
	input.hide()
	input.show()
	_expect(not p.graph._get_drag_coordinate_position().is_finite(), "Hidden list field retained coordinates")
	input.grabbed.emit()
	p.points_root.free()
	_expect(not p.graph._get_drag_coordinate_position().is_finite(), "Points teardown retained list readout")
	_close(p)
	_history(target).clear_history()
	await process_frame
	if native:
		await _test_native_linear_list_without_graph()


func _test_native_linear_list_without_graph() -> void:
	var target := _curve(true)
	var backend := Factory.create(target)
	var point: Resource = backend.get_point(1)
	point.set(&"handle_mode", EasingCurvePoint.HandleMode.LINEAR)
	target.set(&"reverse", true)
	target.set(&"invert", true)
	var p := _presentation(target)
	for frame in range(8):
		await process_frame
		if not p.graph._graph_render_suppressed:
			break
	var input := _input(p, point, 1, "right_control_point")
	input.grabbed.emit()
	input.value = 0.23
	_expect(p.graph._get_drag_coordinate_position().is_equal_approx(Vector2(0.65, 0.23)), "Transformed list coordinates applied Native transform incorrectly")
	input.ungrabbed.emit()
	await process_frame
	p.graph_root.free()
	var history := _history(target)
	history.clear_history()
	input.value_focus_entered.emit()
	input.value = 0.67
	input.value_focus_exited.emit()
	await process_frame
	_expect(is_equal_approx((point.get(&"position") as Vector2).y, 0.33), "Detached Linear list field did not move point")
	_expect(point.get(&"right_control_point") == point.get(&"position"), "Detached Linear handle diverged")
	_expect(history.get_history_count() == 1, "Detached Linear edit lost transaction completion")
	history.undo()
	_expect(is_equal_approx((point.get(&"position") as Vector2).y, 0.77), "Detached Linear Undo failed")
	_close(p)
	history.clear_history()
	await process_frame


func _test_native_point_position_limits() -> void:
	for linear: bool in [false, true]:
		var target := _curve(true)
		var point: Resource = Factory.create(target).get_point(1)
		if linear:
			point.set(&"handle_mode", EasingCurvePoint.HandleMode.LINEAR)
		var p := _presentation(target)
		await process_frame
		var property_name := "left_control_point" if linear else "position"
		var input := _input(p, point, 1, property_name)
		_expect(input.min_value == 0.0 and input.max_value == 1.0, "Native point Y input range differs from X")
		var history := _history(target)
		history.clear_history()
		input.grabbed.emit()
		input.value = 2.5
		_expect((point.get(&"position") as Vector2).y == 1.0, "Native point Y drag exceeded 1")
		input.value = -0.5
		_expect((point.get(&"position") as Vector2).y == 0.0, "Native point Y drag fell below 0")
		input.ungrabbed.emit()
		await process_frame
		_expect(history.get_history_count() == 1, "Clamped Y drag changed transaction count")
		history.undo()
		_expect(is_equal_approx((point.get(&"position") as Vector2).y, 0.4), "Clamped Y Undo failed")
		# Callback guard also clamps values arriving outside the widget's Range.
		p.context._on_native_vector_value_changed(4.0, point, property_name, 1, input)
		_expect((point.get(&"position") as Vector2).y == 1.0, "Native callback bypassed Y limit")
		p.context._edit_native_point_property(Factory.create(target).find_point(point), &"position", Vector2(0.35, -2.0))
		_expect((point.get(&"position") as Vector2).y == 0.0, "Native direct Inspector edit bypassed Y limit")
		if not linear:
			var handle_input := _input(p, point, 1, "left_control_point")
			handle_input.value = 1.5
			_expect((point.get(&"left_control_point") as Vector2).y == 1.5, "Position clamp restricted a Free handle")
		_close(p)
		history.clear_history()
		await process_frame


func _collect_inputs(node: Node, result: Array[EditorSpinSlider]) -> void:
	for child in node.get_children():
		if child is EditorSpinSlider:
			result.append(child)
		_collect_inputs(child, result)


func _button(node: Node, label: String) -> Button:
	if node is Button and (node.text == label or node.tooltip_text == label):
		return node
	for child in node.get_children():
		var found := _button(child, label)
		if found != null:
			return found
	return null


func _point_panel(node: Node, point: Resource) -> Control:
	if node.has_meta(&"point_resource") and node.get_meta(&"point_resource") == point:
		return node as Control
	for child in node.get_children():
		var panel := _point_panel(child, point)
		if panel != null:
			return panel
	return null


func _handle_mode_option(node: Node) -> OptionButton:
	if node is OptionButton and node.item_count == 5:
		return node
	for child in node.get_children():
		var option := _handle_mode_option(child)
		if option != null:
			return option
	return null


func _test_mutations(native_a: bool, native_b: bool) -> void:
	var a := _presentation(_curve(native_a))
	var b := _presentation(_curve(native_b))
	await process_frame
	for current in [a, b]:
		var sibling: Dictionary = b if current == a else a
		var backend := Factory.create(current.curve)
		var other := Factory.create(sibling.curve)
		var unchanged: Variant = other.capture_snapshot().duplicate(true)
		var point: Resource = backend.get_point(1)
		current.graph.edit_point_property(1, &"position", Vector2(0.35, 0.55))
		_expect(is_equal_approx(point.get(&"position").y, 0.55), "Graph edit missed its resource")
		_expect(other.capture_snapshot() == unchanged, "Graph edit mutated sibling")
		_input(current, point).value = 0.6
		_expect(is_equal_approx(point.get(&"position").y, 0.6), "Visible list field missed its resource")
		_expect(other.capture_snapshot() == unchanged, "List edit mutated sibling")
		_handle_mode_option(_point_panel(current.points_root, point)).item_selected.emit(4)
		_expect(point.get(&"handle_mode") == 4, "List Handle Mode missed target")
		_expect(other.capture_snapshot() == unchanged, "List Handle Mode mutated sibling")
		for property in [[&"handle_mode", 3], [&"handle_mode", 0], [&"left_control_state", 2], [&"left_control_state", 0], [&"right_control_state", 1], [&"toolbar_options_reset", true]]:
			current.graph.edit_point_property(1, property[0], property[1])
			if property[0] == &"handle_mode":
				_expect(point.get(&"handle_mode") == property[1], "Handle Mode missed target")
			elif property[0] == &"left_control_state":
				_expect(backend.get_point_control_state(1, 0) == property[1], "Handle lock missed target")
			elif property[0] == &"right_control_state":
				_expect(backend.is_point_control_force_linear(1, 1), "Force Linear missed target")
			else:
				_expect(point.get(&"handle_mode") == 0 and backend.get_point_control_state(1, 0) == 0 and backend.get_point_control_state(1, 1) == 0, "Reset missed target")
			_expect(other.capture_snapshot() == unchanged, "Point option/reset mutated sibling: %s" % property[0])
		var add := _button(current.points_root, "Add Point")
		var count: int = backend.get_point_count()
		add.pressed.emit()
		_expect(backend.get_point_count() == count + 1, "Add Point missed its resource")
		_expect(other.capture_snapshot() == unchanged, "Add Point mutated sibling")
		point = backend.get_point(1)
		var before_reorder: Variant = backend.capture_snapshot().duplicate(true)
		current.context._move_point_relative(point, 1)
		_expect(backend.capture_snapshot() != before_reorder, "Reorder missed target")
		_expect(other.capture_snapshot() == unchanged, "Reorder mutated sibling")
		if current.curve is EasingCurve:
			current.context._on_remove_btn_pressed(point)
		else:
			current.context._remove_native_point(point)
		_expect(backend.find_point(point) < 0, "Remove missed its resource")
		_expect(other.capture_snapshot() == unchanged, "Remove mutated sibling")
	_close(a)
	_close(b)
	await process_frame


func _test_same_resource(native: bool) -> void:
	var target := _curve(native)
	var backend := Factory.create(target)
	var a := _presentation(target)
	var b := _presentation(target)
	await process_frame
	var history := _history(target)
	history.clear_history()
	a.graph.selected_index = 1
	b.graph.selected_index = 2
	var point: Resource = backend.get_point(1)
	var input_a := _input(a, point)
	var input_b := _input(b, point)
	input_a.grabbed.emit()
	input_a.value = 0.66
	_expect(is_equal_approx(input_b.value, 0.66), "Same-resource sibling field did not refresh")
	_expect(b.graph.selected_index == 2, "Sibling inherited selection")
	_expect(not b.graph._backend_point_edit_active, "Sibling acquired Native transaction")
	_expect(not b.context._point_edit_transaction_controller.is_point_edit_active(), "Sibling acquired Legacy transaction")
	input_a.ungrabbed.emit()
	await process_frame
	_expect(history.get_history_count() == 1, "Same-resource edit must create exactly one Undo action")
	history.undo()
	_expect(is_equal_approx(backend.get_point(1).get(&"position").y, 0.4), "Same-resource Undo failed")
	_expect(b.graph.selected_index == 2, "Undo restored selection into sibling")
	history.redo()
	_expect(is_equal_approx(backend.get_point(1).get(&"position").y, 0.66), "Same-resource Redo failed")
	var graph_id: int = a.graph.get_instance_id()
	a.graph._set_right_delete_dragging(true)
	a.graph._store_right_delete_drag_state()
	_expect(not EasingCurveEditor._right_delete_drag_state_by_curve.has(target.get_instance_id()), "Inspector stored shared RMB gesture")
	var c := _presentation(target)
	_expect(c.graph.selected_index == -1, "New same-resource presentation inherited selection")
	var context_ref: WeakRef = weakref(a.context)
	_close(a)
	await process_frame
	await process_frame
	_expect(not is_instance_id_valid(graph_id), "History retained destroyed graph")
	_expect(context_ref.get_ref() == null, "History or callbacks retained destroyed context")
	history.undo()
	history.redo()
	_expect(is_equal_approx(backend.get_point(1).get(&"position").y, 0.66), "Undo/Redo failed after origin disposal")
	_close(b)
	_close(c)
	history.clear_history()
	await process_frame


func _test_teardown(native: bool, graph_first: bool) -> void:
	var target := _curve(native)
	var backend := Factory.create(target)
	var p := _presentation(target)
	await process_frame
	var history := _history(target)
	history.clear_history()
	var context: Context = p.context
	var point: Resource = backend.get_point(1)
	var input := _input(p, point)
	input.grabbed.emit()
	input.value = 0.61
	input.ungrabbed.emit() # Native completion is pending when roots exit.
	var exiting: Control = p.graph_root if graph_first else p.points_root
	exiting.free()
	_expect(not context.disposed, "First root exit disposed surviving surface")
	await process_frame
	_expect(history.get_history_count() == 1, "Partial teardown lost or duplicated applied edit")
	_expect(is_equal_approx(point.get(&"position").y, 0.61), "Teardown discarded applied mutation")
	if graph_first:
		input.grabbed.emit()
		input.value = 0.72
		input.ungrabbed.emit()
		await process_frame
		_expect(is_equal_approx(point.get(&"position").y, 0.72), "Surviving Points field failed")
		_expect(history.get_history_count() == 2, "Surviving Points edit has incorrect Undo count")
		_button(p.points_root, "Add Point").pressed.emit()
		_expect(backend.get_point_count() == 5, "Surviving Points Add failed")
		var graph_name := &"_editor_state_snapshot" if native else &"easing_curve_editor"
		context._parse_property(target, TYPE_NIL, graph_name, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR, false)
		for registration: Dictionary in context.registrations:
			p.column.add_child(registration.control)
			p.graph_root = registration.control
		context.registrations.clear()
		p.graph = context.easing_curve_editor
		p.graph.edit_point_property(1, &"position", Vector2(0.35, 0.81))
		_expect(is_equal_approx(backend.get_point(1).get(&"position").y, 0.81), "Rebuilt graph failed")
	else:
		p.graph.edit_point_property(1, &"position", Vector2(0.35, 0.72))
		_expect(is_equal_approx(point.get(&"position").y, 0.72), "Surviving graph failed")
		p.points_root = context._handle_native_points(target) if native else context._create_points_section(context.handle_points(target), target)
		p.column.add_child(p.points_root)
		_input(p, point).value = 0.81
		_expect(is_equal_approx(point.get(&"position").y, 0.81), "Rebuilt Points field failed")
	var context_ref: WeakRef = weakref(context)
	var actions := history.get_history_count()
	_close(p)
	_expect(context.disposed, "Final root exit did not dispose context")
	context._dispose_presentation()
	context = null
	await process_frame
	await process_frame
	_expect(history.get_history_count() == actions, "Final teardown duplicated completion")
	_expect(context_ref.get_ref() == null, "Disposed context was retained")
	history.undo()
	history.redo()
	history.clear_history()


func _test_clipboard(native: bool) -> void:
	var a := _presentation(_curve(native))
	var b := _presentation(_curve(not native))
	var backend := Factory.create(a.curve)
	var other := Factory.create(b.curve)
	var point: Resource = backend.get_point(1)
	var menu: PopupMenu = a.context._create_point_property_context_menu(1, &"position")
	a.points_root.add_child(menu)
	var unchanged: Variant = other.capture_snapshot().duplicate(true)
	a.context._apply_editor_point_property_change(b.curve, point, 1, &"position", Vector2(0.35, 0.9))
	_expect(is_equal_approx(point.get(&"position").y, 0.4), "Clipboard accepted resource mismatch")
	backend.apply_point_property(1, &"position", Vector2(0.9, 0.4))
	backend.apply_point_order(backend.get_ordered_points(point))
	_expect(backend.find_point(point) != 1, "Clipboard fixture did not reorder point identity")
	a.context._point_property_clipboard.apply_point_value(a.curve, point, &"handle_mode", 3, a.context._apply_editor_point_property_change)
	_expect(point.get(&"handle_mode") == 3, "Clipboard did not recompute reordered identity")
	_expect(other.capture_snapshot() == unchanged, "Clipboard fell through to latest resource")
	if DisplayServer.get_name() != "headless":
		var saved_clipboard := DisplayServer.clipboard_get()
		DisplayServer.clipboard_set("Vector2(0.9, 0.92)")
		menu.id_pressed.emit(1)
		DisplayServer.clipboard_set(saved_clipboard)
		_expect(is_equal_approx(point.get(&"position").y, 0.92), "Captured clipboard menu lost reordered point identity")
		_expect(other.capture_snapshot() == unchanged, "Clipboard menu mutated latest parsed resource")
	backend.remove_point(backend.find_point(point))
	var before: Variant = backend.capture_snapshot().duplicate(true)
	a.context._apply_editor_point_property_change(a.curve, point, 1, &"position", Vector2.ONE)
	_expect(backend.capture_snapshot() == before, "Clipboard accepted removed point")
	_close(a)
	_close(b)
	await process_frame


func _test_pending_disposal(native: bool, queued: bool) -> void:
	var target := _curve(native)
	var backend := Factory.create(target)
	var p := _presentation(target)
	var sibling := _presentation(target)
	await process_frame
	var history := _history(target)
	history.clear_history()
	var point: Resource = backend.get_point(1)
	var field := _input(p, point)
	field.value_focus_entered.emit()
	field.value = 0.73
	_close(sibling)
	_expect(history.get_history_count() == 0, "Closing sibling committed originating transaction")
	if queued:
		field.value_focus_exited.emit()
	var context_ref: WeakRef = weakref(p.context)
	_close(p)
	await process_frame
	await process_frame
	_expect(is_equal_approx(point.get(&"position").y, 0.73), "Full disposal lost text edit")
	_expect(history.get_history_count() == 1, "Full disposal must commit pending text edit exactly once")
	_expect(context_ref.get_ref() == null, "Pending completion retained disposed context")
	history.undo()
	_expect(is_equal_approx(backend.get_point(1).get(&"position").y, 0.4), "Disposed text edit Undo failed")
	history.redo()
	_expect(is_equal_approx(backend.get_point(1).get(&"position").y, 0.73), "Disposed text edit Redo failed")
	history.clear_history()


func _test_graph_survives_points_teardown(native: bool) -> void:
	var target := _curve(native)
	var p := _presentation(target)
	await process_frame
	# Native initial Autofit suppresses drawing until its deferred layout settles.
	for frame in range(8):
		if not p.graph._graph_render_suppressed:
			break
		await process_frame
	p.graph.update_view_transform()
	var history := _history(target)
	history.clear_history()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = p.graph.get_view_pos(p.graph._backend.curve_to_display_position(p.graph._point(1).get(&"position")))
	p.graph._gui_input(press)
	_expect(p.graph._get_drag_coordinate_position().is_finite(), "Graph drag did not show coordinates")
	p.graph._request_point_property_change(1, &"position", Vector2(0.35, 0.67), true)
	p.points_root.free()
	await process_frame
	_expect(not p.context.disposed, "Points teardown disposed active graph")
	_expect(history.get_history_count() == 0, "Points teardown finished active graph gesture")
	_expect(p.graph._get_drag_coordinate_position().is_finite(), "Points teardown dismissed surviving graph coordinates")
	p.graph._handle_left_released()
	_expect(not p.graph._get_drag_coordinate_position().is_finite(), "Graph release retained coordinates")
	_expect(history.get_history_count() == 1, "Surviving graph did not commit exactly one action")
	_close(p)
	await process_frame
	history.undo()
	_expect(is_equal_approx(Factory.create(target).get_point(1).get(&"position").y, 0.4), "Graph gesture Undo failed after final disposal")
	history.clear_history()


func _test_original_reproduction() -> void:
	var native := _presentation(_curve(true))
	var legacy := _presentation(_curve(false))
	legacy.curve.trans_type = EasingCurve.TRANS.CUBIC
	await process_frame
	var before: Variant = Factory.create(legacy.curve).capture_snapshot().duplicate(true)
	var point: Resource = Factory.create(native.curve).get_point(1)
	_input(native, point).value = 0.82
	_expect(is_equal_approx(point.get(&"position").y, 0.82), "Original reproduction failed to edit Native")
	_expect(Factory.create(legacy.curve).capture_snapshot() == before, "Original reproduction edited Legacy")
	_close(native)
	_close(legacy)
	await process_frame


func _find_context(node: Node, target: Resource) -> Context:
	var context := node.get_meta(&"_inspector_context") as Context if node.has_meta(&"_inspector_context") else null
	if context != null and context.resource == target and not context.disposed:
		return context
	for child in node.get_children():
		var found := _find_context(child, target)
		if found != null:
			return found
	return null


func _test_rendered_inspectors() -> void:
	var plugin := Plugin.new()
	plugin.editor_undo_redo = _undo
	# Reuse the loaded addon when present: two plugins recursively wrap the
	# same parameter slider while instantiate_property_editor() is running.
	var existing_plugin: EditorInspectorPlugin
	for node in root.find_children("*", "EditorPlugin", true, false):
		if node.get_script() == load("res://addons/easing_curve/plugin.gd"):
			existing_plugin = node.easing_curve_editor_inspector_plugin
			break
	if existing_plugin == null:
		_undo_plugin.add_inspector_plugin(plugin)
	for kinds in [[false, false, false], [true, true, false], [false, true, false], [true, false, false], [false, false, true], [true, true, true]]:
		var target_a := _curve(kinds[0])
		var target_b := target_a if kinds[2] else _curve(kinds[1])
		var inspector_a := EditorInspector.new()
		var inspector_b := EditorInspector.new()
		for inspector in [inspector_a, inspector_b]:
			inspector.custom_minimum_size = Vector2(620, 850)
			_host.add_child(inspector)
		inspector_a.edit(target_a)
		inspector_b.edit(target_b)
		for frame in range(5):
			await process_frame
		var context_a := _find_context(inspector_a, target_a)
		var context_b := _find_context(inspector_b, target_b)
		_expect(context_a != null and context_b != null and context_a != context_b, "Shared plugin did not construct independent real inspectors")
		if context_a == null or context_b == null:
			inspector_a.free()
			inspector_b.free()
			continue
		var point: Resource = Factory.create(target_a).get_point(1)
		var field := _input({"context": context_a}, point)
		inspector_a.ensure_control_visible(field)
		await process_frame
		var unchanged: Variant = Factory.create(target_b).capture_snapshot().duplicate(true)
		await _type_field(field, "0.63")
		_expect(is_equal_approx(point.get(&"position").y, 0.63), "Rendered keyboard input did not edit originating field")
		if not kinds[2]:
			_expect(Factory.create(target_b).capture_snapshot() == unchanged, "Rendered edit mutated sibling resource")
		else:
			var refreshed_b := _find_context(inspector_b, target_b)
			_expect(is_equal_approx(_input({"context": refreshed_b}, point).value, 0.63), "Rendered same-resource field did not synchronize")
		# Exercise a real shared-plugin rebuild, then edit the untouched inspector.
		if not kinds[2]:
			target_b.set(&"trans_type" if target_b is EasingCurve else &"transition", EasingCurve.TRANS.CUBIC if target_b is EasingCurve else 7)
			inspector_b.edit(null)
			inspector_b.edit(target_b)
			for frame in range(3):
				await process_frame
			context_a = _find_context(inspector_a, target_a)
			field = _input({"context": context_a}, point)
			inspector_a.ensure_control_visible(field)
			await process_frame
			await _type_field(field, "0.76")
			_expect(is_equal_approx(point.get(&"position").y, 0.76), "Visible field stopped tracking after sibling rebuild")
		if kinds == [true, false, false]:
			RenderingServer.force_draw()
			_test_window.get_texture().get_image().save_png("res://test/_temp/ownership-mixed.png")
		inspector_a.edit(null)
		inspector_b.edit(null)
		inspector_a.free()
		inspector_b.free()
		await process_frame
	await _test_rendered_preset_visibility()
	if existing_plugin == null:
		_undo_plugin.remove_inspector_plugin(plugin)


func _test_rendered_preset_visibility() -> void:
	for native: bool in [false, true]:
		var target: Resource = ClassDB.instantiate(&"NativeEasingCurve") if native else EasingCurve.new()
		var trans_property := &"transition" if native else &"trans_type"
		target.set(trans_property, 1 if native else EasingCurve.TRANS.SINE)
		var inspector := EditorInspector.new()
		inspector.custom_minimum_size = Vector2(620, 850)
		_host.add_child(inspector)
		inspector.edit(target)
		await _observe_preset_frames(inspector, target, "initial")
		var history := _history(target)
		history.clear_history()
		# Same-mode and cross-mode transitions must exercise real Inspector reparses.
		var transitions := [4, 6, 7] if native else [EasingCurve.TRANS.QUAD, EasingCurve.TRANS.ELASTIC, EasingCurve.TRANS.CUBIC]
		for trans: int in transitions:
			var context := _find_context(inspector, target)
			var content: Control = context.graph_root_ref.get_ref()
			var toolbar := content.get_child(0) as GridContainer
			var option := toolbar.get_child(4) as OptionButton
			var previous: int = target.get(trans_property)
			option.item_selected.emit(option.get_item_index(trans))
			_expect(not context.easing_curve_editor.is_graph_render_suppressed(), "Transition immediately blanked graph")
			_expect(int(target.get(trans_property)) == trans, "Rendered transition selection did not apply")
			await _observe_preset_frames(inspector, target, "trans_%d" % trans)
			history.undo()
			_expect(int(target.get(trans_property)) == previous, "Transition Undo did not restore preset")
			await _observe_preset_frames(inspector, target, "undo_%d" % trans, false)
			history.redo()
			_expect(int(target.get(trans_property)) == trans, "Transition Redo did not restore preset")
			await _observe_preset_frames(inspector, target, "redo_%d" % trans, false)
			context = _find_context(inspector, target)
			content = context.graph_root_ref.get_ref()
			toolbar = content.get_child(0) as GridContainer
			var ease := toolbar.get_child(1) as OptionButton
			# Repeated selections before layout settles must leave only the latest fit.
			for ease_id: int in [EasingCurve.EASE.OUT, EasingCurve.EASE.IN_OUT, EasingCurve.EASE.OUT_IN]:
				ease.item_selected.emit(ease.get_item_index(ease_id))
				_expect(not context.easing_curve_editor.is_graph_render_suppressed(), "Rapid Ease selection blanked graph")
			await _observe_preset_frames(inspector, target, "ease_%d" % trans)
			context = _find_context(inspector, target)
			content = context.graph_root_ref.get_ref()
			toolbar = content.get_child(0) as GridContainer
			(toolbar.get_child(2) as Button).pressed.emit()
			_expect(int(target.get(&"ease_type")) == EasingCurve.EASE.IN, "Rendered Ease reset did not apply")
			await _observe_preset_frames(inspector, target, "reset_%d" % trans)
		inspector.edit(null)
		inspector.free()
		history.clear_history()
		await process_frame


func _observe_preset_frames(inspector: EditorInspector, target: Resource, label: String, check_fit := true) -> void:
	var frames := Image.create(620, 360 * 6, false, Image.FORMAT_RGBA8)
	for frame in range(6):
		await process_frame
		var context := _find_context(inspector, target)
		_expect(context != null, "Preset update lost the rendered Inspector context")
		if context == null:
			return
		var graph := context.easing_curve_editor
		_expect(not graph.is_graph_render_suppressed(), "Preset update blanked graph on frame %d" % frame)
		RenderingServer.force_draw()
		var screenshot := _test_window.get_texture().get_image()
		var graph_rect := Rect2i(Rect2(graph.global_position + graph._get_graph_view_rect().position, graph._get_graph_view_rect().size))
		var graph_image := screenshot.get_region(graph_rect)
		_expect(_has_curve_ink(graph_image), "Rendered curve disappeared: %s frame %d" % [label, frame])
		frames.blit_rect(graph_image, Rect2i(Vector2i.ZERO, graph_image.get_size()), Vector2i(0, frame * 360))
	var backend := "legacy" if target is EasingCurve else "native"
	_expect(frames.save_png("res://test/_temp/autofit-%s-%s.png" % [backend, label]) == OK, "Could not save Autofit frame capture")
	var settled := _find_context(inspector, target)
	_expect(not settled._is_autofit_pending(), "Rendered Autofit did not settle")
	# Undo/Redo restores saved view state rather than requesting a new fit.
	if not check_fit:
		return
	var graph := settled.easing_curve_editor
	var zoom := graph._zoom_step
	var pan := graph.pan_offset
	graph.autofit()
	_expect(graph._zoom_step == zoom and graph.pan_offset.is_equal_approx(pan), "Rendered Autofit did not match manual fit: %s/%s" % [backend, label])


func _has_curve_ink(image: Image) -> bool:
	var white_pixels := 0
	for y in range(2, image.get_height() - 2, 2):
		for x in range(2, image.get_width() - 2, 2):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.9 and pixel.g > 0.9 and pixel.b > 0.9:
				white_pixels += 1
				if white_pixels >= 8:
					return true
	return false


func _type_field(field: EditorSpinSlider, value: String) -> void:
	var position := field.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	_test_window.push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		_test_window.push_input(click, true)
	await process_frame
	var select_all := InputEventKey.new()
	select_all.keycode = KEY_A
	select_all.ctrl_pressed = true
	select_all.pressed = true
	_test_window.push_input(select_all, true)
	for character in value:
		var key := InputEventKey.new()
		key.unicode = character.unicode_at(0)
		key.pressed = true
		_test_window.push_input(key, true)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	_test_window.push_input(enter, true)
	for frame in range(3):
		await process_frame

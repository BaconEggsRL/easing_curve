extends "res://test/scripts/support/test_case.gd"

const Context := preload("res://addons/easing_curve/scripts/editor/inspector/inspector_curve_context.gd")


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(Engine.is_editor_hint() and ClassDB.class_exists(&"NativeEasingCurve"), "Native Inspector requires an editor host and extension")
	if not Engine.is_editor_hint() or not ClassDB.class_exists(&"NativeEasingCurve"):
		_finish("Native Points transforms")
		return
	for count in [2, 6]:
		await _test_transforms(count)
	for flags in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		await _test_edits(flags)
	await _test_reversed_row_actions()
	_finish("Native Points transforms")


func _fixture(count: int) -> Dictionary:
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var points: Array[Resource] = []
	for index in range(count):
		var point := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
		var x := pow(float(index) / float(count - 1), 1.3)
		var position := Vector2(x, 0.12 + 0.73 * x)
		point.set(&"position", position)
		point.set(&"left_control_point", position + Vector2(-0.08, -0.11))
		point.set(&"right_control_point", position + Vector2(0.13, 0.06))
		if count > 2 and index > 1:
			point.set(&"handle_mode", index - 1)
		if index == 0:
			point.set(&"right_force_linear", true)
		point.set(&"locked", {&"position": index == 0, &"left_control_point": index == count - 1, &"right_control_point": false})
		points.append(point)
	curve.set(&"points", points)
	var context := Context.new()
	var graph := context.handle_easing_curve_editor(curve)
	root.add_child(graph)
	var section := context._handle_native_points(curve)
	root.add_child(section)
	var history := UndoRedo.new()
	context.easing_curve_editor.editor_undo_redo = history
	context._select_native_point(points[1])
	var selected_panel := context._native_points_content.get_child(1)
	var header := _header(selected_panel, "Left Control")
	context._select_native_point_property(header, points[1], &"left_control_point")
	return {"curve": curve, "points": points, "context": context, "graph": graph, "section": section, "history": history}


func _dispose(fixture: Dictionary) -> void:
	fixture.history.clear_history()
	fixture.section.free()
	fixture.graph.free()
	_expect(fixture.context.native_point_display_changed.get_connections().is_empty(), "Display callbacks survived disposal")
	fixture.curve.set(&"invert", not bool(fixture.curve.get(&"invert")))


func _expected(value: Vector2, curve: Resource) -> Vector2:
	if curve.get(&"reverse"):
		value.x = 1.0 - value.x
	if curve.get(&"invert"):
		value.y = 1.0 - value.y
	return value


func _header(panel: Node, label: String) -> Control:
	for candidate in panel.find_children("*", "Label", true, false):
		if candidate.text == label:
			return candidate.get_parent() as Control
	return null


func _inputs(panel: Node, label: String) -> Array[Node]:
	var header := _header(panel, label)
	if header == null:
		return []
	return header.get_parent().get_child(header.get_index() + 1).find_children("*", "EditorSpinSlider", true, false)


func _panel(fixture: Dictionary, point: Resource) -> Node:
	for panel in fixture.context._native_points_content.get_children():
		if panel.get_meta(&"point_resource") == point:
			return panel
	return null


func _assert_list(fixture: Dictionary) -> void:
	var curve: Resource = fixture.curve
	var points: Array = curve.get(&"points")
	var displayed := points.duplicate()
	if curve.get(&"reverse"):
		displayed.reverse()
	var panels: Array = fixture.context._native_points_content.get_children()
	_expect(panels.size() == displayed.size(), "Points row count differs")
	for index in range(displayed.size()):
		var point: Resource = displayed[index]
		var panel: Node = panels[index]
		_expect(panel.get_meta(&"point_resource") == point, "Displayed row ordering differs")
		_expect((_header(panel, "Left Control") != null) == (index > 0), "Left endpoint presentation differs")
		_expect((_header(panel, "Right Control") != null) == (index < displayed.size() - 1), "Right endpoint presentation differs")
		var mode_header := _header(panel, "Handle Mode")
		var mode := mode_header.get_parent().get_child(mode_header.get_index() + 1) as OptionButton
		_expect(mode.selected == int(point.get(&"handle_mode")), "Stale handle mode")
		for label: String in ["Position", "Left Control", "Right Control"]:
			var inputs := _inputs(panel, label)
			if inputs.is_empty():
				continue
			var property_name := &"position"
			if label != "Position":
				var left := label == "Left Control"
				if curve.get(&"reverse"):
					left = not left
				property_name = &"left_control_point" if left else &"right_control_point"
			_expect(_header(panel, label).get_meta(&"point_property_name") == property_name, "Displayed handle targets wrong stored side")
			var value := _expected(point.get(property_name) as Vector2, curve)
			var displayed_value := Vector2(inputs[0].value, inputs[1].value)
			_expect(displayed_value.is_equal_approx(value.snapped(Vector2.ONE * Context.SLIDER_INPUT_STEP)), "Stale %s inputs at row %d: expected %s, got %s" % [label, index, value, displayed_value])
		var selected: Resource = fixture.context.easing_curve_editor.get_selected_point_resource()
		_expect(panel.self_modulate == (Color(0.72, 0.86, 1.0) if selected == point else Color.WHITE), "Selection highlight differs")
	var graph_points: Array = fixture.context.easing_curve_editor.call(&"_get_display_points")
	_expect(graph_points == displayed, "Graph/list point order differs")
	var selected_header: Control = fixture.context._selected_point_property_header
	if is_instance_valid(selected_header):
		_expect(selected_header.get_meta(&"point_resource_id") == fixture.context.easing_curve_editor.get_selected_point_resource().get_instance_id(), "Property selection lost logical point")


func _test_transforms(count: int) -> void:
	var fixture := _fixture(count)
	var curve: Resource = fixture.curve
	var before: Array = curve.call(&"capture_point_states")
	var original_points: Array = curve.get(&"points")
	var samples: Array[float] = []
	for step in range(21):
		samples.append(float(curve.call(&"sample", float(step) / 20.0)))
	var publications := [0]
	curve.changed.connect(func(): publications[0] += 1)
	for sequence in [[&"reverse", &"invert"], [&"invert", &"reverse"], [&"reverse", &"reverse"], [&"invert", &"invert"]]:
		curve.set(&"reverse", false)
		curve.set(&"invert", false)
		await process_frame
		fixture.history.clear_history()
		for property_name: StringName in sequence:
			var panels: Array = fixture.context._native_points_content.get_children()
			var old_value: bool = curve.get(property_name)
			var count_before: int = publications[0]
			fixture.history.create_action("Toggle " + property_name)
			fixture.history.add_do_property(curve, property_name, not old_value)
			fixture.history.add_undo_property(curve, property_name, old_value)
			fixture.history.commit_action()
			if property_name == &"invert":
				_assert_list(fixture)
				_expect(fixture.context._native_points_content.get_children() == panels, "Value-only transform rebuilt rows")
			await process_frame
			_assert_list(fixture)
			_expect(publications[0] == count_before + 1, "Transform refresh recursively published changes")
			_expect(curve.call(&"capture_point_states") == before and curve.get(&"points") == original_points, "Transform mutated stored point state")
			for step in range(21):
				var expected := samples[20 - step if curve.get(&"reverse") else step]
				if curve.get(&"invert"):
					expected = 1.0 - expected
				_expect(is_equal_approx(float(curve.call(&"sample", float(step) / 20.0)), expected), "Transform changed curve sampling")
			_expect(fixture.context.easing_curve_editor.get_selected_point_resource() == original_points[1], "Transform lost logical selection")
			fixture.history.undo()
			await process_frame
			_assert_list(fixture)
			fixture.history.redo()
			await process_frame
			_assert_list(fixture)
	_dispose(fixture)


func _test_edits(flags: Vector2i) -> void:
	var fixture := _fixture(6)
	var curve: Resource = fixture.curve
	curve.set(&"reverse", flags.x != 0)
	curve.set(&"invert", flags.y != 0)
	await process_frame
	var point: Resource = fixture.points[1]
	for label: String in ["Position", "Left Control", "Right Control"]:
		for axis in range(2):
			fixture.history.clear_history()
			var panel := _panel(fixture, point)
			var header := _header(panel, label)
			var property_name: StringName = header.get_meta(&"point_property_name")
			var inputs := _inputs(panel, label)
			var before: Array = curve.call(&"capture_point_states")
			var desired := _expected(point.get(property_name) as Vector2, curve)
			desired[axis] = snappedf(inputs[axis].value + 0.023, Context.SLIDER_INPUT_STEP)
			inputs[axis].value = desired[axis]
			await process_frame
			_expect((point.get(property_name) as Vector2).is_equal_approx(_expected(desired, curve)), "Display edit wrote wrong stored coordinate/side")
			if label != "Position":
				var other := &"right_control_point" if property_name == &"left_control_point" else &"left_control_point"
				_expect(point.get(other) == before[1][other], "Handle edit modified opposite stored side")
			_assert_list(fixture)
			var after: Array = curve.call(&"capture_point_states")
			_expect(fixture.history.has_undo(), "Coordinate edit omitted history")
			fixture.history.undo()
			await process_frame
			_expect(curve.call(&"capture_point_states") == before, "Coordinate Undo failed")
			_expect(not fixture.history.has_undo(), "Coordinate edit created extra history")
			_assert_list(fixture)
			fixture.history.redo()
			await process_frame
			_expect(curve.call(&"capture_point_states") == after, "Coordinate Redo failed")
			_assert_list(fixture)
	# Exercise the same validated paste path used by menus and keyboard shortcuts.
	var paste := Vector2(0.34, 0.63)
	fixture.context._apply_pasted_point_property_value(1, &"right_control_point", paste)
	_expect((point.get(&"right_control_point") as Vector2).is_equal_approx(_expected(paste, curve)), "Paste wrote display coordinates directly")
	if DisplayServer.get_name() != "headless":
		var clipboard := DisplayServer.clipboard_get()
		fixture.context._copy_point_property_value(1, &"right_control_point")
		_expect(str_to_var(DisplayServer.clipboard_get()).is_equal_approx(paste), "Copy omitted display transform")
		fixture.context._copy_point_property_path(1, &"right_control_point")
		_expect(DisplayServer.clipboard_get() == "points/1/right_control_point", "Copy path did not identify stored property")
		DisplayServer.clipboard_set(clipboard)
	else:
		print("SKIP: OS clipboard exchange requires a visible editor; paste mapping was tested")
	# Linear handles alias position, including its lock, in transformed space.
	point.set(&"handle_mode", 1)
	var linear_inputs := _inputs(_panel(fixture, point), "Left Control")
	var desired := _expected(point.get(&"position") as Vector2, curve)
	desired.y = snappedf(linear_inputs[1].value + 0.02, Context.SLIDER_INPUT_STEP)
	linear_inputs[1].value = desired.y
	_expect((point.get(&"position") as Vector2).is_equal_approx(_expected(desired, curve)), "Linear handle did not map to stored position")
	point.call(&"set_locked", &"position", true)
	var locked: Variant = point.get(&"position")
	linear_inputs[1].value += 0.02
	_expect(point.get(&"position") == locked and linear_inputs[1].read_only, "Locked Linear alias remained editable")
	_assert_list(fixture)
	_dispose(fixture)


func _test_reversed_row_actions() -> void:
	var fixture := _fixture(6)
	fixture.curve.set(&"reverse", true)
	await process_frame
	var point: Resource = fixture.points[1]
	var index := _panel(fixture, point).get_index()
	var panel := _panel(fixture, point)
	for button in panel.find_children("*", "Button", true, false):
		if button.tooltip_text == "Swap Previous Point":
			button.pressed.emit()
			break
	await process_frame
	_expect(_panel(fixture, point).get_index() == index - 1, "Reverse previous-row action moved in stored order")
	_expect(fixture.context.easing_curve_editor.get_selected_point_resource() == point, "Row move lost logical selection")
	_assert_list(fixture)
	fixture.history.undo()
	await process_frame
	_expect(_panel(fixture, point).get_index() == index, "Row move Undo lost displayed index")
	_assert_list(fixture)
	_dispose(fixture)

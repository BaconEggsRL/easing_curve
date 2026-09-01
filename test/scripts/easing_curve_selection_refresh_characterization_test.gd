extends "res://test/scripts/test_case.gd"

const EDITOR_HOST = preload("res://test/scripts/editor_host_test_harness.gd")
const EDITOR_DRIVER = preload("res://test/scripts/easing_curve_editor_test_driver.gd")
const EDITOR_UNDO = preload("res://addons/easing_curve/scripts/editor/easing_curve_editor_undo.gd")

func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("easing_curve_selection_refresh_characterization_test.gd"):
		quit(1)
		return
	call_deferred(&"_run")


func _run() -> void:
	_test_add_undo_redo_selection_symmetry()
	_test_normal_property_row_order()
	_test_property_selection_survives_reparse()
	_test_topology_and_resource_switch_selection()
	_test_resource_view_state_persistence()
	_finish("selection and refresh characterization")


func _curve() -> EasingCurve:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [
		EasingCurvePoint.new(Vector2.ZERO),
		EasingCurvePoint.new(Vector2(0.33, 0.35)),
		EasingCurvePoint.new(Vector2(0.66, 0.7)),
		EasingCurvePoint.new(Vector2.ONE),
	]
	return curve


func _commit_add(
		history: UndoRedo,
		curve: EasingCurve,
		inspector: Object,
		point: EasingCurvePoint,
) -> void:
	var before := EDITOR_UNDO.capture_state(curve)
	var selection_before := EDITOR_DRIVER.capture_point_selection(inspector)
	var points: Array[EasingCurvePoint] = curve.points.duplicate()
	points.append(point)
	points.sort_custom(func(a: EasingCurvePoint, b: EasingCurvePoint) -> bool: return a.position.x < b.position.x)
	var added_index := points.find(point)
	curve.set_point_snapshot(curve.make_point_snapshot(points))
	EDITOR_DRIVER.select_point(inspector, curve.points[added_index])
	var selection_after := EDITOR_DRIVER.capture_point_selection(inspector)
	_expect(
		EDITOR_UNDO.commit_applied_action(
			history,
			curve,
			"Add Easing Curve Point",
			EasingCurveEditorUndo.ActionContext.new(before).with_selection(
				Callable(inspector, "_restore_point_selection_state"),
				selection_before,
				selection_after,
			),
		),
		"Add did not create an Undo action",
	)


func _test_add_undo_redo_selection_symmetry() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [EasingCurvePoint.new(Vector2.ZERO), EasingCurvePoint.new(Vector2.ONE)]
	var context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = context.editor
	var inspector: Object = context.inspector
	var history := UndoRedo.new()
	EDITOR_DRIVER.clear_point_selection(inspector)
	editor.selected_index = -1

	var point_a := EasingCurvePoint.new(Vector2(0.33, 0.25))
	_commit_add(history, curve, inspector, point_a)
	_expect(editor.selected_index == 1, "First add did not select point A")
	history.undo()
	_expect(editor.selected_index == -1 and int(inspector.get("_selected_point_index")) == -1, "Undo first add did not restore no selection")
	history.redo()
	_expect(editor.selected_index == 1, "Redo first add did not restore point A selection")

	var point_b := EasingCurvePoint.new(Vector2(0.66, 0.75))
	_commit_add(history, curve, inspector, point_b)
	_expect(editor.selected_index == 2, "Second add did not select point B")
	for cycle in range(2):
		history.undo()
		_expect(editor.selected_index == 1, "Undo second add lost point A selection on cycle %d" % (cycle + 1))
		history.redo()
		_expect(editor.selected_index == 2, "Redo second add lost point B selection on cycle %d" % (cycle + 1))
	history.clear_history(false)
	history.free()
	editor.free()


func _create_property_header(
		inspector: Object,
		point: EasingCurvePoint,
		index: int,
		property_name: StringName,
) -> Dictionary:
	var grid := GridContainer.new()
	grid.columns = 2
	var definition := EasingCurve.get_point_property_definition(property_name)
	if property_name == &"handle_mode":
		inspector.call("_create_handle_mode_property", point, index, definition, grid)
	else:
		inspector.call("_create_vector2_property", point, index, definition, grid)
	return {"grid": grid, "header": grid.get_child(0) as PanelContainer}


func _test_normal_property_row_order() -> void:
	var curve := _curve()
	var context := EDITOR_HOST.create_inspector_context(curve)
	var inspector: Object = context.inspector
	for point_index in range(curve.points.size()):
		var expected_row: Array[StringName] = [
			&"position",
			&"handle_mode",
		]
		if point_index != 0:
			expected_row.append(&"left_control_point")
		if point_index != curve.points.size() - 1:
			expected_row.append(&"right_control_point")
		var definitions: Array = inspector.call(
			"_get_normal_point_property_definitions",
			point_index,
			curve.points.size(),
		)
		var property_names: Array[StringName] = []
		for definition: Dictionary in definitions:
			property_names.append(definition["name"])
			_expect(bool(definition["inspector_visible"]), "%s generated a hidden storage row" % definition["name"])
		_expect(property_names == expected_row, "Point %d normal row order changed" % (point_index + 1))
	context.editor.free()


func _test_property_selection_survives_reparse() -> void:
	var curve := _curve()
	var context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = context.editor
	var inspector: Object = context.inspector
	var selected_point: EasingCurvePoint = curve.points[2]
	for property_name in [&"position", &"handle_mode", &"left_control_point", &"right_control_point"]:
		var first := _create_property_header(inspector, selected_point, 2, property_name)
		var first_header: PanelContainer = first.header
		_expect(first_header != null, "%s did not create a selectable property header" % property_name)
		EDITOR_DRIVER.select_point_property(inspector, first_header, 2, property_name)
		editor.selected_index = 2
		EDITOR_DRIVER.change_point_property(inspector, 2, property_name, selected_point.get(property_name))
		EDITOR_DRIVER.rebuild_for_curve(inspector, curve)
		var recreated := _create_property_header(inspector, selected_point, 2, property_name)
		var recreated_header: PanelContainer = recreated.header
		_expect(int(inspector.get("_selected_point_index")) == 2, "%s reparse changed the logical point" % property_name)
		_expect(StringName(inspector.get("_selected_point_property_name")) == property_name, "%s reparse lost the property name" % property_name)
		_expect(inspector.get("_selected_point_property_header") as PanelContainer == recreated_header, "%s reparse did not attach the recreated header" % property_name)
		_expect(editor.selected_index == 2, "%s reparse lost graph selection synchronization" % property_name)
		first.grid.free()
		recreated.grid.free()
	EDITOR_DRIVER.clear_point_selection(inspector)
	editor.free()


func _test_topology_and_resource_switch_selection() -> void:
	var curve := _curve()
	var context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = context.editor
	var inspector: Object = context.inspector
	var points: Array[EasingCurvePoint] = curve.points.duplicate()
	editor.selected_index = 2
	EDITOR_DRIVER.select_point(inspector, points[2])
	EDITOR_DRIVER.move_point(inspector, 2, 1)
	_expect(curve.points[1] == points[2] and editor.selected_index == 1, "Manual list reorder did not retain the logical point selection")

	EDITOR_DRIVER.change_point_property(inspector, 1, &"position", Vector2(1.0, points[2].position.y), true, points[2])
	_expect(editor._get_display_points() == [points[0], points[1], points[2]], "Endpoint takeover preview did not retain the selected point")
	EDITOR_DRIVER.commit_point_edit(inspector)
	_expect(curve.points.back() == points[2] and editor.selected_index == curve.points.size() - 1, "Endpoint takeover commit did not retain selection")

	var other := _curve()
	editor.set_curve(other)
	_expect(editor.selected_index == -1, "Switching resources leaked graph selection into the other curve")
	editor.set_curve(curve)
	_expect(editor.selected_index == curve.points.size() - 1, "Returning to a resource did not restore its graph selection")
	editor.free()


func _test_resource_view_state_persistence() -> void:
	var curve_a := _curve()
	var curve_b := _curve()
	var context := EDITOR_HOST.create_inspector_context(curve_a)
	var inspector: Object = context.inspector
	context.editor.free()

	var step_a := int(EasingCurve.DEFAULT_SLIDER_VALUE) + 3
	var pan_a := Vector2(31.0, -19.0)
	var section_a := EDITOR_DRIVER.create_curve_editor(inspector, curve_a)
	get_root().add_child(section_a)
	var editor_a := EDITOR_DRIVER.curve_editor(inspector)
	editor_a.set_slider_value(step_a)
	editor_a.pan_offset = pan_a
	editor_a.pan_changed.emit(pan_a)
	var zoom_a := Vector2(editor_a.step_to_zoom(step_a), editor_a.step_to_zoom(step_a))
	_expect(curve_a._last_slider_value == step_a, "Curve A did not store its zoom slider step")
	_expect(curve_a._last_zoom.is_equal_approx(zoom_a), "Curve A did not store its zoom vector")
	_expect(curve_a._last_pan == pan_a, "Curve A did not store its pan offset")
	section_a.free()

	var refreshed_a := EDITOR_DRIVER.create_curve_editor(inspector, curve_a)
	get_root().add_child(refreshed_a)
	editor_a = EDITOR_DRIVER.curve_editor(inspector)
	_expect(editor_a._zoom_step == step_a, "Refreshing Curve A did not restore its zoom step")
	_expect(editor_a._slider.slider.value == step_a, "Refreshing Curve A did not restore its slider value")
	_expect(Vector2(editor_a._zoom_x, editor_a._zoom_y).is_equal_approx(zoom_a), "Refreshing Curve A did not restore its zoom vector")
	_expect(editor_a.pan_offset == pan_a, "Refreshing Curve A did not restore its pan offset")
	refreshed_a.free()

	var section_b := EDITOR_DRIVER.create_curve_editor(inspector, curve_b)
	get_root().add_child(section_b)
	var editor_b := EDITOR_DRIVER.curve_editor(inspector)
	var default_step := int(EasingCurve.DEFAULT_SLIDER_VALUE)
	_expect(editor_b._zoom_step == default_step, "Curve B inherited Curve A's zoom step")
	_expect(editor_b.pan_offset == Vector2.ZERO, "Curve B inherited Curve A's pan offset")

	var step_b := default_step - 4
	var pan_b := Vector2(-22.0, 14.0)
	editor_b.set_slider_value(step_b)
	editor_b.pan_offset = pan_b
	editor_b.pan_changed.emit(pan_b)
	var zoom_b := Vector2(editor_b.step_to_zoom(step_b), editor_b.step_to_zoom(step_b))
	_expect(curve_b._last_slider_value == step_b, "Curve B did not store its independent zoom slider step")
	_expect(curve_b._last_zoom.is_equal_approx(zoom_b), "Curve B did not store its independent zoom vector")
	_expect(curve_b._last_pan == pan_b, "Curve B did not store its independent pan offset")
	section_b.free()

	var returned_a := EDITOR_DRIVER.create_curve_editor(inspector, curve_a)
	get_root().add_child(returned_a)
	editor_a = EDITOR_DRIVER.curve_editor(inspector)
	_expect(editor_a._zoom_step == step_a, "Returning to Curve A restored Curve B's zoom step")
	_expect(editor_a._slider.slider.value == step_a, "Returning to Curve A restored the wrong slider value")
	_expect(Vector2(editor_a._zoom_x, editor_a._zoom_y).is_equal_approx(zoom_a), "Returning to Curve A restored the wrong zoom vector")
	_expect(editor_a.pan_offset == pan_a, "Returning to Curve A restored the wrong pan offset")
	_expect(curve_b._last_slider_value == step_b and curve_b._last_zoom.is_equal_approx(zoom_b) and curve_b._last_pan == pan_b, "Returning to Curve A mutated Curve B's stored view state")
	returned_a.free()

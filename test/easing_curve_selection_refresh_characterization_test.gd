extends SceneTree

const EDITOR_HOST = preload("res://test/editor_host_test_harness.gd")
const EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")

var _failures := 0
var _checks := 0


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
	if _failures == 0:
		print("PASS: %d selection and refresh characterization checks" % _checks)
		quit()
	else:
		push_error("FAIL: %d of %d selection and refresh characterization checks failed" % [_failures, _checks])
		quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


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
	var selection_before: Dictionary = inspector.call("_capture_point_selection_state")
	var points: Array[EasingCurvePoint] = curve.points.duplicate()
	points.append(point)
	points.sort_custom(func(a: EasingCurvePoint, b: EasingCurvePoint) -> bool: return a.position.x < b.position.x)
	var added_index := points.find(point)
	curve.set_point_snapshot(curve.make_point_snapshot(points))
	inspector.call("_select_reordered_point", curve.points[added_index])
	var selection_after: Dictionary = inspector.call("_capture_point_selection_state")
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
	inspector.call("_clear_point_property_selection")
	editor.selected_index = -1

	var point_a := EasingCurvePoint.new(Vector2(0.33, 0.25))
	_commit_add(history, curve, inspector, point_a)
	_expect(editor.selected_index == 1, "First add did not select point A")
	history.undo()
	_expect(editor.selected_index == -1 and inspector.get("_selected_point_index") == -1, "Undo first add did not restore no selection")
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
		inspector.call("_select_point_property", first_header, 2, property_name)
		editor.selected_index = 2
		inspector.call("_apply_point_property_change", 2, property_name, selected_point.get(property_name))
		inspector.call("_parse_begin", curve)
		var recreated := _create_property_header(inspector, selected_point, 2, property_name)
		var recreated_header: PanelContainer = recreated.header
		_expect(inspector.get("_selected_point_index") == 2, "%s reparse changed the logical point" % property_name)
		_expect(inspector.get("_selected_point_property_name") == property_name, "%s reparse lost the property name" % property_name)
		_expect(inspector.get("_selected_point_property_header") == recreated_header, "%s reparse did not attach the recreated header" % property_name)
		_expect(editor.selected_index == 2, "%s reparse lost graph selection synchronization" % property_name)
		first.grid.free()
		recreated.grid.free()
	inspector.call("_clear_point_property_selection")
	editor.free()


func _test_topology_and_resource_switch_selection() -> void:
	var curve := _curve()
	var context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = context.editor
	var inspector: Object = context.inspector
	var points: Array[EasingCurvePoint] = curve.points.duplicate()
	editor.selected_index = 2
	inspector.call("_select_reordered_point", points[2])
	inspector.call("_move_point", 2, 1)
	_expect(curve.points[1] == points[2] and editor.selected_index == 1, "Manual list reorder did not retain the logical point selection")

	inspector.call("_apply_point_property_change", 1, &"position", Vector2(1.0, points[2].position.y), true, points[2])
	_expect(editor._get_display_points() == [points[0], points[1], points[2]], "Endpoint takeover preview did not retain the selected point")
	inspector.call("_commit_point_edit")
	_expect(curve.points.back() == points[2] and editor.selected_index == curve.points.size() - 1, "Endpoint takeover commit did not retain selection")

	var other := _curve()
	editor.set_curve(other)
	_expect(editor.selected_index == -1, "Switching resources leaked graph selection into the other curve")
	editor.set_curve(curve)
	_expect(editor.selected_index == curve.points.size() - 1, "Returning to a resource did not restore its graph selection")
	editor.free()

extends "res://test/scripts/test_case.gd"

const EDITOR_HOST = preload("res://test/scripts/editor_host_test_harness.gd")
const EDITOR_DRIVER = preload("res://test/scripts/easing_curve_editor_test_driver.gd")
const EDITOR_UNDO = preload("res://addons/easing_curve/scripts/editor/easing_curve_editor_undo.gd")

func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("easing_curve_points_list_add_editor_test.gd"):
		quit(1)
		return
	_test_points_list_add_preserves_endpoints()
	_test_points_list_remove_button_undo_redo()

	_finish("Points-list Add")


func _test_points_list_add_preserves_endpoints() -> void:
	_test_missing_endpoint_defaults()
	_test_interior_point_adds()
	_test_graph_point_adds()


func _test_points_list_remove_button_undo_redo() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [
		EasingCurvePoint.new(Vector2.ZERO),
		EasingCurvePoint.new(Vector2(0.5, 0.75)),
		EasingCurvePoint.new(Vector2.ONE),
	]
	var editor_context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = editor_context.editor
	var inspector: EditorInspectorPlugin = editor_context.inspector
	var before := EDITOR_UNDO.capture_state(curve)

	var remove_button := Button.new()
	remove_button.pressed.connect(
		inspector._on_remove_btn_pressed.bind(curve.points[1])
	)
	remove_button.pressed.emit()
	var after := EDITOR_UNDO.capture_state(curve)
	_expect(curve.points.size() == 2, "Remove Point button did not remove its point")

	var history := UndoRedo.new()
	_expect(
		EDITOR_UNDO.commit_applied_action(
			history,
			curve,
			"Remove Easing Curve Point",
			EasingCurveEditorUndo.ActionContext.new(before, after),
		),
		"Remove Point button result did not create an Undo action",
	)
	history.undo()
	_expect(curve.points.size() == 3, "Remove Point button Undo did not restore the point")
	history.redo()
	_expect(curve.points.size() == 2, "Remove Point button Redo did not remove the point")

	remove_button.free()
	history.clear_history(false)
	history.free()
	editor.free()


func _test_missing_endpoint_defaults() -> void:
	var test_cases: Array[Dictionary] = [
		{
			"name": "empty curve",
			"input": [],
			"expected": [Vector2(0.0, 0.0)],
			"added_index": 0,
		},
		{
			"name": "left endpoint only",
			"input": [Vector2(0.0, 0.2)],
			"expected": [Vector2(0.0, 0.2), Vector2(1.0, 1.0)],
			"added_index": 1,
		},
		{
			"name": "left endpoint with interiors",
			"input": [Vector2(0.0, 0.2), Vector2(0.4, 0.7), Vector2(0.8, 0.3)],
			"expected": [Vector2(0.0, 0.2), Vector2(0.4, 0.7), Vector2(0.8, 0.3), Vector2(1.0, 1.0)],
			"added_index": 3,
		},
		{
			"name": "right endpoint only",
			"input": [Vector2(1.0, 0.25)],
			"expected": [Vector2(0.0, 0.0), Vector2(1.0, 0.25)],
			"added_index": 0,
		},
	]

	for test_case in test_cases:
		var curve := EasingCurve.new()
		curve.trans_type = EasingCurve.TRANS.CUSTOM
		var input_points: Array[EasingCurvePoint] = []
		for position: Vector2 in test_case["input"]:
			input_points.append(EasingCurvePoint.new(position))
		curve.points = input_points
		var editor_context := EDITOR_HOST.create_inspector_context(curve)
		var editor: EasingCurveEditor = editor_context.editor
		var inspector: Object = editor_context.inspector
		var notifications := {"changed": 0, "points": 0, "property_list": 0}
		curve.changed.connect(func() -> void: notifications.changed += 1)
		curve.points_changed.connect(
			func(_points: Array[EasingCurvePoint]) -> void: notifications.points += 1,
		)
		curve.property_list_changed.connect(
			func() -> void: notifications.property_list += 1,
		)

		EDITOR_DRIVER.add_point_from_toolbar(inspector)

		var expected_positions: Array = test_case["expected"]
		_expect(curve.points.size() == expected_positions.size(), "%s produced the wrong point count" % test_case["name"])
		for i in range(expected_positions.size()):
			_expect(curve.points[i].position == expected_positions[i], "%s produced the wrong point at index %d" % [test_case["name"], i])
		var added_index := int(test_case["added_index"])
		_expect_selected_point(inspector, editor, curve, added_index, test_case["name"])
		EDITOR_DRIVER.rebuild_for_curve(inspector, curve)
		_expect_selected_point(inspector, editor, curve, added_index, "%s refresh" % test_case["name"])
		_expect(_is_ordered_by_x(curve.points), "%s did not keep point order" % test_case["name"])
		_expect(notifications.changed == 1 and notifications.points == 1 and notifications.property_list == 1, "%s did not refresh the inspector and graph" % test_case["name"])
		editor.free()


func _test_interior_point_adds() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [
		EasingCurvePoint.new(Vector2.ZERO),
		EasingCurvePoint.new(Vector2.ONE),
	]
	var editor_context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = editor_context.editor
	var inspector: Object = editor_context.inspector
	var notifications := {"changed": 0, "points": 0, "property_list": 0}
	curve.changed.connect(func() -> void: notifications.changed += 1)
	curve.points_changed.connect(
		func(_points: Array[EasingCurvePoint]) -> void: notifications.points += 1,
	)
	curve.property_list_changed.connect(
		func() -> void: notifications.property_list += 1,
	)
	var before := EDITOR_UNDO.capture_state(curve)
	var first_y := curve.sample(0.5)

	EDITOR_DRIVER.add_point_from_toolbar(inspector)

	_expect(curve.points.size() == 3, "First interior Add did not increase the point count")
	_expect(curve.points[0].position == Vector2.ZERO and curve.points[2].position == Vector2.ONE, "First interior Add changed an endpoint")
	_expect(curve.points[1].position.x == 0.5 and is_equal_approx(curve.points[1].position.y, first_y), "First interior Add did not sample the midpoint")
	_expect(curve.points[1].handle_mode == EasingCurvePoint.HandleMode.LINEAR, "First interior Add did not use Linear handle mode")
	_expect_selected_point(inspector, editor, curve, 1, "First interior Add")
	EDITOR_DRIVER.rebuild_for_curve(inspector, curve)
	_expect_selected_point(inspector, editor, curve, 1, "First interior Add refresh")

	var second_y := curve.sample(0.25)
	EDITOR_DRIVER.add_point_from_toolbar(inspector)

	_expect(curve.points.size() == 4, "Second interior Add did not increase the point count")
	_expect(curve.points[1].position.x == 0.25 and is_equal_approx(curve.points[1].position.y, second_y), "Second interior Add did not choose the leftmost largest gap")
	_expect(curve.points[1].handle_mode == EasingCurvePoint.HandleMode.LINEAR, "Second interior Add did not use Linear handle mode")
	_expect_selected_point(inspector, editor, curve, 1, "Second interior Add")

	var third_y := curve.sample(0.75)
	EDITOR_DRIVER.add_point_from_toolbar(inspector)

	var after := EDITOR_UNDO.capture_state(curve)
	_expect(curve.points.size() == 5, "Repeated interior Add did not increase the point count")
	_expect(curve.points[3].position.x == 0.75 and is_equal_approx(curve.points[3].position.y, third_y), "Third interior Add did not choose the largest remaining gap")
	_expect(curve.points[1].handle_mode == EasingCurvePoint.HandleMode.LINEAR and curve.points[2].handle_mode == EasingCurvePoint.HandleMode.LINEAR and curve.points[3].handle_mode == EasingCurvePoint.HandleMode.LINEAR, "Repeated interior Adds did not keep Linear handle mode")
	_expect(curve.points[0].position == Vector2.ZERO and curve.points[4].position == Vector2.ONE, "Repeated interior Adds changed an endpoint")
	_expect_selected_point(inspector, editor, curve, 3, "Third interior Add")
	_expect(_is_ordered_by_x(curve.points), "Repeated interior Adds did not keep point order")
	_expect(notifications.changed == 3 and notifications.points == 3 and notifications.property_list == 3, "Repeated interior Adds did not refresh the inspector and graph")

	var history := UndoRedo.new()
	_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Add Easing Curve Point", EasingCurveEditorUndo.ActionContext.new(before, after)), "Interior Add did not produce an Undo/Redo state change")
	history.undo()
	_expect(curve.get_editor_state_snapshot() == before, "Interior Add Undo did not restore the complete point state")
	history.redo()
	_expect(curve.get_editor_state_snapshot() == after, "Interior Add Redo did not restore the complete point state")
	history.clear_history(false)
	history.free()
	editor.free()


func _test_graph_point_adds() -> void:
	var graph_curve := EasingCurve.new()
	graph_curve.trans_type = EasingCurve.TRANS.CUSTOM
	graph_curve.points = [
		EasingCurvePoint.new(Vector2.ZERO),
		EasingCurvePoint.new(Vector2.ONE),
	]
	var graph_context := EDITOR_HOST.create_inspector_context(graph_curve)
	var graph_editor: EasingCurveEditor = graph_context.editor
	var graph_inspector: Object = graph_context.inspector
	var graph_point := EasingCurvePoint.new(Vector2(0.25, 0.75))
	graph_point.left_control_point = Vector2(0.15, 0.75)
	graph_point.right_control_point = Vector2(0.35, 0.75)
	graph_editor.selected_index = 0

	EDITOR_DRIVER.add_point_from_graph(graph_inspector, graph_point)

	_expect(graph_curve.points.size() == 3, "Graph Add did not add exactly one point")
	_expect(graph_curve.points[0].position == Vector2.ZERO and graph_curve.points[2].position == Vector2.ONE, "Graph Add changed an endpoint")
	_expect(graph_curve.points[1].position == graph_point.position, "Graph Add did not preserve the requested point position")
	_expect(_is_ordered_by_x(graph_curve.points), "Graph Add did not keep point order")
	_expect(graph_editor.selected_index == 0, "Graph Add request changed graph selection behavior")
	graph_editor.free()

	var takeover_curve := EasingCurve.new()
	takeover_curve.trans_type = EasingCurve.TRANS.CUSTOM
	takeover_curve.points = [
		EasingCurvePoint.new(Vector2.ZERO),
		EasingCurvePoint.new(Vector2(1.0, 0.25)),
	]
	var takeover_context := EDITOR_HOST.create_inspector_context(takeover_curve)
	var takeover_editor: EasingCurveEditor = takeover_context.editor
	var takeover_inspector: Object = takeover_context.inspector

	takeover_inspector.call(
		"_on_curve_editor_point_add_requested",
		EasingCurvePoint.new(Vector2(1.0, 0.8)),
	)

	_expect(takeover_curve.points.size() == 2, "Graph endpoint Add did not use endpoint takeover")
	_expect(takeover_curve.points[0].position == Vector2.ZERO and takeover_curve.points[1].position == Vector2(1.0, 0.8), "Graph endpoint Add did not replace the right endpoint")
	takeover_editor.free()


func _is_ordered_by_x(points: Array[EasingCurvePoint]) -> bool:
	for i in range(1, points.size()):
		if points[i - 1].position.x > points[i].position.x:
			return false
	return true


func _expect_selected_point(
	inspector: Object,
	editor: EasingCurveEditor,
	curve: EasingCurve,
	point_index: int,
	label: String,
) -> void:
	_expect(editor.selected_index == point_index, "%s did not select the added point in the curve editor" % label)
	_expect(EDITOR_DRIVER.selected_point_index(inspector) == point_index, "%s did not store the added point index" % label)
	_expect(EDITOR_DRIVER.selected_point_resource_id(inspector) == curve.points[point_index].get_instance_id(), "%s did not store the added point resource" % label)

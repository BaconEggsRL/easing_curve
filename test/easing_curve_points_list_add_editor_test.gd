extends SceneTree

const EDITOR_HOST = preload("res://test/editor_host_test_harness.gd")
const EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("easing_curve_points_list_add_editor_test.gd"):
		quit(1)
		return
	_test_points_list_add_preserves_endpoints()

	if _failures == 0:
		print("PASS: %d Points-list Add checks" % _checks)
	else:
		push_error("FAIL: %d of %d Points-list Add checks failed" % [_failures, _checks])
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _test_points_list_add_preserves_endpoints() -> void:
	var test_cases: Array[Dictionary] = [
		{
			"name": "empty curve",
			"input": [],
			"expected": [Vector2(0.0, 0.0)],
		},
		{
			"name": "left endpoint only",
			"input": [Vector2(0.0, 0.2)],
			"expected": [Vector2(0.0, 0.2), Vector2(1.0, 1.0)],
		},
		{
			"name": "left endpoint with interiors",
			"input": [Vector2(0.0, 0.2), Vector2(0.4, 0.7), Vector2(0.8, 0.3)],
			"expected": [Vector2(0.0, 0.2), Vector2(0.4, 0.7), Vector2(0.8, 0.3), Vector2(1.0, 1.0)],
		},
		{
			"name": "both endpoints",
			"input": [Vector2(0.0, 0.2), Vector2(0.5, 0.6), Vector2(1.0, 0.25)],
			"expected": [Vector2(0.0, 0.2), Vector2(0.5, 0.6), Vector2(1.0, 1.0)],
			"check_undo_redo": true,
		},
		{
			"name": "right endpoint only",
			"input": [Vector2(1.0, 0.25)],
			"expected": [Vector2(0.0, 0.0), Vector2(1.0, 0.25)],
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
		var before := EDITOR_UNDO.capture_state(curve)

		inspector.call("_on_add_point_btn_pressed")

		var after := EDITOR_UNDO.capture_state(curve)
		var expected_positions: Array = test_case["expected"]
		_expect(curve.points.size() == expected_positions.size(), "%s produced the wrong point count" % test_case["name"])
		for i in range(expected_positions.size()):
			_expect(curve.points[i].position == expected_positions[i], "%s produced the wrong point at index %d" % [test_case["name"], i])
		_expect(_is_ordered_by_x(curve.points), "%s did not keep point order" % test_case["name"])
		_expect(notifications.changed == 1 and notifications.points == 1 and notifications.property_list == 1, "%s did not refresh the inspector and graph" % test_case["name"])

		if bool(test_case.get("check_undo_redo", false)):
			var history := UndoRedo.new()
			_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Add Easing Curve Point", before, after), "Points-list Add did not produce an Undo/Redo state change")
			history.undo()
			_expect(curve.get_editor_state_snapshot() == before, "Points-list Add Undo did not restore the complete point state")
			history.redo()
			_expect(curve.get_editor_state_snapshot() == after, "Points-list Add Redo did not restore the complete point state")
			history.clear_history(false)
			history.free()
		editor.free()

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

	graph_inspector.call("_on_curve_editor_point_add_requested", graph_point)

	_expect(graph_curve.points.size() == 3, "Graph Add did not add exactly one point")
	_expect(graph_curve.points[0].position == Vector2.ZERO and graph_curve.points[2].position == Vector2.ONE, "Graph Add changed an endpoint")
	_expect(graph_curve.points[1].position == graph_point.position, "Graph Add did not preserve the requested point position")
	_expect(_is_ordered_by_x(graph_curve.points), "Graph Add did not keep point order")
	graph_editor.free()


func _is_ordered_by_x(points: Array[EasingCurvePoint]) -> bool:
	for i in range(1, points.size()):
		if points[i - 1].position.x > points[i].position.x:
			return false
	return true

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
	_test_missing_endpoint_defaults()
	_test_interior_point_adds()
	_test_graph_point_adds()


func _test_missing_endpoint_defaults() -> void:
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

		inspector.call("_on_add_point_btn_pressed")

		var expected_positions: Array = test_case["expected"]
		_expect(curve.points.size() == expected_positions.size(), "%s produced the wrong point count" % test_case["name"])
		for i in range(expected_positions.size()):
			_expect(curve.points[i].position == expected_positions[i], "%s produced the wrong point at index %d" % [test_case["name"], i])
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

	inspector.call("_on_add_point_btn_pressed")

	_expect(curve.points.size() == 3, "First interior Add did not increase the point count")
	_expect(curve.points[0].position == Vector2.ZERO and curve.points[2].position == Vector2.ONE, "First interior Add changed an endpoint")
	_expect(curve.points[1].position.x == 0.5 and is_equal_approx(curve.points[1].position.y, first_y), "First interior Add did not sample the midpoint")
	_expect(curve.points[1].handle_mode == EasingCurvePoint.HandleMode.LINEAR, "First interior Add did not use Linear handle mode")

	var second_y := curve.sample(0.25)
	inspector.call("_on_add_point_btn_pressed")

	_expect(curve.points.size() == 4, "Second interior Add did not increase the point count")
	_expect(curve.points[1].position.x == 0.25 and is_equal_approx(curve.points[1].position.y, second_y), "Second interior Add did not choose the leftmost largest gap")
	_expect(curve.points[1].handle_mode == EasingCurvePoint.HandleMode.LINEAR, "Second interior Add did not use Linear handle mode")

	var third_y := curve.sample(0.75)
	inspector.call("_on_add_point_btn_pressed")

	var after := EDITOR_UNDO.capture_state(curve)
	_expect(curve.points.size() == 5, "Repeated interior Add did not increase the point count")
	_expect(curve.points[3].position.x == 0.75 and is_equal_approx(curve.points[3].position.y, third_y), "Third interior Add did not choose the largest remaining gap")
	_expect(curve.points[1].handle_mode == EasingCurvePoint.HandleMode.LINEAR and curve.points[2].handle_mode == EasingCurvePoint.HandleMode.LINEAR and curve.points[3].handle_mode == EasingCurvePoint.HandleMode.LINEAR, "Repeated interior Adds did not keep Linear handle mode")
	_expect(curve.points[0].position == Vector2.ZERO and curve.points[4].position == Vector2.ONE, "Repeated interior Adds changed an endpoint")
	_expect(_is_ordered_by_x(curve.points), "Repeated interior Adds did not keep point order")
	_expect(notifications.changed == 3 and notifications.points == 3 and notifications.property_list == 3, "Repeated interior Adds did not refresh the inspector and graph")

	var history := UndoRedo.new()
	_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Add Easing Curve Point", before, after), "Interior Add did not produce an Undo/Redo state change")
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

	graph_inspector.call("_on_curve_editor_point_add_requested", graph_point)

	_expect(graph_curve.points.size() == 3, "Graph Add did not add exactly one point")
	_expect(graph_curve.points[0].position == Vector2.ZERO and graph_curve.points[2].position == Vector2.ONE, "Graph Add changed an endpoint")
	_expect(graph_curve.points[1].position == graph_point.position, "Graph Add did not preserve the requested point position")
	_expect(_is_ordered_by_x(graph_curve.points), "Graph Add did not keep point order")
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

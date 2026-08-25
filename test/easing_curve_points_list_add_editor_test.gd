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

	inspector.call("_on_add_point_btn_pressed")

	var after := EDITOR_UNDO.capture_state(curve)
	_expect(curve.points.size() == 3, "Points-list Add did not add exactly one point")
	_expect(curve.points[0].position == Vector2.ZERO, "Points-list Add replaced the left endpoint")
	_expect(curve.points[2].position == Vector2.ONE, "Points-list Add replaced the right endpoint")
	_expect(curve.points[1].position == Vector2(0.5, 0.5), "Points-list Add did not use the midpoint default")
	_expect(notifications.changed == 1 and notifications.points == 1 and notifications.property_list == 1, "Points-list Add did not refresh the inspector and graph")

	var history := UndoRedo.new()
	_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Add Easing Curve Point", before, after), "Points-list Add did not produce an Undo/Redo state change")
	history.undo()
	_expect(curve.get_editor_state_snapshot() == before, "Points-list Add Undo did not restore the endpoints")
	history.redo()
	_expect(curve.get_editor_state_snapshot() == after, "Points-list Add Redo did not restore the midpoint")
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
	graph_editor.free()

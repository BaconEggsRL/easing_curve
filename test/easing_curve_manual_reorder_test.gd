extends SceneTree

const EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_test_basic_timeline_slot_swap()
	_test_locked_points_and_handles_move_as_a_unit()
	_test_endpoint_slots_are_swapped_without_takeover()
	_test_multiple_swaps_and_undo_redo()

	if _failures == 0:
		print("PASS: %d EasingCurve manual reorder checks" % _checks)
	else:
		push_error("FAIL: %d of %d EasingCurve manual reorder checks failed" % [_failures, _checks])
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _expect_vector(actual: Vector2, expected: Vector2, message: String) -> void:
	_expect(actual.is_equal_approx(expected), "%s: expected %s, got %s" % [message, expected, actual])


func _make_curve(points: Array[EasingCurvePoint]) -> EasingCurve:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = points
	return curve


func _make_point(position: Vector2, left: Vector2, right: Vector2) -> EasingCurvePoint:
	var point := EasingCurvePoint.new(position)
	point.left_control_point = left
	point.right_control_point = right
	return point


func _test_basic_timeline_slot_swap() -> void:
	var a := _make_point(Vector2(0.2, 0.3), Vector2(0.1, 0.1), Vector2(0.3, 0.4))
	var b := _make_point(Vector2(0.6, 0.8), Vector2(0.5, 0.7), Vector2(0.7, 0.9))
	var curve := _make_curve([a, b])

	curve.swap_points(0, 1)
	_expect_vector(a.position, Vector2(0.6, 0.3), "Manual reorder changed point A's Y")
	_expect_vector(b.position, Vector2(0.2, 0.8), "Manual reorder changed point B's Y")
	_expect_vector(a.left_control_point, Vector2(0.5, 0.1), "Manual reorder did not translate A's left handle")
	_expect_vector(a.right_control_point, Vector2(0.7, 0.4), "Manual reorder did not translate A's right handle")
	_expect_vector(b.left_control_point, Vector2(0.1, 0.7), "Manual reorder did not translate B's left handle")
	_expect_vector(b.right_control_point, Vector2(0.3, 0.9), "Manual reorder did not translate B's right handle")
	_expect(curve.points == [b, a], "Manual reorder did not make point order agree with X slots")


func _test_locked_points_and_handles_move_as_a_unit() -> void:
	var a := _make_point(Vector2(0.2, 0.3), Vector2(0.1, 0.2), Vector2(0.3, 0.4))
	var b := _make_point(Vector2(0.6, 0.8), Vector2(0.5, 0.7), Vector2(0.7, 0.9))
	a.set_locked("position", true)
	a.set_locked("left_control_point", true)
	a.set_locked("right_control_point", true)
	var curve := _make_curve([a, b])

	curve.swap_points(a, b)
	_expect_vector(a.position, Vector2(0.6, 0.3), "Position lock blocked manual timeline reorder")
	_expect_vector(a.left_control_point, Vector2(0.5, 0.2), "Left-control lock blocked manual timeline reorder")
	_expect_vector(a.right_control_point, Vector2(0.7, 0.4), "Right-control lock blocked manual timeline reorder")
	_expect(
		a.locked.position and a.locked.left_control_point and a.locked.right_control_point,
		"Manual reorder changed point lock state",
	)


func _test_endpoint_slots_are_swapped_without_takeover() -> void:
	var left := _make_point(Vector2(0.0, 0.2), Vector2(-0.1, 0.2), Vector2(0.1, 0.2))
	var middle := _make_point(Vector2(0.5, 0.5), Vector2(0.4, 0.5), Vector2(0.6, 0.5))
	var right := _make_point(Vector2(1.0, 0.8), Vector2(0.9, 0.8), Vector2(1.1, 0.8))
	var curve := _make_curve([left, middle, right])

	curve.swap_points(0, 1)
	_expect(curve.points.size() == 3, "Manual endpoint slot swap removed a point")
	_expect(curve.points == [middle, left, right], "Manual endpoint slot swap did not retain all timeline slots")
	_expect_vector(middle.position, Vector2(0.0, 0.5), "Manual endpoint slot swap changed middle Y")
	_expect_vector(left.position, Vector2(0.5, 0.2), "Manual endpoint slot swap changed left Y")


func _test_multiple_swaps_and_undo_redo() -> void:
	var a := _make_point(Vector2(0.1, 0.1), Vector2(0.0, 0.1), Vector2(0.2, 0.1))
	var b := _make_point(Vector2(0.3, 0.3), Vector2(0.2, 0.3), Vector2(0.4, 0.3))
	var c := _make_point(Vector2(0.5, 0.5), Vector2(0.4, 0.5), Vector2(0.6, 0.5))
	var d := _make_point(Vector2(0.7, 0.7), Vector2(0.6, 0.7), Vector2(0.8, 0.7))
	var curve := _make_curve([a, b, c, d])
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)

	curve.swap_points(1, 2)
	curve.swap_points(2, 3)
	var after := EDITOR_UNDO.capture_state(curve)
	_expect(
		EDITOR_UNDO.commit_applied_action(history, curve, "Reorder Easing Curve Points", before, after),
		"Manual reorder did not create one Undo/Redo action",
	)
	_expect(curve.points == [a, c, d, b], "Multiple manual reorders did not move the logical point through X slots")
	_expect_vector(b.position, Vector2(0.7, 0.3), "Multiple manual reorders changed the moved point's Y")
	_expect_vector(b.left_control_point, Vector2(0.6, 0.3), "Multiple manual reorders changed the moved point's left offset")
	_expect_vector(b.right_control_point, Vector2(0.8, 0.3), "Multiple manual reorders changed the moved point's right offset")

	history.undo()
	_expect(curve.get_editor_state_snapshot() == before, "Manual reorder Undo did not restore geometry and order")
	_expect(not history.has_undo(), "Manual reorder created more than one Undo action")
	history.redo()
	_expect(curve.get_editor_state_snapshot() == after, "Manual reorder Redo did not restore geometry and order")
	history.clear_history(false)
	history.free()

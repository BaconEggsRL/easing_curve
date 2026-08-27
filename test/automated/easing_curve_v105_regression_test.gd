extends SceneTree

const ROUND_TRIP_PATH := "res://test/_v105_state_round_trip.tres"

var _failures := 0
var _checks := 0


func _init() -> void:
	_test_handle_modes_and_control_states()
	_test_point_ordering_and_endpoint_takeover()
	_test_bezier_evaluator_pathologies()
	_test_fallbacks_and_snapshot_round_trip()
	_cleanup()

	if _failures == 0:
		print("PASS: %d EasingCurve v1.0.5 regression checks" % _checks)
	else:
		push_error("FAIL: %d of %d EasingCurve v1.0.5 regression checks failed" % [_failures, _checks])
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _expect_finite_samples(curve: EasingCurve, label: String) -> void:
	for index in range(257):
		var x := float(index) / 256.0
		var sample := curve.sample(x)
		_expect(not is_nan(sample) and not is_inf(sample), "%s produced a non-finite sample at %f" % [label, x])
		_expect(is_equal_approx(sample, curve.sample(x)), "%s was non-deterministic at %f" % [label, x])


func _make_point(position: Vector2) -> EasingCurvePoint:
	var point := EasingCurvePoint.new(position)
	point.left_control_point = position + Vector2(-0.2, -0.1)
	point.right_control_point = position + Vector2(0.3, 0.2)
	return point


func _make_curve(points: Array[EasingCurvePoint]) -> EasingCurve:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = points
	return curve


func _test_handle_modes_and_control_states() -> void:
	var point := _make_point(Vector2(0.5, 0.5))
	point.handle_mode = EasingCurvePoint.HandleMode.FREE
	_expect(point.handle_mode == EasingCurvePoint.HandleMode.FREE, "Free mode was not applied")

	point.handle_mode = EasingCurvePoint.HandleMode.BALANCED
	var balanced_left := point.left_control_point - point.position
	var balanced_right := point.right_control_point - point.position
	_expect(
		is_equal_approx(balanced_left.normalized().dot(balanced_right.normalized()), -1.0),
		"Balanced mode did not align handles in opposite directions",
	)
	_expect(
		is_equal_approx(balanced_left.length(), Vector2(-0.2, -0.1).length())
		and is_equal_approx(balanced_right.length(), Vector2(0.3, 0.2).length()),
		"Balanced mode did not preserve individual handle lengths",
	)

	point.handle_mode = EasingCurvePoint.HandleMode.MIRRORED
	_expect(
		point.left_control_point.is_equal_approx(2.0 * point.position - point.right_control_point),
		"Mirrored mode did not make handles symmetric",
	)

	point.handle_mode = EasingCurvePoint.HandleMode.LINKED
	_expect(point.left_control_point == point.right_control_point, "Linked mode did not share handle position")

	point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	_expect(
		point.left_control_point == point.position and point.right_control_point == point.position,
		"Linear mode did not collapse handles",
	)
	point.handle_mode = EasingCurvePoint.HandleMode.FREE
	_expect(
		point.left_control_point == point.position + Vector2.LEFT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH
		and point.right_control_point == point.position + Vector2.RIGHT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH,
		"Linear-to-Free did not restore default handles",
	)

	point.left_force_linear = true
	_expect(point.left_control_point == point.position, "Force Linear did not collapse the selected handle")
	point.left_force_linear = false
	_expect(point.left_control_point == point.position + Vector2.LEFT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH, "Clearing Force Linear did not restore the default handle")
	point.set_locked("right_control_point", true)
	var locked_right := point.right_control_point
	point.position += Vector2(0.1, 0.0)
	_expect(point.right_control_point == locked_right, "Locked control moved with its point")
	_expect(point.left_control_point != point.position, "Unlocked control did not move with its point")


func _test_point_ordering_and_endpoint_takeover() -> void:
	var left := EasingCurvePoint.new(Vector2(0.0, 0.1))
	var middle := EasingCurvePoint.new(Vector2(0.5, 0.5))
	var right := EasingCurvePoint.new(Vector2(1.0, 0.9))
	var active := EasingCurvePoint.new(Vector2(0.25, 0.4))
	var ordered := EasingCurve.build_ordered_points_with_endpoint_takeover([left, middle, right, active], active)
	_expect(ordered == [left, active, middle, right], "Crossing several X positions did not produce graph order")

	var duplicate_a := EasingCurvePoint.new(Vector2(0.5, 0.2))
	var duplicate_b := EasingCurvePoint.new(Vector2(0.5, 0.7))
	var duplicate_curve := _make_curve([left, duplicate_a, duplicate_b, right])
	_expect(duplicate_curve.points.size() == 4, "Interior duplicate X points were deduplicated")
	_expect(duplicate_curve.points[1] == duplicate_a and duplicate_curve.points[2] == duplicate_b, "Interior duplicate X order was not stable")
	var duplicate_sample := duplicate_curve.sample(0.5)
	_expect(is_equal_approx(duplicate_sample, duplicate_curve.sample(0.5)), "Interior duplicate X sampling was non-deterministic")

	var left_curve := _make_curve([middle, right, left])
	var left_winner := EasingCurvePoint.new(Vector2(0.0, 0.8))
	left_curve.add_point(left_winner)
	_expect(left_curve.points.size() == 3 and left not in left_curve.points, "Left endpoint takeover did not remove only the old endpoint")
	_expect(is_equal_approx(left_curve.sample(0.0), 0.8), "Left endpoint takeover did not control sample(0.0)")

	var right_curve := _make_curve([left, middle, right])
	var right_winner := EasingCurvePoint.new(Vector2(1.0, 0.2))
	right_curve.add_point(right_winner)
	_expect(right_curve.points.size() == 3 and right not in right_curve.points, "Right endpoint takeover did not remove only the old endpoint")
	_expect(is_equal_approx(right_curve.sample(1.0), 0.2), "Right endpoint takeover did not control sample(1.0)")


func _test_bezier_evaluator_pathologies() -> void:
	var first := EasingCurvePoint.new(Vector2(0.0, 0.0))
	var second := EasingCurvePoint.new(Vector2(0.5, 1.2))
	var third := EasingCurvePoint.new(Vector2(1.0, 1.0))
	first.right_control_point = Vector2(2.0, -2.0)
	second.left_control_point = Vector2(-1.0, 2.0)
	second.right_control_point = Vector2(1.8, -1.0)
	third.left_control_point = Vector2(-0.8, 2.0)
	var pathological := _make_curve([first, second, third])
	var stored_snapshot := pathological.get_point_snapshot()
	_expect_finite_samples(pathological, "Extreme/crossing controls")
	_expect(pathological.get_point_snapshot() == stored_snapshot, "Effective evaluation controls mutated stored Free handles")

	var narrow_a := EasingCurvePoint.new(Vector2(0.0, 0.0))
	var narrow_b := EasingCurvePoint.new(Vector2(0.0000005, 0.6))
	var narrow_c := EasingCurvePoint.new(Vector2(1.0, 1.0))
	var narrow := _make_curve([narrow_a, narrow_b, narrow_c])
	_expect_finite_samples(narrow, "Near-zero-width segment")
	_expect(is_equal_approx(narrow.sample(narrow_b.position.x), narrow_b.position.y), "Near-zero-width segment did not deterministically select its later point")


func _test_fallbacks_and_snapshot_round_trip() -> void:
	_expect(is_equal_approx(_make_curve([]).sample(0.5), 0.0), "Empty curve fallback changed")
	_expect(is_equal_approx(_make_curve([EasingCurvePoint.new(Vector2(0.4, 0.9))]).sample(0.4), 0.0), "Single-point fallback changed")
	var missing_endpoints := _make_curve([
		EasingCurvePoint.new(Vector2(0.2, 0.3)),
		EasingCurvePoint.new(Vector2(0.8, 0.7)),
	])
	_expect(is_equal_approx(missing_endpoints.sample(0.0), 0.0), "Missing left endpoint fallback changed")
	_expect(is_equal_approx(missing_endpoints.sample(1.0), 0.0), "Missing right endpoint fallback changed")

	var point := _make_point(Vector2(0.5, 0.5))
	point.handle_mode = EasingCurvePoint.HandleMode.LINKED
	point.left_force_linear = true
	point.set_locked("left_control_point", true)
	var source := _make_curve([EasingCurvePoint.new(Vector2.ZERO), point, EasingCurvePoint.new(Vector2.ONE)])
	var snapshot := source.get_point_snapshot()
	var restored := _make_curve([])
	restored.set_point_snapshot(snapshot)
	_expect(restored.get_point_snapshot() == snapshot, "Point snapshot did not preserve geometry and v1.0.5 control state")
	_expect(ResourceSaver.save(source, ROUND_TRIP_PATH) == OK, "Could not save v1.0.5 point state")
	var loaded := ResourceLoader.load(ROUND_TRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EasingCurve
	_expect(loaded != null and loaded.get_point_snapshot() == snapshot, "Save/load did not preserve v1.0.5 point state")


func _cleanup() -> void:
	if FileAccess.file_exists(ROUND_TRIP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUND_TRIP_PATH))

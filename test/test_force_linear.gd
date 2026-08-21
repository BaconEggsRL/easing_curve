extends Node2D


func _ready() -> void:
	_test_force_linear_snapshots()


func _test_force_linear_snapshots() -> void:
	var curve := EasingCurve.new()
	curve.set_trans(EasingCurve.TRANS.CUSTOM)

	var point := EasingCurvePoint.new(Vector2(0.5, 0.5))
	point.left_control_point = Vector2(0.3, 0.4)
	point.right_control_point = Vector2(0.7, 0.6)

	curve.points = [point]

	# ---------------------------------
	# Test 1: Free force-linear restore
	# ---------------------------------
	point.left_force_linear = true

	var snapshot := curve.get_point_snapshot()

	point.left_force_linear = false

	curve.set_point_snapshot(snapshot)

	print("TEST 1")
	print("left force: ", curve.points[0].left_force_linear)
	print("left: ", curve.points[0].left_control_point)
	print("position: ", curve.points[0].position)

	# ---------------------------------
	# Test 2: Dormant flag in Balanced
	# ---------------------------------
	point = curve.points[0]
	point.left_force_linear = false
	point.left_control_point = Vector2(0.3, 0.4)
	point.right_control_point = Vector2(0.7, 0.6)
	point.handle_mode = EasingCurvePoint.HandleMode.BALANCED
	point.set_force_linear_state(true, false, false)

	snapshot = curve.get_point_snapshot()

	curve.set_point_snapshot(snapshot)

	print("TEST 2")
	print("mode: ", curve.points[0].handle_mode)
	print("left force: ", curve.points[0].left_force_linear)
	print("left: ", curve.points[0].left_control_point)
	print("right: ", curve.points[0].right_control_point)


	# ---------------------------------
	# Test 3: Reverse swaps sides
	# ---------------------------------
	point = curve.points[0]
	point.handle_mode = EasingCurvePoint.HandleMode.FREE
	point.set_force_linear_state(true, false, false)

	var reverse_source := curve.get_point_snapshot()
	var reversed := curve._reverse_point_snapshot(reverse_source)

	print("TEST 3 - REVERSE")
	print("left force: ", reversed["left_force_linear"])
	print("right force: ", reversed["right_force_linear"])


	# ---------------------------------
	# Test 4: Backward compatibility
	# ---------------------------------
	var old_snapshot := curve.get_point_snapshot()

	old_snapshot.erase("left_force_linear")
	old_snapshot.erase("right_force_linear")

	curve.set_point_snapshot(old_snapshot)

	print("TEST 4 - OLD SNAPSHOT")
	print("left force: ", curve.points[0].left_force_linear)
	print("right force: ", curve.points[0].right_force_linear)

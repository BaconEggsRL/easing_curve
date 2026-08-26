extends SceneTree

const EDITOR_HOST = preload("res://test/editor_host_test_harness.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("easing_curve_point_state_characterization_test.gd"):
		quit(1)
		return
	_test_handle_mode_transition_matrix()
	_test_display_space_relationships()
	_test_lock_force_linear_precedence()
	_test_inspector_snapshot_state_precedence_and_reset()

	if _failures == 0:
		print("PASS: %d point-state characterization checks" % _checks)
		quit()
	else:
		push_error("FAIL: %d of %d point-state characterization checks failed" % [_failures, _checks])
		quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _point() -> EasingCurvePoint:
	var point := EasingCurvePoint.new(Vector2(0.5, 0.5))
	point.left_control_point = Vector2(0.2, 0.1)
	point.right_control_point = Vector2(0.6, 0.7)
	return point


func _is_opposite_in_handle_space(point: EasingCurvePoint, left: Vector2, right: Vector2) -> bool:
	var left_delta := (left - point.position) * point.handle_display_scale
	var right_delta := (right - point.position) * point.handle_display_scale
	return is_zero_approx(left_delta.cross(right_delta)) and left_delta.dot(right_delta) <= 0.0


func _test_handle_mode_transition_matrix() -> void:
	for source in EasingCurvePoint.HandleMode.values():
		for destination in EasingCurvePoint.HandleMode.values():
			var point := _point()
			point.handle_mode = source
			var before_left := point.left_control_point
			var before_right := point.right_control_point
			point.handle_mode = destination
			var label := "%s -> %s" % [
				EasingCurvePoint.HandleMode.keys()[source],
				EasingCurvePoint.HandleMode.keys()[destination],
			]
			_expect(
				point.left_control_point.is_finite() and point.right_control_point.is_finite(),
				"%s produced non-finite handle geometry" % label,
			)
			match destination:
				EasingCurvePoint.HandleMode.LINEAR:
					_expect(
						point.left_control_point == point.position and point.right_control_point == point.position,
						"%s did not collapse both handles" % label,
					)
				EasingCurvePoint.HandleMode.LINKED:
					_expect(
						point.left_control_point == point.right_control_point,
						"%s did not synchronize Linked handles" % label,
					)
				EasingCurvePoint.HandleMode.BALANCED:
					_expect(
						_is_opposite_in_handle_space(point, point.left_control_point, point.right_control_point),
						"%s did not align Balanced handles in opposite directions" % label,
					)
				EasingCurvePoint.HandleMode.MIRRORED:
					_expect(
						_is_opposite_in_handle_space(point, point.left_control_point, point.right_control_point),
						"%s did not mirror handle directions" % label,
					)
					_expect(
						is_equal_approx(
							point.left_control_point.distance_to(point.position),
							point.right_control_point.distance_to(point.position),
						),
						"%s did not equalize mirrored handle lengths" % label,
					)
				EasingCurvePoint.HandleMode.FREE:
					if source != EasingCurvePoint.HandleMode.LINEAR:
						_expect(
							point.left_control_point == before_left and point.right_control_point == before_right,
							"%s unexpectedly changed Free geometry" % label,
						)
			if source == EasingCurvePoint.HandleMode.LINEAR and destination != EasingCurvePoint.HandleMode.LINEAR:
				if destination == EasingCurvePoint.HandleMode.LINKED:
					_expect(
						point.left_control_point.is_equal_approx(point.position + Vector2.RIGHT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH),
						"%s did not restore the Linked default handle" % label,
					)
				else:
					_expect(
						point.left_control_point.is_equal_approx(point.position + Vector2.LEFT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH)
						and point.right_control_point.is_equal_approx(point.position + Vector2.RIGHT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH),
						"%s did not restore default handles after Linear" % label,
					)


func _test_display_space_relationships() -> void:
	var balanced := _point()
	balanced.handle_display_scale = Vector2(2.0, 5.0)
	balanced.handle_mode = EasingCurvePoint.HandleMode.BALANCED
	var right_display_length := ((balanced.right_control_point - balanced.position) * balanced.handle_display_scale).length()
	balanced.left_control_point = Vector2(0.1, 0.35)
	_expect(
		_is_opposite_in_handle_space(balanced, balanced.left_control_point, balanced.right_control_point),
		"Balanced drag lost its display-space opposite-direction relationship",
	)
	_expect(
		is_equal_approx(((balanced.right_control_point - balanced.position) * balanced.handle_display_scale).length(), right_display_length),
		"Balanced drag did not preserve the opposite display-space length",
	)

	var mirrored := _point()
	mirrored.handle_display_scale = Vector2(3.0, 0.5)
	mirrored.handle_mode = EasingCurvePoint.HandleMode.MIRRORED
	mirrored.left_control_point = Vector2(0.15, 0.3)
	_expect(
		((mirrored.right_control_point - mirrored.position) * mirrored.handle_display_scale).is_equal_approx(-((mirrored.left_control_point - mirrored.position) * mirrored.handle_display_scale)),
		"Mirrored drag did not use the non-uniform display scale relationship",
	)


func _test_lock_force_linear_precedence() -> void:
	for side in [EasingCurvePoint.ControlSide.LEFT, EasingCurvePoint.ControlSide.RIGHT]:
		var property_name := &"left_control_point" if side == EasingCurvePoint.ControlSide.LEFT else &"right_control_point"
		var force_property := &"left_force_linear" if side == EasingCurvePoint.ControlSide.LEFT else &"right_force_linear"
		var point := _point()
		point.set_locked(property_name, true)
		point.set(force_property, true)
		_expect(point.locked[property_name], "Direct Force Linear unexpectedly cleared the prior %s lock" % property_name)
		_expect(point.get(force_property), "Force Linear did not remain enabled for %s" % property_name)
		_expect(point.get(property_name) == point.position, "Force Linear did not collapse %s" % property_name)

		point.set_locked(property_name, true)
		_expect(point.locked[property_name], "Lock did not remain enabled after Force Linear for %s" % property_name)
		_expect(point.get(force_property), "Direct point Lock unexpectedly clears Force Linear for %s" % property_name)
		point.set(force_property, false)
		var expected := point.position + (Vector2.LEFT if side == EasingCurvePoint.ControlSide.LEFT else Vector2.RIGHT) * EasingCurvePoint.DEFAULT_HANDLE_LENGTH
		_expect(point.get(property_name).is_equal_approx(expected), "Clearing Force Linear did not restore %s default geometry" % property_name)

	var linked := _point()
	linked.handle_mode = EasingCurvePoint.HandleMode.LINKED
	linked.set_locked("left_control_point", true)
	linked.right_force_linear = true
	_expect(
		linked.is_control_forced_linear(EasingCurvePoint.ControlSide.LEFT)
		and linked.is_control_forced_linear(EasingCurvePoint.ControlSide.RIGHT),
		"Linked Force Linear did not apply to both sides",
	)
	_expect(linked.left_control_point == linked.position and linked.right_control_point == linked.position, "Linked Force Linear did not collapse both controls")
	linked.right_force_linear = false
	_expect(
		not linked.is_control_forced_linear(EasingCurvePoint.ControlSide.LEFT)
		and not linked.is_control_forced_linear(EasingCurvePoint.ControlSide.RIGHT),
		"Clearing the active Linked Force Linear did not clear the shared state",
	)
	_expect(linked.left_control_point == linked.right_control_point, "Clearing Linked Force Linear did not restore synchronized controls")
	linked.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	linked.left_force_linear = true
	linked.handle_mode = EasingCurvePoint.HandleMode.FREE
	_expect(linked.left_control_point == linked.position, "Handle mode change did not retain active left Force Linear geometry")


func _test_inspector_snapshot_state_precedence_and_reset() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [EasingCurvePoint.new(Vector2.ZERO), _point(), EasingCurvePoint.new(Vector2.ONE)]
	var context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = context.editor
	var inspector: Object = context.inspector
	for property_name in [&"left_control_point", &"right_control_point"]:
		var force_property := &"left_force_linear" if property_name == &"left_control_point" else &"right_force_linear"
		var locks: Dictionary[String, bool] = curve.points[1].locked.duplicate(true)
		locks[property_name] = true
		inspector.call("_apply_point_property_change", 1, &"locked", locks)
		inspector.call("_apply_point_property_change", 1, force_property, true)
		_expect(not curve.points[1].locked[property_name], "Inspector Force Linear did not win over a pre-existing %s lock" % property_name)
		_expect(bool(curve.points[1].get(force_property)), "Inspector Force Linear did not remain enabled for %s" % property_name)
		_expect(curve.points[1].get(property_name) == curve.points[1].position, "Inspector Force Linear did not collapse %s" % property_name)

		locks = curve.points[1].locked.duplicate(true)
		locks[property_name] = true
		inspector.call("_apply_point_property_change", 1, &"locked", locks)
		var offset := Vector2.LEFT if property_name == &"left_control_point" else Vector2.RIGHT
		_expect(not bool(curve.points[1].get(force_property)), "Inspector Lock did not win over active %s Force Linear" % property_name)
		_expect(curve.points[1].get(property_name).is_equal_approx(curve.points[1].position + offset * EasingCurvePoint.DEFAULT_HANDLE_LENGTH), "Inspector Lock did not restore %s default geometry" % property_name)

	inspector.call("_apply_point_property_change", 1, &"left_force_linear", true)
	inspector.call("_apply_point_property_change", 1, &"left_control_lock", true)
	_expect(curve.points[1].locked["left_control_point"], "Synthetic Free control lock did not lock the left control")
	_expect(not curve.points[1].left_force_linear, "Synthetic Free control lock did not win over Force Linear")
	_expect(curve.points[1].left_control_point.is_equal_approx(curve.points[1].position + Vector2.LEFT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH), "Synthetic Free control lock did not restore the left default handle")

	inspector.call("_apply_point_property_change", 1, &"handle_mode", EasingCurvePoint.HandleMode.LINKED)
	inspector.call("_apply_point_property_change", 1, &"left_control_lock", true)
	_expect(curve.points[1].locked["left_control_point"] and curve.points[1].locked["right_control_point"], "Synthetic Linked control lock did not apply to both controls")
	inspector.call("_apply_point_property_change", 1, &"right_force_linear", true)
	_expect(
		curve.points[1].is_control_forced_linear(EasingCurvePoint.ControlSide.LEFT)
		and curve.points[1].is_control_forced_linear(EasingCurvePoint.ControlSide.RIGHT),
		"Inspector Linked Force Linear did not apply to both controls",
	)
	_expect(curve.points[1].left_control_point == curve.points[1].position and curve.points[1].right_control_point == curve.points[1].position, "Inspector Linked Force Linear did not collapse both controls")
	inspector.call("_apply_point_property_change", 1, &"right_control_lock", true)
	_expect(not curve.points[1].left_force_linear and not curve.points[1].right_force_linear, "Synthetic Linked lock did not clear shared Force Linear")
	_expect(curve.points[1].locked["left_control_point"] and curve.points[1].locked["right_control_point"], "Synthetic Linked lock did not keep both controls locked")
	inspector.call("_apply_point_property_change", 1, &"left_control_lock", false)
	_expect(not curve.points[1].locked["left_control_point"] and not curve.points[1].locked["right_control_point"], "Unlocking a synthetic Linked control lock did not unlock both controls")
	inspector.call("_apply_point_property_change", 1, &"toolbar_options_reset", true)
	_expect(curve.points[1].handle_mode == EasingCurvePoint.HandleMode.FREE, "Toolbar reset did not restore Free handle mode")
	_expect(not curve.points[1].left_force_linear and not curve.points[1].right_force_linear, "Toolbar reset did not clear Force Linear state")
	_expect(not curve.points[1].locked["left_control_point"] and not curve.points[1].locked["right_control_point"], "Toolbar reset did not clear control locks")
	editor.free()

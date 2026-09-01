extends "res://test/scripts/test_case.gd"

const EDITOR_HOST = preload("res://test/scripts/editor_host_test_harness.gd")
const EDITOR_DRIVER = preload("res://test/scripts/easing_curve_editor_test_driver.gd")
const POINT_STATE = preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_point_state.gd"
)
const SNAPSHOT_MUTATOR = preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_point_snapshot_mutator.gd"
)
const POINT_STATE_TRANSITION = preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_point_state_transition.gd"
)

func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("easing_curve_point_state_characterization_test.gd"):
		quit(1)
		return
	_test_handle_mode_transition_matrix()
	_test_control_move_matrix()
	_test_position_move_lock_relationships()
	_test_display_space_relationships()
	_test_lock_force_linear_precedence()
	_test_point_state_carrier()
	_test_transition_public_constant_parity()
	_test_transition_input_is_unchanged()
	_test_live_transition_policy_parity()
	_test_live_snapshot_transition_parity()
	_test_snapshot_transition_uses_saved_state()
	_test_intentional_live_snapshot_policy_differences()
	_test_point_signal_contract()
	_test_inspector_snapshot_state_precedence_and_reset()

	_finish("point-state characterization")


func _point() -> EasingCurvePoint:
	var point := EasingCurvePoint.new(Vector2(0.5, 0.5))
	point.left_control_point = Vector2(0.2, 0.1)
	point.right_control_point = Vector2(0.6, 0.7)
	return point


func _set_control_point(
	point: EasingCurvePoint,
	side: EasingCurvePoint.ControlSide,
	value: Vector2,
) -> void:
	if side == EasingCurvePoint.ControlSide.LEFT:
		point.left_control_point = value
	else:
		point.right_control_point = value


func _get_control_point(
	point: EasingCurvePoint,
	side: EasingCurvePoint.ControlSide,
) -> Vector2:
	return (
		point.left_control_point
		if side == EasingCurvePoint.ControlSide.LEFT
		else point.right_control_point
	)


func _make_point_snapshot(point: EasingCurvePoint) -> Dictionary:
	return EasingCurve.new().make_point_snapshot([point])


func _capture_point_state(point: EasingCurvePoint):
	var state = POINT_STATE.new()
	state.position = point.position
	state.left_control_point = point.left_control_point
	state.right_control_point = point.right_control_point
	state.handle_mode = point.handle_mode
	state.locks = point.locked.duplicate(true)
	state.left_force_linear = point.left_force_linear
	state.right_force_linear = point.right_force_linear
	state.handle_display_scale = point.handle_display_scale
	state.use_display_space_handles = point.use_display_space_handles
	return state


func _capture_snapshot_state(
	snapshot: Dictionary,
	i: int,
	context_point: EasingCurvePoint,
):
	var state = POINT_STATE.new()
	state.position = Vector2(snapshot["positions"][i])
	state.left_control_point = Vector2(snapshot["left_control_points"][i])
	state.right_control_point = Vector2(snapshot["right_control_points"][i])
	state.handle_mode = int(snapshot["handle_modes"][i])
	state.locks = snapshot["locks"][i].duplicate(true)
	state.left_force_linear = bool(snapshot["left_force_linear"][i])
	state.right_force_linear = bool(snapshot["right_force_linear"][i])
	state.handle_display_scale = context_point.handle_display_scale
	state.use_display_space_handles = context_point.use_display_space_handles
	return state


func _states_match(a, b) -> bool:
	return (
		a.position.is_equal_approx(b.position)
		and a.left_control_point.is_equal_approx(b.left_control_point)
		and a.right_control_point.is_equal_approx(b.right_control_point)
		and a.handle_mode == b.handle_mode
		and a.locks == b.locks
		and a.left_force_linear == b.left_force_linear
		and a.right_force_linear == b.right_force_linear
		and a.handle_display_scale.is_equal_approx(b.handle_display_scale)
		and a.use_display_space_handles == b.use_display_space_handles
	)


func _state_summary(state) -> String:
	return (
		"position=%s left=%s right=%s mode=%s locks=%s linear=(%s,%s) scale=%s display=%s"
		% [
			state.position,
			state.left_control_point,
			state.right_control_point,
			state.handle_mode,
			state.locks,
			state.left_force_linear,
			state.right_force_linear,
			state.handle_display_scale,
			state.use_display_space_handles,
		]
	)


func _expect_states_match(actual, expected, label: String) -> void:
	_expect(
		_states_match(actual, expected),
		"%s\n  actual: %s\n  expected: %s" % [
			label,
			_state_summary(actual),
			_state_summary(expected),
		],
	)


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


func _test_control_move_matrix() -> void:
	for mode in EasingCurvePoint.HandleMode.values():
		for side in [EasingCurvePoint.ControlSide.LEFT, EasingCurvePoint.ControlSide.RIGHT]:
			var point := _point()
			point.handle_display_scale = Vector2(2.0, 5.0)
			point.handle_mode = mode
			var before_left := point.left_control_point
			var before_right := point.right_control_point
			var target := (
				Vector2(0.1, 0.8)
				if side == EasingCurvePoint.ControlSide.LEFT
				else Vector2(0.9, 0.2)
			)
			_set_control_point(point, side, target)
			var label := "%s %s control move" % [
				EasingCurvePoint.HandleMode.keys()[mode],
				EasingCurvePoint.ControlSide.keys()[side],
			]

			_expect(
				point.left_control_point.is_finite()
				and point.right_control_point.is_finite(),
				"%s produced non-finite geometry" % label,
			)
			match mode:
				EasingCurvePoint.HandleMode.FREE:
					_expect(
						_get_control_point(point, side) == target,
						"%s did not apply the dragged control" % label,
					)
					_expect(
						(
							point.right_control_point == before_right
							if side == EasingCurvePoint.ControlSide.LEFT
							else point.left_control_point == before_left
						),
						"%s changed the opposite Free control" % label,
					)
				EasingCurvePoint.HandleMode.LINEAR:
					_expect(
						point.left_control_point == point.position
						and point.right_control_point == point.position,
						"%s did not retain collapsed Linear controls" % label,
					)
				EasingCurvePoint.HandleMode.BALANCED:
					_expect(
						_get_control_point(point, side) == target,
						"%s did not apply the dragged control" % label,
					)
					_expect(
						_is_opposite_in_handle_space(
							point,
							point.left_control_point,
							point.right_control_point,
						),
						"%s lost its opposite-direction relationship" % label,
					)
				EasingCurvePoint.HandleMode.MIRRORED:
					var left_delta := (
						(point.left_control_point - point.position)
						* point.handle_display_scale
					)
					var right_delta := (
						(point.right_control_point - point.position)
						* point.handle_display_scale
					)
					_expect(
						right_delta.is_equal_approx(-left_delta),
						"%s lost its display-space mirrored relationship" % label,
					)
				EasingCurvePoint.HandleMode.LINKED:
					_expect(
						point.left_control_point == target
						and point.right_control_point == target,
						"%s did not move both controls together" % label,
					)

			if mode in [EasingCurvePoint.HandleMode.FREE, EasingCurvePoint.HandleMode.LINKED]:
				point.set_force_linear_state(
					side == EasingCurvePoint.ControlSide.LEFT,
					side == EasingCurvePoint.ControlSide.RIGHT,
				)
				_set_control_point(point, side, target)
				_expect(
					_get_control_point(point, side) == point.position,
					"%s allowed an active Force Linear control to move" % label,
				)


func _test_position_move_lock_relationships() -> void:
	for locked_side in [
		-1,
		EasingCurvePoint.ControlSide.LEFT,
		EasingCurvePoint.ControlSide.RIGHT,
	]:
		var point := _point()
		var before_position := point.position
		var before_left := point.left_control_point
		var before_right := point.right_control_point
		if locked_side == EasingCurvePoint.ControlSide.LEFT:
			point.set_locked("left_control_point", true)
		elif locked_side == EasingCurvePoint.ControlSide.RIGHT:
			point.set_locked("right_control_point", true)
		var target := Vector2(0.65, 0.35)
		var delta := target - before_position
		point.position = target

		_expect(point.position == target, "Position move did not apply its target")
		_expect(
			point.left_control_point == (
				before_left
				if locked_side == EasingCurvePoint.ControlSide.LEFT
				else before_left + delta
			),
			"Position move violated the left control lock relationship",
		)
		_expect(
			point.right_control_point == (
				before_right
				if locked_side == EasingCurvePoint.ControlSide.RIGHT
				else before_right + delta
			),
			"Position move violated the right control lock relationship",
		)

	var forced_move := _point()
	forced_move.set_locked("left_control_point", true)
	forced_move.set_locked("right_control_point", true)
	var forced_left_offset := forced_move.left_control_point - forced_move.position
	var forced_right_offset := forced_move.right_control_point - forced_move.position
	forced_move.move_horizontally(0.2, true)
	_expect(
		forced_move.left_control_point - forced_move.position == forced_left_offset
		and forced_move.right_control_point - forced_move.position == forced_right_offset,
		"Lock-ignoring horizontal move did not preserve both handle offsets",
	)

	var rejected := _point()
	var rejected_state = _capture_point_state(rejected)
	rejected.position = Vector2(INF, 0.5)
	_expect_states_match(
		_capture_point_state(rejected),
		rejected_state,
		"Non-finite Position input changed point state",
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


func _test_point_state_carrier() -> void:
	var point := _point()
	point.handle_display_scale = Vector2(2.0, 3.0)
	point.use_display_space_handles = false
	point.left_force_linear = true
	point.set_locked("position", true)

	var state = _capture_point_state(point)
	_expect(state.position == point.position, "PointState did not capture Position")
	_expect(state.left_control_point == point.left_control_point, "PointState did not capture Left Control")
	_expect(state.right_control_point == point.right_control_point, "PointState did not capture Right Control")
	_expect(state.handle_mode == point.handle_mode, "PointState did not capture Handle Mode")
	_expect(state.locks == point.locked, "PointState did not capture Locks")
	_expect(state.left_force_linear == point.left_force_linear, "PointState did not capture Left Force Linear")
	_expect(state.right_force_linear == point.right_force_linear, "PointState did not capture Right Force Linear")
	_expect(state.handle_display_scale == point.handle_display_scale, "PointState did not capture Handle Display Scale")
	_expect(state.use_display_space_handles == point.use_display_space_handles, "PointState did not capture display-space policy")

	state.locks["position"] = false
	_expect(point.locked["position"], "PointState Locks alias the source point dictionary")


func _test_transition_public_constant_parity() -> void:
	_expect(
		POINT_STATE_TRANSITION.HandleMode.values()
		== EasingCurvePoint.HandleMode.values(),
		"Transition Handle Mode values diverged from the public point API",
	)
	_expect(
		POINT_STATE_TRANSITION.ControlSide.values()
		== EasingCurvePoint.ControlSide.values(),
		"Transition Control Side values diverged from the public point API",
	)
	_expect(
		POINT_STATE_TRANSITION.ControlState.values()
		== EasingCurvePoint.ControlState.values(),
		"Transition Control State values diverged from the public point API",
	)
	_expect(
		POINT_STATE_TRANSITION.DEFAULT_HANDLE_LENGTH
		== EasingCurvePoint.DEFAULT_HANDLE_LENGTH,
		"Transition default handle length diverged from the public point API",
	)
	_expect(
		POINT_STATE_TRANSITION.LONGEST_HANDLE_WINS
		== EasingCurvePoint.LONGEST_HANDLE_WINS,
		"Transition longest-handle policy diverged from the public point API",
	)


func _test_transition_input_is_unchanged() -> void:
	var source = _capture_point_state(_point())
	var original_left: Vector2 = source.left_control_point
	var original_right: Vector2 = source.right_control_point
	var result = POINT_STATE_TRANSITION.set_handle_mode(
		source,
		EasingCurvePoint.HandleMode.LINEAR,
		POINT_STATE_TRANSITION.Policy.LIVE,
	)

	_expect(result != source, "Transition returned its mutable input state")
	_expect(
		source.handle_mode == EasingCurvePoint.HandleMode.FREE
		and source.left_control_point == original_left
		and source.right_control_point == original_right,
		"Transition mutated its input geometry",
	)
	result.locks["position"] = true
	_expect(
		not source.locks["position"],
		"Transition result Locks alias its input dictionary",
	)


func _test_live_transition_policy_parity() -> void:
	for source in EasingCurvePoint.HandleMode.values():
		for destination in EasingCurvePoint.HandleMode.values():
			var point := _point()
			point.handle_display_scale = Vector2(2.0, 5.0)
			point.handle_mode = source
			var state = _capture_point_state(point)

			point.handle_mode = destination
			state = POINT_STATE_TRANSITION.set_handle_mode(
				state,
				destination,
				POINT_STATE_TRANSITION.Policy.LIVE,
			)
			_expect_states_match(
				state,
				_capture_point_state(point),
				"Live policy Handle Mode parity %s -> %s" % [
					EasingCurvePoint.HandleMode.keys()[source],
					EasingCurvePoint.HandleMode.keys()[destination],
				],
			)

	for mode in EasingCurvePoint.HandleMode.values():
		for side in [EasingCurvePoint.ControlSide.LEFT, EasingCurvePoint.ControlSide.RIGHT]:
			var force_property := (
				&"left_force_linear"
				if side == EasingCurvePoint.ControlSide.LEFT
				else &"right_force_linear"
			)
			for enabled in [true, false]:
				var point := _point()
				point.handle_mode = mode
				if not enabled:
					point.set_force_linear_state(
						side == EasingCurvePoint.ControlSide.LEFT,
						side == EasingCurvePoint.ControlSide.RIGHT,
					)
				var state = _capture_point_state(point)

				point.set(force_property, enabled)
				state = POINT_STATE_TRANSITION.set_force_linear(
					state,
					side,
					enabled,
					POINT_STATE_TRANSITION.Policy.LIVE,
				)
				_expect_states_match(
					state,
					_capture_point_state(point),
					"Live policy %s %s=%s parity" % [
						EasingCurvePoint.HandleMode.keys()[mode],
						force_property,
						enabled,
					],
				)

	for mode in EasingCurvePoint.HandleMode.values():
		for property_name in [
			&"position",
			&"left_control_point",
			&"right_control_point",
		]:
			var point := _point()
			point.handle_mode = mode
			var state = _capture_point_state(point)

			point.set_locked(property_name, true)
			state = POINT_STATE_TRANSITION.set_lock(
				state,
				property_name,
				true,
				POINT_STATE_TRANSITION.Policy.LIVE,
			)
			_expect_states_match(
				state,
				_capture_point_state(point),
				"Live policy %s %s Lock parity" % [
					EasingCurvePoint.HandleMode.keys()[mode],
					property_name,
				],
			)


func _test_live_snapshot_transition_parity() -> void:
	var display_scale := Vector2(2.0, 5.0)
	for source in EasingCurvePoint.HandleMode.values():
		for destination in EasingCurvePoint.HandleMode.values():
			var live := _point()
			var snapshot_context := _point()
			live.handle_display_scale = display_scale
			snapshot_context.handle_display_scale = display_scale
			live.handle_mode = source
			snapshot_context.handle_mode = source
			var snapshot := _make_point_snapshot(snapshot_context)

			live.handle_mode = destination
			var applied: bool = SNAPSHOT_MUTATOR.apply(
				snapshot,
				snapshot_context,
				0,
				&"handle_mode",
				destination,
			)
			var label := "Neutral Handle Mode parity %s -> %s" % [
				EasingCurvePoint.HandleMode.keys()[source],
				EasingCurvePoint.HandleMode.keys()[destination],
			]
			_expect(applied, "%s rejected the snapshot mutation" % label)
			_expect_states_match(
				_capture_snapshot_state(snapshot, 0, snapshot_context),
				_capture_point_state(live),
				"%s diverged" % label,
			)

	for side in [EasingCurvePoint.ControlSide.LEFT, EasingCurvePoint.ControlSide.RIGHT]:
		var property_name := (
			&"left_force_linear"
			if side == EasingCurvePoint.ControlSide.LEFT
			else &"right_force_linear"
		)
		for enabled in [true, false]:
			var live := _point()
			var snapshot_context := _point()
			if not enabled:
				live.set(property_name, true)
				snapshot_context.set(property_name, true)
			var snapshot := _make_point_snapshot(snapshot_context)

			live.set(property_name, enabled)
			var applied: bool = SNAPSHOT_MUTATOR.apply(
				snapshot,
				snapshot_context,
				0,
				property_name,
				enabled,
			)
			var label := "Unlocked Free %s=%s parity" % [property_name, enabled]
			_expect(applied, "%s rejected the snapshot mutation" % label)
			_expect_states_match(
				_capture_snapshot_state(snapshot, 0, snapshot_context),
				_capture_point_state(live),
				"%s diverged" % label,
			)


func _test_snapshot_transition_uses_saved_state() -> void:
	var point := _point()
	var saved_position := Vector2(0.3, 0.6)
	point.position = saved_position
	var snapshot := _make_point_snapshot(point)

	var live_position := Vector2(0.8, 0.2)
	point.position = live_position
	var applied: bool = SNAPSHOT_MUTATOR.apply(
		snapshot,
		point,
		0,
		&"handle_mode",
		EasingCurvePoint.HandleMode.LINEAR,
	)
	var snapshot_state = _capture_snapshot_state(snapshot, 0, point)
	_expect(applied, "Saved-state Linear transition was rejected")
	_expect(
		snapshot_state.position == saved_position,
		"Snapshot transition changed the saved Position",
	)
	_expect(
		snapshot_state.left_control_point == saved_position
		and snapshot_state.right_control_point == saved_position,
		"Snapshot transition used the post-save live Position",
	)
	_expect(
		point.position == live_position,
		"Snapshot transition mutated the live point resource",
	)

	point = _point()
	snapshot = _make_point_snapshot(point)
	point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	applied = SNAPSHOT_MUTATOR.apply(
		snapshot,
		point,
		0,
		&"left_control_state",
		EasingCurvePoint.ControlState.LOCKED,
	)
	snapshot_state = _capture_snapshot_state(snapshot, 0, point)
	_expect(
		applied and snapshot_state.locks["left_control_point"],
		"Snapshot Control State eligibility used the post-save live Handle Mode",
	)

	point = _point()
	point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	snapshot = _make_point_snapshot(point)
	point.handle_mode = EasingCurvePoint.HandleMode.FREE
	applied = SNAPSHOT_MUTATOR.apply(
		snapshot,
		point,
		0,
		&"left_control_state",
		EasingCurvePoint.ControlState.LOCKED,
	)
	_expect(
		not applied,
		"Snapshot Linear state accepted a Control State because the live mode changed",
	)

	point = _point()
	point.position = saved_position
	point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	snapshot = _make_point_snapshot(point)
	point.handle_mode = EasingCurvePoint.HandleMode.FREE
	point.position = live_position
	SNAPSHOT_MUTATOR.apply(
		snapshot,
		point,
		0,
		&"handle_mode",
		EasingCurvePoint.HandleMode.FREE,
	)
	snapshot_state = _capture_snapshot_state(snapshot, 0, point)
	_expect(
		snapshot_state.left_control_point
		== saved_position + Vector2.LEFT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH
		and snapshot_state.right_control_point
		== saved_position + Vector2.RIGHT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH,
		"Snapshot Linear-to-Free transition used post-save live geometry",
	)


func _test_intentional_live_snapshot_policy_differences() -> void:
	for side in [EasingCurvePoint.ControlSide.LEFT, EasingCurvePoint.ControlSide.RIGHT]:
		var control_property := (
			"left_control_point"
			if side == EasingCurvePoint.ControlSide.LEFT
			else "right_control_point"
		)
		var force_property := (
			&"left_force_linear"
			if side == EasingCurvePoint.ControlSide.LEFT
			else &"right_force_linear"
		)
		var live := _point()
		var snapshot_context := _point()
		live.set_locked(control_property, true)
		snapshot_context.set_locked(control_property, true)
		var snapshot := _make_point_snapshot(snapshot_context)

		live.set(force_property, true)
		SNAPSHOT_MUTATOR.apply(snapshot, snapshot_context, 0, force_property, true)
		var snapshot_state = _capture_snapshot_state(snapshot, 0, snapshot_context)
		_expect(
			live.locked[control_property],
			"Live Force Linear no longer retains a prior %s lock" % control_property,
		)
		_expect(
			not snapshot_state.locks[control_property],
			"Inspector Force Linear no longer wins over a prior %s lock" % control_property,
		)
		_expect(
			live.get(force_property) and (
				snapshot_state.left_force_linear
				if side == EasingCurvePoint.ControlSide.LEFT
				else snapshot_state.right_force_linear
			),
			"Force Linear did not remain enabled in both policy paths for %s" % control_property,
		)

		live = _point()
		snapshot_context = _point()
		live.set(force_property, true)
		snapshot_context.set(force_property, true)
		snapshot = _make_point_snapshot(snapshot_context)
		var next_locks: Dictionary[String, bool] = snapshot_context.locked.duplicate(true)
		next_locks[control_property] = true

		live.set_locked(control_property, true)
		SNAPSHOT_MUTATOR.apply(snapshot, snapshot_context, 0, &"locked", next_locks)
		snapshot_state = _capture_snapshot_state(snapshot, 0, snapshot_context)
		_expect(
			bool(live.get(force_property)),
			"Live Lock no longer retains active %s" % force_property,
		)
		_expect(
			not (
				snapshot_state.left_force_linear
				if side == EasingCurvePoint.ControlSide.LEFT
				else snapshot_state.right_force_linear
			),
			"Inspector Lock no longer wins over active %s" % force_property,
		)

	var linked_live := _point()
	var linked_snapshot_context := _point()
	linked_live.handle_mode = EasingCurvePoint.HandleMode.LINKED
	linked_snapshot_context.handle_mode = EasingCurvePoint.HandleMode.LINKED
	var linked_snapshot := _make_point_snapshot(linked_snapshot_context)
	linked_live.set_locked("left_control_point", true)
	SNAPSHOT_MUTATOR.apply(
		linked_snapshot,
		linked_snapshot_context,
		0,
		&"left_control_lock",
		true,
	)
	var linked_snapshot_state = _capture_snapshot_state(
		linked_snapshot,
		0,
		linked_snapshot_context,
	)
	_expect(
		linked_live.locked["left_control_point"]
		and not linked_live.locked["right_control_point"],
		"Live Linked Lock no longer preserves an asymmetric raw state",
	)
	_expect(
		linked_snapshot_state.locks["left_control_point"]
		and linked_snapshot_state.locks["right_control_point"],
		"Inspector Linked Lock no longer normalizes both sides",
	)

	linked_live = _point()
	linked_snapshot_context = _point()
	linked_live.handle_mode = EasingCurvePoint.HandleMode.LINKED
	linked_snapshot_context.handle_mode = EasingCurvePoint.HandleMode.LINKED
	linked_snapshot = _make_point_snapshot(linked_snapshot_context)
	linked_live.right_force_linear = true
	SNAPSHOT_MUTATOR.apply(
		linked_snapshot,
		linked_snapshot_context,
		0,
		&"right_force_linear",
		true,
	)
	linked_snapshot_state = _capture_snapshot_state(
		linked_snapshot,
		0,
		linked_snapshot_context,
	)
	_expect(
		not linked_live.left_force_linear and linked_live.right_force_linear,
		"Live Linked Force Linear no longer preserves an asymmetric raw state",
	)
	_expect(
		linked_snapshot_state.left_force_linear
		and linked_snapshot_state.right_force_linear,
		"Inspector Linked Force Linear no longer normalizes both sides",
	)


func _record_point_events(point: EasingCurvePoint) -> Array[String]:
	var events: Array[String] = []
	point.lock_changed.connect(
		func(property_name: String, locked_value: bool) -> void:
			events.append("lock:%s:%s" % [property_name, locked_value])
	)
	point.changed.connect(func() -> void: events.append("changed"))
	return events


func _test_point_signal_contract() -> void:
	var point := _point()
	var events := _record_point_events(point)
	point.set_locked("position", true)
	_expect(
		events == ["lock:position:true", "changed"],
		"set_locked() signal order changed: %s" % [events],
	)

	point = _point()
	events = _record_point_events(point)
	var locks: Dictionary[String, bool] = point.locked.duplicate(true)
	locks["position"] = true
	point.set_locks(locks)
	_expect(events == ["changed"], "set_locks() signal contract changed: %s" % [events])

	point = _point()
	events = _record_point_events(point)
	point.position = Vector2(0.55, 0.45)
	_expect(events == ["changed"], "Position mutation signal count changed: %s" % [events])

	point = _point()
	events = _record_point_events(point)
	point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	_expect(events == ["changed"], "Handle Mode mutation signal count changed: %s" % [events])

	point = _point()
	events = _record_point_events(point)
	point.left_force_linear = true
	_expect(events == ["changed"], "Force Linear mutation signal count changed: %s" % [events])

	point = _point()
	events = _record_point_events(point)
	point.position = point.position
	point.handle_mode = point.handle_mode
	point.set_locked("position", false)
	point.left_force_linear = false
	_expect(events.is_empty(), "No-op point setters emitted signals: %s" % [events])

	point = _point()
	events = _record_point_events(point)
	point.set_force_linear_state(false, false, false)
	_expect(
		events == ["changed"],
		"set_force_linear_state() no-op notification contract changed: %s" % [events],
	)


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
		EDITOR_DRIVER.change_point_property(inspector, 1, &"locked", locks)
		EDITOR_DRIVER.change_point_property(inspector, 1, force_property, true)
		_expect(not curve.points[1].locked[property_name], "Inspector Force Linear did not win over a pre-existing %s lock" % property_name)
		_expect(bool(curve.points[1].get(force_property)), "Inspector Force Linear did not remain enabled for %s" % property_name)
		_expect(curve.points[1].get(property_name) == curve.points[1].position, "Inspector Force Linear did not collapse %s" % property_name)

		locks = curve.points[1].locked.duplicate(true)
		locks[property_name] = true
		EDITOR_DRIVER.change_point_property(inspector, 1, &"locked", locks)
		var offset := Vector2.LEFT if property_name == &"left_control_point" else Vector2.RIGHT
		_expect(not bool(curve.points[1].get(force_property)), "Inspector Lock did not win over active %s Force Linear" % property_name)
		_expect(curve.points[1].get(property_name).is_equal_approx(curve.points[1].position + offset * EasingCurvePoint.DEFAULT_HANDLE_LENGTH), "Inspector Lock did not restore %s default geometry" % property_name)

	EDITOR_DRIVER.change_point_property(inspector, 1, &"left_force_linear", true)
	EDITOR_DRIVER.change_point_property(inspector, 1, &"left_control_lock", true)
	_expect(curve.points[1].locked["left_control_point"], "Synthetic Free control lock did not lock the left control")
	_expect(not curve.points[1].left_force_linear, "Synthetic Free control lock did not win over Force Linear")
	_expect(curve.points[1].left_control_point.is_equal_approx(curve.points[1].position + Vector2.LEFT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH), "Synthetic Free control lock did not restore the left default handle")

	EDITOR_DRIVER.change_point_property(inspector, 1, &"position_lock", true)
	_expect(curve.points[1].locked["position"], "Synthetic position lock did not lock the position")
	EDITOR_DRIVER.change_point_property(inspector, 1, &"position_lock", false)
	_expect(not curve.points[1].locked["position"], "Synthetic position lock did not unlock the position")

	EDITOR_DRIVER.change_point_property(inspector, 1, &"toolbar_options_reset", true)
	_expect(curve.points[1].handle_mode == EasingCurvePoint.HandleMode.FREE, "Toolbar reset did not prepare Free mode for the asymmetric lock merge")
	EDITOR_DRIVER.change_point_property(inspector, 1, &"left_control_lock", true)
	EDITOR_DRIVER.change_point_property(inspector, 1, &"handle_mode", EasingCurvePoint.HandleMode.LINKED)
	_expect(curve.points[1].locked["left_control_point"] and curve.points[1].locked["right_control_point"], "Linked mode did not merge an asymmetric Free control lock")

	EDITOR_DRIVER.change_point_property(inspector, 1, &"toolbar_options_reset", true)
	EDITOR_DRIVER.change_point_property(inspector, 1, &"right_force_linear", true)
	EDITOR_DRIVER.change_point_property(inspector, 1, &"handle_mode", EasingCurvePoint.HandleMode.LINKED)
	_expect(curve.points[1].left_force_linear and curve.points[1].right_force_linear, "Linked mode did not merge an asymmetric Free Force Linear state")
	_expect(curve.points[1].left_control_point == curve.points[1].position and curve.points[1].right_control_point == curve.points[1].position, "Linked mode did not collapse controls for a merged Force Linear state")

	EDITOR_DRIVER.change_point_property(inspector, 1, &"toolbar_options_reset", true)
	EDITOR_DRIVER.change_point_property(inspector, 1, &"handle_mode", EasingCurvePoint.HandleMode.LINKED)
	EDITOR_DRIVER.change_point_property(inspector, 1, &"left_control_lock", true)
	_expect(curve.points[1].locked["left_control_point"] and curve.points[1].locked["right_control_point"], "Synthetic Linked control lock did not apply to both controls")
	EDITOR_DRIVER.change_point_property(inspector, 1, &"right_force_linear", true)
	_expect(
		curve.points[1].is_control_forced_linear(EasingCurvePoint.ControlSide.LEFT)
		and curve.points[1].is_control_forced_linear(EasingCurvePoint.ControlSide.RIGHT),
		"Inspector Linked Force Linear did not apply to both controls",
	)
	_expect(curve.points[1].left_control_point == curve.points[1].position and curve.points[1].right_control_point == curve.points[1].position, "Inspector Linked Force Linear did not collapse both controls")
	EDITOR_DRIVER.change_point_property(inspector, 1, &"right_control_lock", true)
	_expect(not curve.points[1].left_force_linear and not curve.points[1].right_force_linear, "Synthetic Linked lock did not clear shared Force Linear")
	_expect(curve.points[1].locked["left_control_point"] and curve.points[1].locked["right_control_point"], "Synthetic Linked lock did not keep both controls locked")
	EDITOR_DRIVER.change_point_property(inspector, 1, &"left_control_lock", false)
	_expect(not curve.points[1].locked["left_control_point"] and not curve.points[1].locked["right_control_point"], "Unlocking a synthetic Linked control lock did not unlock both controls")
	EDITOR_DRIVER.change_point_property(inspector, 1, &"toolbar_options_reset", true)
	_expect(curve.points[1].handle_mode == EasingCurvePoint.HandleMode.FREE, "Toolbar reset did not restore Free handle mode")
	_expect(not curve.points[1].left_force_linear and not curve.points[1].right_force_linear, "Toolbar reset did not clear Force Linear state")
	_expect(not curve.points[1].locked["left_control_point"] and not curve.points[1].locked["right_control_point"], "Toolbar reset did not clear control locks")
	editor.free()

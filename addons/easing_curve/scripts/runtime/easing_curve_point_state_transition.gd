@tool
extends RefCounted
## Pure transitions for EasingCurvePoint state.
##
## Callers own serialization and notifications. Policy makes the intentional
## difference between direct resource setters and Inspector user intent explicit.

const POINT_STATE = preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_point_state.gd"
)
const DEFAULT_HANDLE_LENGTH := 0.1
const LONGEST_HANDLE_WINS := true

enum HandleMode {
	FREE,
	LINEAR,
	BALANCED,
	MIRRORED,
	LINKED,
}

enum ControlSide {
	LEFT,
	RIGHT,
}

enum ControlState {
	FREE,
	LINEAR,
	LOCKED,
}

enum Policy {
	LIVE,
	INSPECTOR,
}


static func supports_control_state(state: POINT_STATE) -> bool:
	return state.handle_mode in [
		HandleMode.FREE,
		HandleMode.LINKED,
	]


static func is_lock_active(state: POINT_STATE, property_name: StringName) -> bool:
	if property_name == &"position":
		return state.locks.get(String(property_name), false)

	if state.handle_mode not in [HandleMode.FREE, HandleMode.LINKED]:
		return false

	return state.locks.get(String(property_name), false)


static func is_control_forced_linear(state: POINT_STATE, side: int) -> bool:
	return _is_control_forced_linear(state, side)


static func set_position(
	source: POINT_STATE,
	value: Vector2,
	ignore_control_locks := false,
) -> POINT_STATE:
	var state := _copy(source)
	if not value.is_finite() or state.position == value:
		return state

	var delta := value - state.position
	var left_locked := (
		is_lock_active(state, &"left_control_point")
		and not ignore_control_locks
	)
	var right_locked := (
		is_lock_active(state, &"right_control_point")
		and not ignore_control_locks
	)

	if not left_locked:
		state.left_control_point += delta
	if not right_locked:
		state.right_control_point += delta
	state.position = value
	return state


static func get_control_point_pair(
	state: POINT_STATE,
	side: int,
	value: Vector2,
) -> Dictionary:
	var left := state.left_control_point
	var right := state.right_control_point

	if state.handle_mode == HandleMode.LINEAR:
		return {
			"left": state.position,
			"right": state.position,
		}

	if side == ControlSide.LEFT:
		left = value
	else:
		right = value

	match state.handle_mode:
		HandleMode.BALANCED:
			var opposite := (
				state.right_control_point
				if side == ControlSide.LEFT
				else state.left_control_point
			)
			var moved_delta := _to_handle_space(state, value - state.position)
			var opposite_delta := _to_handle_space(
				state,
				opposite - state.position,
			)
			var opposite_length := _get_safe_length(
				opposite_delta,
				Vector2.ZERO,
			)
			var direction := _get_safe_direction(-moved_delta)
			var balanced_delta := _from_handle_space(
				state,
				direction * opposite_length,
			)
			var balanced := state.position + balanced_delta

			if side == ControlSide.LEFT:
				right = balanced
			else:
				left = balanced

		HandleMode.MIRRORED:
			var moved_delta := _to_handle_space(state, value - state.position)
			var mirrored := (
				state.position
				+ _from_handle_space(state, -moved_delta)
			)

			if side == ControlSide.LEFT:
				right = mirrored
			else:
				left = mirrored

		HandleMode.LINKED:
			left = value
			right = value

	return {
		"left": left,
		"right": right,
	}


static func set_handle_mode(
	source: POINT_STATE,
	mode: int,
	policy: Policy,
) -> POINT_STATE:
	var state := _copy(source)
	_set_handle_mode(state, mode, policy)
	return state


static func _set_handle_mode(
	state: POINT_STATE,
	mode: int,
	policy: Policy,
) -> void:
	var handles := get_handles_for_mode_change(state, mode)

	if policy == Policy.INSPECTOR and mode == HandleMode.LINKED:
		var shared_locked := (
			bool(state.locks.get("left_control_point", false))
			or bool(state.locks.get("right_control_point", false))
		)
		var shared_force_linear := (
			state.left_force_linear or state.right_force_linear
		)

		state.locks["left_control_point"] = shared_locked
		state.locks["right_control_point"] = shared_locked
		state.left_force_linear = shared_force_linear
		state.right_force_linear = shared_force_linear

	state.handle_mode = mode
	state.left_control_point = handles["left"]
	state.right_control_point = handles["right"]
	_apply_force_linear_geometry(state)


static func set_control_state(
	source: POINT_STATE,
	side: int,
	control_state: int,
) -> POINT_STATE:
	var state := _copy(source)
	_set_control_state(state, side, control_state)
	return state


static func _set_control_state(
	state: POINT_STATE,
	side: int,
	control_state: int,
) -> void:
	var linked := state.handle_mode == HandleMode.LINKED
	var sides: Array[int] = [side]
	if linked:
		sides = [
			ControlSide.LEFT,
			ControlSide.RIGHT,
		]

	var had_force_linear := (
		state.left_force_linear
		if linked
		else _force_linear(state, side)
	)

	for control_side in sides:
		_set_force_linear_value(
			state,
			control_side,
			control_state == ControlState.LINEAR,
		)
		state.locks[_control_property(control_side)] = (
			control_state == ControlState.LOCKED
		)

		if control_state == ControlState.LINEAR:
			_set_control(state, control_side, state.position)
		elif had_force_linear:
			_set_default_control(state, control_side)

	if linked and control_state != ControlState.LINEAR and had_force_linear:
		_set_linked_default(state)


static func set_force_linear(
	source: POINT_STATE,
	side: int,
	enabled: bool,
	policy: Policy,
) -> POINT_STATE:
	var state := _copy(source)
	_set_force_linear(state, side, enabled, policy)
	return state


static func set_force_linear_state(
	source: POINT_STATE,
	left: bool,
	right: bool,
	apply_geometry := true,
) -> POINT_STATE:
	var state := _copy(source)
	state.left_force_linear = left
	state.right_force_linear = right

	if apply_geometry:
		if state.handle_mode == HandleMode.LINKED and not left and not right:
			_set_linked_default(state)
		else:
			_apply_force_linear_geometry(state)

	return state


static func _set_force_linear(
	state: POINT_STATE,
	side: int,
	enabled: bool,
	policy: Policy,
) -> void:
	if policy == Policy.LIVE:
		_set_live_force_linear(state, side, enabled)
		return

	if state.handle_mode == HandleMode.LINKED:
		state.left_force_linear = enabled
		state.right_force_linear = enabled

		if enabled:
			# The newest Inspector intent wins over Lock.
			state.locks["left_control_point"] = false
			state.locks["right_control_point"] = false
			state.left_control_point = state.position
			state.right_control_point = state.position
		else:
			_set_linked_default(state)
		return

	_set_force_linear_value(state, side, enabled)
	if enabled:
		# The newest Inspector intent wins over Lock.
		state.locks[_control_property(side)] = false
		_set_control(state, side, state.position)
	else:
		_set_default_control(state, side)


static func set_locks(
	source: POINT_STATE,
	locks: Dictionary,
	policy: Policy,
) -> POINT_STATE:
	var state := _copy(source)
	_set_locks(state, locks, policy)
	return state


static func _set_locks(
	state: POINT_STATE,
	locks: Dictionary,
	policy: Policy,
) -> void:
	var next: Dictionary = locks.duplicate(true)
	if policy == Policy.LIVE:
		state.locks = next
		return

	var previous: Dictionary = state.locks
	var linked := state.handle_mode == HandleMode.LINKED
	var cleared_linked_linear := false

	for side in [
		ControlSide.LEFT,
		ControlSide.RIGHT,
	]:
		var property_name := _control_property(side)
		var newly_locked := (
			not bool(previous.get(property_name, false))
			and bool(next.get(property_name, false))
		)
		if not newly_locked or not _force_linear(state, side):
			continue

		# The newest Inspector intent wins over Force Linear.
		_set_force_linear_value(state, side, false)
		_set_default_control(state, side)
		cleared_linked_linear = linked

	state.locks = next
	if cleared_linked_linear:
		_set_linked_default(state)


static func set_lock(
	source: POINT_STATE,
	property_name: StringName,
	enabled: bool,
	policy: Policy,
) -> POINT_STATE:
	var state := _copy(source)
	_set_lock(state, property_name, enabled, policy)
	return state


static func _set_lock(
	state: POINT_STATE,
	property_name: StringName,
	enabled: bool,
	policy: Policy,
) -> void:
	var locks: Dictionary = state.locks.duplicate(true)
	locks[property_name] = enabled
	if (
		policy == Policy.INSPECTOR
		and state.handle_mode == HandleMode.LINKED
		and property_name in [&"left_control_point", &"right_control_point"]
	):
		locks["left_control_point"] = enabled
		locks["right_control_point"] = enabled
	_set_locks(state, locks, policy)


static func get_handles_for_mode_change(
	state: POINT_STATE,
	mode: int,
) -> Dictionary:
	var left := state.left_control_point
	var right := state.right_control_point

	if mode == HandleMode.LINEAR:
		return {
			"left": state.position,
			"right": state.position,
		}

	if state.handle_mode == HandleMode.LINEAR:
		left = state.position + Vector2.LEFT * DEFAULT_HANDLE_LENGTH
		right = state.position + Vector2.RIGHT * DEFAULT_HANDLE_LENGTH

		if mode == HandleMode.LINKED:
			var linked := _get_linked_handle_position(state, left, right)
			return {
				"left": linked,
				"right": linked,
			}

		return {
			"left": left,
			"right": right,
		}

	match mode:
		HandleMode.FREE:
			pass

		HandleMode.BALANCED:
			var left_delta := _to_handle_space(state, left - state.position)
			var right_delta := _to_handle_space(state, right - state.position)
			var left_length := _get_safe_length(left_delta, Vector2.ZERO)
			var right_length := _get_safe_length(right_delta, Vector2.ZERO)
			var use_left := (
				LONGEST_HANDLE_WINS
				and left_length > right_length
			)
			var direction := -left_delta if use_left else right_delta
			direction = _get_safe_direction(direction)

			left = (
				state.position
				+ _from_handle_space(state, -direction * left_length)
			)
			right = (
				state.position
				+ _from_handle_space(state, direction * right_length)
			)

		HandleMode.MIRRORED:
			var left_length := _get_safe_length(left, state.position)
			var right_length := _get_safe_length(right, state.position)
			var use_left := (
				LONGEST_HANDLE_WINS
				and left_length > right_length
			)
			var direction := (
				state.position - left
				if use_left
				else right - state.position
			)
			direction = _get_safe_direction(direction)
			var length := (
				maxf(left_length, right_length)
				if LONGEST_HANDLE_WINS
				else right_length
			)
			if is_zero_approx(length):
				length = DEFAULT_HANDLE_LENGTH

			left = state.position - direction * length
			right = state.position + direction * length

		HandleMode.LINKED:
			var linked := _get_linked_handle_position(state, left, right)
			left = linked
			right = linked

	return {
		"left": left,
		"right": right,
	}


static func _set_live_force_linear(
	state: POINT_STATE,
	side: int,
	enabled: bool,
) -> void:
	if _is_control_forced_linear(state, side) == enabled:
		return

	_set_force_linear_value(state, side, enabled)
	if state.handle_mode == HandleMode.LINKED:
		if state.left_force_linear or state.right_force_linear:
			state.left_control_point = state.position
			state.right_control_point = state.position
		else:
			_set_linked_default(state)
	elif state.handle_mode == HandleMode.FREE:
		if enabled:
			_set_control(state, side, state.position)
		else:
			_set_default_control(state, side)


static func _apply_force_linear_geometry(state: POINT_STATE) -> void:
	if not supports_control_state(state):
		return

	if state.handle_mode == HandleMode.LINKED:
		if state.left_force_linear or state.right_force_linear:
			state.left_control_point = state.position
			state.right_control_point = state.position
		return

	if state.left_force_linear:
		state.left_control_point = state.position
	if state.right_force_linear:
		state.right_control_point = state.position


static func _set_control(
	state: POINT_STATE,
	side: int,
	value: Vector2,
) -> void:
	if side == ControlSide.LEFT:
		state.left_control_point = value
	else:
		state.right_control_point = value


static func _set_default_control(
	state: POINT_STATE,
	side: int,
) -> void:
	var offset := (
		Vector2.LEFT
		if side == ControlSide.LEFT
		else Vector2.RIGHT
	)
	_set_control(
		state,
		side,
		state.position + offset * DEFAULT_HANDLE_LENGTH,
	)


static func _set_linked_default(state: POINT_STATE) -> void:
	var linked_default := (
		state.position + Vector2.RIGHT * DEFAULT_HANDLE_LENGTH
	)
	state.left_control_point = linked_default
	state.right_control_point = linked_default


static func _is_control_forced_linear(
	state: POINT_STATE,
	side: int,
) -> bool:
	if state.handle_mode == HandleMode.LINKED:
		return state.left_force_linear or state.right_force_linear
	return _force_linear(state, side)


static func _force_linear(
	state: POINT_STATE,
	side: int,
) -> bool:
	return (
		state.left_force_linear
		if side == ControlSide.LEFT
		else state.right_force_linear
	)


static func _set_force_linear_value(
	state: POINT_STATE,
	side: int,
	value: bool,
) -> void:
	if side == ControlSide.LEFT:
		state.left_force_linear = value
	else:
		state.right_force_linear = value


static func _control_property(side: int) -> StringName:
	return (
		&"left_control_point"
		if side == ControlSide.LEFT
		else &"right_control_point"
	)


static func _get_linked_handle_position(
	state: POINT_STATE,
	left: Vector2,
	right: Vector2,
) -> Vector2:
	var left_length := _get_safe_length(left, state.position)
	var right_length := _get_safe_length(right, state.position)
	var use_left := (
		LONGEST_HANDLE_WINS
		and left_length > right_length
	)
	return left if use_left else right


static func _get_safe_direction(
	direction: Vector2,
	fallback := Vector2.RIGHT,
) -> Vector2:
	if not direction.is_finite():
		return fallback

	var max_component := maxf(absf(direction.x), absf(direction.y))
	if is_zero_approx(max_component):
		return fallback

	var scaled := direction / max_component
	var scaled_length := sqrt(scaled.x * scaled.x + scaled.y * scaled.y)
	if not is_finite(scaled_length) or is_zero_approx(scaled_length):
		return fallback

	return scaled / scaled_length


static func _get_safe_length(from: Vector2, to: Vector2) -> float:
	var delta := from - to
	if not delta.is_finite():
		return 0.0

	var max_component := maxf(absf(delta.x), absf(delta.y))
	if is_zero_approx(max_component):
		return 0.0

	var scaled := delta / max_component
	return max_component * sqrt(scaled.x * scaled.x + scaled.y * scaled.y)


static func _to_handle_space(state: POINT_STATE, delta: Vector2) -> Vector2:
	return delta * state.handle_display_scale if state.use_display_space_handles else delta


static func _from_handle_space(state: POINT_STATE, delta: Vector2) -> Vector2:
	return delta / state.handle_display_scale if state.use_display_space_handles else delta


static func _copy(source: POINT_STATE) -> POINT_STATE:
	var state := POINT_STATE.new()
	state.position = source.position
	state.left_control_point = source.left_control_point
	state.right_control_point = source.right_control_point
	state.handle_mode = source.handle_mode
	state.locks = source.locks.duplicate(true)
	state.left_force_linear = source.left_force_linear
	state.right_force_linear = source.right_force_linear
	state.handle_display_scale = source.handle_display_scale
	state.use_display_space_handles = source.use_display_space_handles
	return state

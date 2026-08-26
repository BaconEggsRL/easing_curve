@tool
extends RefCounted
## Centralizes editor-side state transitions for primitive point snapshots.
##
## The Inspector supplies user intent. This helper owns the Handle Mode,
## Control State, Force Linear, and Lock precedence rules.

const PROPERTIES := [
	&"handle_mode",
	&"left_control_state",
	&"right_control_state",
	&"toolbar_options_reset",
	&"left_force_linear",
	&"right_force_linear",
	&"locked",
	&"position_lock",
	&"left_control_lock",
	&"right_control_lock",
]


static func handles(property_name: StringName) -> bool:
	return property_name in PROPERTIES


static func apply(
	snapshot: Dictionary,
	point: EasingCurvePoint,
	i: int,
	property_name: StringName,
	value: Variant,
) -> bool:
	var state := _read(snapshot, i)

	match property_name:
		&"handle_mode":
			var mode := int(value)
			if mode not in EasingCurvePoint.HandleMode.values():
				return false
			_set_handle_mode(state, point, mode)

		&"left_control_state", &"right_control_state":
			if not point.supports_control_state():
				return false

			var control_state := int(value)
			if control_state not in EasingCurvePoint.ControlState.values():
				return false
			_set_control_state(state, _side(property_name), control_state)

		&"toolbar_options_reset":
			_set_handle_mode(state, point, EasingCurvePoint.HandleMode.FREE)
			_set_control_state(
				state,
				EasingCurvePoint.ControlSide.LEFT,
				EasingCurvePoint.ControlState.FREE,
			)
			_set_control_state(
				state,
				EasingCurvePoint.ControlSide.RIGHT,
				EasingCurvePoint.ControlState.FREE,
			)

		&"left_force_linear", &"right_force_linear":
			_set_force_linear(state, _side(property_name), bool(value))

		&"locked":
			if value is not Dictionary:
				return false
			_set_locks(state, value)

		&"position_lock", &"left_control_lock", &"right_control_lock":
			_set_lock(state, _lock_property(property_name), bool(value))

		_:
			return false

	_write(snapshot, i, state)
	return true


static func _read(snapshot: Dictionary, i: int) -> Dictionary:
	return {
		"position": snapshot["positions"][i],
		"left_control_point": snapshot["left_control_points"][i],
		"right_control_point": snapshot["right_control_points"][i],
		"handle_mode": snapshot["handle_modes"][i],
		"locks": snapshot["locks"][i].duplicate(true),
		"left_force_linear": bool(snapshot["left_force_linear"][i]),
		"right_force_linear": bool(snapshot["right_force_linear"][i]),
	}


static func _write(snapshot: Dictionary, i: int, state: Dictionary) -> void:
	var left_controls: PackedVector2Array = snapshot["left_control_points"]
	var right_controls: PackedVector2Array = snapshot["right_control_points"]
	var modes: PackedInt32Array = snapshot["handle_modes"]
	var locks: Array = snapshot["locks"]
	var left_linear: PackedByteArray = snapshot["left_force_linear"]
	var right_linear: PackedByteArray = snapshot["right_force_linear"]

	left_controls[i] = state.left_control_point
	right_controls[i] = state.right_control_point
	modes[i] = state.handle_mode
	locks[i] = state.locks.duplicate(true)
	left_linear[i] = int(state.left_force_linear)
	right_linear[i] = int(state.right_force_linear)

	snapshot["left_control_points"] = left_controls
	snapshot["right_control_points"] = right_controls
	snapshot["handle_modes"] = modes
	snapshot["locks"] = locks
	snapshot["left_force_linear"] = left_linear
	snapshot["right_force_linear"] = right_linear


static func _set_handle_mode(state: Dictionary, point: EasingCurvePoint, mode: int) -> void:
	var handles := point.get_handles_for_mode_change(mode)

	if mode == EasingCurvePoint.HandleMode.LINKED:
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
		if shared_force_linear:
			handles["left"] = point.position
			handles["right"] = point.position

	if mode == EasingCurvePoint.HandleMode.FREE:
		if state.left_force_linear:
			handles["left"] = point.position
		if state.right_force_linear:
			handles["right"] = point.position

	state.handle_mode = mode
	state.left_control_point = handles["left"]
	state.right_control_point = handles["right"]


static func _set_control_state(
	state: Dictionary,
	side: EasingCurvePoint.ControlSide,
	control_state: int,
) -> void:
	var linked := state.handle_mode == EasingCurvePoint.HandleMode.LINKED
	var sides: Array[EasingCurvePoint.ControlSide] = [side]
	if linked:
		sides = [
			EasingCurvePoint.ControlSide.LEFT,
			EasingCurvePoint.ControlSide.RIGHT,
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
			control_state == EasingCurvePoint.ControlState.LINEAR,
		)
		state.locks[_control_property(control_side)] = (
			control_state == EasingCurvePoint.ControlState.LOCKED
		)

		if control_state == EasingCurvePoint.ControlState.LINEAR:
			_set_control(state, control_side, state.position)
		elif had_force_linear:
			_set_default_control(state, control_side)

	if linked and control_state != EasingCurvePoint.ControlState.LINEAR and had_force_linear:
		_set_linked_default(state)


static func _set_force_linear(
	state: Dictionary,
	side: EasingCurvePoint.ControlSide,
	enabled: bool,
) -> void:
	if state.handle_mode == EasingCurvePoint.HandleMode.LINKED:
		state.left_force_linear = enabled
		state.right_force_linear = enabled

		if enabled:
			# Force Linear wins over Lock.
			state.locks["left_control_point"] = false
			state.locks["right_control_point"] = false
			state.left_control_point = state.position
			state.right_control_point = state.position
		else:
			_set_linked_default(state)
		return

	_set_force_linear_value(state, side, enabled)
	if enabled:
		# Force Linear wins over Lock.
		state.locks[_control_property(side)] = false
		_set_control(state, side, state.position)
	else:
		_set_default_control(state, side)


static func _set_locks(state: Dictionary, locks: Dictionary) -> void:
	var previous: Dictionary = state.locks
	var next := locks.duplicate(true)
	var linked := state.handle_mode == EasingCurvePoint.HandleMode.LINKED
	var cleared_linked_linear := false

	for side in [
		EasingCurvePoint.ControlSide.LEFT,
		EasingCurvePoint.ControlSide.RIGHT,
	]:
		var property_name := _control_property(side)
		var newly_locked := (
			not previous.get(property_name, false)
			and next.get(property_name, false)
		)
		if not newly_locked or not _force_linear(state, side):
			continue

		# Lock wins over active Force Linear.
		_set_force_linear_value(state, side, false)
		_set_default_control(state, side)
		cleared_linked_linear = linked

	state.locks = next
	if cleared_linked_linear:
		_set_linked_default(state)


static func _set_lock(state: Dictionary, property_name: StringName, enabled: bool) -> void:
	var locks: Dictionary = state.locks.duplicate(true)
	locks[property_name] = enabled
	if (
		state.handle_mode == EasingCurvePoint.HandleMode.LINKED
		and property_name in [&"left_control_point", &"right_control_point"]
	):
		locks["left_control_point"] = enabled
		locks["right_control_point"] = enabled
	_set_locks(state, locks)


static func _set_control(
	state: Dictionary,
	side: EasingCurvePoint.ControlSide,
	value: Vector2,
) -> void:
	if side == EasingCurvePoint.ControlSide.LEFT:
		state.left_control_point = value
	else:
		state.right_control_point = value


static func _set_default_control(state: Dictionary, side: EasingCurvePoint.ControlSide) -> void:
	_set_control(
		state,
		side,
		state.position + _offset(side) * EasingCurvePoint.DEFAULT_HANDLE_LENGTH,
	)


static func _set_linked_default(state: Dictionary) -> void:
	var linked_default := (
		state.position + Vector2.RIGHT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH
	)
	state.left_control_point = linked_default
	state.right_control_point = linked_default


static func _force_linear(state: Dictionary, side: EasingCurvePoint.ControlSide) -> bool:
	return state.left_force_linear if side == EasingCurvePoint.ControlSide.LEFT else state.right_force_linear


static func _set_force_linear_value(
	state: Dictionary,
	side: EasingCurvePoint.ControlSide,
	value: bool,
) -> void:
	if side == EasingCurvePoint.ControlSide.LEFT:
		state.left_force_linear = value
	else:
		state.right_force_linear = value


static func _side(property_name: StringName) -> EasingCurvePoint.ControlSide:
	return (
		EasingCurvePoint.ControlSide.LEFT
		if property_name in [&"left_control_state", &"left_force_linear"]
		else EasingCurvePoint.ControlSide.RIGHT
	)


static func _control_property(side: EasingCurvePoint.ControlSide) -> StringName:
	return &"left_control_point" if side == EasingCurvePoint.ControlSide.LEFT else &"right_control_point"


static func _lock_property(property_name: StringName) -> StringName:
	match property_name:
		&"position_lock":
			return &"position"
		&"left_control_lock":
			return &"left_control_point"
		&"right_control_lock":
			return &"right_control_point"
	return &""


static func _offset(side: EasingCurvePoint.ControlSide) -> Vector2:
	return Vector2.LEFT if side == EasingCurvePoint.ControlSide.LEFT else Vector2.RIGHT

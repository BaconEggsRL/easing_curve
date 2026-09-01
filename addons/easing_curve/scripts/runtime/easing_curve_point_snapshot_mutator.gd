@tool
extends RefCounted
## Adapts primitive point snapshots to pure point-state transitions.
##
## The Inspector supplies user intent. The transition component owns Handle
## Mode, Control State, Force Linear, and Lock precedence rules.

const POINT_STATE = preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_point_state.gd"
)
const POINT_STATE_TRANSITION = preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_point_state_transition.gd"
)


static func apply(
	snapshot: Dictionary,
	context_point: EasingCurvePoint,
	i: int,
	property_name: StringName,
	value: Variant,
) -> bool:
	var state := _read(snapshot, context_point, i)

	match property_name:
		&"handle_mode":
			var mode := int(value)
			if mode not in EasingCurvePoint.HandleMode.values():
				return false
			state = POINT_STATE_TRANSITION.set_handle_mode(
				state,
				mode,
				POINT_STATE_TRANSITION.Policy.INSPECTOR,
			)

		&"left_control_state", &"right_control_state":
			if not POINT_STATE_TRANSITION.supports_control_state(state):
				return false

			var control_state := int(value)
			if control_state not in EasingCurvePoint.ControlState.values():
				return false
			state = POINT_STATE_TRANSITION.set_control_state(
				state,
				_side(property_name),
				control_state,
			)

		&"toolbar_options_reset":
			state = POINT_STATE_TRANSITION.set_handle_mode(
				state,
				EasingCurvePoint.HandleMode.FREE,
				POINT_STATE_TRANSITION.Policy.INSPECTOR,
			)
			state = POINT_STATE_TRANSITION.set_control_state(
				state,
				EasingCurvePoint.ControlSide.LEFT,
				EasingCurvePoint.ControlState.FREE,
			)
			state = POINT_STATE_TRANSITION.set_control_state(
				state,
				EasingCurvePoint.ControlSide.RIGHT,
				EasingCurvePoint.ControlState.FREE,
			)

		&"left_force_linear", &"right_force_linear":
			state = POINT_STATE_TRANSITION.set_force_linear(
				state,
				_side(property_name),
				bool(value),
				POINT_STATE_TRANSITION.Policy.INSPECTOR,
			)

		&"locked":
			if value is not Dictionary:
				return false
			state = POINT_STATE_TRANSITION.set_locks(
				state,
				value,
				POINT_STATE_TRANSITION.Policy.INSPECTOR,
			)

		&"position_lock", &"left_control_lock", &"right_control_lock":
			state = POINT_STATE_TRANSITION.set_lock(
				state,
				_lock_property(property_name),
				bool(value),
				POINT_STATE_TRANSITION.Policy.INSPECTOR,
			)

		_:
			return false

	_write(snapshot, i, state)
	return true


static func _read(
	snapshot: Dictionary,
	context_point: EasingCurvePoint,
	i: int,
) -> POINT_STATE:
	var state := POINT_STATE.new()
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


static func _write(snapshot: Dictionary, i: int, state: POINT_STATE) -> void:
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


static func _side(property_name: StringName) -> EasingCurvePoint.ControlSide:
	return (
		EasingCurvePoint.ControlSide.LEFT
		if property_name in [&"left_control_state", &"left_force_linear"]
		else EasingCurvePoint.ControlSide.RIGHT
	)


static func _lock_property(property_name: StringName) -> StringName:
	match property_name:
		&"position_lock":
			return &"position"
		&"left_control_lock":
			return &"left_control_point"
		&"right_control_lock":
			return &"right_control_point"
	return &""

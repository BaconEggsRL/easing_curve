@tool
class_name EasingCurvePoint
extends Resource
## Point class for cubic bezier curves.
##
## Contains data for point position, left control and right control handles.
## Supports Free, Linear, Balanced, and Mirrored handle modes.

## Stores the locked state of each Vector2 property and conveys back to the editor plugin.
signal lock_changed(property_name: String, locked: bool)

const POINT_STATE = preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_point_state.gd"
)
const POINT_STATE_TRANSITION = preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_point_state_transition.gd"
)
const DEFAULT_HANDLE_LENGTH := POINT_STATE_TRANSITION.DEFAULT_HANDLE_LENGTH
var handle_display_scale := Vector2.ONE

var _ignore_control_locks_for_position_change := false
var use_display_space_handles := true

# TRUE:
# Free → Balanced: longer handle determines orientation; individual lengths remain unchanged.
# Free → Mirrored: longer handle determines orientation and length.
# Balanced → Mirrored: longer handle determines final mirrored length.
#
# FALSE:
# Balanced: right handle always determines orientation.
# Mirrored: right handle determines both orientation and final length.
#
# If the handles have equal lengths, the right handle wins in either mode.
const LONGEST_HANDLE_WINS := POINT_STATE_TRANSITION.LONGEST_HANDLE_WINS

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

@export var position: Vector2 = Vector2.ZERO: set = set_position

var _left_control_point := Vector2.ZERO
@export var left_control_point: Vector2:
	get:
		return _left_control_point
	set(value):
		set_left_control_point(value)

var _right_control_point := Vector2.ZERO
@export var right_control_point: Vector2:
	get:
		return _right_control_point
	set(value):
		set_right_control_point(value)

@export var handle_mode: HandleMode = HandleMode.FREE: set = set_handle_mode

var _left_force_linear := false
var _right_force_linear := false

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var left_force_linear: bool:
	get:
		return _left_force_linear
	set(value):
		set_left_force_linear(value)

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var right_force_linear: bool:
	get:
		return _right_force_linear
	set(value):
		set_right_force_linear(value)

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var locked: Dictionary[String, bool] = {
	"position": false,
	"left_control_point": false,
	"right_control_point": false
}: set = set_locks


func _set(property: StringName, value: Variant) -> bool:
	if property in ["position", "left_control_point", "right_control_point"]:
		emit_changed()
	return false


func _init(pos: Vector2 = Vector2.ZERO) -> void:
	position = pos
	left_control_point = pos
	right_control_point = pos
	emit_changed()


func _capture_transition_state() -> POINT_STATE:
	var state := POINT_STATE.new()
	state.position = position
	state.left_control_point = _left_control_point
	state.right_control_point = _right_control_point
	state.handle_mode = handle_mode
	state.locks = locked.duplicate(true)
	state.left_force_linear = _left_force_linear
	state.right_force_linear = _right_force_linear
	state.handle_display_scale = handle_display_scale
	state.use_display_space_handles = use_display_space_handles
	return state


func is_lock_active(property_name: StringName) -> bool:
	if property_name == &"position":
		return locked.get(String(property_name), false)

	if handle_mode not in [
		HandleMode.FREE,
		HandleMode.LINKED,
	]:
		return false

	return locked.get(String(property_name), false)


func is_lockable_property(property_name: StringName) -> bool:
	return locked.has(String(property_name))


func is_position_input_editable(property_name: String) -> bool:
	if not is_lockable_property(StringName(property_name)):
		return true

	if property_name == "position":
		return not is_lock_active(&"position")

	if property_name == "left_control_point":
		return is_control_position_editable(ControlSide.LEFT)

	if property_name == "right_control_point":
		return is_control_position_editable(ControlSide.RIGHT)

	return true


func is_control_position_editable(side: ControlSide) -> bool:
	var property_name := (
		&"left_control_point"
		if side == ControlSide.LEFT
		else &"right_control_point"
	)
	if handle_mode == HandleMode.LINEAR:
		return not bool(locked.get(String(property_name), false))

	return (
		not is_lock_active(property_name)
		and not is_control_force_linear_active(side)
	)


func set_locked(property_name: String, toggled_on: bool) -> void:
	if not is_lockable_property(StringName(property_name)):
		return

	if locked.get(property_name, false) == toggled_on:
		return

	var state := POINT_STATE_TRANSITION.set_lock(
		_capture_transition_state(),
		StringName(property_name),
		toggled_on,
		POINT_STATE_TRANSITION.Policy.LIVE,
	)
	locked[property_name] = state.locks[property_name]

	lock_changed.emit(property_name, toggled_on)
	emit_changed()


func set_locks(value: Dictionary[String, bool]) -> void:
	if locked == value:
		return

	var state := POINT_STATE_TRANSITION.set_locks(
		_capture_transition_state(),
		value,
		POINT_STATE_TRANSITION.Policy.LIVE,
	)
	locked = state.locks

	emit_changed()


func set_position(value: Vector2) -> void:
	if not value.is_finite():
		return

	if position == value:
		return

	var state := POINT_STATE_TRANSITION.set_position(
		_capture_transition_state(),
		value,
		_ignore_control_locks_for_position_change,
	)
	_left_control_point = state.left_control_point
	_right_control_point = state.right_control_point
	position = state.position

	emit_changed()


func move_horizontally(delta_x: float, ignore_control_locks: bool = false) -> void:
	if is_zero_approx(delta_x):
		return

	var target_position := Vector2(position.x + delta_x, position.y)
	if not target_position.is_finite():
		return

	if not ignore_control_locks:
		set_position(target_position)
		return

	var previous_ignore_control_locks := _ignore_control_locks_for_position_change
	_ignore_control_locks_for_position_change = ignore_control_locks
	set_position(target_position)
	_ignore_control_locks_for_position_change = previous_ignore_control_locks


func set_left_control_point(value: Vector2) -> void:
	_set_control_point(ControlSide.LEFT, value)


func set_right_control_point(value: Vector2) -> void:
	_set_control_point(ControlSide.RIGHT, value)


func get_control_point_pair(
	side: ControlSide,
	value: Vector2,
) -> Dictionary:
	return POINT_STATE_TRANSITION.get_control_point_pair(
		_capture_transition_state(),
		side,
		value,
	)


func _set_control_point(
	side: ControlSide,
	value: Vector2,
) -> void:
	if not value.is_finite():
		print(
			"CONTROL REJECTED - INPUT NON-FINITE",
			" side=", side,
			" value=", value,
		)
		return

	if is_control_force_linear_active(side):
		value = position

	var pair := get_control_point_pair(side, value)

	var left: Vector2 = pair["left"]
	var right: Vector2 = pair["right"]

	if not left.is_finite() or not right.is_finite():
		print(
			"CONTROL REJECTED - GENERATED NON-FINITE",
			"\n  mode: ", HandleMode.keys()[handle_mode],
			"\n  side: ", ControlSide.keys()[side],
			"\n  input: ", value,
			"\n  current left: ", _left_control_point,
			"\n  current right: ", _right_control_point,
			"\n  generated left: ", left,
			"\n  generated right: ", right,
		)
		return

	if (
		_left_control_point == left
		and _right_control_point == right
	):
		return

	_left_control_point = left
	_right_control_point = right

	emit_changed()


func set_handle_mode(value: HandleMode) -> void:
	if handle_mode == value:
		return

	var state := POINT_STATE_TRANSITION.set_handle_mode(
		_capture_transition_state(),
		value,
		POINT_STATE_TRANSITION.Policy.LIVE,
	)
	handle_mode = state.handle_mode
	_left_control_point = state.left_control_point
	_right_control_point = state.right_control_point
	_left_force_linear = state.left_force_linear
	_right_force_linear = state.right_force_linear

	emit_changed()


#Any -> Linear
	#collapse both handles
#
#Linear -> Free
	#create default horizontal handles
#
#Linear -> Balanced
	#create default horizontal handles
#
#Linear -> Mirrored
	#create default horizontal mirrored handles
#
#Free -> Balanced
	#immediately align opposite rotations
	#preserve each handle's current length
#
#Free -> Mirrored
	#immediately mirror angle + length
#
#Balanced -> Free
	#preserve geometry
#
#Balanced -> Mirrored
	#immediately equalize lengths
#
#Mirrored -> Free
	#preserve geometry
#
#Mirrored -> Balanced
	#preserve geometry
func get_handles_for_mode_change(value: HandleMode) -> Dictionary:
	return POINT_STATE_TRANSITION.get_handles_for_mode_change(
		_capture_transition_state(),
		value,
	)


func is_control_forced_linear(side: ControlSide) -> bool:
	if handle_mode == HandleMode.LINKED:
		return left_force_linear or right_force_linear
	return (
		left_force_linear
		if side == ControlSide.LEFT
		else right_force_linear
	)


func supports_control_state() -> bool:
	return handle_mode in [
		HandleMode.FREE,
		HandleMode.LINKED,
	]


func is_control_force_linear_active(side: ControlSide) -> bool:
	return (
		supports_control_state()
		and is_control_forced_linear(side)
	)


func set_left_force_linear(value: bool) -> void:
	_set_control_force_linear(ControlSide.LEFT, value)


func set_right_force_linear(value: bool) -> void:
	_set_control_force_linear(ControlSide.RIGHT, value)


func _set_control_force_linear(
	side: ControlSide,
	enabled: bool,
) -> void:
	if is_control_forced_linear(side) == enabled:
		return

	var state := POINT_STATE_TRANSITION.set_force_linear(
		_capture_transition_state(),
		side,
		enabled,
		POINT_STATE_TRANSITION.Policy.LIVE,
	)
	_left_force_linear = state.left_force_linear
	_right_force_linear = state.right_force_linear
	_left_control_point = state.left_control_point
	_right_control_point = state.right_control_point

	emit_changed()


func set_force_linear_state(
	left: bool,
	right: bool,
	apply_geometry := true,
) -> void:
	var state := POINT_STATE_TRANSITION.set_force_linear_state(
		_capture_transition_state(),
		left,
		right,
		apply_geometry,
	)
	_left_force_linear = state.left_force_linear
	_right_force_linear = state.right_force_linear
	_left_control_point = state.left_control_point
	_right_control_point = state.right_control_point

	emit_changed()


func set_handle_display_scale(value: Vector2) -> void:
	if not value.is_finite():
		return

	if is_zero_approx(value.x) or is_zero_approx(value.y):
		return

	handle_display_scale = value.abs()

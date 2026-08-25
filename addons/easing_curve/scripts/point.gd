@tool
class_name EasingCurvePoint
extends Resource
## Point class for cubic bezier curves.
##
## Contains data for point position, left control and right control handles.
## Supports Free, Linear, Balanced, and Mirrored handle modes.

## Stores the locked state of each Vector2 property and conveys back to the editor plugin.
signal lock_changed(property_name: String, locked: bool)

const DEFAULT_HANDLE_LENGTH := 0.1

var use_display_space_handles := true
var handle_display_scale := Vector2.ONE

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

@export var position: Vector2 = Vector2.ZERO: set = set_position

var _left_control_point := Vector2.ZERO
var _right_control_point := Vector2.ZERO
var _ignore_control_locks_for_position_change := false

@export var left_control_point: Vector2:
	get:
		return _left_control_point
	set(value):
		set_left_control_point(value)

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

## Stores editor-only Vector2 input sliders outside the resource property graph.
static var _input_controls: Dictionary[int, Dictionary] = {}

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


func is_lock_active(property_name: StringName) -> bool:
	if property_name == &"position":
		return locked.get(String(property_name), false)

	if handle_mode not in [
		HandleMode.FREE,
		HandleMode.LINKED,
	]:
		return false

	return locked.get(String(property_name), false)


func _update_input_lock_state(property_name: String) -> void:
	var read_only := is_lock_active(StringName(property_name))

	var x_input := _get_input(property_name, "x")
	var y_input := _get_input(property_name, "y")

	if x_input:
		x_input.read_only = read_only

	if y_input:
		y_input.read_only = read_only


func set_locked(property_name: String, toggled_on: bool) -> void:
	if locked.get(property_name, false) == toggled_on:
		return

	locked[property_name] = toggled_on
	_update_input_lock_state(property_name)

	lock_changed.emit(property_name, toggled_on)
	emit_changed()


func set_locks(value: Dictionary[String, bool]) -> void:
	if locked == value:
		return

	locked = value

	_update_input_lock_state("position")
	_update_input_lock_state("left_control_point")
	_update_input_lock_state("right_control_point")

	emit_changed()


func set_position(value: Vector2) -> void:
	if not value.is_finite():
		return

	if position == value:
		return

	var delta := value - position

	var left_locked := (
		is_lock_active("left_control_point")
		and not _ignore_control_locks_for_position_change
	)
	var right_locked := (
		is_lock_active("right_control_point")
		and not _ignore_control_locks_for_position_change
	)

	if not left_locked:
		_left_control_point += delta

	if not right_locked:
		_right_control_point += delta

	position = value

	_set_input_value("position", "x", value.x)
	_set_input_value("position", "y", value.y)
	_update_control_point_inputs("left_control_point")
	_update_control_point_inputs("right_control_point")

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


func _update_control_point_inputs(property_name: String) -> void:
	var value := (
		_left_control_point
		if property_name == "left_control_point"
		else _right_control_point
	)
	_set_input_value(property_name, "x", value.x)
	_set_input_value(property_name, "y", value.y)


func get_control_point_pair(
	side: ControlSide,
	value: Vector2,
) -> Dictionary:
	var left := _left_control_point
	var right := _right_control_point

	if handle_mode == HandleMode.LINEAR:
		return {
			"left": position,
			"right": position,
		}

	if side == ControlSide.LEFT:
		left = value
	else:
		right = value

	match handle_mode:

		HandleMode.BALANCED:
			var opposite := (
				_right_control_point
				if side == ControlSide.LEFT
				else _left_control_point
			)

			var moved_delta := _to_handle_space(
				value - position
			)

			var opposite_delta := _to_handle_space(
				opposite - position
			)

			var opposite_length := _get_safe_length(
				opposite_delta,
				Vector2.ZERO,
			)

			var direction := _get_safe_direction(
				-moved_delta,
			)

			var balanced_delta := _from_handle_space(
				direction * opposite_length
			)

			var balanced := position + balanced_delta

			if not balanced.is_finite():
				print(
					"BALANCED OVERFLOW",
					"\n  dragged value: ", value,
					"\n  opposite: ", opposite,
					"\n  display-space handles: ", use_display_space_handles,
					"\n  display scale: ", handle_display_scale,
					"\n  result: ", balanced,
				)

			if side == ControlSide.LEFT:
				right = balanced
			else:
				left = balanced


		HandleMode.MIRRORED:
			var moved_delta := _to_handle_space(
				value - position
			)

			var mirrored := (
				position
				+ _from_handle_space(-moved_delta)
			)

			if not mirrored.is_finite():
				print(
					"MIRRORED OVERFLOW",
					"\n  position: ", position,
					"\n  dragged value: ", value,
					"\n  mirrored: ", mirrored,
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

	_update_control_point_inputs("left_control_point")
	_update_control_point_inputs("right_control_point")

	emit_changed()


func set_input_control(property_name: String, axis: String, control: Object) -> void:
	var id := get_instance_id()
	if not _input_controls.has(id):
		_input_controls[id] = {}
	_input_controls[id][property_name + axis] = weakref(control)


func _get_input(property_name: String, axis: String) -> Object:
	var input_ref: WeakRef = _input_controls.get(get_instance_id(), {}).get(property_name + axis)
	return input_ref.get_ref() if input_ref else null


func _set_input_value(property_name: String, axis: String, value: float) -> void:
	var input := _get_input(property_name, axis)
	if input != null and input.has_method("set_value_no_signal"):
		input.call("set_value_no_signal", value)


func set_handle_mode(value: HandleMode) -> void:
	if handle_mode == value:
		return

	var handles := get_handles_for_mode_change(value)
	handle_mode = value
	_left_control_point = handles["left"]
	_right_control_point = handles["right"]

	_apply_free_force_linear_state()

	_update_control_point_inputs("left_control_point")
	_update_control_point_inputs("right_control_point")

	_update_input_lock_state("position")
	_update_input_lock_state("left_control_point")
	_update_input_lock_state("right_control_point")

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
	var left := left_control_point
	var right := right_control_point

	if value == HandleMode.LINEAR:
		return {
			"left": position,
			"right": position,
		}

	if handle_mode == HandleMode.LINEAR:
		left = position + Vector2.LEFT * DEFAULT_HANDLE_LENGTH
		right = position + Vector2.RIGHT * DEFAULT_HANDLE_LENGTH

		if value == HandleMode.LINKED:
			var linked := _get_linked_handle_position(left, right)
			return {
				"left": linked,
				"right": linked,
			}

		return {
			"left": left,
			"right": right,
		}

	match value:
		HandleMode.FREE:
			pass

		HandleMode.BALANCED:
			var left_delta := _to_handle_space(
				left - position
			)
			var right_delta := _to_handle_space(
				right - position
			)

			var left_length := _get_safe_length(
				left_delta,
				Vector2.ZERO,
			)
			var right_length := _get_safe_length(
				right_delta,
				Vector2.ZERO,
			)

			var use_left := (
				LONGEST_HANDLE_WINS
				and left_length > right_length
			)

			var direction := (
				-left_delta
				if use_left
				else right_delta
			)

			direction = _get_safe_direction(direction)

			left = (
				position
				+ _from_handle_space(
					-direction * left_length
				)
			)

			right = (
				position
				+ _from_handle_space(
					direction * right_length
				)
			)

		HandleMode.MIRRORED:
			var left_length := _get_safe_length(
				left,
				position,
			)
			var right_length := _get_safe_length(
				right,
				position,
			)

			var use_left := (
				LONGEST_HANDLE_WINS
				and left_length > right_length
			)

			var direction := (
				position - left
				if use_left
				else right - position
			)

			direction = _get_safe_direction(direction)

			var length := (
				maxf(left_length, right_length)
				if LONGEST_HANDLE_WINS
				else right_length
			)

			if is_zero_approx(length):
				length = DEFAULT_HANDLE_LENGTH

			left = position - direction * length
			right = position + direction * length


		HandleMode.LINKED:
			var linked := _get_linked_handle_position(
				left,
				right,
			)

			left = linked
			right = linked


	return {
		"left": left,
		"right": right,
	}



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

	if side == ControlSide.LEFT:
		_left_force_linear = enabled
	else:
		_right_force_linear = enabled

	if handle_mode == HandleMode.LINKED:
		if _left_force_linear or _right_force_linear:
			_set_control_point_direct(ControlSide.LEFT, position)
			_set_control_point_direct(ControlSide.RIGHT, position)
		else:
			var linked_default := (
				position + Vector2.RIGHT * DEFAULT_HANDLE_LENGTH
			)
			_set_control_point_direct(ControlSide.LEFT, linked_default)
			_set_control_point_direct(ControlSide.RIGHT, linked_default)

	elif handle_mode == HandleMode.FREE:
		if enabled:
			_set_control_point_direct(side, position)
		else:
			_initialize_default_handle(side)

	emit_changed()


func _set_control_point_direct(
	side: ControlSide,
	value: Vector2,
) -> void:
	if side == ControlSide.LEFT:
		_left_control_point = value
		_update_control_point_inputs("left_control_point")
	else:
		_right_control_point = value
		_update_control_point_inputs("right_control_point")


func _initialize_default_handle(side: ControlSide) -> void:
	var offset := (
		Vector2.LEFT
		if side == ControlSide.LEFT
		else Vector2.RIGHT
	)

	_set_control_point_direct(
		side,
		position + offset * DEFAULT_HANDLE_LENGTH,
	)


func _initialize_default_handles() -> void:
	_initialize_default_handle(ControlSide.LEFT)
	_initialize_default_handle(ControlSide.RIGHT)


func _apply_free_force_linear_state() -> void:
	if not supports_control_state():
		return

	if handle_mode == HandleMode.LINKED:
		if _left_force_linear or _right_force_linear:
			_set_control_point_direct(ControlSide.LEFT, position)
			_set_control_point_direct(ControlSide.RIGHT, position)
		return

	if _left_force_linear:
		_set_control_point_direct(ControlSide.LEFT, position)

	if _right_force_linear:
		_set_control_point_direct(ControlSide.RIGHT, position)


func set_force_linear_state(
	left: bool,
	right: bool,
	apply_geometry := true,
) -> void:
	_left_force_linear = left
	_right_force_linear = right

	if apply_geometry:
		if handle_mode == HandleMode.LINKED and not left and not right:
			var linked_default := (
				position + Vector2.RIGHT * DEFAULT_HANDLE_LENGTH
			)
			_set_control_point_direct(ControlSide.LEFT, linked_default)
			_set_control_point_direct(ControlSide.RIGHT, linked_default)
		else:
			_apply_free_force_linear_state()

	emit_changed()


func _get_linked_handle_position(
	left: Vector2,
	right: Vector2,
) -> Vector2:
	var left_length := _get_safe_length(
		left,
		position,
	)
	var right_length := _get_safe_length(
		right,
		position,
	)

	var use_left := (
		LONGEST_HANDLE_WINS
		and left_length > right_length
	)

	# Right wins when lengths are equal, or whenever
	# LONGEST_HANDLE_WINS is false.
	return left if use_left else right


func _get_safe_direction(
	direction: Vector2,
	fallback := Vector2.RIGHT,
) -> Vector2:
	if not direction.is_finite():
		return fallback

	var max_component := maxf(
		absf(direction.x),
		absf(direction.y),
	)

	if is_zero_approx(max_component):
		return fallback

	var scaled := direction / max_component
	var scaled_length := sqrt(
		scaled.x * scaled.x
		+ scaled.y * scaled.y
	)

	if (
		not is_finite(scaled_length)
		or is_zero_approx(scaled_length)
	):
		return fallback

	return scaled / scaled_length


func _get_safe_length(from: Vector2, to: Vector2) -> float:
	var delta := from - to

	if not delta.is_finite():
		return 0.0

	var max_component := maxf(
		absf(delta.x),
		absf(delta.y),
	)

	if is_zero_approx(max_component):
		return 0.0

	var scaled := delta / max_component

	return (
		max_component
		* sqrt(
			scaled.x * scaled.x
			+ scaled.y * scaled.y
		)
	)


func set_handle_display_scale(value: Vector2) -> void:
	if not value.is_finite():
		return

	if is_zero_approx(value.x) or is_zero_approx(value.y):
		return

	handle_display_scale = value.abs()


func _to_handle_space(delta: Vector2) -> Vector2:
	if not use_display_space_handles:
		return delta

	return delta * handle_display_scale


func _from_handle_space(delta: Vector2) -> Vector2:
	if not use_display_space_handles:
		return delta

	return delta / handle_display_scale

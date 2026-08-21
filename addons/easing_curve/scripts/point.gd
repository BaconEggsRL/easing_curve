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

@export var position: Vector2 = Vector2.ZERO: set = set_position

var _left_control_point := Vector2.ZERO
var _right_control_point := Vector2.ZERO

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
	if position == value:
		return

	var delta := value - position

	var left_locked := is_lock_active("left_control_point")
	var right_locked := is_lock_active("right_control_point")

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
			var opposite_length := opposite.distance_to(position)
			var direction := position - value

			if not direction.is_zero_approx():
				var balanced := (
					position
					+ direction.normalized() * opposite_length
				)

				if side == ControlSide.LEFT:
					right = balanced
				else:
					left = balanced

		HandleMode.MIRRORED:
			var mirrored := position + (position - value)

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
	if is_control_force_linear_active(side):
		value = position

	var pair := get_control_point_pair(side, value)

	var left: Vector2 = pair["left"]
	var right: Vector2 = pair["right"]

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

	var previous_mode := handle_mode
	handle_mode = value

	if handle_mode == HandleMode.LINEAR:
		_left_control_point = position
		_right_control_point = position

	elif previous_mode == HandleMode.LINEAR:
		_initialize_default_handles()

		if handle_mode == HandleMode.LINKED:
			var linked := _get_linked_handle_position(
				_left_control_point,
				_right_control_point,
			)
			_left_control_point = linked
			_right_control_point = linked

	elif handle_mode == HandleMode.LINKED:
		var linked := _get_linked_handle_position(
			_left_control_point,
			_right_control_point,
		)
		_left_control_point = linked
		_right_control_point = linked

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
			var left_length := left.distance_to(position)
			var right_length := right.distance_to(position)

			var use_left := (
				LONGEST_HANDLE_WINS
				and left_length > right_length
			)

			var direction := (
				position - left
				if use_left
				else right - position
			)

			if direction.is_zero_approx():
				direction = Vector2.RIGHT

			direction = direction.normalized()

			left = position - direction * left_length
			right = position + direction * right_length

		HandleMode.MIRRORED:
			var left_length := left.distance_to(position)
			var right_length := right.distance_to(position)

			var use_left := (
				LONGEST_HANDLE_WINS
				and left_length > right_length
			)

			var direction := (
				position - left
				if use_left
				else right - position
			)

			if direction.is_zero_approx():
				direction = Vector2.RIGHT

			direction = direction.normalized()

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
	return (
		left_force_linear
		if side == ControlSide.LEFT
		else right_force_linear
	)


func is_control_force_linear_active(side: ControlSide) -> bool:
	return (
		handle_mode == HandleMode.FREE
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

	if handle_mode == HandleMode.FREE:
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
	if handle_mode != HandleMode.FREE:
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
		_apply_free_force_linear_state()

	emit_changed()


func _get_linked_handle_position(
	left: Vector2,
	right: Vector2,
) -> Vector2:
	var left_length := left.distance_to(position)
	var right_length := right.distance_to(position)

	var use_left := (
		LONGEST_HANDLE_WINS
		and left_length > right_length
	)

	# Right wins when lengths are equal, or whenever
	# LONGEST_HANDLE_WINS is false.
	return left if use_left else right

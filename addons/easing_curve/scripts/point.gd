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

enum HandleMode {
	FREE,
	LINEAR,
	BALANCED,
	MIRRORED,
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


func set_locked(property_name: String, toggled_on: bool) -> void:
	if locked.get(property_name, false) == toggled_on:
		return
	var x_input = _get_input(property_name, "x")
	var y_input = _get_input(property_name, "y")
	if x_input:
		x_input.read_only = toggled_on
	if y_input:
		y_input.read_only = toggled_on
	locked[property_name] = toggled_on
	lock_changed.emit(property_name, toggled_on)
	emit_changed()


func set_locks(value: Dictionary[String, bool]) -> void:
	if locked == value:
		return
	locked = value
	emit_changed()


func set_position(value: Vector2) -> void:
	if position == value:
		return

	var delta := value - position

	_left_control_point += delta
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

	return {
		"left": left,
		"right": right,
	}


func _set_control_point(
	side: ControlSide,
	value: Vector2,
) -> void:
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

	_update_control_point_inputs("left_control_point")
	_update_control_point_inputs("right_control_point")

	emit_changed()


func _initialize_default_handles() -> void:
	_left_control_point = (
		position
		+ Vector2.LEFT * DEFAULT_HANDLE_LENGTH
	)
	_right_control_point = (
		position
		+ Vector2.RIGHT * DEFAULT_HANDLE_LENGTH
	)


func get_handles_for_mode_change(value: HandleMode) -> Dictionary:
	if (
		handle_mode == HandleMode.LINEAR
		and value != HandleMode.LINEAR
	):
		return {
			"left": position + Vector2.LEFT * DEFAULT_HANDLE_LENGTH,
			"right": position + Vector2.RIGHT * DEFAULT_HANDLE_LENGTH,
		}

	if value == HandleMode.LINEAR:
		return {
			"left": position,
			"right": position,
		}

	return {
		"left": left_control_point,
		"right": right_control_point,
	}

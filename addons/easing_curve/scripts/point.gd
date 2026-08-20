@tool
class_name EasingCurvePoint
extends Resource
## Point class for cubic bezier curves.
##
## Contains data for point position, left control and right control handles.
## Supports Free, Linear, Balanced, and Mirrored handle modes.

## Stores the locked state of each Vector2 property and conveys back to the editor plugin.
signal lock_changed(property_name: String, locked: bool)

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


func _set_control_point(side: ControlSide, value: Vector2) -> void:
	if handle_mode == HandleMode.LINEAR:
		value = position

	var current := (
		_left_control_point
		if side == ControlSide.LEFT
		else _right_control_point
	)

	if current == value:
		return

	if side == ControlSide.LEFT:
		_left_control_point = value
	else:
		_right_control_point = value

	match handle_mode:
		HandleMode.BALANCED:
			_set_balanced_opposite(side, value)

		HandleMode.MIRRORED:
			_set_mirrored_opposite(side, value)

	_update_control_point_inputs("left_control_point")
	_update_control_point_inputs("right_control_point")

	emit_changed()


func _set_balanced_opposite(
	side: ControlSide,
	value: Vector2
) -> void:
	var opposite := (
		_right_control_point
		if side == ControlSide.LEFT
		else _left_control_point
	)

	var opposite_length := opposite.distance_to(position)
	var direction := position - value

	if direction.is_zero_approx():
		return

	var balanced_value := (
		position
		+ direction.normalized() * opposite_length
	)

	if side == ControlSide.LEFT:
		_right_control_point = balanced_value
	else:
		_left_control_point = balanced_value


func _set_mirrored_opposite(
	side: ControlSide,
	value: Vector2
) -> void:
	var mirrored_value := position + (position - value)

	if side == ControlSide.LEFT:
		_right_control_point = mirrored_value
	else:
		_left_control_point = mirrored_value



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

	handle_mode = value

	if handle_mode == HandleMode.LINEAR:
		_left_control_point = position
		_right_control_point = position

		_update_control_point_inputs("left_control_point")
		_update_control_point_inputs("right_control_point")

	emit_changed()

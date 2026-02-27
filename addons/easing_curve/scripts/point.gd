@tool
class_name Point
extends Resource
## Point class for cubic bezier curves.
##
## Contains data for point position, left control and right control handles.
## Future state will also include handle modes for each point (free, linear, etc.)

## Stores the locked state of each Vector2 property and conveys back to the editor plugin.
signal lock_changed(property_name: String, locked: bool)

@export var position: Vector2 = Vector2.ZERO: set = set_position
@export var left_control_point: Vector2 = Vector2.ZERO: set = set_left_control_point
@export var right_control_point: Vector2 = Vector2.ZERO: set = set_right_control_point

## Stores references to the editor plugin Vector2 input sliders.
var input = {
	"position":
		{"x": null, "y": null},
	"left_control_point":
		{"x": null, "y": null},
	"right_control_point":
		{"x": null, "y": null}
}

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var locked:Dictionary[String, bool] = {
	"position": false,
	"left_control_point": false,
	"right_control_point": false
}


func _set(property: StringName, value: Variant) -> bool:
	if property in ["position", "left_control_point", "right_control_point"]:
		emit_changed()
	return false


func _init(pos: Vector2 = Vector2.ZERO) -> void:
	position = pos
	left_control_point = pos
	right_control_point = pos
	emit_changed()


func set_locked(property_name: String, toggled_on:bool) -> void:
	var x_input = input[property_name].x
	var y_input = input[property_name].y
	if x_input:
		x_input.read_only = toggled_on
	if y_input:
		y_input.read_only = toggled_on
	locked[property_name] = toggled_on
	lock_changed.emit(property_name, toggled_on)
	emit_changed()


func set_position(value) -> void:
	var x_input = input["position"].x
	var y_input = input["position"].y
	if x_input:
		x_input.value = value.x
	if y_input:
		y_input.value = value.y
	position = value
	emit_changed()


func set_left_control_point(value) -> void:
	var x_input = input["left_control_point"].x
	var y_input = input["left_control_point"].y
	if x_input:
		x_input.value = value.x
	if y_input:
		y_input.value = value.y
	left_control_point = value
	emit_changed()


func set_right_control_point(value) -> void:
	var x_input = input["right_control_point"].x
	var y_input = input["right_control_point"].y
	if x_input:
		x_input.value = value.x
	if y_input:
		y_input.value = value.y
	right_control_point = value
	emit_changed()

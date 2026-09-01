@tool
class_name EasingCurveDragHandle
extends TextureRect
## Drag handle used to re-order points in a list.
##
## This is used by the Inspector point-list controller when generating the point list.

var index: int
var point_panel: PanelContainer
var point_list: VBoxContainer


func _ready():
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered():
	mouse_default_cursor_shape = Control.CURSOR_DRAG


func _on_mouse_exited():
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _get_drag_data(at_position: Vector2) -> Variant:
	var drag_data = { "index": index, "point": point_panel }
	var preview = TextureRect.new()
	preview.texture = texture
	preview.scale = Vector2(1.2, 1.2)
	set_drag_preview(preview)
	return drag_data


func _can_drop_data(position: Vector2, data) -> bool:
	return false


func _drop_data(position: Vector2, data) -> void:
	pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		if point_list != null and point_list.has_method("clear_drop_index"):
			point_list.call("clear_drop_index")

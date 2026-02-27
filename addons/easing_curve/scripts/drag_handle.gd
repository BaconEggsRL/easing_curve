@tool
class_name DragHandle
extends TextureRect
## Drag handle used to re-order points in a list.
##
## This is used in the EasingCurve editor inspector plugin when generating the point list.
## Contains reference for the curve, editor, and undo redo.

var index: int
var point_panel: PanelContainer
var point_list: VBoxContainer
var curve: EasingCurve
var easing_curve_editor: EasingCurveEditor
var editor_undo_redo: EditorUndoRedoManager


func _ready():
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered():
	# print("enter")
	mouse_default_cursor_shape = Control.CURSOR_DRAG


func _on_mouse_exited():
	# print("exit")
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _get_drag_data(at_position: Vector2) -> Variant:
	var drag_data = { "index": index, "point": point_panel }
	var preview = TextureRect.new()
	preview.texture = texture
	preview.scale = Vector2(1.2, 1.2)
	set_drag_preview(preview)
	return drag_data


func _can_drop_data(position: Vector2, data) -> bool:
	return data.has("index") and data.has("point")


func _drop_data(position: Vector2, data) -> void:
	if not _can_drop_data(position, data):
		return
	var from_index = data["index"]
	var to_index = index
	if from_index != to_index:
		editor_undo_redo.create_action("Move point")
		editor_undo_redo.add_do_method(curve, "swap_points", from_index, to_index)
		editor_undo_redo.add_undo_method(curve, "swap_points", to_index, from_index)
		editor_undo_redo.commit_action()

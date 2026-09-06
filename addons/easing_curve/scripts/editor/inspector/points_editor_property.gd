@tool
extends EditorProperty

func set_content(content: Control) -> void:
	add_child(content)
	_hide_property_chrome()


func _ready() -> void:
	_hide_property_chrome()


func _update_property() -> void:
	_hide_property_chrome()


func publish_current_value() -> void:
	var object := get_edited_object()
	var property_name := get_edited_property()
	if object == null or property_name.is_empty():
		return
	var current: Node = self
	while current != null and current is not EditorInspector:
		current = current.get_parent()
	if current is EditorInspector:
		current.call(&"_edit_request_change", object, String(property_name))


func _hide_property_chrome() -> void:
	label = ""
	draw_label = false
	draw_background = false
	selectable = false
	name_split_ratio = 0.0
	tooltip_text = ""
	var property_name := get_edited_property()
	if not property_name.is_empty():
		property_can_revert_changed.emit(property_name, false)

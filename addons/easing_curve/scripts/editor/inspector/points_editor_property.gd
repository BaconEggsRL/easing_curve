@tool
extends EditorProperty


func set_content(content: Control) -> void:
	add_child(content)
	_hide_property_chrome()


func _ready() -> void:
	_hide_property_chrome()


func _update_property() -> void:
	_hide_property_chrome()


func _hide_property_chrome() -> void:
	label = ""
	draw_label = false
	draw_background = false
	selectable = false
	name_split_ratio = 0.0
	tooltip_text = ""

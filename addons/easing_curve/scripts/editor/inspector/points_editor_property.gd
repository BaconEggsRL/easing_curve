@tool
extends EditorProperty

const SNAPSHOT_PUBLICATION_META := &"_easing_curve_publishing_editor_snapshot"


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
	if object.has_method(&"_dont_undo_redo"):
		object.set_meta(SNAPSHOT_PUBLICATION_META, true)
		emit_changed(property_name, object.get(property_name), "", false)
		object.remove_meta(SNAPSHOT_PUBLICATION_META)
		return
	var current: Node = self
	while current != null and current is not EditorInspector:
		current = current.get_parent()
	if current is EditorInspector:
		current.call(&"_edit_request_change", object, "")
		current.emit_signal(&"property_edited", String(property_name))


func _hide_property_chrome() -> void:
	label = ""
	draw_label = false
	draw_background = false
	selectable = false
	name_split_ratio = 0.0
	tooltip_text = ""

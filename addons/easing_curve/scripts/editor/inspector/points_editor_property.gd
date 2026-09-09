@tool
extends EditorProperty

class ContentSlot extends Container:
	var chrome_width := 0.0

	func _get_minimum_size() -> Vector2:
		if get_child_count() == 0:
			return Vector2.ZERO
		var content := get_child(0) as Control
		if not content.visible:
			return Vector2.ZERO
		var minimum := content.get_combined_minimum_size()
		# EditorProperty places unlabeled content one physical pixel from its edge.
		minimum.x = maxf(0.0, minimum.x + 1.0 - chrome_width)
		return minimum

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN and get_child_count() > 0:
			fit_child_in_rect(get_child(0), Rect2(Vector2.ZERO, size))


var _content_slot: ContentSlot
var _chrome_update_queued := false


func set_content(content: Control) -> void:
	_content_slot = ContentSlot.new()
	_content_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_slot.add_child(content)
	add_child(_content_slot)
	_hide_property_chrome()
	_queue_chrome_width_update()


func _ready() -> void:
	_hide_property_chrome()
	minimum_size_changed.connect(_queue_chrome_width_update)
	_queue_chrome_width_update()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_queue_chrome_width_update()


func _queue_chrome_width_update() -> void:
	if _chrome_update_queued or not is_instance_valid(_content_slot):
		return
	_chrome_update_queued = true
	_update_chrome_width.call_deferred()


func _update_chrome_width() -> void:
	_chrome_update_queued = false
	if not is_instance_valid(_content_slot):
		return
	# EditorProperty ignores the script minimum-size virtual. Measure its native
	# horizontal reservation, keeping its vertical sizing and layout untouched.
	var chrome_width := maxf(0.0, get_minimum_size().x - _content_slot.get_combined_minimum_size().x)
	if not is_equal_approx(_content_slot.chrome_width, chrome_width):
		_content_slot.chrome_width = chrome_width
		_content_slot.update_minimum_size()


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

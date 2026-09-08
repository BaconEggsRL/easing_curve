@tool
extends RefCounted
## Owns point-property clipboard formatting, validation, and menu actions.
##
## Selection, mutation policy, transactions, and Undo/Redo remain on the
## Inspector side of the explicit apply callback.

const MENU_COPY_VALUE := 0
const MENU_PASTE_VALUE := 1
const MENU_COPY_PATH := 2
const BackendFactory := preload("res://addons/easing_curve/scripts/editor/backend/curve_editor_backend_factory.gd")


static func property_path(
	point_index: int,
	property_name: StringName,
) -> String:
	return "points/%d/%s" % [
		point_index,
		String(property_name),
	]


func copy_value(
	curve: EasingCurve,
	point_index: int,
	property_name: StringName,
) -> void:
	copy_point_value(curve, _point_at(curve, point_index), property_name)


func paste_value(
	curve: EasingCurve,
	point_index: int,
	property_name: StringName,
	apply_callback: Callable,
) -> void:
	paste_point_value(
		curve,
		_point_at(curve, point_index),
		property_name,
		apply_callback,
	)


func apply_value(
	curve: EasingCurve,
	point_index: int,
	property_name: StringName,
	value: Variant,
	apply_callback: Callable,
) -> void:
	apply_point_value(
		curve,
		_point_at(curve, point_index),
		property_name,
		value,
		apply_callback,
	)


func copy_point_value(
	curve_resource: Resource,
	point: Resource,
	property_name: StringName,
) -> void:
	if not _can_access_point_value(curve_resource, point, property_name):
		return
	var value: Variant = point.get(property_name)
	var backend := BackendFactory.create(curve_resource)
	if value is Vector2 and backend != null and backend.get_backend_id() == &"native":
		value = backend.curve_to_display_position(value)
	DisplayServer.clipboard_set(var_to_str(value))


func paste_point_value(
	curve_resource: Resource,
	point: Resource,
	property_name: StringName,
	apply_callback: Callable,
) -> void:
	apply_point_value(
		curve_resource,
		point,
		property_name,
		parse_point_value(DisplayServer.clipboard_get(), property_name),
		apply_callback,
	)


func apply_point_value(
	curve_resource: Resource,
	point: Resource,
	property_name: StringName,
	value: Variant,
	apply_callback: Callable,
) -> void:
	var point_index := _point_index(curve_resource, point)
	if (
		point_index < 0
		or not is_value_compatible(property_name, value)
		or not apply_callback.is_valid()
	):
		return
	apply_callback.call(curve_resource, point, point_index, property_name, value)


static func copy_path(
	point_index: int,
	property_name: StringName,
) -> void:
	DisplayServer.clipboard_set(property_path(point_index, property_name))


static func copy_point_path(
	curve_resource: Resource,
	point: Resource,
	property_name: StringName,
) -> void:
	var point_index := _point_index(curve_resource, point)
	if point_index >= 0:
		copy_path(point_index, property_name)


static func is_value_compatible(
	property_name: StringName,
	value: Variant,
) -> bool:
	var definition := EasingCurve.get_point_property_definition(property_name)
	if (
		definition.is_empty()
		or not EasingCurve.is_point_property_copy_paste_enabled(property_name)
		or typeof(value) != definition["type"]
	):
		return false

	if property_name == &"handle_mode":
		return int(value) in EasingCurvePoint.HandleMode.values()

	return true


static func clipboard_has_compatible_value(
	property_name: StringName,
) -> bool:
	var clipboard := DisplayServer.clipboard_get()
	if clipboard.is_empty():
		return false

	return is_value_compatible(property_name, parse_point_value(clipboard, property_name))


static func parse_point_value(text: String, property_name: StringName) -> Variant:
	# Clipboard text is arbitrary. Variant parsing can log color errors for Markdown.
	if not EasingCurve.is_point_property_copy_paste_enabled(property_name):
		return null
	var definition := EasingCurve.get_point_property_definition(property_name)
	var value := text.strip_edges()
	if definition.get("type") == TYPE_INT:
		return value.to_int() if value.is_valid_int() else null
	if definition.get("type") != TYPE_VECTOR2 or not value.begins_with("Vector2"):
		return null
	var arguments := value.trim_prefix("Vector2").strip_edges()
	if not arguments.begins_with("(") or not arguments.ends_with(")"):
		return null
	var components := arguments.substr(1, arguments.length() - 2).split(",")
	if components.size() != 2:
		return null
	var x := components[0].strip_edges()
	var y := components[1].strip_edges()
	if not x.is_valid_float() or not y.is_valid_float():
		return null
	return Vector2(x.to_float(), y.to_float())


func create_context_menu(
	curve: EasingCurve,
	point_index: int,
	property_name: StringName,
	apply_callback: Callable,
) -> PopupMenu:
	return create_point_context_menu(
		curve,
		_point_at(curve, point_index),
		property_name,
		apply_callback,
	)


func create_point_context_menu(
	curve_resource: Resource,
	point: Resource,
	property_name: StringName,
	apply_callback: Callable,
) -> PopupMenu:
	var menu := PopupMenu.new()
	menu.add_item("Copy Value", MENU_COPY_VALUE, KEY_MASK_CMD_OR_CTRL | KEY_C)
	menu.add_item("Paste Value", MENU_PASTE_VALUE, KEY_MASK_CMD_OR_CTRL | KEY_V)
	menu.add_separator()
	menu.add_item(
		"Copy Property Path",
		MENU_COPY_PATH,
		KEY_MASK_CMD_OR_CTRL | KEY_MASK_SHIFT | KEY_C,
	)
	var curve_id := curve_resource.get_instance_id() if is_instance_valid(curve_resource) else 0
	var point_id := point.get_instance_id() if is_instance_valid(point) else 0
	var callback_object_id := apply_callback.get_object_id() if apply_callback.is_valid() else 0
	var callback_method := apply_callback.get_method() if apply_callback.is_valid() else StringName()
	menu.id_pressed.connect(
		_on_context_menu_id_pressed.bind(
			curve_id,
			point_id,
			property_name,
			callback_object_id,
			callback_method,
		)
	)
	return menu


func _on_context_menu_id_pressed(
	id: int,
	curve_id: int,
	point_id: int,
	property_name: StringName,
	callback_object_id: int,
	callback_method: StringName,
) -> void:
	var curve_resource := instance_from_id(curve_id) as Resource
	var point := instance_from_id(point_id) as Resource
	match id:
		MENU_COPY_VALUE:
			copy_point_value(curve_resource, point, property_name)
		MENU_PASTE_VALUE:
			var callback_object := instance_from_id(callback_object_id)
			if callback_object != null and not callback_method.is_empty():
				paste_point_value(
					curve_resource,
					point,
					property_name,
					Callable(callback_object, callback_method),
				)
		MENU_COPY_PATH:
			copy_point_path(curve_resource, point, property_name)


static func update_context_menu_paste_enabled(
	menu: PopupMenu,
	property_name: StringName,
) -> void:
	var paste_index := menu.get_item_index(MENU_PASTE_VALUE)
	if paste_index < 0:
		return
	menu.set_item_disabled(
		paste_index,
		not clipboard_has_compatible_value(property_name),
	)


static func _can_access_value(
	curve: EasingCurve,
	point_index: int,
	property_name: StringName,
) -> bool:
	return _can_access_point_value(
		curve,
		_point_at(curve, point_index),
		property_name,
	)


static func _can_access_point_value(
	curve_resource: Resource,
	point: Resource,
	property_name: StringName,
) -> bool:
	return (
		is_instance_valid(point)
		and _point_index(curve_resource, point) >= 0
		and EasingCurve.is_point_property_copy_paste_enabled(property_name)
	)


static func _point_at(curve_resource: Resource, point_index: int) -> Resource:
	var points := _get_resource_points(curve_resource)
	return points[point_index] if point_index >= 0 and point_index < points.size() else null


static func _point_index(curve_resource: Resource, point: Resource) -> int:
	if curve_resource == null or not is_instance_valid(point):
		return -1
	return _get_resource_points(curve_resource).find(point)


static func _get_resource_points(curve_resource: Resource) -> Array[Resource]:
	if curve_resource == null:
		return []
	var points: Array[Resource] = []
	var resource_points: Variant = curve_resource.get(&"points")
	if not resource_points is Array:
		return points
	for point in resource_points:
		if point is Resource:
			points.append(point)
	return points

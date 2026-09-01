@tool
extends RefCounted
## Owns point-property clipboard formatting, validation, and menu actions.
##
## Selection, mutation policy, transactions, and Undo/Redo remain on the
## Inspector side of the explicit apply callback.

const MENU_COPY_VALUE := 0
const MENU_PASTE_VALUE := 1
const MENU_COPY_PATH := 2


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
	if not _can_access_value(curve, point_index, property_name):
		return

	DisplayServer.clipboard_set(
		var_to_str(curve.points[point_index].get(property_name))
	)


func paste_value(
	curve: EasingCurve,
	point_index: int,
	property_name: StringName,
	apply_callback: Callable,
) -> void:
	apply_value(
		curve,
		point_index,
		property_name,
		str_to_var(DisplayServer.clipboard_get()),
		apply_callback,
	)


func apply_value(
	curve: EasingCurve,
	point_index: int,
	property_name: StringName,
	value: Variant,
	apply_callback: Callable,
) -> void:
	if (
		not _can_access_value(curve, point_index, property_name)
		or not is_value_compatible(property_name, value)
		or not apply_callback.is_valid()
	):
		return

	apply_callback.call(point_index, property_name, value)


static func copy_path(
	point_index: int,
	property_name: StringName,
) -> void:
	DisplayServer.clipboard_set(property_path(point_index, property_name))


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

	return is_value_compatible(property_name, str_to_var(clipboard))


func create_context_menu(
	curve: EasingCurve,
	point_index: int,
	property_name: StringName,
	apply_callback: Callable,
) -> PopupMenu:
	var menu := PopupMenu.new()
	menu.add_item("Copy Value", MENU_COPY_VALUE, KEY_MASK_CTRL | KEY_C)
	menu.add_item("Paste Value", MENU_PASTE_VALUE, KEY_MASK_CTRL | KEY_V)
	menu.add_separator()
	menu.add_item(
		"Copy Property Path",
		MENU_COPY_PATH,
		KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_C,
	)
	menu.id_pressed.connect(
		func(id: int) -> void:
			match id:
				MENU_COPY_VALUE:
					copy_value(curve, point_index, property_name)
				MENU_PASTE_VALUE:
					paste_value(
						curve,
						point_index,
						property_name,
						apply_callback,
					)
				MENU_COPY_PATH:
					copy_path(point_index, property_name)
	)
	return menu


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
	return (
		curve != null
		and point_index >= 0
		and point_index < curve.points.size()
		and EasingCurve.is_point_property_copy_paste_enabled(property_name)
	)

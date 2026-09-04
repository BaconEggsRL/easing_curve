@tool
extends RefCounted

const DEFAULT_NEW_POINT_HANDLE_MODE_SETTING := (
	"easing_curve/curve_editor/default_new_point_handle_mode"
)
const DEFAULT_NEW_POINT_HANDLE_MODE := EasingCurvePoint.HandleMode.FREE
const HANDLE_MODE_HINT := "Free,Linear,Balanced,Mirrored,Linked"


static func setup() -> void:
	if not Engine.is_editor_hint():
		return
	var settings := EditorInterface.get_editor_settings()
	if settings == null:
		return
	if not settings.has_setting(DEFAULT_NEW_POINT_HANDLE_MODE_SETTING):
		settings.set_setting(
			DEFAULT_NEW_POINT_HANDLE_MODE_SETTING,
			DEFAULT_NEW_POINT_HANDLE_MODE,
		)
	settings.set_initial_value(
		DEFAULT_NEW_POINT_HANDLE_MODE_SETTING,
		DEFAULT_NEW_POINT_HANDLE_MODE,
		false,
	)
	settings.add_property_info({
		"name": DEFAULT_NEW_POINT_HANDLE_MODE_SETTING,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": HANDLE_MODE_HINT,
	})
	var stored_value := int(settings.get_setting(
		DEFAULT_NEW_POINT_HANDLE_MODE_SETTING,
	))
	if not is_valid_handle_mode(stored_value):
		settings.set_setting(
			DEFAULT_NEW_POINT_HANDLE_MODE_SETTING,
			DEFAULT_NEW_POINT_HANDLE_MODE,
		)


static func get_default_new_point_handle_mode() -> int:
	if not Engine.is_editor_hint():
		return DEFAULT_NEW_POINT_HANDLE_MODE
	setup()
	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(
		DEFAULT_NEW_POINT_HANDLE_MODE_SETTING
	):
		return DEFAULT_NEW_POINT_HANDLE_MODE
	var value := int(settings.get_setting(
		DEFAULT_NEW_POINT_HANDLE_MODE_SETTING,
	))
	return value if is_valid_handle_mode(value) else DEFAULT_NEW_POINT_HANDLE_MODE


static func set_default_new_point_handle_mode(value: int) -> void:
	if not Engine.is_editor_hint():
		return
	setup()
	var settings := EditorInterface.get_editor_settings()
	if settings == null:
		return
	settings.set_setting(
		DEFAULT_NEW_POINT_HANDLE_MODE_SETTING,
		value if is_valid_handle_mode(value) else DEFAULT_NEW_POINT_HANDLE_MODE,
	)


static func is_valid_handle_mode(value: int) -> bool:
	return value >= EasingCurvePoint.HandleMode.FREE and value <= EasingCurvePoint.HandleMode.LINKED

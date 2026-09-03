@tool
extends "res://addons/easing_curve/scripts/editor/backend/curve_editor_backend.gd"

const IMPLEMENTED_TRANSITION_IDS := [
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
	100, 101, 104, 105, 106,
]


static func is_available() -> bool:
	return ClassDB.class_exists(&"NativeEasingCurve")


static func supports(resource: Resource) -> bool:
	return is_available() and resource != null and resource.get_class() == &"NativeEasingCurve"


func get_backend_id() -> StringName:
	return &"native"


func get_capabilities() -> Dictionary[StringName, bool]:
	return {
		CAP_RUNTIME_CALLABLE: false,
		CAP_CALLABLE_BAKING: true,
		CAP_HANDLE_MODES: true,
		CAP_POINT_OPTIONS: true,
		CAP_POINT_GEOMETRY: true,
		CAP_POINT_TOPOLOGY: false,
		CAP_CONVERSION: false,
	}


func get_transition_ids() -> PackedInt32Array:
	return PackedInt32Array(IMPLEMENTED_TRANSITION_IDS)


func is_point_graph() -> bool:
	return int(curve.get(&"transition")) == 100


func get_point_count() -> int:
	return int(curve.call(&"get_point_count"))


func get_point(index: int) -> Resource:
	return curve.call(&"get_point", index) as Resource


func get_points() -> Array[Resource]:
	var result: Array[Resource] = []
	result.assign(curve.get(&"points"))
	return result


func sample(offset: float) -> float:
	return float(curve.call(&"sample", offset))


func get_point_control_state(index: int, side: int) -> int:
	var point := get_point(index)
	if point == null:
		return CONTROL_STATE_FREE
	var lock_property := _control_property(side)
	var locks := point.call(&"get_locks") as Dictionary
	if (
		int(point.get(&"handle_mode")) == 4
		and (
			locks.get(&"left_control_point", false)
			or locks.get(&"right_control_point", false)
		)
	):
		return CONTROL_STATE_LOCKED
	if locks.get(lock_property, false):
		return CONTROL_STATE_LOCKED
	if is_point_control_force_linear(index, side):
		return CONTROL_STATE_LINEAR
	return CONTROL_STATE_FREE


func point_supports_control_state(index: int) -> bool:
	var point := get_point(index)
	if point == null:
		return false
	return int(point.get(&"handle_mode")) in [0, 4]


func is_point_control_force_linear(index: int, side: int) -> bool:
	var point := get_point(index)
	if point == null or not point_supports_control_state(index):
		return false
	if int(point.get(&"handle_mode")) == 4:
		return bool(point.get(&"left_force_linear")) or bool(point.get(&"right_force_linear"))
	return bool(point.get(_force_linear_property(side)))


func is_point_property_locked(index: int, property_name: StringName) -> bool:
	var point := get_point(index)
	return point != null and bool(point.call(&"is_lock_active", property_name))


func apply_point_property(
	index: int,
	property_name: StringName,
	value: Variant,
	_changing: bool = false,
) -> bool:
	if index < 0 or index >= get_point_count():
		return false
	var current_point := get_point(index)
	var point := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	if (
		current_point == null
		or point == null
		or not bool(point.call(&"apply_state", current_point.call(&"capture_state")))
	):
		return false
	match property_name:
		&"position", &"left_control_point", &"right_control_point":
			if value is not Vector2:
				return false
			point.set(property_name, value)
		&"handle_mode":
			point.set(&"handle_mode", int(value))
		&"left_control_state", &"right_control_state":
			var side := (
				CONTROL_SIDE_LEFT
				if property_name == &"left_control_state"
				else CONTROL_SIDE_RIGHT
			)
			if not _apply_control_state(point, side, int(value)):
				return false
		&"toolbar_options_reset":
			point.set(&"handle_mode", 0)
			_apply_control_state(point, CONTROL_SIDE_LEFT, CONTROL_STATE_FREE)
			_apply_control_state(point, CONTROL_SIDE_RIGHT, CONTROL_STATE_FREE)
		_:
			return false
	return bool(current_point.call(&"apply_state", point.call(&"capture_state")))


func capture_snapshot() -> Variant:
	return curve.call(&"capture_point_states")


func apply_snapshot(snapshot: Variant) -> bool:
	return snapshot is Array and bool(curve.call(&"apply_point_states", snapshot))


func create_preview_backend() -> RefCounted:
	var preview_curve := curve.call(&"create_runtime_copy") as Resource
	return get_script().new(preview_curve) if preview_curve != null else null


func _apply_control_state(point: Resource, side: int, control_state: int) -> bool:
	if control_state not in [CONTROL_STATE_FREE, CONTROL_STATE_LINEAR, CONTROL_STATE_LOCKED]:
		return false
	if int(point.get(&"handle_mode")) not in [0, 4]:
		return false
	var lock_property := _control_property(side)
	var force_property := _force_linear_property(side)
	point.call(&"set_locked", lock_property, false)
	point.set(force_property, control_state == CONTROL_STATE_LINEAR)
	if control_state == CONTROL_STATE_LOCKED:
		point.call(&"set_locked", lock_property, true)
	return true


func _control_property(side: int) -> StringName:
	return &"left_control_point" if side == CONTROL_SIDE_LEFT else &"right_control_point"


func _force_linear_property(side: int) -> StringName:
	return &"left_force_linear" if side == CONTROL_SIDE_LEFT else &"right_force_linear"

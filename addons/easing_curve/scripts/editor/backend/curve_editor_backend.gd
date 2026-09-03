@tool
extends RefCounted

const CAP_RUNTIME_CALLABLE := &"runtime_callable"
const CAP_CALLABLE_BAKING := &"callable_baking"
const CAP_HANDLE_MODES := &"handle_modes"
const CAP_POINT_OPTIONS := &"point_options"
const CAP_CONVERSION := &"conversion"

const CONTROL_SIDE_LEFT := 0
const CONTROL_SIDE_RIGHT := 1
const CONTROL_STATE_FREE := 0
const CONTROL_STATE_LINEAR := 1
const CONTROL_STATE_LOCKED := 2

var curve: Resource


func _init(value: Resource) -> void:
	curve = value


func get_backend_id() -> StringName:
	return &""


func get_capabilities() -> Dictionary[StringName, bool]:
	return {}


func get_transition_ids() -> PackedInt32Array:
	return PackedInt32Array()


func is_point_graph() -> bool:
	return false


func get_value_range() -> Vector2:
	return Vector2(0.0, 1.0)


func get_point_count() -> int:
	return 0


func get_point(index: int) -> Resource:
	return null


func get_points() -> Array[Resource]:
	var result: Array[Resource] = []
	for index in range(get_point_count()):
		var point := get_point(index)
		if point != null:
			result.append(point)
	return result


func find_point(point: Resource) -> int:
	for index in range(get_point_count()):
		if get_point(index) == point:
			return index
	return -1


func sample(offset: float) -> float:
	return 0.0


func get_point_control_state(_index: int, _side: int) -> int:
	return CONTROL_STATE_FREE


func point_supports_control_state(_index: int) -> bool:
	return false


func is_point_control_force_linear(_index: int, _side: int) -> bool:
	return false


func apply_point_property(_index: int, _property_name: StringName, _value: Variant) -> bool:
	return false


func capture_snapshot() -> Variant:
	return null


func apply_snapshot(_snapshot: Variant) -> bool:
	return false


func create_preview_backend() -> RefCounted:
	return null

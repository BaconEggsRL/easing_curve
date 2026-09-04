@tool
extends RefCounted

const CAP_RUNTIME_CALLABLE := &"runtime_callable"
const CAP_CALLABLE_BAKING := &"callable_baking"
const CAP_HANDLE_MODES := &"handle_modes"
const CAP_POINT_OPTIONS := &"point_options"
const CAP_POINT_GEOMETRY := &"point_geometry"
const CAP_POINT_TOPOLOGY := &"point_topology"
const CAP_CONVERSION := &"conversion"

const CONTROL_SIDE_LEFT := 0
const CONTROL_SIDE_RIGHT := 1
const CONTROL_STATE_FREE := 0
const CONTROL_STATE_LINEAR := 1
const CONTROL_STATE_LOCKED := 2
const POINT_ORDER_EPSILON := 0.000001

const SNAPSHOT_POINT_ORDER := &"point_order"
const SNAPSHOT_POINT_STATES := &"point_states"
const SNAPSHOT_LIVE_STATE := &"live_state"

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


func create_point(_position: Vector2) -> Resource:
	return null


func add_point(_point: Resource) -> int:
	return -1


func remove_point(_index: int) -> bool:
	return false


func get_ordered_points(active_point: Resource = null) -> Array[Resource]:
	var result := get_points()
	if active_point == null:
		return result
	var active_position: Variant = active_point.get(&"position")
	if active_position is not Vector2:
		return []
	var takes_left_endpoint := absf(active_position.x) <= POINT_ORDER_EPSILON
	var takes_right_endpoint := absf(active_position.x - 1.0) <= POINT_ORDER_EPSILON
	for index in range(result.size() - 1, -1, -1):
		var point := result[index]
		if point == active_point:
			continue
		var position: Variant = point.get(&"position")
		if position is not Vector2:
			return []
		if (
			(takes_left_endpoint and absf(position.x) <= POINT_ORDER_EPSILON)
			or (takes_right_endpoint and absf(position.x - 1.0) <= POINT_ORDER_EPSILON)
		):
			result.remove_at(index)
	if active_point not in result:
		result.append(active_point)
	return _sort_points_by_x(result)


func get_display_points(active_point: Resource = null) -> Array[Resource]:
	return get_ordered_points(active_point)


func curve_to_display_position(position: Vector2) -> Vector2:
	return position


func display_to_curve_position(position: Vector2) -> Vector2:
	return position


func get_display_control_point(point: Resource, side: int) -> Vector2:
	var property_name := (
		&"left_control_point"
		if side == CONTROL_SIDE_LEFT
		else &"right_control_point"
	)
	return curve_to_display_position(point.get(property_name) as Vector2)


func display_control_side_to_curve(side: int) -> int:
	return side


func apply_point_order(_point_order: Array[Resource]) -> int:
	return -1


func swap_points(_from_index: int, _to_index: int) -> bool:
	return false


func sample(offset: float) -> float:
	return 0.0


func get_point_control_state(_index: int, _side: int) -> int:
	return CONTROL_STATE_FREE


func point_supports_control_state(_index: int) -> bool:
	return false


func is_point_control_force_linear(_index: int, _side: int) -> bool:
	return false


func is_point_property_locked(_index: int, _property_name: StringName) -> bool:
	return false


func prepare_point_control_drag(_index: int, _display_scale: Vector2) -> void:
	pass


func begin_point_edit() -> void:
	pass


func finish_point_edit() -> void:
	pass


func apply_point_property(
	_index: int,
	_property_name: StringName,
	_value: Variant,
	_changing: bool = false,
) -> bool:
	return false


func capture_snapshot() -> Variant:
	return null


func apply_snapshot(_snapshot: Variant) -> bool:
	return false


func create_preview_backend() -> RefCounted:
	return null


func _sort_points_by_x(point_order: Array[Resource]) -> Array[Resource]:
	var entries: Array[Dictionary] = []
	for index in range(point_order.size()):
		var point := point_order[index]
		if point == null:
			return []
		var position: Variant = point.get(&"position")
		if position is not Vector2:
			return []
		entries.append({
			&"point": point,
			&"index": index,
			&"bucket": roundi(position.x / POINT_ORDER_EPSILON),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a[&"bucket"] == b[&"bucket"]:
			return a[&"index"] < b[&"index"]
		return a[&"bucket"] < b[&"bucket"]
	)
	var result: Array[Resource] = []
	for entry in entries:
		result.append(entry[&"point"])
	return result

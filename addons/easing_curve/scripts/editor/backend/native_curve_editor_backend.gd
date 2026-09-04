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
		CAP_POINT_TOPOLOGY: true,
		CAP_CONVERSION: false,
	}


func get_transition_ids() -> PackedInt32Array:
	return PackedInt32Array(IMPLEMENTED_TRANSITION_IDS)


func is_point_graph() -> bool:
	return (
		int(curve.get(&"transition")) == 100
		or bool(curve.call(&"is_builtin_bezier_preset"))
	)


func get_point_count() -> int:
	return int(curve.call(&"get_point_count"))


func get_point(index: int) -> Resource:
	return curve.call(&"get_point", index) as Resource


func get_points() -> Array[Resource]:
	var result: Array[Resource] = []
	result.assign(curve.get(&"points"))
	return result


func create_point(position: Vector2) -> Resource:
	var point := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	if point == null:
		return null
	point.set(&"position", position)
	point.set(&"left_control_point", position - Vector2(0.1, 0.0))
	point.set(&"right_control_point", position + Vector2(0.1, 0.0))
	return point


func add_point(point: Resource) -> int:
	if not _is_native_point(point):
		return -1
	var point_order := get_ordered_points(point)
	if point_order.is_empty() or not _apply_topology(point_order):
		return -1
	return find_point(point)


func remove_point(index: int) -> bool:
	if index < 0 or index >= get_point_count():
		return false
	var point_order := get_points()
	point_order.remove_at(index)
	return _apply_topology(point_order)


func apply_point_order(point_order: Array[Resource]) -> int:
	var current := get_points()
	if point_order.size() != current.size() or not _is_unique_native_points(point_order):
		return -1
	for point in point_order:
		if point not in current:
			return -1
	return 0 if _apply_topology(point_order) else -1


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
	return {
		SNAPSHOT_POINT_ORDER: get_points(),
		SNAPSHOT_POINT_STATES: curve.call(&"capture_point_states"),
	}


func apply_snapshot(snapshot: Variant) -> bool:
	if snapshot is not Dictionary:
		return false
	var point_order: Variant = snapshot.get(SNAPSHOT_POINT_ORDER)
	var point_states: Variant = snapshot.get(SNAPSHOT_POINT_STATES)
	if point_order is not Array or point_states is not Array:
		return false
	var resources: Array[Resource] = []
	resources.assign(point_order)
	if not _is_unique_native_points(resources):
		return false
	return bool(curve.call(&"apply_point_topology_snapshot", resources, point_states))


func create_preview_backend() -> RefCounted:
	var preview_curve := curve.call(&"create_runtime_copy") as Resource
	return get_script().new(preview_curve) if preview_curve != null else null


func begin_point_edit() -> void:
	curve.call(&"begin_point_edit")


func finish_point_edit() -> void:
	curve.call(&"finish_point_edit")


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


func _apply_topology(point_order: Array[Resource]) -> bool:
	if not _is_unique_native_points(point_order):
		return false
	var point_states: Array = []
	for point in point_order:
		point_states.append(point.call(&"capture_state"))
	return bool(curve.call(&"apply_point_topology_snapshot", point_order, point_states))


func _is_unique_native_points(point_order: Array[Resource]) -> bool:
	var seen := {}
	for point in point_order:
		if not _is_native_point(point):
			return false
		var point_id := point.get_instance_id()
		if seen.has(point_id):
			return false
		seen[point_id] = true
	return true


func _is_native_point(point: Resource) -> bool:
	return point != null and point.get_class() == &"NativeEasingCurvePoint"

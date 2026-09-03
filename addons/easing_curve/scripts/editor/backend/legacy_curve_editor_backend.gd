@tool
extends "res://addons/easing_curve/scripts/editor/backend/curve_editor_backend.gd"

const PointSnapshotMutator := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_point_snapshot_mutator.gd"
)

var _point_edit_active := false


static func supports(resource: Resource) -> bool:
	return resource is EasingCurve


func get_backend_id() -> StringName:
	return &"legacy"


func get_capabilities() -> Dictionary[StringName, bool]:
	return {
		CAP_RUNTIME_CALLABLE: true,
		CAP_CALLABLE_BAKING: false,
		CAP_HANDLE_MODES: true,
		CAP_POINT_OPTIONS: true,
		CAP_POINT_GEOMETRY: true,
		CAP_POINT_TOPOLOGY: true,
		CAP_CONVERSION: false,
	}


func get_transition_ids() -> PackedInt32Array:
	return PackedInt32Array(EasingCurve.TRANS.values())


func is_point_graph() -> bool:
	return (curve as EasingCurve).curve_mode == EasingCurve.CurveMode.BEZIER


func get_value_range() -> Vector2:
	return Vector2(EasingCurve.min_value, EasingCurve.max_value)


func get_point_count() -> int:
	return (curve as EasingCurve).points.size()


func get_point(index: int) -> Resource:
	var points := (curve as EasingCurve).points
	return points[index] if index >= 0 and index < points.size() else null


func get_points() -> Array[Resource]:
	var result: Array[Resource] = []
	result.assign((curve as EasingCurve).points)
	return result


func sample(offset: float) -> float:
	return (curve as EasingCurve).sample(offset)


func get_point_control_state(index: int, side: int) -> int:
	var point := get_point(index) as EasingCurvePoint
	if point == null:
		return CONTROL_STATE_FREE
	var lock_property := (
		&"left_control_point"
		if side == CONTROL_SIDE_LEFT
		else &"right_control_point"
	)
	if (
		point.handle_mode == EasingCurvePoint.HandleMode.LINKED
		and (
			point.locked.get(&"left_control_point", false)
			or point.locked.get(&"right_control_point", false)
		)
	):
		return CONTROL_STATE_LOCKED
	if point.locked.get(lock_property, false):
		return CONTROL_STATE_LOCKED
	if point.is_control_force_linear_active(side as EasingCurvePoint.ControlSide):
		return CONTROL_STATE_LINEAR
	return CONTROL_STATE_FREE


func point_supports_control_state(index: int) -> bool:
	var point := get_point(index) as EasingCurvePoint
	return point != null and point.supports_control_state()


func is_point_control_force_linear(index: int, side: int) -> bool:
	var point := get_point(index) as EasingCurvePoint
	return (
		point != null
		and point.is_control_force_linear_active(side as EasingCurvePoint.ControlSide)
	)


func is_point_property_locked(index: int, property_name: StringName) -> bool:
	var point := get_point(index) as EasingCurvePoint
	return point != null and point.is_lock_active(property_name)


func prepare_point_control_drag(index: int, display_scale: Vector2) -> void:
	var point := get_point(index) as EasingCurvePoint
	if point != null:
		point.set_handle_display_scale(display_scale)


func begin_point_edit() -> void:
	if _point_edit_active:
		return
	_point_edit_active = true
	(curve as EasingCurve)._begin_editor_point_edit()


func finish_point_edit() -> void:
	if not _point_edit_active:
		return
	_point_edit_active = false
	(curve as EasingCurve)._finish_editor_point_edit()


func apply_point_property(
	index: int,
	property_name: StringName,
	value: Variant,
	changing: bool = false,
) -> bool:
	var point := get_point(index) as EasingCurvePoint
	if point == null:
		return false
	if _point_edit_active and property_name in [
		&"position",
		&"left_control_point",
		&"right_control_point",
	]:
		if value is not Vector2:
			return false
		point.set(property_name, value)
		return true
	var snapshot := (curve as EasingCurve).get_point_snapshot()
	if _apply_geometry_change(snapshot, point, index, property_name, value):
		snapshot["changing"] = changing
		(curve as EasingCurve).set_point_snapshot(snapshot)
		return true
	if PointSnapshotMutator.apply(snapshot, point, index, property_name, value):
		snapshot["changing"] = changing
		(curve as EasingCurve).set_point_snapshot(snapshot)
		return true
	if (
		EasingCurve.is_point_property_snapshot_lifecycle_ordinary(property_name)
		and EasingCurve.set_point_snapshot_property_value(
			snapshot,
			property_name,
			index,
			value,
		)
	):
		snapshot["changing"] = changing
		(curve as EasingCurve).set_point_snapshot(snapshot)
		return true
	return false


func capture_snapshot() -> Variant:
	return (curve as EasingCurve).get_point_snapshot()


func apply_snapshot(snapshot: Variant) -> bool:
	if snapshot is not Dictionary:
		return false
	(curve as EasingCurve).set_point_snapshot(snapshot)
	return true


func create_preview_backend() -> RefCounted:
	var preview_curve := (curve as EasingCurve).duplicate(true) as EasingCurve
	return get_script().new(preview_curve) if preview_curve != null else null


func _apply_geometry_change(
	snapshot: Dictionary,
	point: EasingCurvePoint,
	index: int,
	property_name: StringName,
	value: Variant,
) -> bool:
	if value is not Vector2:
		return false
	match property_name:
		&"position":
			var positions: PackedVector2Array = snapshot["positions"]
			var old_position := positions[index]
			var new_position: Vector2 = value
			positions[index] = new_position
			snapshot["positions"] = positions
			var delta := new_position - old_position
			if not point.is_lock_active(&"left_control_point"):
				var left_controls: PackedVector2Array = snapshot["left_control_points"]
				left_controls[index] += delta
				snapshot["left_control_points"] = left_controls
			if not point.is_lock_active(&"right_control_point"):
				var right_controls: PackedVector2Array = snapshot["right_control_points"]
				right_controls[index] += delta
				snapshot["right_control_points"] = right_controls
			return true
		&"left_control_point", &"right_control_point":
			var side := (
				EasingCurvePoint.ControlSide.LEFT
				if property_name == &"left_control_point"
				else EasingCurvePoint.ControlSide.RIGHT
			)
			var pair := point.get_control_point_pair(side, value)
			var left_controls: PackedVector2Array = snapshot["left_control_points"]
			var right_controls: PackedVector2Array = snapshot["right_control_points"]
			left_controls[index] = pair["left"]
			right_controls[index] = pair["right"]
			snapshot["left_control_points"] = left_controls
			snapshot["right_control_points"] = right_controls
			return true
	return false

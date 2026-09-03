@tool
extends "res://addons/easing_curve/scripts/editor/backend/curve_editor_backend.gd"

const PointSnapshotMutator := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_point_snapshot_mutator.gd"
)


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


func apply_point_property(index: int, property_name: StringName, value: Variant) -> bool:
	var point := get_point(index) as EasingCurvePoint
	if point == null:
		return false
	var snapshot := (curve as EasingCurve).get_point_snapshot()
	if PointSnapshotMutator.apply(snapshot, point, index, property_name, value):
		(curve as EasingCurve).set_point_snapshot(snapshot)
		return true
	if EasingCurve.get_point_property_definition(property_name).is_empty():
		return false
	(curve as EasingCurve).set_point_property(index, property_name, value)
	return true


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

@tool
extends "res://addons/easing_curve/scripts/editor/backend/curve_editor_backend.gd"


static func supports(resource: Resource) -> bool:
	return resource is EasingCurve


func get_backend_id() -> StringName:
	return &"legacy"


func get_capabilities() -> Dictionary[StringName, bool]:
	return {
		CAP_RUNTIME_CALLABLE: true,
		CAP_CALLABLE_BAKING: false,
		CAP_HANDLE_MODES: true,
		CAP_CONVERSION: false,
	}


func get_transition_ids() -> PackedInt32Array:
	return PackedInt32Array(EasingCurve.TRANS.values())


func get_point_count() -> int:
	return (curve as EasingCurve).points.size()


func get_point(index: int) -> Resource:
	var points := (curve as EasingCurve).points
	return points[index] if index >= 0 and index < points.size() else null


func sample(offset: float) -> float:
	return (curve as EasingCurve).sample(offset)


func capture_snapshot() -> Variant:
	return (curve as EasingCurve).get_point_snapshot()


func apply_snapshot(snapshot: Variant) -> bool:
	if snapshot is not Dictionary:
		return false
	(curve as EasingCurve).set_point_snapshot(snapshot)
	return true

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
		CAP_CONVERSION: false,
	}


func get_transition_ids() -> PackedInt32Array:
	return PackedInt32Array(IMPLEMENTED_TRANSITION_IDS)


func get_point_count() -> int:
	return int(curve.call(&"get_point_count"))


func get_point(index: int) -> Resource:
	return curve.call(&"get_point", index) as Resource


func sample(offset: float) -> float:
	return float(curve.call(&"sample", offset))


func capture_snapshot() -> Variant:
	return curve.call(&"capture_point_states")


func apply_snapshot(snapshot: Variant) -> bool:
	return snapshot is Array and bool(curve.call(&"apply_point_states", snapshot))

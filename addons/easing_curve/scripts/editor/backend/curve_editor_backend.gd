@tool
extends RefCounted

const CAP_RUNTIME_CALLABLE := &"runtime_callable"
const CAP_CALLABLE_BAKING := &"callable_baking"
const CAP_HANDLE_MODES := &"handle_modes"
const CAP_CONVERSION := &"conversion"

var curve: Resource


func _init(value: Resource) -> void:
	curve = value


func get_backend_id() -> StringName:
	return &""


func get_capabilities() -> Dictionary[StringName, bool]:
	return {}


func get_transition_ids() -> PackedInt32Array:
	return PackedInt32Array()


func get_point_count() -> int:
	return 0


func get_point(index: int) -> Resource:
	return null


func sample(offset: float) -> float:
	return 0.0


func capture_snapshot() -> Variant:
	return null


func apply_snapshot(_snapshot: Variant) -> bool:
	return false

@tool
extends RefCounted
## Primitive snapshot/storage schema for EasingCurve compatibility boundaries.
##
## This component owns names and shape validation only. It deliberately does
## not own EasingCurve mutation, notifications, point-state policy, topology,
## Undo/Redo, or runtime sampling.

# Godot-facing editor/live-debug bridge properties.
const POINT_SNAPSHOT_PROPERTY := &"_point_snapshot"
const FUNCTION_SNAPSHOT_PROPERTY := &"_function_snapshot"
const EDITOR_STATE_SNAPSHOT_PROPERTY := &"_editor_state_snapshot"

# Dynamic primitive point storage.
const POINT_STORAGE_COUNT := &"_point_count"
const POINT_STORAGE_PREFIX := "_point_"

# Point snapshot keys.
const POINT_POSITIONS := &"positions"
const POINT_LEFT_CONTROL_POINTS := &"left_control_points"
const POINT_RIGHT_CONTROL_POINTS := &"right_control_points"
const POINT_HANDLE_MODES := &"handle_modes"
const POINT_LOCKS := &"locks"
const POINT_LEFT_FORCE_LINEAR := &"left_force_linear"
const POINT_RIGHT_FORCE_LINEAR := &"right_force_linear"
const POINT_CHANGING := &"changing"

# Function snapshot keys that are not transition parameter names.
const FUNCTION_GENERATED_POINTS_X := &"generated_points_x"
const FUNCTION_GENERATED_POINTS_Y := &"generated_points_y"
const FUNCTION_FORCE_NOTIFY := &"force_notify"

# Editor-state snapshot keys.
const EDITOR_EASE_TYPE := &"ease_type"
const EDITOR_TRANS_TYPE := &"trans_type"
const EDITOR_CURVE_MODE := &"curve_mode"
const EDITOR_FROM_START := &"from_start"
const EDITOR_REVERSE := &"reverse"
const EDITOR_INVERT := &"invert"
const EDITOR_BEZIER_PARAMETER_SNAPSHOT := &"bezier_parameter_snapshot"
const EDITOR_POINT_SNAPSHOT := &"point_snapshot"
const EDITOR_FUNCTION_SNAPSHOT := &"function_snapshot"
const EDITOR_POINT_RESOURCE_IDS := &"point_resource_ids"


static func validate_point_snapshot(
		snapshot: Dictionary,
		property_definitions: Array[Dictionary],
) -> Dictionary:
	# Compatibility validation is intentionally permissive: missing point keys
	# remain accepted because legacy/partial snapshots rely on setter fallbacks.
	# Present known keys must use the established primitive container type.
	var errors: Array[String] = []
	for definition in property_definitions:
		var snapshot_key: StringName = definition.get("snapshot_key", StringName())
		if snapshot_key.is_empty() or not snapshot.has(snapshot_key):
			continue
		var property_type := int(definition.get("type", TYPE_NIL))
		var values: Variant = snapshot[snapshot_key]
		if not is_point_snapshot_container(values, property_type):
			errors.append(
				"%s must use %s snapshot storage" % [
					snapshot_key,
					_point_snapshot_container_name(property_type),
				]
			)
			continue
		if property_type == TYPE_DICTIONARY:
			for index in range(values.size()):
				if values[index] is not Dictionary:
					errors.append("%s[%d] must be a Dictionary" % [snapshot_key, index])

	if snapshot.has(POINT_CHANGING) and snapshot[POINT_CHANGING] is not bool:
		errors.append("%s must be a bool" % POINT_CHANGING)

	var point_count := -1
	if snapshot.get(POINT_POSITIONS) is PackedVector2Array:
		point_count = snapshot[POINT_POSITIONS].size()

	return {
		"compatible": errors.is_empty(),
		"errors": errors,
		"point_count": point_count,
	}


static func can_mutate_point_snapshot(
		snapshot: Dictionary,
		point_index: int,
) -> bool:
	# Snapshot mutation is stricter than compatibility loading: the semantic
	# mutator requires the complete current-format state it reads so it never
	# guesses Handle Mode, lock, or Force Linear policy.
	if point_index < 0:
		return false
	var required := [
		[POINT_POSITIONS, TYPE_VECTOR2],
		[POINT_LEFT_CONTROL_POINTS, TYPE_VECTOR2],
		[POINT_RIGHT_CONTROL_POINTS, TYPE_VECTOR2],
		[POINT_HANDLE_MODES, TYPE_INT],
		[POINT_LOCKS, TYPE_DICTIONARY],
		[POINT_LEFT_FORCE_LINEAR, TYPE_BOOL],
		[POINT_RIGHT_FORCE_LINEAR, TYPE_BOOL],
	]
	for entry in required:
		var snapshot_key: StringName = entry[0]
		var property_type: int = entry[1]
		if not snapshot.has(snapshot_key):
			return false
		var values: Variant = snapshot[snapshot_key]
		if not is_point_snapshot_container(values, property_type):
			return false
		if point_index >= values.size():
			return false
		if property_type == TYPE_DICTIONARY and values[point_index] is not Dictionary:
			return false
	return true


static func is_point_snapshot_container(values: Variant, property_type: int) -> bool:
	match property_type:
		TYPE_VECTOR2:
			return values is PackedVector2Array
		TYPE_INT:
			return values is PackedInt32Array
		TYPE_BOOL:
			return values is PackedByteArray
		TYPE_DICTIONARY:
			return values is Array
	return false


static func validate_function_snapshot(snapshot: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	for key in [FUNCTION_GENERATED_POINTS_X, FUNCTION_GENERATED_POINTS_Y]:
		if snapshot.has(key) and not is_function_float_array(snapshot[key]):
			errors.append("%s must be Array, PackedFloat32Array, or PackedFloat64Array" % key)
	if snapshot.has(FUNCTION_FORCE_NOTIFY) and snapshot[FUNCTION_FORCE_NOTIFY] is not bool:
		errors.append("%s must be a bool" % FUNCTION_FORCE_NOTIFY)
	return {
		"compatible": errors.is_empty(),
		"errors": errors,
	}


static func is_function_float_array(value: Variant) -> bool:
	return (
		value is Array
		or value is PackedFloat32Array
		or value is PackedFloat64Array
	)


static func validate_editor_state_snapshot(snapshot: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	for key in [EDITOR_EASE_TYPE, EDITOR_TRANS_TYPE, EDITOR_CURVE_MODE]:
		if snapshot.has(key) and snapshot[key] is not int:
			errors.append("%s must be an int" % key)
	for key in [EDITOR_FROM_START, EDITOR_REVERSE, EDITOR_INVERT]:
		if snapshot.has(key) and snapshot[key] is not bool:
			errors.append("%s must be a bool" % key)
	for key in [
		EDITOR_BEZIER_PARAMETER_SNAPSHOT,
		EDITOR_POINT_SNAPSHOT,
		EDITOR_FUNCTION_SNAPSHOT,
	]:
		if snapshot.has(key) and snapshot[key] is not Dictionary:
			errors.append("%s must be a Dictionary" % key)
	if (
		snapshot.has(EDITOR_POINT_RESOURCE_IDS)
		and snapshot[EDITOR_POINT_RESOURCE_IDS] is not PackedInt64Array
	):
		errors.append("%s must be a PackedInt64Array" % EDITOR_POINT_RESOURCE_IDS)
	return {
		"compatible": errors.is_empty(),
		"errors": errors,
	}


static func _point_snapshot_container_name(property_type: int) -> String:
	match property_type:
		TYPE_VECTOR2:
			return "PackedVector2Array"
		TYPE_INT:
			return "PackedInt32Array"
		TYPE_BOOL:
			return "PackedByteArray"
		TYPE_DICTIONARY:
			return "Array[Dictionary]"
	return "supported primitive container"

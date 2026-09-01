@tool
extends RefCounted
## Primitive snapshot/storage codec for EasingCurve compatibility boundaries.
##
## This component owns snapshot names, primitive container encoding/decoding,
## representation transforms, and compatibility-safe shape validation. It
## deliberately does not own EasingCurve mutation, notifications, point-state
## policy, topology, Undo/Redo, or runtime sampling.

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


static func create_point_snapshot_values(property_type: int) -> Variant:
	match property_type:
		TYPE_VECTOR2:
			return PackedVector2Array()
		TYPE_INT:
			return PackedInt32Array()
		TYPE_BOOL:
			return PackedByteArray()
		TYPE_DICTIONARY:
			return []
	return null


static func append_point_snapshot_value(
		values: Variant,
		property_type: int,
		value: Variant,
) -> bool:
	match property_type:
		TYPE_VECTOR2:
			if values is PackedVector2Array and value is Vector2:
				values.append(value)
				return true
		TYPE_INT:
			if values is PackedInt32Array and value is int:
				values.append(value)
				return true
		TYPE_BOOL:
			if values is PackedByteArray and value is bool:
				values.append(int(value))
				return true
		TYPE_DICTIONARY:
			if values is Array and value is Dictionary:
				values.append(value.duplicate(true))
				return true
	return false


static func reverse_point_snapshot_values(
		values: Variant,
		property_type: int,
) -> Variant:
	var reversed_values := create_point_snapshot_values(property_type)
	if reversed_values == null:
		return null

	for index in range(values.size() - 1, -1, -1):
		var value: Variant = values[index]
		if property_type == TYPE_BOOL and values is PackedByteArray:
			value = bool(value)
		if not append_point_snapshot_value(reversed_values, property_type, value):
			return null
	return reversed_values


static func encode_point_snapshot(
		point_values: Array,
		property_definitions: Array[Dictionary],
) -> Dictionary:
	var snapshot := {}
	for definition in property_definitions:
		var property_name: StringName = definition.get("name", StringName())
		var snapshot_key: StringName = definition.get("snapshot_key", StringName())
		var property_type := int(definition.get("type", TYPE_NIL))
		if property_name.is_empty() or snapshot_key.is_empty():
			continue
		var values := create_point_snapshot_values(property_type)
		if values == null:
			continue
		for point in point_values:
			var value: Variant
			if point == null:
				value = _null_point_snapshot_value(definition)
			else:
				value = point.get(property_name)
			if not append_point_snapshot_value(values, property_type, value):
				values = null
				break
		if values != null:
			snapshot[snapshot_key] = values
	return snapshot


static func decode_point_snapshot(snapshot: Dictionary) -> Dictionary:
	return {
		POINT_POSITIONS: snapshot.get(POINT_POSITIONS, PackedVector2Array()),
		POINT_LEFT_CONTROL_POINTS: snapshot.get(
			POINT_LEFT_CONTROL_POINTS,
			PackedVector2Array(),
		),
		POINT_RIGHT_CONTROL_POINTS: snapshot.get(
			POINT_RIGHT_CONTROL_POINTS,
			PackedVector2Array(),
		),
		POINT_HANDLE_MODES: snapshot.get(POINT_HANDLE_MODES, PackedInt32Array()),
		POINT_LOCKS: snapshot.get(POINT_LOCKS, []),
		POINT_LEFT_FORCE_LINEAR: snapshot.get(
			POINT_LEFT_FORCE_LINEAR,
			PackedByteArray(),
		),
		POINT_RIGHT_FORCE_LINEAR: snapshot.get(
			POINT_RIGHT_FORCE_LINEAR,
			PackedByteArray(),
		),
		POINT_CHANGING: bool(snapshot.get(POINT_CHANGING, false)),
	}


static func get_point_snapshot_property_value(
		snapshot: Dictionary,
		definition: Dictionary,
		point_index: int,
) -> Variant:
	var snapshot_key: StringName = definition.get("snapshot_key", StringName())
	if definition.is_empty() or snapshot_key.is_empty() or point_index < 0:
		return null

	match int(definition.get("type", TYPE_NIL)):
		TYPE_VECTOR2:
			var values: PackedVector2Array = snapshot.get(snapshot_key, PackedVector2Array())
			return values[point_index] if point_index < values.size() else null
		TYPE_INT:
			var values: PackedInt32Array = snapshot.get(snapshot_key, PackedInt32Array())
			return values[point_index] if point_index < values.size() else null
		TYPE_BOOL:
			var values: PackedByteArray = snapshot.get(snapshot_key, PackedByteArray())
			return bool(values[point_index]) if point_index < values.size() else null
		TYPE_DICTIONARY:
			var values: Array = snapshot.get(snapshot_key, [])
			return (
				values[point_index].duplicate(true)
				if point_index < values.size() and values[point_index] is Dictionary
				else null
			)
	return null


static func set_point_snapshot_property_value(
		snapshot: Dictionary,
		definition: Dictionary,
		point_index: int,
		value: Variant,
) -> bool:
	var snapshot_key: StringName = definition.get("snapshot_key", StringName())
	if definition.is_empty() or snapshot_key.is_empty() or point_index < 0:
		return false

	match int(definition.get("type", TYPE_NIL)):
		TYPE_VECTOR2:
			var values: PackedVector2Array = snapshot.get(snapshot_key, PackedVector2Array())
			if value is not Vector2 or point_index >= values.size():
				return false
			values[point_index] = value
			snapshot[snapshot_key] = values
			return true
		TYPE_INT:
			var values: PackedInt32Array = snapshot.get(snapshot_key, PackedInt32Array())
			if value is not int or point_index >= values.size():
				return false
			values[point_index] = value
			snapshot[snapshot_key] = values
			return true
		TYPE_BOOL:
			var values: PackedByteArray = snapshot.get(snapshot_key, PackedByteArray())
			if value is not bool or point_index >= values.size():
				return false
			values[point_index] = int(value)
			snapshot[snapshot_key] = values
			return true
		TYPE_DICTIONARY:
			var values: Array = snapshot.get(snapshot_key, [])
			if value is not Dictionary or point_index >= values.size():
				return false
			values[point_index] = value.duplicate(true)
			snapshot[snapshot_key] = values
			return true
	return false


static func reverse_point_snapshot(
		snapshot: Dictionary,
		ordinary_property_definitions: Array[Dictionary],
		expected_point_count: int,
) -> Dictionary:
	var result := snapshot.duplicate(true)
	var decoded := decode_point_snapshot(snapshot)
	var positions: PackedVector2Array = decoded[POINT_POSITIONS]
	var left_controls: PackedVector2Array = decoded[POINT_LEFT_CONTROL_POINTS]
	var right_controls: PackedVector2Array = decoded[POINT_RIGHT_CONTROL_POINTS]
	var locks: Array = decoded[POINT_LOCKS]
	var handle_modes: PackedInt32Array = decoded[POINT_HANDLE_MODES]
	var left_force_linear: PackedByteArray = decoded[POINT_LEFT_FORCE_LINEAR]
	var right_force_linear: PackedByteArray = decoded[POINT_RIGHT_FORCE_LINEAR]

	var reversed_positions := PackedVector2Array()
	var reversed_left_controls := PackedVector2Array()
	var reversed_right_controls := PackedVector2Array()
	var reversed_locks: Array[Dictionary] = []
	var reversed_handle_modes := PackedInt32Array()
	var reversed_left_force_linear := PackedByteArray()
	var reversed_right_force_linear := PackedByteArray()

	for i in range(positions.size() - 1, -1, -1):
		var position := positions[i]
		position.x = 1.0 - position.x
		reversed_positions.append(position)

		var left_control := right_controls[i]
		left_control.x = 1.0 - left_control.x
		reversed_left_controls.append(left_control)

		var right_control := left_controls[i]
		right_control.x = 1.0 - right_control.x
		reversed_right_controls.append(right_control)

		var lock_values: Dictionary = (
			locks[i]
			if i < locks.size() and locks[i] is Dictionary
			else {}
		)
		if i < handle_modes.size():
			reversed_handle_modes.append(handle_modes[i])
		reversed_left_force_linear.append(
			right_force_linear[i] if i < right_force_linear.size() else 0
		)
		reversed_right_force_linear.append(
			left_force_linear[i] if i < left_force_linear.size() else 0
		)
		reversed_locks.append({
			"position": bool(lock_values.get("position", false)),
			"left_control_point": bool(lock_values.get("right_control_point", false)),
			"right_control_point": bool(lock_values.get("left_control_point", false)),
		})

	result[POINT_POSITIONS] = reversed_positions
	result[POINT_LEFT_CONTROL_POINTS] = reversed_left_controls
	result[POINT_RIGHT_CONTROL_POINTS] = reversed_right_controls
	result[POINT_LOCKS] = reversed_locks
	result[POINT_HANDLE_MODES] = reversed_handle_modes
	result[POINT_LEFT_FORCE_LINEAR] = reversed_left_force_linear
	result[POINT_RIGHT_FORCE_LINEAR] = reversed_right_force_linear

	for definition in ordinary_property_definitions:
		var snapshot_key: StringName = definition.get("snapshot_key", StringName())
		var property_type := int(definition.get("type", TYPE_NIL))
		var values: Variant = snapshot.get(snapshot_key, null)
		if snapshot_key.is_empty() or values == null or values.size() != expected_point_count:
			continue
		var reversed_values := reverse_point_snapshot_values(values, property_type)
		if reversed_values != null:
			result[snapshot_key] = reversed_values
	return result


static func invert_point_snapshot(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	var decoded := decode_point_snapshot(snapshot)
	for snapshot_key in [
		POINT_POSITIONS,
		POINT_LEFT_CONTROL_POINTS,
		POINT_RIGHT_CONTROL_POINTS,
	]:
		var source: PackedVector2Array = decoded[snapshot_key]
		var output := PackedVector2Array()
		for value in source:
			var transformed := value
			transformed.y = 1.0 - transformed.y
			output.append(transformed)
		result[snapshot_key] = output
	return result


static func _null_point_snapshot_value(definition: Dictionary) -> Variant:
	var snapshot_key: StringName = definition.get("snapshot_key", StringName())
	if snapshot_key == POINT_LOCKS:
		# Preserve the historical null-point encoding used by EasingCurve.
		return {}
	var default_value: Variant = definition.get("default", null)
	return default_value.duplicate(true) if default_value is Dictionary else default_value


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

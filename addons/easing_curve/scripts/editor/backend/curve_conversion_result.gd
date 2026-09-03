@tool
extends RefCounted

const SCHEMA_VERSION := 1

const FIELD_EXACT := &"exact"
const FIELD_APPROXIMATED := &"approximated"
const FIELD_BAKED := &"baked"
const FIELD_UNSUPPORTED := &"unsupported"
const FIELD_OUTCOMES: Array[StringName] = [
	FIELD_EXACT,
	FIELD_APPROXIMATED,
	FIELD_BAKED,
	FIELD_UNSUPPORTED,
]

const KEY_SCHEMA_VERSION := &"schema_version"
const KEY_SOURCE_BACKEND := &"source_backend"
const KEY_TARGET_BACKEND := &"target_backend"
const KEY_RESOURCE := &"resource"
const KEY_FIELDS := &"fields"
const KEY_WARNINGS := &"warnings"
const KEY_ERRORS := &"errors"


static func create(
	source_backend: StringName,
	target_backend: StringName,
	converted_resource: Resource,
	field_outcomes: Dictionary,
	warnings := PackedStringArray(),
	errors := PackedStringArray(),
) -> Dictionary:
	if source_backend.is_empty() or target_backend.is_empty():
		return {}
	var normalized_fields := _normalize_field_outcomes(field_outcomes)
	if normalized_fields.size() != field_outcomes.size():
		return {}
	return {
		KEY_SCHEMA_VERSION: SCHEMA_VERSION,
		KEY_SOURCE_BACKEND: source_backend,
		KEY_TARGET_BACKEND: target_backend,
		KEY_RESOURCE: converted_resource,
		KEY_FIELDS: normalized_fields,
		KEY_WARNINGS: PackedStringArray(warnings),
		KEY_ERRORS: PackedStringArray(errors),
	}


static func is_valid(result: Variant) -> bool:
	if result is not Dictionary:
		return false
	var value := result as Dictionary
	if value.keys().size() != 7:
		return false
	for key: StringName in [
		KEY_SCHEMA_VERSION,
		KEY_SOURCE_BACKEND,
		KEY_TARGET_BACKEND,
		KEY_RESOURCE,
		KEY_FIELDS,
		KEY_WARNINGS,
		KEY_ERRORS,
	]:
		if not value.has(key):
			return false
	if value[KEY_SCHEMA_VERSION] != SCHEMA_VERSION:
		return false
	if value[KEY_SOURCE_BACKEND] is not StringName or value[KEY_SOURCE_BACKEND].is_empty():
		return false
	if value[KEY_TARGET_BACKEND] is not StringName or value[KEY_TARGET_BACKEND].is_empty():
		return false
	if value[KEY_RESOURCE] != null and value[KEY_RESOURCE] is not Resource:
		return false
	if value[KEY_FIELDS] is not Dictionary:
		return false
	if _normalize_field_outcomes(value[KEY_FIELDS]).size() != value[KEY_FIELDS].size():
		return false
	return value[KEY_WARNINGS] is PackedStringArray and value[KEY_ERRORS] is PackedStringArray


static func is_success(result: Variant) -> bool:
	return (
		is_valid(result)
		and result[KEY_RESOURCE] is Resource
		and result[KEY_ERRORS].is_empty()
		and not has_unsupported_fields(result)
	)


static func is_lossy(result: Variant) -> bool:
	if not is_valid(result):
		return true
	for outcome: Variant in result[KEY_FIELDS].values():
		if outcome != FIELD_EXACT:
			return true
	return false


static func has_unsupported_fields(result: Variant) -> bool:
	return (
		is_valid(result)
		and result[KEY_FIELDS].values().has(FIELD_UNSUPPORTED)
	)


static func _normalize_field_outcomes(field_outcomes: Dictionary) -> Dictionary:
	var normalized := {}
	for field: Variant in field_outcomes:
		if field is not String and field is not StringName:
			continue
		var outcome: Variant = field_outcomes[field]
		if outcome is not String and outcome is not StringName:
			continue
		var normalized_outcome := StringName(outcome)
		if normalized_outcome not in FIELD_OUTCOMES:
			continue
		normalized[StringName(field)] = normalized_outcome
	return normalized

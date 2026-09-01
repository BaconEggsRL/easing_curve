extends "res://test/scripts/support/test_case.gd"

const LEGACY_PRE_FLAT_PATH := "res://test/presets/legacy_pre_flat_triangle.tres"
const LEGACY_MISSING_FORCE_PATH := "res://test/presets/legacy_flat_without_force_linear.tres"
const ROUND_TRIP_DIRECTORY := "user://_serialization_transition_contract"
const SAMPLE_INPUTS := [0.0, 0.25, 0.5, 0.75, 1.0]
const SNAPSHOT_CODEC := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_snapshot_codec.gd"
)

func _init() -> void:
	_test_legacy_resource_fixtures()
	_test_missing_snapshot_force_linear_defaults()
	_test_legacy_point_snapshot_fallbacks()
	_test_sparse_point_storage_fallbacks()
	_test_partial_function_snapshot_fallbacks()
	_test_partial_editor_state_snapshot_fallbacks()
	_test_snapshot_schema_and_validation_boundary()
	_test_snapshot_codec_encode_decode_transform_boundary()
	_test_dynamic_storage_and_remaining_codec_boundary()
	_test_enum_numeric_contracts()
	_test_transition_catalog_contract()
	_test_exported_property_contract()
	_test_point_storage_schema()
	_test_point_property_snapshot_lifecycle_contract()
	_test_point_snapshot_property_access()
	_test_bool_snapshot_value_support()
	_cleanup()

	_finish("serialization and transition contract")


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(is_equal_approx(actual, expected), "%s: %f != %f" % [message, actual, expected])


func _vector_arrays_equal_approx(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		if not a[index].is_equal_approx(b[index]):
			return false
	return true


func _property_by_name(object: Object, property_name: StringName) -> Dictionary:
	for property: Dictionary in object.get_property_list():
		if property.name == property_name:
			return property
	return {}


func _expect_property(
		curve: EasingCurve,
		property_name: StringName,
		expected_type: int,
		expected_default: Variant,
		expected_editor: bool,
) -> void:
	var property := _property_by_name(curve, property_name)
	_expect(not property.is_empty(), "%s is missing from property metadata" % property_name)
	if property.is_empty():
		return
	_expect(property.type == expected_type, "%s property type changed" % property_name)
	_expect(bool(property.usage & PROPERTY_USAGE_STORAGE), "%s is no longer stored" % property_name)
	_expect(bool(property.usage & PROPERTY_USAGE_EDITOR) == expected_editor, "%s editor visibility changed" % property_name)
	var actual: Variant = curve.get(property_name)
	if actual is float:
		_expect_approx(actual, expected_default, "%s default changed" % property_name)
	else:
		_expect(actual == expected_default, "%s default changed" % property_name)


func _test_legacy_resource_fixtures() -> void:
	# Historical resource data from commits cefdbd4 (pre-flat) and 2feaa6f
	# (flat storage before handle mode and Force Linear fields).
	_expect(
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROUND_TRIP_DIRECTORY)) == OK,
		"Could not create the temporary current-format round-trip directory",
	)
	var fixtures := [
		{
			"path": LEGACY_PRE_FLAT_PATH,
			"label": "pre-flat Array[Resource] fixture",
			"first_right": Vector2(-0.00048399717, 0.0),
			"last_right": Vector2(1.0, 1.0),
		},
		{
			"path": LEGACY_MISSING_FORCE_PATH,
			"label": "flat fixture without Force Linear fields",
			"first_right": Vector2.ZERO,
			"last_right": Vector2(1.1, 0.0),
		},
	]
	for fixture: Dictionary in fixtures:
		var path: String = fixture.path
		var curve := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EasingCurve
		_expect(curve != null, "%s did not load" % fixture.label)
		if curve == null:
			continue
		_expect(curve.trans_type == EasingCurve.TRANS.CUSTOM, "%s transition changed" % fixture.label)
		_expect(curve.points.size() == 3, "%s point count changed" % fixture.label)
		if curve.points.size() != 3:
			continue
		_expect(curve.points[0].position == Vector2.ZERO, "%s first position changed" % fixture.label)
		_expect(curve.points[1].position == Vector2(0.5, 1.0), "%s midpoint changed" % fixture.label)
		_expect(curve.points[2].position == Vector2(1.0, 0.0), "%s final position changed" % fixture.label)
		_expect(curve.points[0].right_control_point == fixture.first_right, "%s first handle changed" % fixture.label)
		_expect(curve.points[2].right_control_point == fixture.last_right, "%s final handle changed" % fixture.label)
		_expect(not curve.points[0].left_force_linear and not curve.points[0].right_force_linear, "%s Force Linear defaults changed" % fixture.label)
		for point in curve.points:
			_expect(point.handle_mode == EasingCurvePoint.HandleMode.FREE, "%s Handle Mode fallback changed" % fixture.label)
			_expect(
				point.locked == {
					"position": false,
					"left_control_point": false,
					"right_control_point": false,
				},
				"%s lock fallback changed" % fixture.label,
			)
			_expect(not point.left_force_linear and not point.right_force_linear, "%s Force Linear fallback changed" % fixture.label)
		var samples := _samples(curve)
		_expect_approx(samples[0], 0.0, "%s sample at zero changed" % fixture.label)
		_expect_approx(samples[2], 1.0, "%s midpoint sample changed" % fixture.label)
		_expect_approx(samples[4], 0.0, "%s final sample changed" % fixture.label)
		_expect(absf(samples[1] - 0.5) < 0.01, "%s quarter sample changed" % fixture.label)
		_expect(absf(samples[3] - 0.5) < 0.01, "%s three-quarter sample changed" % fixture.label)

		var copy_path := "%s/%s.tres" % [ROUND_TRIP_DIRECTORY, path.get_file().get_basename()]
		_expect(ResourceSaver.save(curve, copy_path) == OK, "%s did not save to current format" % fixture.label)
		var reloaded := ResourceLoader.load(copy_path, "", ResourceLoader.CACHE_MODE_IGNORE) as EasingCurve
		_expect(reloaded != null, "%s current-format copy did not reload" % fixture.label)
		if reloaded != null:
			_expect(_point_snapshots_equal(curve.get_point_snapshot(), reloaded.get_point_snapshot()), "%s point state changed after current-format round trip" % fixture.label)
			_expect(_samples_equal(samples, _samples(reloaded)), "%s samples changed after current-format round trip" % fixture.label)


func _test_missing_snapshot_force_linear_defaults() -> void:
	var curve := EasingCurve.new()
	var snapshot := curve.get_point_snapshot()
	snapshot.erase("left_force_linear")
	snapshot.erase("right_force_linear")
	curve.set_point_snapshot(snapshot)
	for point in curve.points:
		_expect(not point.left_force_linear and not point.right_force_linear, "Missing snapshot Force Linear keys did not default to false")


func _test_legacy_point_snapshot_fallbacks() -> void:
	var legacy_snapshot := {
		"positions": PackedVector2Array([
			Vector2(0.0, 0.0),
			Vector2(0.45, 0.8),
			Vector2(1.0, 1.0),
		]),
		"left_control_points": PackedVector2Array([
			Vector2(-0.1, -0.05),
			Vector2(0.3, 0.7),
			Vector2(0.85, 0.9),
		]),
		"right_control_points": PackedVector2Array([
			Vector2(0.2, 0.3),
			Vector2(0.7, 0.9),
			Vector2(1.1, 1.05),
		]),
	}
	var target := EasingCurve.new()
	target.trans_type = EasingCurve.TRANS.CUSTOM
	target.set_point_snapshot(legacy_snapshot)

	_expect(target.points.size() == 3, "Legacy point snapshot did not rebuild topology from positions")
	if target.points.size() != 3:
		return

	var expected_locks := {
		"position": false,
		"left_control_point": false,
		"right_control_point": false,
	}
	for index in range(target.points.size()):
		var point := target.points[index]
		_expect(point.position == legacy_snapshot.positions[index], "Legacy point snapshot position %d changed" % index)
		_expect(point.left_control_point == legacy_snapshot.left_control_points[index], "Legacy point snapshot left control %d changed" % index)
		_expect(point.right_control_point == legacy_snapshot.right_control_points[index], "Legacy point snapshot right control %d changed" % index)
		_expect(point.handle_mode == EasingCurvePoint.HandleMode.FREE, "Missing Handle Mode did not default to Free at point %d" % index)
		_expect(point.locked == expected_locks, "Missing locks did not default to unlocked at point %d" % index)
		_expect(not point.left_force_linear and not point.right_force_linear, "Missing Force Linear state did not default to false at point %d" % index)


func _test_sparse_point_storage_fallbacks() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.set(EasingCurve.POINT_STORAGE_COUNT, 1)
	curve.set(&"_point_2/position", Vector2(0.75, 0.25))

	_expect(curve.points.size() == 3, "Sparse flat point storage write did not grow point topology")
	if curve.points.size() != 3:
		return
	_expect(curve.points[2].position == Vector2(0.75, 0.25), "Sparse flat point storage write lost its value")

	curve.set(&"_point_2/locked", {"position": true})
	_expect(
		curve.points[2].locked == {
			"position": true,
			"left_control_point": false,
			"right_control_point": false,
		},
		"Partial flat lock storage did not default omitted lock fields to false",
	)


func _test_partial_function_snapshot_fallbacks() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.SPRING
	curve.frequency = 4.25
	curve.decay = 3.75
	var generated_x_before := curve._irregular_points_x.duplicate()
	var generated_y_before := curve._irregular_points_y.duplicate()

	curve.set_function_snapshot({"frequency": 5.5})
	_expect(is_equal_approx(curve.frequency, 5.5), "Partial function snapshot did not apply a present parameter")
	_expect(is_equal_approx(curve.decay, 3.75), "Partial function snapshot did not preserve an omitted parameter")
	_expect(curve._irregular_points_x == generated_x_before, "Partial function snapshot did not preserve omitted generated X data")
	_expect(curve._irregular_points_y == generated_y_before, "Partial function snapshot did not preserve omitted generated Y data")

	curve.set_function_snapshot({
		"generated_points_x": PackedFloat32Array([0.0, 0.5, 1.0]),
		"generated_points_y": PackedFloat64Array([0.0, 0.25, 1.0]),
	})
	_expect(curve._irregular_points_x == [0.0, 0.5, 1.0], "Function snapshot stopped accepting PackedFloat32Array generated data")
	_expect(curve._irregular_points_y == [0.0, 0.25, 1.0], "Function snapshot stopped accepting PackedFloat64Array generated data")

	curve.set_function_snapshot({
		"generated_points_x": [0.0, 0.4, 1.0],
		"generated_points_y": [0.0, 0.6, 1.0],
	})
	_expect(curve._irregular_points_x == [0.0, 0.4, 1.0], "Function snapshot stopped accepting Array generated data")
	_expect(curve._irregular_points_y == [0.0, 0.6, 1.0], "Function snapshot stopped accepting Array generated data")


func _test_partial_editor_state_snapshot_fallbacks() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.BACK
	curve.ease_type = EasingCurve.EASE.OUT
	curve.overshoot = 2.75
	curve.reverse = true
	var point_snapshot_before := curve.get_point_snapshot()
	var function_snapshot_before := curve.get_function_snapshot()

	curve.set_editor_state_snapshot({"invert": true})
	_expect(curve.trans_type == EasingCurve.TRANS.BACK, "Partial editor snapshot changed an omitted transition")
	_expect(curve.ease_type == EasingCurve.EASE.OUT, "Partial editor snapshot changed an omitted Ease")
	_expect(is_equal_approx(curve.overshoot, 2.75), "Partial editor snapshot changed an omitted Bézier parameter")
	_expect(curve.reverse, "Partial editor snapshot changed an omitted Reverse flag")
	_expect(curve.invert, "Partial editor snapshot did not apply a present Invert flag")
	_expect(curve.get_point_snapshot() == point_snapshot_before, "Partial editor snapshot changed omitted point state")
	_expect(curve.get_function_snapshot() == function_snapshot_before, "Partial editor snapshot changed omitted function state")


func _test_snapshot_schema_and_validation_boundary() -> void:
	_expect(SNAPSHOT_CODEC.POINT_SNAPSHOT_PROPERTY == EasingCurve.POINT_SNAPSHOT_PROPERTY, "Point snapshot bridge property name changed")
	_expect(SNAPSHOT_CODEC.FUNCTION_SNAPSHOT_PROPERTY == EasingCurve.FUNCTION_SNAPSHOT_PROPERTY, "Function snapshot bridge property name changed")
	_expect(SNAPSHOT_CODEC.EDITOR_STATE_SNAPSHOT_PROPERTY == EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY, "Editor-state snapshot bridge property name changed")
	_expect(SNAPSHOT_CODEC.POINT_STORAGE_COUNT == EasingCurve.POINT_STORAGE_COUNT, "Point storage count property name changed")
	_expect(SNAPSHOT_CODEC.POINT_STORAGE_PREFIX == EasingCurve.POINT_STORAGE_PREFIX, "Point storage prefix changed")

	var expected_snapshot_keys := {
		&"position": SNAPSHOT_CODEC.POINT_POSITIONS,
		&"left_control_point": SNAPSHOT_CODEC.POINT_LEFT_CONTROL_POINTS,
		&"right_control_point": SNAPSHOT_CODEC.POINT_RIGHT_CONTROL_POINTS,
		&"locked": SNAPSHOT_CODEC.POINT_LOCKS,
		&"handle_mode": SNAPSHOT_CODEC.POINT_HANDLE_MODES,
		&"left_force_linear": SNAPSHOT_CODEC.POINT_LEFT_FORCE_LINEAR,
		&"right_force_linear": SNAPSHOT_CODEC.POINT_RIGHT_FORCE_LINEAR,
	}
	for property_name: StringName in expected_snapshot_keys:
		_expect(
			EasingCurve.get_point_property_snapshot_key(property_name) == expected_snapshot_keys[property_name],
			"Shared snapshot schema key changed for %s" % property_name,
		)

	var legacy_snapshot := {
		"positions": PackedVector2Array([Vector2.ZERO, Vector2.ONE]),
		"left_control_points": PackedVector2Array([Vector2.ZERO, Vector2.ONE]),
		"right_control_points": PackedVector2Array([Vector2.ZERO, Vector2.ONE]),
	}
	var legacy_validation := SNAPSHOT_CODEC.validate_point_snapshot(
		legacy_snapshot,
		EasingCurve.POINT_PROPERTY_DEFINITIONS,
	)
	_expect(bool(legacy_validation.compatible), "Validation rejected a characterized legacy point snapshot")
	_expect(int(legacy_validation.point_count) == 2, "Validation changed point-count discovery")

	var malformed_point_snapshot := legacy_snapshot.duplicate(true)
	malformed_point_snapshot[SNAPSHOT_CODEC.POINT_POSITIONS] = [Vector2.ZERO, Vector2.ONE]
	var malformed_point_validation := SNAPSHOT_CODEC.validate_point_snapshot(
		malformed_point_snapshot,
		EasingCurve.POINT_PROPERTY_DEFINITIONS,
	)
	_expect(not bool(malformed_point_validation.compatible), "Validation accepted Array point positions instead of PackedVector2Array")
	_expect(not malformed_point_validation.errors.is_empty(), "Malformed point validation did not report an error")

	var complete_snapshot := EasingCurve.new().get_point_snapshot()
	_expect(SNAPSHOT_CODEC.can_mutate_point_snapshot(complete_snapshot, 0), "Current point snapshot was rejected by the semantic mutation boundary")
	var partial_snapshot := complete_snapshot.duplicate(true)
	partial_snapshot.erase(SNAPSHOT_CODEC.POINT_HANDLE_MODES)
	_expect(not SNAPSHOT_CODEC.can_mutate_point_snapshot(partial_snapshot, 0), "Semantic mutation boundary accepted missing Handle Mode state")
	_expect(not SNAPSHOT_CODEC.can_mutate_point_snapshot(complete_snapshot, -1), "Semantic mutation boundary accepted a negative point index")

	var function_validation := SNAPSHOT_CODEC.validate_function_snapshot({
		SNAPSHOT_CODEC.FUNCTION_GENERATED_POINTS_X: PackedFloat32Array([0.0, 1.0]),
		SNAPSHOT_CODEC.FUNCTION_GENERATED_POINTS_Y: [0.0, 1.0],
	})
	_expect(bool(function_validation.compatible), "Function snapshot validation rejected characterized array forms")
	var bad_function_validation := SNAPSHOT_CODEC.validate_function_snapshot({
		SNAPSHOT_CODEC.FUNCTION_GENERATED_POINTS_X: "invalid",
	})
	_expect(not bool(bad_function_validation.compatible), "Function snapshot validation accepted an invalid generated-array container")

	var editor_validation := SNAPSHOT_CODEC.validate_editor_state_snapshot({
		SNAPSHOT_CODEC.EDITOR_INVERT: true,
	})
	_expect(bool(editor_validation.compatible), "Editor snapshot validation rejected a characterized partial snapshot")
	var bad_editor_validation := SNAPSHOT_CODEC.validate_editor_state_snapshot({
		SNAPSHOT_CODEC.EDITOR_POINT_SNAPSHOT: [],
	})
	_expect(not bool(bad_editor_validation.compatible), "Editor snapshot validation accepted a non-Dictionary point snapshot")


func _test_snapshot_codec_encode_decode_transform_boundary() -> void:
	var curve := EasingCurve.new()
	var encoded := SNAPSHOT_CODEC.encode_point_snapshot(
		curve.points,
		EasingCurve.POINT_PROPERTY_DEFINITIONS,
	)
	_expect(encoded == curve.get_point_snapshot(), "Codec point encoding diverged from the EasingCurve facade")
	_expect(encoded[SNAPSHOT_CODEC.POINT_POSITIONS] is PackedVector2Array, "Codec point positions changed storage type")
	_expect(encoded[SNAPSHOT_CODEC.POINT_HANDLE_MODES] is PackedInt32Array, "Codec Handle Modes changed storage type")
	_expect(encoded[SNAPSHOT_CODEC.POINT_LEFT_FORCE_LINEAR] is PackedByteArray, "Codec Force Linear changed storage type")
	_expect(encoded[SNAPSHOT_CODEC.POINT_LOCKS] is Array, "Codec locks changed storage type")

	var decoded := SNAPSHOT_CODEC.decode_point_snapshot({
		SNAPSHOT_CODEC.POINT_POSITIONS: PackedVector2Array([Vector2.ZERO, Vector2.ONE]),
		SNAPSHOT_CODEC.POINT_CHANGING: true,
	})
	_expect(decoded[SNAPSHOT_CODEC.POINT_POSITIONS].size() == 2, "Codec point decoding changed topology discovery")
	_expect(decoded[SNAPSHOT_CODEC.POINT_LEFT_CONTROL_POINTS].is_empty(), "Codec point decoding stopped defaulting missing left controls")
	_expect(decoded[SNAPSHOT_CODEC.POINT_RIGHT_CONTROL_POINTS].is_empty(), "Codec point decoding stopped defaulting missing right controls")
	_expect(decoded[SNAPSHOT_CODEC.POINT_HANDLE_MODES].is_empty(), "Codec point decoding stopped defaulting missing Handle Modes")
	_expect(decoded[SNAPSHOT_CODEC.POINT_LOCKS].is_empty(), "Codec point decoding stopped defaulting missing locks")
	_expect(decoded[SNAPSHOT_CODEC.POINT_LEFT_FORCE_LINEAR].is_empty(), "Codec point decoding stopped defaulting missing left Force Linear")
	_expect(decoded[SNAPSHOT_CODEC.POINT_RIGHT_FORCE_LINEAR].is_empty(), "Codec point decoding stopped defaulting missing right Force Linear")
	_expect(decoded[SNAPSHOT_CODEC.POINT_CHANGING], "Codec point decoding lost changing metadata")

	var source := {
		SNAPSHOT_CODEC.POINT_POSITIONS: PackedVector2Array([
			Vector2(0.0, 0.2),
			Vector2(1.0, 0.8),
		]),
		SNAPSHOT_CODEC.POINT_LEFT_CONTROL_POINTS: PackedVector2Array([
			Vector2(-0.1, 0.1),
			Vector2(0.7, 0.7),
		]),
		SNAPSHOT_CODEC.POINT_RIGHT_CONTROL_POINTS: PackedVector2Array([
			Vector2(0.3, 0.3),
			Vector2(1.2, 0.9),
		]),
		SNAPSHOT_CODEC.POINT_HANDLE_MODES: PackedInt32Array([1, 2]),
		SNAPSHOT_CODEC.POINT_LOCKS: [
			{"position": true, "left_control_point": true, "right_control_point": false},
			{"position": false, "left_control_point": false, "right_control_point": true},
		],
		SNAPSHOT_CODEC.POINT_LEFT_FORCE_LINEAR: PackedByteArray([1, 0]),
		SNAPSHOT_CODEC.POINT_RIGHT_FORCE_LINEAR: PackedByteArray([0, 1]),
		"marker": "preserved",
	}
	var reversed := SNAPSHOT_CODEC.reverse_point_snapshot(source, [], 2)
	_expect(_vector_arrays_equal_approx(reversed[SNAPSHOT_CODEC.POINT_POSITIONS], PackedVector2Array([Vector2(0.0, 0.8), Vector2(1.0, 0.2)])), "Codec reverse changed point position semantics")
	_expect(_vector_arrays_equal_approx(reversed[SNAPSHOT_CODEC.POINT_LEFT_CONTROL_POINTS], PackedVector2Array([Vector2(-0.2, 0.9), Vector2(0.7, 0.3)])), "Codec reverse changed left-handle role swapping")
	_expect(_vector_arrays_equal_approx(reversed[SNAPSHOT_CODEC.POINT_RIGHT_CONTROL_POINTS], PackedVector2Array([Vector2(0.3, 0.7), Vector2(1.1, 0.1)])), "Codec reverse changed right-handle role swapping")
	_expect(reversed[SNAPSHOT_CODEC.POINT_HANDLE_MODES] == PackedInt32Array([2, 1]), "Codec reverse changed Handle Mode ordering")
	_expect(reversed[SNAPSHOT_CODEC.POINT_LOCKS][0] == {"position": false, "left_control_point": true, "right_control_point": false}, "Codec reverse changed lock role swapping")
	_expect(reversed[SNAPSHOT_CODEC.POINT_LEFT_FORCE_LINEAR] == PackedByteArray([1, 0]), "Codec reverse changed left Force Linear role swapping")
	_expect(reversed[SNAPSHOT_CODEC.POINT_RIGHT_FORCE_LINEAR] == PackedByteArray([0, 1]), "Codec reverse changed right Force Linear role swapping")
	_expect(reversed.marker == "preserved", "Codec reverse dropped unrelated snapshot metadata")

	var inverted := SNAPSHOT_CODEC.invert_point_snapshot(source)
	_expect(_vector_arrays_equal_approx(inverted[SNAPSHOT_CODEC.POINT_POSITIONS], PackedVector2Array([Vector2(0.0, 0.8), Vector2(1.0, 0.2)])), "Codec invert changed point Y reflection")
	_expect(_vector_arrays_equal_approx(inverted[SNAPSHOT_CODEC.POINT_LEFT_CONTROL_POINTS], PackedVector2Array([Vector2(-0.1, 0.9), Vector2(0.7, 0.3)])), "Codec invert changed left-handle Y reflection")
	_expect(_vector_arrays_equal_approx(inverted[SNAPSHOT_CODEC.POINT_RIGHT_CONTROL_POINTS], PackedVector2Array([Vector2(0.3, 0.7), Vector2(1.2, 0.1)])), "Codec invert changed right-handle Y reflection")
	_expect(inverted[SNAPSHOT_CODEC.POINT_LOCKS] == source[SNAPSHOT_CODEC.POINT_LOCKS], "Codec invert changed lock state")
	_expect(inverted.marker == "preserved", "Codec invert dropped unrelated snapshot metadata")


func _test_dynamic_storage_and_remaining_codec_boundary() -> void:
	var curve := EasingCurve.new()
	curve.set(EasingCurve.POINT_STORAGE_COUNT, 2)
	var codec_properties := SNAPSHOT_CODEC.build_dynamic_property_list(
		2,
		EasingCurve.POINT_PROPERTY_DEFINITIONS,
	)
	_expect(
		curve._get_property_list() == codec_properties,
		"EasingCurve dynamic property list diverged from the codec",
	)
	_expect(
		codec_properties.size() == 4 + 2 * EasingCurve.POINT_PROPERTY_DEFINITIONS.size(),
		"Codec dynamic property list changed its bridge/storage field count",
	)
	_expect(
		codec_properties[0].name == EasingCurve.POINT_SNAPSHOT_PROPERTY
		and codec_properties[1].name == EasingCurve.FUNCTION_SNAPSHOT_PROPERTY
		and codec_properties[2].name == EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY
		and codec_properties[3].name == EasingCurve.POINT_STORAGE_COUNT,
		"Codec dynamic property list changed bridge/storage header ordering",
	)

	var storage_name := SNAPSHOT_CODEC.get_point_storage_name(2, &"right_control_point")
	_expect(storage_name == &"_point_2/right_control_point", "Codec point storage name encoding changed")
	_expect(curve._get_point_storage_name(2, &"right_control_point") == storage_name, "EasingCurve point storage naming diverged from the codec")
	var parsed := SNAPSHOT_CODEC.parse_point_storage_name(
		storage_name,
		EasingCurve.POINT_PROPERTY_DEFINITIONS,
	)
	_expect(parsed == {"index": 2, "name": &"right_control_point"}, "Codec point storage name decoding changed")
	_expect(curve._parse_point_storage_name(storage_name) == parsed, "EasingCurve point storage parsing diverged from the codec")
	_expect(SNAPSHOT_CODEC.parse_point_storage_name(&"_point_x/position", EasingCurve.POINT_PROPERTY_DEFINITIONS).is_empty(), "Codec accepted a non-numeric point storage index")
	_expect(SNAPSHOT_CODEC.parse_point_storage_name(&"_point_0/unknown", EasingCurve.POINT_PROPERTY_DEFINITIONS).is_empty(), "Codec accepted an unknown point storage property")
	_expect(SNAPSHOT_CODEC.parse_point_storage_name(&"position", EasingCurve.POINT_PROPERTY_DEFINITIONS).is_empty(), "Codec accepted a non-storage property name")

	var lock_source := {"position": true}
	var lock_encoded: Dictionary = SNAPSHOT_CODEC.encode_point_storage_value(lock_source)
	lock_source.position = false
	_expect(bool(lock_encoded.position), "Codec point storage value encoding aliased a Dictionary caller")

	var function_parameters := {
		&"frequency": 4.25,
		&"decay": 3.5,
	}
	var generated_x: Array[float] = [0.0, 0.4, 1.0]
	var generated_y: Array[float] = [0.0, 0.7, 1.0]
	var function_snapshot := SNAPSHOT_CODEC.encode_function_snapshot(
		function_parameters,
		generated_x,
		generated_y,
	)
	_expect(is_equal_approx(float(function_snapshot.frequency), 4.25), "Codec function snapshot changed parameter encoding")
	_expect(function_snapshot[SNAPSHOT_CODEC.FUNCTION_GENERATED_POINTS_X] is PackedFloat64Array, "Codec generated function X data changed storage type")
	_expect(function_snapshot[SNAPSHOT_CODEC.FUNCTION_GENERATED_POINTS_Y] is PackedFloat64Array, "Codec generated function Y data changed storage type")
	_expect(function_snapshot[SNAPSHOT_CODEC.FUNCTION_GENERATED_POINTS_X] == PackedFloat64Array(generated_x), "Codec generated function X data changed values")
	_expect(function_snapshot[SNAPSHOT_CODEC.FUNCTION_GENERATED_POINTS_Y] == PackedFloat64Array(generated_y), "Codec generated function Y data changed values")

	var generated_fallback := SNAPSHOT_CODEC.decode_generated_function_snapshot(
		{},
		generated_x,
		generated_y,
	)
	_expect(generated_fallback.points_x == generated_x and generated_fallback.points_y == generated_y, "Codec generated function fallback stopped preserving current values")
	var generated_decoded := SNAPSHOT_CODEC.decode_generated_function_snapshot(
		{
			SNAPSHOT_CODEC.FUNCTION_GENERATED_POINTS_X: PackedFloat32Array([0.0, 0.5, 1.0]),
			SNAPSHOT_CODEC.FUNCTION_GENERATED_POINTS_Y: PackedFloat64Array([0.0, 0.25, 1.0]),
		},
		generated_x,
		generated_y,
	)
	_expect(generated_decoded.points_x == [0.0, 0.5, 1.0], "Codec generated function X decoding changed accepted PackedFloat32Array input")
	_expect(generated_decoded.points_y == [0.0, 0.25, 1.0], "Codec generated function Y decoding changed accepted PackedFloat64Array input")
	_expect(SNAPSHOT_CODEC.function_snapshot_float_array([0, 0.5, 1]) == [0.0, 0.5, 1.0], "Codec function float-array normalization changed")

	curve.trans_type = EasingCurve.TRANS.SPRING
	curve.frequency = 4.25
	curve.decay = 3.5
	curve._irregular_points_x = generated_x
	curve._irregular_points_y = generated_y
	var curve_parameter_values := {}
	for property_name in EasingCurve.get_all_function_parameters():
		curve_parameter_values[property_name] = curve.get(property_name)
	_expect(
		curve.get_function_snapshot() == SNAPSHOT_CODEC.encode_function_snapshot(
			curve_parameter_values,
			curve._irregular_points_x,
			curve._irregular_points_y,
		),
		"EasingCurve function snapshot encoding diverged from the codec",
	)

	var editor_snapshot := SNAPSHOT_CODEC.encode_editor_state_snapshot(
		EasingCurve.EASE.OUT,
		EasingCurve.TRANS.BACK,
		EasingCurve.CurveMode.BEZIER,
		false,
		true,
		false,
		{"overshoot": 2.75},
		{"point": "snapshot"},
		{"function": "snapshot"},
	)
	_expect(editor_snapshot[SNAPSHOT_CODEC.EDITOR_EASE_TYPE] == EasingCurve.EASE.OUT, "Codec editor snapshot changed Ease encoding")
	_expect(editor_snapshot[SNAPSHOT_CODEC.EDITOR_POINT_SNAPSHOT] == {"point": "snapshot"}, "Codec editor snapshot changed nested point snapshot encoding")
	var decoded_editor := SNAPSHOT_CODEC.decode_editor_state_snapshot(
		{SNAPSHOT_CODEC.EDITOR_INVERT: true},
		editor_snapshot,
	)
	_expect(decoded_editor[SNAPSHOT_CODEC.EDITOR_INVERT], "Codec partial editor snapshot did not apply a present flag")
	_expect(decoded_editor[SNAPSHOT_CODEC.EDITOR_REVERSE], "Codec partial editor snapshot did not preserve an omitted flag")
	_expect(decoded_editor[SNAPSHOT_CODEC.EDITOR_TRANS_TYPE] == EasingCurve.TRANS.BACK, "Codec partial editor snapshot did not preserve an omitted transition")
	_expect(decoded_editor[SNAPSHOT_CODEC.EDITOR_POINT_SNAPSHOT] == {"point": "snapshot"}, "Codec partial editor snapshot did not preserve omitted point state")
	var point_ids := PackedInt64Array([12, 34])
	var editor_with_ids := SNAPSHOT_CODEC.with_editor_point_resource_ids(editor_snapshot, point_ids)
	_expect(editor_with_ids[SNAPSHOT_CODEC.EDITOR_POINT_RESOURCE_IDS] == point_ids, "Codec editor snapshot point Resource ID injection changed")
	_expect(not editor_snapshot.has(SNAPSHOT_CODEC.EDITOR_POINT_RESOURCE_IDS), "Codec editor snapshot point Resource ID injection mutated the source snapshot")


func _test_enum_numeric_contracts() -> void:
	_expect(EasingCurve.CurveMode.BEZIER == 0 and EasingCurve.CurveMode.FUNCTION == 1, "CurveMode numeric contract changed")
	_expect(EasingCurve.EASE.IN == 0 and EasingCurve.EASE.OUT == 1 and EasingCurve.EASE.IN_OUT == 2 and EasingCurve.EASE.OUT_IN == 3, "EASE numeric contract changed")
	var transitions := {
		&"CUSTOM": 0, &"CONSTANT": 1, &"LINEAR": 2, &"JITTER": 3, &"IRREGULAR": 4,
		&"STEP": 5, &"POWER": 6, &"QUAD": 7, &"CUBIC": 8, &"QUART": 9,
		&"QUINT": 10, &"EXPO": 11, &"CIRC": 12, &"BACK": 13, &"ELASTIC": 14,
		&"BOUNCE": 15, &"SPRING": 16, &"PHYSICS_SPRING": 17, &"CSS_LINEAR": 18,
		&"SINE": 19, &"CSS_CUBIC_BEZIER": 20,
	}
	for name: StringName in transitions:
		_expect(EasingCurve.TRANS[name] == transitions[name], "TRANS.%s numeric contract changed" % name)
	_expect(EasingCurve.TRANS.size() == transitions.size(), "TRANS membership changed without an explicit contract update")
	_expect(EasingCurvePoint.HandleMode.FREE == 0 and EasingCurvePoint.HandleMode.LINEAR == 1 and EasingCurvePoint.HandleMode.BALANCED == 2 and EasingCurvePoint.HandleMode.MIRRORED == 3 and EasingCurvePoint.HandleMode.LINKED == 4, "HandleMode numeric contract changed")
	_expect(EasingCurvePoint.ControlState.FREE == 0 and EasingCurvePoint.ControlState.LINEAR == 1 and EasingCurvePoint.ControlState.LOCKED == 2, "ControlState numeric contract changed")


func _test_transition_catalog_contract() -> void:
	var function_transitions: Array[EasingCurve.TRANS] = [EasingCurve.TRANS.JITTER, EasingCurve.TRANS.IRREGULAR, EasingCurve.TRANS.STEP, EasingCurve.TRANS.POWER, EasingCurve.TRANS.ELASTIC, EasingCurve.TRANS.BOUNCE, EasingCurve.TRANS.SPRING, EasingCurve.TRANS.PHYSICS_SPRING, EasingCurve.TRANS.CSS_LINEAR, EasingCurve.TRANS.CSS_CUBIC_BEZIER]
	var generated: Array[EasingCurve.TRANS] = [EasingCurve.TRANS.JITTER, EasingCurve.TRANS.IRREGULAR]
	var function_classes: Array[EasingCurve.TRANS] = [EasingCurve.TRANS.JITTER, EasingCurve.TRANS.IRREGULAR, EasingCurve.TRANS.STEP, EasingCurve.TRANS.POWER, EasingCurve.TRANS.ELASTIC, EasingCurve.TRANS.BOUNCE, EasingCurve.TRANS.SPRING, EasingCurve.TRANS.PHYSICS_SPRING, EasingCurve.TRANS.CSS_LINEAR, EasingCurve.TRANS.CSS_CUBIC_BEZIER]
	var function_class_contracts := {
		EasingCurve.TRANS.JITTER: {"class": EasingCurve.EASING_LIBRARY.Irregular, "extended": false},
		EasingCurve.TRANS.IRREGULAR: {"class": EasingCurve.EASING_LIBRARY.Irregular, "extended": false},
		EasingCurve.TRANS.STEP: {"class": EasingCurve.EASING_LIBRARY.Step, "extended": false},
		EasingCurve.TRANS.POWER: {"class": EasingCurve.EASING_LIBRARY.Power, "extended": false},
		EasingCurve.TRANS.ELASTIC: {"class": EasingCurve.EASING_LIBRARY.Elastic, "extended": true},
		EasingCurve.TRANS.BOUNCE: {"class": EasingCurve.EASING_LIBRARY.Bounce, "extended": true},
		EasingCurve.TRANS.SPRING: {"class": EasingCurve.EASING_LIBRARY.Spring, "extended": true},
		EasingCurve.TRANS.PHYSICS_SPRING: {"class": EasingCurve.EASING_LIBRARY.PhysicsSpring, "extended": true},
		EasingCurve.TRANS.CSS_LINEAR: {"class": EasingCurve.EASING_LIBRARY.CSSLinear, "extended": true},
		EasingCurve.TRANS.CSS_CUBIC_BEZIER: {"class": EasingCurve.EASING_LIBRARY.CSSCubicBezier, "extended": true},
	}
	var parameters := {
		EasingCurve.TRANS.CONSTANT: [&"constant_value"], EasingCurve.TRANS.BACK: [&"overshoot"],
		EasingCurve.TRANS.JITTER: [&"num_points", &"randomness"], EasingCurve.TRANS.IRREGULAR: [&"num_points", &"randomness"],
		EasingCurve.TRANS.STEP: [&"steps", &"from_start", &"y_offset"], EasingCurve.TRANS.POWER: [&"power"],
		EasingCurve.TRANS.ELASTIC: [&"amplitude", &"period"], EasingCurve.TRANS.BOUNCE: [&"num_bounces", &"bounce_damping"],
		EasingCurve.TRANS.SPRING: [&"frequency", &"decay"], EasingCurve.TRANS.PHYSICS_SPRING: [&"stiffness", &"damping", &"mass", &"velocity"],
	}
	var editor_properties := {
		EasingCurve.TRANS.JITTER: [&"generate_tool_button"], EasingCurve.TRANS.IRREGULAR: [&"generate_tool_button"],
		EasingCurve.TRANS.CSS_LINEAR: [&"css_linear"], EasingCurve.TRANS.CSS_CUBIC_BEZIER: [&"css_cubic_bezier"],
	}
	var transitions_without_ease: Array[EasingCurve.TRANS] = [EasingCurve.TRANS.CUSTOM, EasingCurve.TRANS.CONSTANT, EasingCurve.TRANS.LINEAR, EasingCurve.TRANS.STEP, EasingCurve.TRANS.CSS_LINEAR, EasingCurve.TRANS.CSS_CUBIC_BEZIER]
	_expect(EasingCurve.TRANSITION_DEFINITIONS.size() == EasingCurve.TRANS.size(), "TRANSITION_DEFINITIONS membership changed")
	for transition in EasingCurve.TRANS.values():
		var definition := EasingCurve.get_transition_definition(transition)
		_expect(not definition.is_empty(), "%s is missing a transition definition" % EasingCurve.TRANS.keys()[transition])
		var mode: int = int(definition.get("mode", -1))
		_expect(mode == EasingCurve.CurveMode.BEZIER or mode == EasingCurve.CurveMode.FUNCTION, "%s has an invalid transition definition mode" % EasingCurve.TRANS.keys()[transition])
		var expected_function: bool = transition in function_transitions
		_expect(mode == (EasingCurve.CurveMode.FUNCTION if expected_function else EasingCurve.CurveMode.BEZIER), "%s transition definition mode changed" % EasingCurve.TRANS.keys()[transition])
		_expect(EasingCurve.is_function_transition(transition) == expected_function, "%s transition definition function classification changed" % EasingCurve.TRANS.keys()[transition])
		var expected_supports_ease: bool = transition not in transitions_without_ease
		_expect(definition.has("supports_ease") and bool(definition.get("supports_ease", false)) == expected_supports_ease, "%s transition definition Ease support changed" % EasingCurve.TRANS.keys()[transition])
		_expect(EasingCurve.transition_supports_ease(transition) == expected_supports_ease, "%s transition Ease support changed" % EasingCurve.TRANS.keys()[transition])
		var expected_generated: bool = transition in generated
		_expect(bool(definition.get("generated", false)) == expected_generated, "%s transition definition generated-data contract changed" % EasingCurve.TRANS.keys()[transition])
		_expect(EasingCurve.uses_generated_function_data(transition) == expected_generated, "%s generated-data registration changed" % EasingCurve.TRANS.keys()[transition])
		var expected_class: Dictionary = function_class_contracts.get(transition, {})
		_expect(definition.get("class") == expected_class.get("class"), "%s transition definition class changed" % EasingCurve.TRANS.keys()[transition])
		_expect(bool(definition.get("extended", false)) == bool(expected_class.get("extended", false)), "%s transition definition extended class flag changed" % EasingCurve.TRANS.keys()[transition])
		var expected_parameters: Array = parameters.get(transition, [])
		_expect(definition.get("parameters", []) == expected_parameters, "%s transition definition parameters changed" % EasingCurve.TRANS.keys()[transition])
		_expect(definition.get("editor_properties", []) == editor_properties.get(transition, []), "%s transition definition editor properties changed" % EasingCurve.TRANS.keys()[transition])
	for transition in EasingCurve.TRANS.values():
		var expected_function: bool = transition in function_transitions
		_expect(EasingCurve.is_function_transition(transition) == expected_function, "%s function-mode registration changed" % EasingCurve.TRANS.keys()[transition])
		var curve := EasingCurve.new()
		curve.trans_type = transition
		_expect((curve.curve_mode == EasingCurve.CurveMode.FUNCTION) == expected_function, "%s curve mode registration changed" % EasingCurve.TRANS.keys()[transition])
		if expected_function:
			_expect(curve.function_callable.is_valid(), "%s callable was not initialized" % EasingCurve.TRANS.keys()[transition])
			_expect(not is_nan(curve.sample(0.37)) and not is_inf(curve.sample(0.37)), "%s callable produced a non-finite sample" % EasingCurve.TRANS.keys()[transition])
		_expect(EasingCurve.get_transition_parameters(transition) == parameters.get(transition, []), "%s transition parameter order changed" % EasingCurve.TRANS.keys()[transition])
		_expect(EasingCurve.get_transition_editor_properties(transition) == editor_properties.get(transition, []), "%s transition editor property order changed" % EasingCurve.TRANS.keys()[transition])
	var jitter_curve := EasingCurve.new()
	jitter_curve.trans_type = EasingCurve.TRANS.JITTER
	var jitter_points_x: Array[float] = jitter_curve._irregular_points_x
	var jitter_points_y: Array[float] = jitter_curve._irregular_points_y
	for sample_x: float in [0.15, 0.42, 0.8]:
		var expected_sample: float = float(EasingCurve.EASING_LIBRARY.Irregular.easeIn(
			sample_x,
			0.0,
			1.0,
			1.0,
			jitter_points_x,
			jitter_points_y,
		))
		_expect(
			is_equal_approx(jitter_curve.sample(sample_x), expected_sample),
			"JITTER no longer uses the generated-array Irregular backend",
		)
	_expect(EasingCurve.NON_DEFERRED_FUNCTION_PARAMETERS == [&"from_start"], "Non-deferred parameter contract changed")


func _test_exported_property_contract() -> void:
	var curve := EasingCurve.new()
	_expect_property(curve, &"ease_type", TYPE_INT, EasingCurve.EASE.IN, false)
	_expect_property(curve, &"trans_type", TYPE_INT, EasingCurve.TRANS.LINEAR, false)
	_expect_property(curve, &"reverse", TYPE_BOOL, false, true)
	_expect_property(curve, &"invert", TYPE_BOOL, false, true)
	var contracts := {
		&"constant_value": [EasingCurve.TRANS.CONSTANT, TYPE_FLOAT, 0.5], &"overshoot": [EasingCurve.TRANS.BACK, TYPE_FLOAT, 1.70158],
		&"num_points": [EasingCurve.TRANS.JITTER, TYPE_INT, 3], &"randomness": [EasingCurve.TRANS.JITTER, TYPE_FLOAT, 3.5],
		&"steps": [EasingCurve.TRANS.STEP, TYPE_INT, 4], &"from_start": [EasingCurve.TRANS.STEP, TYPE_BOOL, false], &"y_offset": [EasingCurve.TRANS.STEP, TYPE_FLOAT, 0.0],
		&"power": [EasingCurve.TRANS.POWER, TYPE_FLOAT, 2.0], &"amplitude": [EasingCurve.TRANS.ELASTIC, TYPE_FLOAT, 1.0], &"period": [EasingCurve.TRANS.ELASTIC, TYPE_FLOAT, 0.3],
		&"num_bounces": [EasingCurve.TRANS.BOUNCE, TYPE_INT, 3], &"bounce_damping": [EasingCurve.TRANS.BOUNCE, TYPE_FLOAT, 75.0],
		&"frequency": [EasingCurve.TRANS.SPRING, TYPE_FLOAT, 2.5], &"decay": [EasingCurve.TRANS.SPRING, TYPE_FLOAT, 2.2],
		&"stiffness": [EasingCurve.TRANS.PHYSICS_SPRING, TYPE_FLOAT, 100.0], &"damping": [EasingCurve.TRANS.PHYSICS_SPRING, TYPE_FLOAT, 10.0], &"mass": [EasingCurve.TRANS.PHYSICS_SPRING, TYPE_FLOAT, 1.0], &"velocity": [EasingCurve.TRANS.PHYSICS_SPRING, TYPE_FLOAT, 0.0],
		&"css_linear": [EasingCurve.TRANS.CSS_LINEAR, TYPE_STRING, "linear(0, 1)"], &"css_cubic_bezier": [EasingCurve.TRANS.CSS_CUBIC_BEZIER, TYPE_STRING, "cubic-bezier(0.25, 0.1, 0.25, 1)"],
	}
	for property_name: StringName in contracts:
		var contract: Array = contracts[property_name]
		curve.trans_type = contract[0]
		_expect_property(curve, property_name, contract[1], contract[2], true)


func _test_point_storage_schema() -> void:
	var curve := EasingCurve.new()
	curve.set("_point_count", 3)
	var expected_names: Array[StringName] = [EasingCurve.POINT_STORAGE_COUNT]
	var expected_definitions: Array[Dictionary] = [
		{"name": &"position", "type": TYPE_VECTOR2, "snapshot_key": &"positions", "default": Vector2.ZERO, "inspector_visible": true, "editor_kind": EasingCurve.POINT_EDITOR_KIND_VECTOR2, "snapshot_lifecycle": EasingCurve.POINT_SNAPSHOT_LIFECYCLE_SEMANTIC},
		{"name": &"left_control_point", "type": TYPE_VECTOR2, "snapshot_key": &"left_control_points", "default": Vector2.ZERO, "inspector_visible": true, "editor_kind": EasingCurve.POINT_EDITOR_KIND_VECTOR2, "snapshot_lifecycle": EasingCurve.POINT_SNAPSHOT_LIFECYCLE_SEMANTIC},
		{"name": &"right_control_point", "type": TYPE_VECTOR2, "snapshot_key": &"right_control_points", "default": Vector2.ZERO, "inspector_visible": true, "editor_kind": EasingCurve.POINT_EDITOR_KIND_VECTOR2, "snapshot_lifecycle": EasingCurve.POINT_SNAPSHOT_LIFECYCLE_SEMANTIC},
		{"name": &"locked", "type": TYPE_DICTIONARY, "snapshot_key": &"locks", "default": {"position": false, "left_control_point": false, "right_control_point": false}, "inspector_visible": false, "snapshot_lifecycle": EasingCurve.POINT_SNAPSHOT_LIFECYCLE_SEMANTIC},
		{"name": &"handle_mode", "type": TYPE_INT, "snapshot_key": &"handle_modes", "default": EasingCurvePoint.HandleMode.FREE, "inspector_visible": true, "editor_kind": EasingCurve.POINT_EDITOR_KIND_HANDLE_MODE, "snapshot_lifecycle": EasingCurve.POINT_SNAPSHOT_LIFECYCLE_SEMANTIC},
		{"name": &"left_force_linear", "type": TYPE_BOOL, "snapshot_key": &"left_force_linear", "default": false, "inspector_visible": false, "snapshot_lifecycle": EasingCurve.POINT_SNAPSHOT_LIFECYCLE_SEMANTIC},
		{"name": &"right_force_linear", "type": TYPE_BOOL, "snapshot_key": &"right_force_linear", "default": false, "inspector_visible": false, "snapshot_lifecycle": EasingCurve.POINT_SNAPSHOT_LIFECYCLE_SEMANTIC},
	]
	_expect(EasingCurve.POINT_PROPERTY_DEFINITIONS.size() == expected_definitions.size(), "Point property definition count changed")
	for definition_index in range(expected_definitions.size()):
		var expected_definition := expected_definitions[definition_index]
		var definition: Dictionary = EasingCurve.POINT_PROPERTY_DEFINITIONS[definition_index]
		_expect(definition.get("name") == expected_definition.name, "Point property definition order changed at index %d" % definition_index)
		_expect(definition.get("type") == expected_definition.type, "Point property type changed for %s" % expected_definition.name)
		_expect(definition.get("snapshot_key") == expected_definition.snapshot_key, "Point property snapshot key changed for %s" % expected_definition.name)
		_expect(EasingCurve.get_point_property_snapshot_key(expected_definition.name) == expected_definition.snapshot_key, "Point property snapshot key lookup changed for %s" % expected_definition.name)
		_expect(EasingCurve.get_point_property_snapshot_lifecycle(expected_definition.name) == expected_definition.snapshot_lifecycle, "Point property snapshot lifecycle changed for %s" % expected_definition.name)
		_expect(definition.get("default") == expected_definition.default, "Point property default changed for %s" % expected_definition.name)
		_expect(definition.get("inspector_visible") == expected_definition.inspector_visible, "Point property Inspector visibility changed for %s" % expected_definition.name)
		if expected_definition.has("editor_kind"):
			_expect(definition.get("editor_kind") == expected_definition.editor_kind, "Point property editor kind changed for %s" % expected_definition.name)
			_expect(EasingCurve.get_point_property_editor_kind(expected_definition.name) == expected_definition.editor_kind, "Point property editor kind lookup changed for %s" % expected_definition.name)
		else:
			_expect(not definition.has("editor_kind"), "Hidden storage property %s unexpectedly gained an editor kind" % expected_definition.name)
		_expect(EasingCurve.get_point_property_default(expected_definition.name) == expected_definition.default, "Point property default lookup changed for %s" % expected_definition.name)
		_expect(EasingCurve.is_point_property_resettable(expected_definition.name) == expected_definition.inspector_visible, "Point property reset eligibility changed for %s" % expected_definition.name)
		_expect(EasingCurve.is_point_property_copy_paste_enabled(expected_definition.name) == expected_definition.inspector_visible, "Point property copy/paste eligibility changed for %s" % expected_definition.name)
	for index in range(3):
		for property_name in EasingCurve.POINT_PROPERTIES:
			expected_names.append(StringName("_point_%d/%s" % [index, property_name]))
	_expect(EasingCurve.POINT_PROPERTIES == [&"position", &"left_control_point", &"right_control_point", &"locked", &"handle_mode", &"left_force_linear", &"right_force_linear"], "POINT_PROPERTIES schema order changed")
	for property_name in expected_names:
		var property := _property_by_name(curve, property_name)
		_expect(not property.is_empty(), "%s is missing from the primitive point schema" % property_name)
		if not property.is_empty():
			_expect(bool(property.usage & PROPERTY_USAGE_STORAGE), "%s is no longer stored" % property_name)
			_expect(not bool(property.usage & PROPERTY_USAGE_EDITOR), "%s unexpectedly became an Inspector field" % property_name)
			if property_name != EasingCurve.POINT_STORAGE_COUNT:
				var parsed_name := String(property_name).get_slice("/", 1)
				var definition := EasingCurve.get_point_property_definition(parsed_name)
				_expect(not definition.is_empty() and property.type == definition.type, "%s storage type no longer matches its descriptor" % property_name)
	var points_property := _property_by_name(curve, &"points")
	_expect(not points_property.is_empty() and bool(points_property.usage & PROPERTY_USAGE_EDITOR) and not bool(points_property.usage & PROPERTY_USAGE_STORAGE), "points no longer remains editor-visible and non-storage")
	var snapshot := curve.get_point_snapshot()
	for key in [&"positions", &"left_control_points", &"right_control_points", &"handle_modes", &"locks", &"left_force_linear", &"right_force_linear"]:
		_expect(snapshot.has(key), "Point snapshot key %s is missing" % key)
	_expect(not EasingCurve.POINT_PROPERTIES.has(&"changing"), "Snapshot changing metadata became a point property")


func _test_point_property_snapshot_lifecycle_contract() -> void:
	for definition: Dictionary in EasingCurve.POINT_PROPERTY_DEFINITIONS:
		var property_name: StringName = definition["name"]
		_expect(definition.has("snapshot_lifecycle"), "%s is missing snapshot lifecycle metadata" % property_name)
		_expect(
			EasingCurve.get_point_property_snapshot_lifecycle(property_name) in [
				EasingCurve.POINT_SNAPSHOT_LIFECYCLE_ORDINARY,
				EasingCurve.POINT_SNAPSHOT_LIFECYCLE_SEMANTIC,
			],
			"%s has an invalid snapshot lifecycle" % property_name,
		)
	_expect(
		EasingCurve.get_point_property_definition_snapshot_lifecycle({
			"name": &"malformed_missing_lifecycle",
		}) == StringName(),
		"Missing snapshot lifecycle was accepted",
	)
	_expect(
		EasingCurve.get_point_property_definition_snapshot_lifecycle({
			"name": &"malformed_invalid_lifecycle",
			"snapshot_lifecycle": &"invalid",
		}) == StringName(),
		"Invalid snapshot lifecycle was accepted",
	)
	_expect(
		EasingCurve.get_point_property_definition_snapshot_lifecycle({
			"snapshot_lifecycle": EasingCurve.POINT_SNAPSHOT_LIFECYCLE_ORDINARY,
		}) == EasingCurve.POINT_SNAPSHOT_LIFECYCLE_ORDINARY,
		"Valid ordinary snapshot lifecycle was rejected",
	)
	_expect(
		EasingCurve.get_point_property_definition_snapshot_lifecycle({
			"snapshot_lifecycle": EasingCurve.POINT_SNAPSHOT_LIFECYCLE_SEMANTIC,
		}) == EasingCurve.POINT_SNAPSHOT_LIFECYCLE_SEMANTIC,
		"Valid semantic snapshot lifecycle was rejected",
	)
	_expect(
		EasingCurve.get_point_property_snapshot_lifecycle(&"unknown") == StringName(),
		"Unknown point property lifecycle was accepted",
	)


func _test_point_snapshot_property_access() -> void:
	var curve := EasingCurve.new()
	var snapshot := curve.get_point_snapshot()
	var values := {
		&"position": Vector2(0.25, 0.75),
		&"left_control_point": Vector2(0.1, 0.2),
		&"right_control_point": Vector2(0.9, 0.8),
		&"locked": {"position": true, "left_control_point": false, "right_control_point": true},
		&"handle_mode": EasingCurvePoint.HandleMode.MIRRORED,
		&"left_force_linear": true,
		&"right_force_linear": false,
	}
	for property_name: StringName in values:
		_expect(EasingCurve.set_point_snapshot_property_value(snapshot, property_name, 0, values[property_name]), "Snapshot setter rejected %s" % property_name)
		_expect(EasingCurve.get_point_snapshot_property_value(snapshot, property_name, 0) == values[property_name], "Snapshot getter/setter changed %s" % property_name)
	_expect(snapshot["positions"] is PackedVector2Array and snapshot["handle_modes"] is PackedInt32Array and snapshot["left_force_linear"] is PackedByteArray and snapshot["locks"] is Array, "Snapshot helper changed existing storage types")
	var locks: Dictionary = values[&"locked"]
	locks["position"] = false
	_expect(bool(EasingCurve.get_point_snapshot_property_value(snapshot, &"locked", 0).get("position", false)), "Snapshot lock value unexpectedly aliased caller Dictionary")
	_expect(not EasingCurve.set_point_snapshot_property_value(snapshot, &"position", -1, Vector2.ZERO), "Snapshot setter accepted a negative index")
	_expect(not EasingCurve.set_point_snapshot_property_value(snapshot, &"position", 99, Vector2.ZERO), "Snapshot setter accepted an invalid index")
	_expect(not EasingCurve.set_point_snapshot_property_value(snapshot, &"position", 0, true), "Snapshot setter accepted an invalid value type")
	_expect(EasingCurve.get_point_snapshot_property_value(snapshot, &"unknown", 0) == null and not EasingCurve.set_point_snapshot_property_value(snapshot, &"unknown", 0, 0), "Unknown snapshot property was accepted")


func _test_bool_snapshot_value_support() -> void:
	var values: Variant = EasingCurve._create_point_snapshot_values(TYPE_BOOL)
	_expect(values is PackedByteArray, "Boolean snapshot values no longer use PackedByteArray")
	_expect(EasingCurve._append_point_snapshot_value(values, TYPE_BOOL, false), "Boolean snapshot values rejected false")
	_expect(EasingCurve._append_point_snapshot_value(values, TYPE_BOOL, true), "Boolean snapshot values rejected true")
	var reversed: Variant = EasingCurve._reverse_point_snapshot_values(values, TYPE_BOOL)
	_expect(reversed is PackedByteArray, "Reversed Boolean snapshot values changed storage type")
	_expect(reversed == PackedByteArray([1, 0]), "Boolean snapshot reversal did not normalize PackedByteArray values")


func _samples(curve: EasingCurve) -> PackedFloat64Array:
	var samples := PackedFloat64Array()
	for input: float in SAMPLE_INPUTS:
		samples.append(curve.sample(input))
	return samples


func _samples_equal(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		if not is_equal_approx(a[index], b[index]):
			return false
	return true


func _point_snapshots_equal(a: Dictionary, b: Dictionary) -> bool:
	for key in [&"positions", &"left_control_points", &"right_control_points", &"handle_modes", &"locks", &"left_force_linear", &"right_force_linear"]:
		if a.get(key) != b.get(key):
			return false
	return true


func _cleanup() -> void:
	for fixture_path in [LEGACY_PRE_FLAT_PATH, LEGACY_MISSING_FORCE_PATH]:
		var copy_path := "%s/%s.tres" % [ROUND_TRIP_DIRECTORY, fixture_path.get_file().get_basename()]
		DirAccess.remove_absolute(ProjectSettings.globalize_path(copy_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUND_TRIP_DIRECTORY))

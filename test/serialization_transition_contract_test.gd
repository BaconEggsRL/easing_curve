extends SceneTree

const LEGACY_PRE_FLAT_PATH := "res://test/presets/legacy_pre_flat_triangle.tres"
const LEGACY_MISSING_FORCE_PATH := "res://test/presets/legacy_flat_without_force_linear.tres"
const ROUND_TRIP_DIRECTORY := "res://test/_serialization_transition_contract"
const SAMPLE_INPUTS := [0.0, 0.25, 0.5, 0.75, 1.0]

var _failures := 0
var _checks := 0


func _init() -> void:
	_test_legacy_resource_fixtures()
	_test_missing_snapshot_force_linear_defaults()
	_test_enum_numeric_contracts()
	_test_transition_catalog_contract()
	_test_exported_property_contract()
	_test_point_storage_schema()
	_test_point_property_snapshot_lifecycle_contract()
	_test_point_snapshot_property_access()
	_test_bool_snapshot_value_support()
	_cleanup()

	if _failures == 0:
		print("PASS: %d serialization and transition contract checks" % _checks)
		quit(0)
	else:
		push_error("FAIL: %d of %d serialization and transition contract checks failed" % [_failures, _checks])
		quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(is_equal_approx(actual, expected), "%s: %f != %f" % [message, actual, expected])


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
	var function_classes: Array[EasingCurve.TRANS] = [EasingCurve.TRANS.STEP, EasingCurve.TRANS.POWER, EasingCurve.TRANS.ELASTIC, EasingCurve.TRANS.BOUNCE, EasingCurve.TRANS.SPRING, EasingCurve.TRANS.PHYSICS_SPRING, EasingCurve.TRANS.CSS_LINEAR, EasingCurve.TRANS.CSS_CUBIC_BEZIER]
	var function_class_contracts := {
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
	_expect(EasingCurve.FUNCTION_TRANSITIONS == function_transitions, "FUNCTION_TRANSITIONS registration or order changed")
	_expect(EasingCurve.GENERATED_FUNCTION_TRANSITIONS == generated, "Generated transition registration changed")
	_expect(EasingCurve.FUNCTION_CLASSES.keys().size() == function_classes.size(), "FUNCTION_CLASSES membership changed")
	for transition in function_classes:
		_expect(EasingCurve.FUNCTION_CLASSES.has(transition), "%s lost its function class" % EasingCurve.TRANS.keys()[transition])
		if EasingCurve.FUNCTION_CLASSES.has(transition):
			var actual_class: Dictionary = EasingCurve.FUNCTION_CLASSES[transition]
			var expected_class: Dictionary = function_class_contracts[transition]
			_expect(actual_class.get("class") == expected_class.class, "%s function class changed" % EasingCurve.TRANS.keys()[transition])
			_expect(actual_class.get("extended") == expected_class.extended, "%s callable ease variant changed" % EasingCurve.TRANS.keys()[transition])
	for transition in EasingCurve.TRANS.values():
		var expected_function: bool = transition in function_transitions
		_expect(EasingCurve.is_function_transition(transition) == expected_function, "%s function-mode registration changed" % EasingCurve.TRANS.keys()[transition])
		var curve := EasingCurve.new()
		curve.trans_type = transition
		_expect((curve.curve_mode == EasingCurve.CurveMode.FUNCTION) == expected_function, "%s curve mode registration changed" % EasingCurve.TRANS.keys()[transition])
		if expected_function:
			_expect(curve.function_callable.is_valid(), "%s callable was not initialized" % EasingCurve.TRANS.keys()[transition])
			_expect(not is_nan(curve.sample(0.37)) and not is_inf(curve.sample(0.37)), "%s callable produced a non-finite sample" % EasingCurve.TRANS.keys()[transition])
		var expected_bezier: Array = parameters.get(transition, [])
		_expect(EasingCurve.BEZIER_PARAMETERS.get(transition, []) == expected_bezier if transition in [EasingCurve.TRANS.CONSTANT, EasingCurve.TRANS.BACK] else EasingCurve.BEZIER_PARAMETERS.get(transition, []) == [], "%s Bezier parameter registration changed" % EasingCurve.TRANS.keys()[transition])
		var expected_function_parameters: Array = parameters.get(transition, []) if expected_function else []
		_expect(EasingCurve.FUNCTION_PARAMETERS.get(transition, []) == expected_function_parameters, "%s function parameter order changed" % EasingCurve.TRANS.keys()[transition])
		_expect(EasingCurve.FUNCTION_EDITOR_PROPERTIES.get(transition, []) == editor_properties.get(transition, []), "%s editor property registration changed" % EasingCurve.TRANS.keys()[transition])
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

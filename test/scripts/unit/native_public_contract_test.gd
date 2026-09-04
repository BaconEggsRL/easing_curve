extends "res://test/scripts/support/test_case.gd"

const LEGACY_CURVE_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve.gd"
)
const LEGACY_POINT_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/point.gd"
)
const CONVERSION_RESULT := preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_conversion_result.gd"
)
const NATIVE_FIXTURE_ROOT := "res://test/presets/native/contracts/"

const LEGACY_CURVE_METHODS := [
	"add_point", "auto_smooth_handles", "build_ordered_points_with_endpoint_takeover",
	"clear_function", "cubic_bezier", "cubic_bezier_pair", "derivative", "do_nothing",
	"force_update", "generate_from_function", "generate_irregular", "get_all_bezier_parameters",
	"get_all_function_parameters", "get_all_parameters", "get_bezier_fallback_value",
	"get_canonical_preset_point_snapshot", "get_default_for_property", "get_editor_state_snapshot",
	"get_function_parameter_default", "get_function_snapshot", "get_last_solved_t",
	"get_parameter_default", "get_point_property_default", "get_point_property_definition",
	"get_point_property_definition_snapshot_lifecycle", "get_point_property_editor_kind",
	"get_point_property_snapshot_key", "get_point_property_snapshot_lifecycle",
	"get_point_snapshot", "get_point_snapshot_property_value", "get_transition_definition",
	"get_transition_editor_properties", "get_transition_parameters", "has_builtin_bezier_preset",
	"has_function_parameter_default", "has_parameter_default", "is_deferred_function_parameter",
	"is_deferred_parameter", "is_function_transition", "is_left_endpoint_x",
	"is_point_property_copy_paste_enabled", "is_point_property_inspector_visible",
	"is_point_property_resettable", "is_point_property_snapshot_lifecycle_ordinary",
	"is_right_endpoint_x", "is_selected_preset_modified", "make_point_snapshot", "notify_changed",
	"printpoints", "remove_point", "reset_selected_preset", "sample", "sample_bezier_points",
	"sample_bezier_segment", "set_ease", "set_editor_state_snapshot", "set_function",
	"set_function_snapshot", "set_point", "set_point_locked", "set_point_property",
	"set_point_snapshot", "set_point_snapshot_property_value", "set_trans", "sort_point_list_by_x",
	"sort_points", "swap_points", "swap_properties", "transition_supports_ease",
	"uses_generated_function_data",
]
const LEGACY_POINT_METHODS := [
	"get_control_point_pair", "get_handles_for_mode_change", "is_control_force_linear_active",
	"is_control_forced_linear", "is_control_position_editable", "is_lock_active",
	"is_lockable_property", "is_position_input_editable", "move_horizontally",
	"set_force_linear_state", "set_handle_display_scale", "set_handle_mode",
	"set_left_control_point", "set_left_force_linear", "set_locked", "set_locks",
	"set_position", "set_right_control_point", "set_right_force_linear", "supports_control_state",
]
const NATIVE_CURVE_METHODS := [
	"_apply_live_editor_snapshot", "add_point", "apply_point_states", "apply_point_topology_snapshot", "bake_callable", "begin_point_edit", "capture_point_states", "clear_points",
	"create_runtime_copy", "cubic_bezier", "get_amplitude", "get_constant_value", "get_damping",
	"get_decay", "get_ease_type", "get_editor_state_snapshot", "get_format_status", "get_format_version", "get_frequency",
	"get_mass", "get_overshoot", "get_period", "get_point", "get_point_count", "get_points",
	"get_power", "get_steps", "get_stiffness", "get_transition", "get_velocity", "get_y_offset",
	"insert_point", "is_builtin_bezier_preset", "is_format_supported", "is_from_start", "is_invert", "is_preset_override_active", "is_reverse", "is_selected_preset_modified",
	"remove_point", "sample", "set_amplitude", "set_constant_value", "set_damping", "set_decay",
	"reset_selected_preset", "set_ease_type", "set_editor_state_snapshot", "set_format_version", "set_frequency", "set_from_start", "set_invert",
	"set_mass", "set_overshoot", "set_period", "set_point", "set_points", "set_power",
	"set_preset_override_active", "set_reverse", "set_steps", "set_stiffness", "set_transition", "set_velocity", "set_y_offset", "finish_point_edit",
]
const NATIVE_POINT_METHODS := [
	"apply_state", "capture_state", "get_handle_mode", "get_left_control_point", "get_locks",
	"get_position", "get_right_control_point", "is_left_force_linear", "is_lock_active",
	"is_right_force_linear", "set_handle_mode", "set_left_control_point",
	"set_left_force_linear", "set_locked", "set_locks", "set_position",
	"set_right_control_point", "set_right_force_linear",
]

const LEGACY_CURVE_PROPERTIES := {
	"amplitude": TYPE_FLOAT,
	"bounce_damping": TYPE_FLOAT,
	"constant_value": TYPE_FLOAT,
	"css_cubic_bezier": TYPE_STRING,
	"css_linear": TYPE_STRING,
	"curve_mode": TYPE_INT,
	"damping": TYPE_FLOAT,
	"decay": TYPE_FLOAT,
	"ease_type": TYPE_INT,
	"easing_curve_editor": TYPE_BOOL,
	"frequency": TYPE_FLOAT,
	"from_start": TYPE_BOOL,
	"function_callable": TYPE_CALLABLE,
	"generate_tool_button": TYPE_CALLABLE,
	"invert": TYPE_BOOL,
	"mass": TYPE_FLOAT,
	"num_bounces": TYPE_INT,
	"num_points": TYPE_INT,
	"overshoot": TYPE_FLOAT,
	"period": TYPE_FLOAT,
	"points": TYPE_ARRAY,
	"power": TYPE_FLOAT,
	"randomness": TYPE_FLOAT,
	"reverse": TYPE_BOOL,
	"steps": TYPE_INT,
	"stiffness": TYPE_FLOAT,
	"trans_type": TYPE_INT,
	"velocity": TYPE_FLOAT,
	"y_offset": TYPE_FLOAT,
}
const LEGACY_POINT_PROPERTIES := {
	"handle_display_scale": TYPE_VECTOR2,
	"handle_mode": TYPE_INT,
	"left_control_point": TYPE_VECTOR2,
	"left_force_linear": TYPE_BOOL,
	"locked": TYPE_DICTIONARY,
	"position": TYPE_VECTOR2,
	"right_control_point": TYPE_VECTOR2,
	"right_force_linear": TYPE_BOOL,
	"use_display_space_handles": TYPE_BOOL,
}
const NATIVE_CURVE_PROPERTIES := {
	"_editor_state_snapshot": TYPE_DICTIONARY,
	"amplitude": TYPE_FLOAT,
	"constant_value": TYPE_FLOAT,
	"damping": TYPE_FLOAT,
	"decay": TYPE_FLOAT,
	"ease_type": TYPE_INT,
	"format_version": TYPE_INT,
	"frequency": TYPE_FLOAT,
	"from_start": TYPE_BOOL,
	"invert": TYPE_BOOL,
	"mass": TYPE_FLOAT,
	"overshoot": TYPE_FLOAT,
	"period": TYPE_FLOAT,
	"points": TYPE_ARRAY,
	"preset_override_active": TYPE_BOOL,
	"power": TYPE_FLOAT,
	"reverse": TYPE_BOOL,
	"steps": TYPE_INT,
	"stiffness": TYPE_FLOAT,
	"transition": TYPE_INT,
	"velocity": TYPE_FLOAT,
	"y_offset": TYPE_FLOAT,
}
const NATIVE_POINT_PROPERTIES := {
	"handle_mode": TYPE_INT,
	"left_control_point": TYPE_VECTOR2,
	"left_force_linear": TYPE_BOOL,
	"locked": TYPE_DICTIONARY,
	"position": TYPE_VECTOR2,
	"right_control_point": TYPE_VECTOR2,
	"right_force_linear": TYPE_BOOL,
}


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_legacy_reflection_contract()
	_test_native_reflection_contract()
	_test_format_version_contract()
	_test_conversion_result_contract()
	_finish("dual public API and Native format contract")


func _test_legacy_reflection_contract() -> void:
	var legacy_curve_properties := _script_public_properties(LEGACY_CURVE_SCRIPT)
	_expect(
		_script_public_method_names(LEGACY_CURVE_SCRIPT) == _sorted(LEGACY_CURVE_METHODS),
		"EasingCurve public method set changed",
	)
	_expect(
		_script_public_method_names(LEGACY_POINT_SCRIPT) == _sorted(LEGACY_POINT_METHODS),
		"EasingCurvePoint public method set changed",
	)
	_expect(
		legacy_curve_properties == LEGACY_CURVE_PROPERTIES,
		"EasingCurve public property contract changed: %s" % legacy_curve_properties,
	)
	_expect(
		_script_public_properties(LEGACY_POINT_SCRIPT) == LEGACY_POINT_PROPERTIES,
		"EasingCurvePoint public property contract changed",
	)
	_expect(
		_signal_contract((LEGACY_CURVE_SCRIPT as Script).get_script_signal_list()) == {
			"points_changed": PackedInt32Array([TYPE_ARRAY]),
			"range_changed": PackedInt32Array(),
		},
		"EasingCurve signal contract changed",
	)
	_expect(
		_signal_contract((LEGACY_POINT_SCRIPT as Script).get_script_signal_list()) == {
			"lock_changed": PackedInt32Array([TYPE_STRING, TYPE_BOOL]),
		},
		"EasingCurvePoint signal contract changed",
	)
	_expect(EasingCurve.EASE == {"IN": 0, "OUT": 1, "IN_OUT": 2, "OUT_IN": 3}, "EasingCurve EASE IDs changed")
	_expect(EasingCurve.CurveMode == {"BEZIER": 0, "FUNCTION": 1}, "EasingCurve CurveMode IDs changed")
	_expect(
		EasingCurve.TRANS == {
			"CUSTOM": 0, "CONSTANT": 1, "LINEAR": 2, "JITTER": 3, "IRREGULAR": 4,
			"STEP": 5, "POWER": 6, "QUAD": 7, "CUBIC": 8, "QUART": 9, "QUINT": 10,
			"EXPO": 11, "CIRC": 12, "BACK": 13, "ELASTIC": 14, "BOUNCE": 15,
			"SPRING": 16, "PHYSICS_SPRING": 17, "CSS_LINEAR": 18, "SINE": 19,
			"CSS_CUBIC_BEZIER": 20,
		},
		"EasingCurve TRANS IDs changed",
	)
	_expect(
		EasingCurvePoint.HandleMode == {
			"FREE": 0, "LINEAR": 1, "BALANCED": 2, "MIRRORED": 3, "LINKED": 4,
		},
		"EasingCurvePoint HandleMode IDs changed",
	)
	_expect(EasingCurvePoint.ControlSide == {"LEFT": 0, "RIGHT": 1}, "EasingCurvePoint ControlSide IDs changed")
	_expect(
		EasingCurvePoint.ControlState == {"FREE": 0, "LINEAR": 1, "LOCKED": 2},
		"EasingCurvePoint ControlState IDs changed",
	)


func _test_native_reflection_contract() -> void:
	_expect(
		_native_method_names(&"NativeEasingCurve") == _sorted(NATIVE_CURVE_METHODS),
		"NativeEasingCurve public method set changed",
	)
	_expect(
		_native_method_names(&"NativeEasingCurvePoint") == _sorted(NATIVE_POINT_METHODS),
		"NativeEasingCurvePoint public method set changed",
	)
	_expect(
		_native_properties(&"NativeEasingCurve") == NATIVE_CURVE_PROPERTIES,
		"NativeEasingCurve public property contract changed",
	)
	_expect(
		_native_properties(&"NativeEasingCurvePoint") == NATIVE_POINT_PROPERTIES,
		"NativeEasingCurvePoint public property contract changed",
	)
	_expect(
		_signal_contract(ClassDB.class_get_signal_list(&"NativeEasingCurve", true)) == {
			"points_changed": PackedInt32Array([TYPE_ARRAY]),
		},
		"NativeEasingCurve signal contract changed",
	)
	_expect(
		_signal_contract(ClassDB.class_get_signal_list(&"NativeEasingCurvePoint", true)) == {
			"lock_changed": PackedInt32Array([TYPE_STRING_NAME, TYPE_BOOL]),
		},
		"NativeEasingCurvePoint signal contract changed",
	)
	_expect(_native_integer_constants(&"NativeEasingCurve") == _expected_native_curve_constants(), "NativeEasingCurve integer constants changed")
	_expect(
		_native_integer_constants(&"NativeEasingCurvePoint") == {
			"HANDLE_FREE": 0,
			"HANDLE_LINEAR": 1,
			"HANDLE_BALANCED": 2,
			"HANDLE_MIRRORED": 3,
			"HANDLE_LINKED": 4,
		},
		"NativeEasingCurvePoint integer constants changed",
	)


func _test_format_version_contract() -> void:
	_assert_format_fixture("absent_version_native_curve.tres", 3, 2, true)
	_assert_format_fixture("old_v1_native_curve.tres", 1, 1, false)
	_assert_format_fixture("current_v2_native_curve.tres", 2, 1, true)
	_assert_format_fixture("future_v4_native_curve.tres", 4, 3, false)

	var malformed := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	malformed.set(&"format_version", 0)
	_expect(malformed.get(&"format_version") == 0, "malformed Native format version was not retained")
	_expect(malformed.call(&"get_format_status") == 0, "malformed Native format status changed")
	_expect(not malformed.call(&"is_format_supported"), "malformed Native format was accepted")
	_expect(not is_finite(malformed.call(&"sample", 0.5)), "malformed Native format sampled silently")

	var packed := load(NATIVE_FIXTURE_ROOT + "native_format_version_embedded.tscn") as PackedScene
	_expect(packed != null, "embedded Native format fixture did not load")
	if packed != null:
		var root := packed.instantiate()
		_assert_embedded_format_resources(root, "embedded")
		var repacked := PackedScene.new()
		_expect(repacked.pack(root) == OK, "embedded Native format fixture could not be repacked")
		root.free()
		var round_trip_path := "res://test/_temp/native_format_version_embedded_round_trip.tscn"
		_expect(ResourceSaver.save(repacked, round_trip_path) == OK, "embedded Native format fixture could not be saved")
		var loaded_packed := ResourceLoader.load(
			round_trip_path,
			"",
			ResourceLoader.CACHE_MODE_IGNORE,
		) as PackedScene
		_expect(loaded_packed != null, "embedded Native format round trip did not load")
		if loaded_packed != null:
			var loaded_root := loaded_packed.instantiate()
			_assert_embedded_format_resources(loaded_root, "embedded round trip")
			loaded_root.free()


func _test_conversion_result_contract() -> void:
	var converted := EasingCurve.new()
	var exact := CONVERSION_RESULT.create(
		&"native",
		&"legacy",
		converted,
		{&"transition": CONVERSION_RESULT.FIELD_EXACT},
	)
	_expect(CONVERSION_RESULT.is_valid(exact), "exact conversion result is invalid")
	_expect(CONVERSION_RESULT.is_success(exact), "exact conversion result is not successful")
	_expect(not CONVERSION_RESULT.is_lossy(exact), "exact conversion result is lossy")

	var baked := CONVERSION_RESULT.create(
		&"legacy",
		&"native",
		ClassDB.instantiate(&"NativeEasingCurve") as Resource,
		{
			&"transition": CONVERSION_RESULT.FIELD_EXACT,
			&"function_callable": CONVERSION_RESULT.FIELD_BAKED,
		},
		PackedStringArray(["Callable was baked to points."]),
	)
	_expect(CONVERSION_RESULT.is_valid(baked), "baked conversion result is invalid")
	_expect(CONVERSION_RESULT.is_success(baked), "baked conversion result is not successful")
	_expect(CONVERSION_RESULT.is_lossy(baked), "baked conversion result was reported exact")

	var unsupported := CONVERSION_RESULT.create(
		&"legacy",
		&"native",
		null,
		{&"transition": CONVERSION_RESULT.FIELD_UNSUPPORTED},
		PackedStringArray(),
		PackedStringArray(["Transition is unsupported."]),
	)
	_expect(CONVERSION_RESULT.is_valid(unsupported), "unsupported conversion result is invalid")
	_expect(not CONVERSION_RESULT.is_success(unsupported), "unsupported conversion result succeeded")
	_expect(CONVERSION_RESULT.has_unsupported_fields(unsupported), "unsupported field was not reported")
	_expect(CONVERSION_RESULT.is_lossy(unsupported), "unsupported conversion result was reported exact")
	_expect(
		CONVERSION_RESULT.create(&"legacy", &"native", null, {&"bad": &"unknown"}).is_empty(),
		"unknown conversion field outcome was accepted",
	)


func _assert_format_fixture(file_name: String, version: int, status: int, supported: bool) -> void:
	var curve := ResourceLoader.load(
		NATIVE_FIXTURE_ROOT + file_name,
		"",
		ResourceLoader.CACHE_MODE_IGNORE,
	) as Resource
	_assert_format_resource(curve, version, status, supported, file_name)
	if curve == null:
		return
	var runtime_copy := curve.call(&"create_runtime_copy") as Resource
	_assert_format_resource(runtime_copy, version, status, supported, file_name + " runtime copy")
	var round_trip_path := "res://test/_temp/round_trip_%s" % file_name
	_expect(ResourceSaver.save(curve, round_trip_path) == OK, "%s could not be saved" % file_name)
	var round_trip := ResourceLoader.load(round_trip_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	_assert_format_resource(round_trip, version, status, supported, file_name + " round trip")


func _assert_format_resource(
	curve: Resource,
	version: int,
	status: int,
	supported: bool,
	context: String,
) -> void:
	_expect(curve != null, "%s Native resource is missing" % context)
	if curve == null:
		return
	_expect(curve.get(&"format_version") == version, "%s format version changed" % context)
	_expect(curve.call(&"get_format_status") == status, "%s format status changed" % context)
	_expect(curve.call(&"is_format_supported") == supported, "%s support decision changed" % context)
	_expect(is_finite(curve.call(&"sample", 0.5)) == supported, "%s sampling support changed" % context)


func _assert_embedded_format_resources(root: Node, context: String) -> void:
	_assert_format_resource(root.get_meta(&"absent") as Resource, 3, 2, true, context + " absent")
	_assert_format_resource(root.get_meta(&"old") as Resource, 1, 1, false, context + " old")
	_assert_format_resource(root.get_meta(&"current") as Resource, 2, 1, true, context + " current")
	_assert_format_resource(root.get_meta(&"future") as Resource, 4, 3, false, context + " future")


func _script_public_method_names(script: Script) -> PackedStringArray:
	var names := PackedStringArray()
	for method: Dictionary in script.get_script_method_list():
		var method_name := String(method[&"name"])
		if not method_name.begins_with("_") and not method_name.begins_with("@"):
			names.append(method_name)
	names.sort()
	return names


func _script_public_properties(script: Script) -> Dictionary:
	var properties := {}
	for property: Dictionary in script.get_script_property_list():
		var property_name := String(property[&"name"])
		if property_name.begins_with("_") or property_name.ends_with(".gd"):
			continue
		if int(property[&"type"]) == TYPE_NIL:
			continue
		properties[property_name] = int(property[&"type"])
	return properties


func _native_method_names(native_class_name: StringName) -> PackedStringArray:
	var names := PackedStringArray()
	for method: Dictionary in ClassDB.class_get_method_list(native_class_name, true):
		names.append(String(method[&"name"]))
	names.sort()
	return names


func _native_properties(native_class_name: StringName) -> Dictionary:
	var properties := {}
	for property: Dictionary in ClassDB.class_get_property_list(native_class_name, true):
		properties[String(property[&"name"])] = int(property[&"type"])
	return properties


func _signal_contract(signal_list: Array) -> Dictionary:
	var signals := {}
	for signal_info: Dictionary in signal_list:
		var argument_types := PackedInt32Array()
		for argument: Dictionary in signal_info.get(&"args", []):
			argument_types.append(int(argument[&"type"]))
		signals[String(signal_info[&"name"])] = argument_types
	return signals


func _native_integer_constants(native_class_name: StringName) -> Dictionary:
	var constants := {}
	for constant_name: StringName in ClassDB.class_get_integer_constant_list(native_class_name, true):
		constants[String(constant_name)] = ClassDB.class_get_integer_constant(native_class_name, constant_name)
	return constants


func _expected_native_curve_constants() -> Dictionary:
	return {
		"FORMAT_VERSION": 3,
		"TRANS_LINEAR": 0, "TRANS_SINE": 1, "TRANS_QUINT": 2, "TRANS_QUART": 3,
		"TRANS_QUAD": 4, "TRANS_EXPO": 5, "TRANS_ELASTIC": 6, "TRANS_CUBIC": 7,
		"TRANS_CIRC": 8, "TRANS_BOUNCE": 9, "TRANS_BACK": 10, "TRANS_SPRING": 11,
		"TRANS_CUSTOM": 100, "TRANS_CONSTANT": 101, "TRANS_JITTER": 102,
		"TRANS_IRREGULAR": 103, "TRANS_STEP": 104, "TRANS_POWER": 105,
		"TRANS_PHYSICS_SPRING": 106, "TRANS_CSS_LINEAR": 107,
		"TRANS_CSS_CUBIC_BEZIER": 108,
		"EASE_IN": 0, "EASE_OUT": 1, "EASE_IN_OUT": 2, "EASE_OUT_IN": 3,
		"FORMAT_STATUS_INVALID": 0, "FORMAT_STATUS_OLDER": 1,
		"FORMAT_STATUS_CURRENT": 2, "FORMAT_STATUS_NEWER": 3,
	}


func _sorted(values: Array) -> PackedStringArray:
	var result := PackedStringArray(values)
	result.sort()
	return result

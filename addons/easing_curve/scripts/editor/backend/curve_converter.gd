@tool
extends RefCounted

const CONVERSION_RESULT := preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_conversion_result.gd"
)
const LEGACY_CURVE := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve.gd"
)
const LEGACY_POINT := preload(
	"res://addons/easing_curve/scripts/runtime/point.gd"
)

const LEGACY_TO_NATIVE_TRANSITIONS := {
	EasingCurve.TRANS.CUSTOM: 100,
	EasingCurve.TRANS.CONSTANT: 101,
	EasingCurve.TRANS.LINEAR: 0,
	EasingCurve.TRANS.JITTER: 102,
	EasingCurve.TRANS.IRREGULAR: 103,
	EasingCurve.TRANS.STEP: 104,
	EasingCurve.TRANS.POWER: 105,
	EasingCurve.TRANS.QUAD: 4,
	EasingCurve.TRANS.CUBIC: 7,
	EasingCurve.TRANS.QUART: 3,
	EasingCurve.TRANS.QUINT: 2,
	EasingCurve.TRANS.EXPO: 5,
	EasingCurve.TRANS.CIRC: 8,
	EasingCurve.TRANS.BACK: 10,
	EasingCurve.TRANS.ELASTIC: 6,
	EasingCurve.TRANS.BOUNCE: 9,
	EasingCurve.TRANS.SPRING: 11,
	EasingCurve.TRANS.PHYSICS_SPRING: 106,
	EasingCurve.TRANS.CSS_LINEAR: 107,
	EasingCurve.TRANS.SINE: 1,
	EasingCurve.TRANS.CSS_CUBIC_BEZIER: 108,
}
const NATIVE_TO_LEGACY_TRANSITIONS := {
	0: EasingCurve.TRANS.LINEAR,
	1: EasingCurve.TRANS.SINE,
	2: EasingCurve.TRANS.QUINT,
	3: EasingCurve.TRANS.QUART,
	4: EasingCurve.TRANS.QUAD,
	5: EasingCurve.TRANS.EXPO,
	6: EasingCurve.TRANS.ELASTIC,
	7: EasingCurve.TRANS.CUBIC,
	8: EasingCurve.TRANS.CIRC,
	9: EasingCurve.TRANS.BOUNCE,
	10: EasingCurve.TRANS.BACK,
	11: EasingCurve.TRANS.SPRING,
	100: EasingCurve.TRANS.CUSTOM,
	101: EasingCurve.TRANS.CONSTANT,
	102: EasingCurve.TRANS.JITTER,
	103: EasingCurve.TRANS.IRREGULAR,
	104: EasingCurve.TRANS.STEP,
	105: EasingCurve.TRANS.POWER,
	106: EasingCurve.TRANS.PHYSICS_SPRING,
	107: EasingCurve.TRANS.CSS_LINEAR,
	108: EasingCurve.TRANS.CSS_CUBIC_BEZIER,
}
const SHARED_PARAMETERS: Array[StringName] = [
	&"constant_value",
	&"overshoot",
	&"num_points",
	&"randomness",
	&"steps",
	&"from_start",
	&"y_offset",
	&"power",
	&"amplitude",
	&"period",
	&"num_bounces",
	&"bounce_damping",
	&"frequency",
	&"decay",
	&"stiffness",
	&"damping",
	&"mass",
	&"velocity",
	&"css_linear",
	&"css_cubic_bezier",
]


static func legacy_to_native(
	source: EasingCurve,
	allow_callable_bake := false,
	bake_resolution := 40,
) -> Dictionary:
	if source == null or not ClassDB.class_exists(&"NativeEasingCurve"):
		return _failure(&"legacy", &"native", &"resource", "NativeEasingCurve is unavailable on this platform.")
	if not LEGACY_TO_NATIVE_TRANSITIONS.has(source.trans_type):
		return _failure(&"legacy", &"native", &"transition", "The legacy transition is not mapped to Native.")

	var target := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	var fields := _base_field_outcomes()
	target.set(&"ease_type", source.ease_type)
	_copy_shared_parameters(source, target)
	if source.curve_mode == EasingCurve.CurveMode.FUNCTION and source.trans_type == EasingCurve.TRANS.CUSTOM:
		if not allow_callable_bake or not source.function_callable.is_valid():
			fields[&"function_callable"] = CONVERSION_RESULT.FIELD_UNSUPPORTED
			return CONVERSION_RESULT.create(
				&"legacy",
				&"native",
				null,
				fields,
				PackedStringArray(["Live Callables require an explicit bake." ]),
			)
		if not bool(target.call(&"bake_callable", source.function_callable, bake_resolution)):
			return _failure(&"legacy", &"native", &"function_callable", "Callable baking failed.")
		fields[&"function_callable"] = CONVERSION_RESULT.FIELD_BAKED
	else:
		target.set(&"transition", LEGACY_TO_NATIVE_TRANSITIONS[source.trans_type])
		if EasingCurve.uses_generated_function_data(source.trans_type):
			target.call(&"set_generated_points", _legacy_generated_points(source))
			fields[&"generated_data"] = CONVERSION_RESULT.FIELD_EXACT
		if (
			source.curve_mode == EasingCurve.CurveMode.BEZIER
			and (source.trans_type == EasingCurve.TRANS.CUSTOM or source.is_selected_preset_modified())
		):
			var raw_points := _legacy_raw_points(source)
			target.set(&"points", _legacy_points_to_native(raw_points))
			target.set(&"preset_override_active", source.trans_type != EasingCurve.TRANS.CUSTOM)
			fields[&"points"] = CONVERSION_RESULT.FIELD_EXACT

	target.set(&"reverse", source.reverse)
	target.set(&"invert", source.invert)
	return CONVERSION_RESULT.create(&"legacy", &"native", target, fields)


static func native_to_legacy(source: Resource) -> Dictionary:
	if source == null or source.get_class() != &"NativeEasingCurve":
		return _failure(&"native", &"legacy", &"resource", "The source is not a NativeEasingCurve.")
	var native_transition := int(source.get(&"transition"))
	if not NATIVE_TO_LEGACY_TRANSITIONS.has(native_transition):
		return _failure(&"native", &"legacy", &"transition", "The Native transition is not mapped to legacy.")

	var target := LEGACY_CURVE.new() as EasingCurve
	target.trans_type = NATIVE_TO_LEGACY_TRANSITIONS[native_transition]
	target.ease_type = int(source.get(&"ease_type"))
	_copy_shared_parameters(source, target)
	var fields := _base_field_outcomes()
	if native_transition in [102, 103]:
		var generated := source.call(&"get_generated_points") as PackedVector2Array
		var generated_x: Array[float] = []
		var generated_y: Array[float] = []
		for point: Vector2 in generated:
			generated_x.append(point.x)
			generated_y.append(point.y)
		target.set(&"_irregular_points_x", generated_x)
		target.set(&"_irregular_points_y", generated_y)
		fields[&"generated_data"] = CONVERSION_RESULT.FIELD_EXACT
	if native_transition == 100 or bool(source.call(&"is_selected_preset_modified")):
		target.points = _native_points_to_legacy(source.get(&"points"))
		fields[&"points"] = CONVERSION_RESULT.FIELD_EXACT
	target.reverse = bool(source.get(&"reverse"))
	target.invert = bool(source.get(&"invert"))
	return CONVERSION_RESULT.create(&"native", &"legacy", target, fields)


static func _copy_shared_parameters(source: Resource, target: Resource) -> void:
	for property_name: StringName in SHARED_PARAMETERS:
		target.set(property_name, source.get(property_name))


static func _base_field_outcomes() -> Dictionary:
	var fields := {
		&"transition": CONVERSION_RESULT.FIELD_EXACT,
		&"ease_type": CONVERSION_RESULT.FIELD_EXACT,
		&"reverse": CONVERSION_RESULT.FIELD_EXACT,
		&"invert": CONVERSION_RESULT.FIELD_EXACT,
	}
	for property_name: StringName in SHARED_PARAMETERS:
		fields[property_name] = CONVERSION_RESULT.FIELD_EXACT
	return fields


static func _failure(
	source_backend: StringName,
	target_backend: StringName,
	field: StringName,
	message: String,
) -> Dictionary:
	return CONVERSION_RESULT.create(
		source_backend,
		target_backend,
		null,
		{field: CONVERSION_RESULT.FIELD_UNSUPPORTED},
		PackedStringArray(),
		PackedStringArray([message]),
	)


static func _legacy_generated_points(source: EasingCurve) -> PackedVector2Array:
	var result := PackedVector2Array()
	var points_x: Array = source.get(&"_irregular_points_x")
	var points_y: Array = source.get(&"_irregular_points_y")
	for index in range(mini(points_x.size(), points_y.size())):
		result.append(Vector2(float(points_x[index]), float(points_y[index])))
	return result


static func _legacy_raw_points(source: EasingCurve) -> Array[EasingCurvePoint]:
	var snapshot := source.get_point_snapshot()
	if source.invert:
		snapshot = source.call(&"_invert_point_snapshot", snapshot)
	if source.reverse:
		snapshot = source.call(&"_reverse_point_snapshot", snapshot)
	var holder := LEGACY_CURVE.new() as EasingCurve
	holder.set_point_snapshot(snapshot)
	return holder.points


static func _legacy_points_to_native(source_points: Array[EasingCurvePoint]) -> Array[Resource]:
	var result: Array[Resource] = []
	for source_point: EasingCurvePoint in source_points:
		var point := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
		point.set(&"position", source_point.position)
		point.set(&"left_control_point", source_point.left_control_point)
		point.set(&"right_control_point", source_point.right_control_point)
		point.set(&"handle_mode", source_point.handle_mode)
		point.set(&"left_force_linear", source_point.left_force_linear)
		point.set(&"right_force_linear", source_point.right_force_linear)
		point.call(&"set_locks", source_point.locked.duplicate(true))
		result.append(point)
	return result


static func _native_points_to_legacy(source_points: Array) -> Array[EasingCurvePoint]:
	var result: Array[EasingCurvePoint] = []
	for source_point: Resource in source_points:
		var point := LEGACY_POINT.new() as EasingCurvePoint
		point.position = source_point.get(&"position")
		point.left_control_point = source_point.get(&"left_control_point")
		point.right_control_point = source_point.get(&"right_control_point")
		point.set_handle_mode(int(source_point.get(&"handle_mode")))
		point.left_force_linear = bool(source_point.get(&"left_force_linear"))
		point.right_force_linear = bool(source_point.get(&"right_force_linear"))
		var source_locks := source_point.call(&"get_locks") as Dictionary
		var locks: Dictionary[String, bool] = {
			"position": bool(source_locks.get(&"position", false)),
			"left_control_point": bool(source_locks.get(&"left_control_point", false)),
			"right_control_point": bool(source_locks.get(&"right_control_point", false)),
		}
		point.set_locks(locks)
		result.append(point)
	return result

@tool
extends RefCounted
## Pure construction of built-in Bézier preset geometry.
##
## The EasingCurve resource remains responsible for transition metadata,
## mutation, notifications, transforms, and serialization. This helper only
## creates new point Resources for a requested built-in Bézier preset.


static func build(
	transition_name: StringName,
	ease_name: StringName,
	constant_value: float,
	overshoot: float,
) -> Array[EasingCurvePoint]:
	match transition_name:
		&"CONSTANT":
			return _constant(constant_value)
		&"LINEAR":
			return _linear()
		&"SINE":
			# A sine graph is not polynomial; these handles are optimized approximations.
			return _composed_for_ease(
				ease_name,
				Vector4(.361149818, -.000326393, .673540771, .486909956),
				Vector4(.326459229, .513090014, .638850212, 1.0003264),
			)
		&"QUAD":
			# Degree elevation makes each quadratic half an exact cubic Bézier.
			return _composed_for_ease(
				ease_name,
				Vector4(1.0 / 3.0, 0.0, 2.0 / 3.0, 1.0 / 3.0),
				Vector4(1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1.0),
			)
		&"CUBIC":
			return _cubic(ease_name)
		&"QUART":
			# Degree-four and degree-five graphs require optimized cubic approximations.
			return _composed_for_ease(
				ease_name,
				Vector4(.439210773, .004901892, .732221782, -.067109145),
				Vector4(.267778218, 1.06710911, .560789227, .995098114),
			)
		&"QUINT":
			return _composed_for_ease(
				ease_name,
				Vector4(.522905409, .010620826, .775169373, -.113423072),
				Vector4(.224830627, 1.11342311, .477094591, .989379168),
			)
		&"EXPO":
			# Godot's endpoint corrections introduce small discontinuities that continuous geometry cannot copy.
			return _composed_for_ease(
				ease_name,
				Vector4(.632421792, .015909066, .846576214, -.060294569),
				Vector4(.153921053, 1.0531143, .359647602, .985371113),
			)
		&"CIRC":
			# A polynomial cubic can only approximate a circular arc.
			return _composed_for_ease(
				ease_name,
				Vector4(.565830648, .002238899, .999889314, .459180534),
				Vector4(.000110686, .540819466, .434169352, .99776113),
			)
		&"BACK":
			return _back(ease_name, overshoot)
	return []


static func _constant(value: float) -> Array[EasingCurvePoint]:
	return [
		EasingCurvePoint.new(Vector2(0.0, value)),
		EasingCurvePoint.new(Vector2(1.0, value)),
	]


static func _linear() -> Array[EasingCurvePoint]:
	return [
		EasingCurvePoint.new(Vector2.ZERO),
		EasingCurvePoint.new(Vector2.ONE),
	]


static func cubic_bezier(controls: Vector4) -> Array[EasingCurvePoint]:
	var p0 := EasingCurvePoint.new(Vector2.ZERO)
	var p1 := EasingCurvePoint.new(Vector2.ONE)
	p0.right_control_point = Vector2(controls.x, controls.y)
	p1.left_control_point = Vector2(controls.z, controls.w)
	return [p0, p1]


static func cubic_bezier_pair(
	first_controls: Vector4,
	second_controls: Vector4,
) -> Array[EasingCurvePoint]:
	# Combined Tween modes are two normalized halves joined at their mathematical transition.
	# Scaling unit control sets around (0.5, 0.5) keeps that boundary editor-visible.
	var p0 := EasingCurvePoint.new(Vector2.ZERO)
	var midpoint := EasingCurvePoint.new(Vector2(0.5, 0.5))
	var p1 := EasingCurvePoint.new(Vector2.ONE)
	p0.right_control_point = Vector2(first_controls.x, first_controls.y) * 0.5
	midpoint.left_control_point = Vector2(first_controls.z, first_controls.w) * 0.5
	midpoint.right_control_point = Vector2(0.5, 0.5) + Vector2(second_controls.x, second_controls.y) * 0.5
	p1.left_control_point = Vector2(0.5, 0.5) + Vector2(second_controls.z, second_controls.w) * 0.5
	return [p0, midpoint, p1]


static func _composed_for_ease(
	ease_name: StringName,
	in_controls: Vector4,
	out_controls: Vector4,
) -> Array[EasingCurvePoint]:
	match ease_name:
		&"IN":
			return cubic_bezier(in_controls)
		&"OUT":
			return cubic_bezier(out_controls)
		&"IN_OUT":
			return cubic_bezier_pair(in_controls, out_controls)
		&"OUT_IN":
			return cubic_bezier_pair(out_controls, in_controls)
	return []


static func _cubic(ease_name: StringName) -> Array[EasingCurvePoint]:
	match ease_name:
		&"IN":
			return cubic_bezier(Vector4(1.0 / 3.0, 0.0, 2.0 / 3.0, 0.0))
		&"OUT":
			return cubic_bezier(Vector4(1.0 / 3.0, 1.0, 2.0 / 3.0, 1.0))
		&"IN_OUT":
			return cubic_bezier_pair(
				Vector4(1.0 / 3.0, 0.0, 2.0 / 3.0, 0.0),
				Vector4(1.0 / 3.0, 1.0, 2.0 / 3.0, 1.0),
			)
		&"OUT_IN":
			# OUT_IN simplifies to one global cubic, so it needs no midpoint.
			return cubic_bezier(Vector4(1.0 / 3.0, 1.0, 2.0 / 3.0, 0.0))
	return []


static func _back(
	ease_name: StringName,
	overshoot: float,
) -> Array[EasingCurvePoint]:
	var in_controls := Vector4(
		1.0 / 3.0,
		0.0,
		2.0 / 3.0,
		-overshoot / 3.0,
	)
	var out_controls := Vector4(
		1.0 / 3.0,
		1.0 + overshoot / 3.0,
		2.0 / 3.0,
		1.0,
	)

	if ease_name == &"IN_OUT":
		var in_out_overshoot := overshoot * 1.525
		return cubic_bezier_pair(
			Vector4(
				1.0 / 3.0,
				0.0,
				2.0 / 3.0,
				-in_out_overshoot / 3.0,
			),
			Vector4(
				1.0 / 3.0,
				1.0 + in_out_overshoot / 3.0,
				2.0 / 3.0,
				1.0,
			),
		)

	return _composed_for_ease(ease_name, in_controls, out_controls)

extends "res://test/scripts/support/test_case.gd"

const EASING_LIBRARY := preload("res://addons/easing_curve/scripts/runtime/easing.gd")
const ROUND_TRIP_PATH := "res://test/_tween_bezier_round_trip.tres"
const ANALYTIC_ERROR_LIMIT := 0.000002
const SAMPLE_COUNT := 10000
const EDGE_OFFSETS := [
	0.00000001,
	0.0000001,
	0.000001,
	0.00001,
	0.0001,
	0.9999,
	0.99999,
	0.999999,
	0.9999999,
	0.99999999,
]
const BEZIER_TRANSITION_PAIRS := [
	[EasingCurve.TRANS.LINEAR, Tween.TRANS_LINEAR],
	[EasingCurve.TRANS.SINE, Tween.TRANS_SINE],
	[EasingCurve.TRANS.QUINT, Tween.TRANS_QUINT],
	[EasingCurve.TRANS.QUART, Tween.TRANS_QUART],
	[EasingCurve.TRANS.QUAD, Tween.TRANS_QUAD],
	[EasingCurve.TRANS.EXPO, Tween.TRANS_EXPO],
	[EasingCurve.TRANS.CUBIC, Tween.TRANS_CUBIC],
	[EasingCurve.TRANS.CIRC, Tween.TRANS_CIRC],
	[EasingCurve.TRANS.BACK, Tween.TRANS_BACK],
]
const ANALYTIC_TRANSITIONS := [
	Tween.TRANS_LINEAR,
	Tween.TRANS_SINE,
	Tween.TRANS_QUINT,
	Tween.TRANS_QUART,
	Tween.TRANS_QUAD,
	Tween.TRANS_EXPO,
	Tween.TRANS_ELASTIC,
	Tween.TRANS_CUBIC,
	Tween.TRANS_CIRC,
	Tween.TRANS_BOUNCE,
	Tween.TRANS_BACK,
	Tween.TRANS_SPRING,
]
const TWEEN_TRANSITION_NAMES := [
	"LINEAR",
	"SINE",
	"QUINT",
	"QUART",
	"QUAD",
	"EXPO",
	"ELASTIC",
	"CUBIC",
	"CIRC",
	"BOUNCE",
	"BACK",
	"SPRING",
]
const TWEEN_EASES := [Tween.EASE_IN, Tween.EASE_OUT, Tween.EASE_IN_OUT, Tween.EASE_OUT_IN]
const EASE_NAMES := ["IN", "OUT", "IN_OUT", "OUT_IN"]
# Ceilings sit just above measured dense-sample maxima; 0.000001 covers float/solver noise for exact presets.
const BEZIER_ERROR_LIMITS := {
	EasingCurve.TRANS.LINEAR: [0.000001, 0.000001, 0.000001, 0.000001],
	EasingCurve.TRANS.SINE: [0.00003, 0.00003, 0.000015, 0.000015],
	EasingCurve.TRANS.QUINT: [0.0008, 0.0008, 0.0004, 0.0004],
	EasingCurve.TRANS.QUART: [0.00035, 0.00035, 0.00016, 0.00016],
	EasingCurve.TRANS.QUAD: [0.000001, 0.000001, 0.000001, 0.000001],
	EasingCurve.TRANS.EXPO: [0.0011, 0.00095, 0.0007, 0.00056],
	EasingCurve.TRANS.CUBIC: [0.000001, 0.000001, 0.000001, 0.000001],
	EasingCurve.TRANS.CIRC: [0.00025, 0.00025, 0.0001, 0.00013],
	EasingCurve.TRANS.BACK: [0.000001, 0.000001, 0.000001, 0.000001],
}
const EXPECTED_POINT_COUNTS := {
	EasingCurve.TRANS.LINEAR: [2, 2, 2, 2],
	EasingCurve.TRANS.SINE: [2, 2, 3, 3],
	EasingCurve.TRANS.QUINT: [2, 2, 3, 3],
	EasingCurve.TRANS.QUART: [2, 2, 3, 3],
	EasingCurve.TRANS.QUAD: [2, 2, 3, 3],
	EasingCurve.TRANS.EXPO: [2, 2, 3, 3],
	EasingCurve.TRANS.CUBIC: [2, 2, 3, 2],
	EasingCurve.TRANS.CIRC: [2, 2, 3, 3],
	EasingCurve.TRANS.BACK: [2, 2, 3, 3],
}

var _bezier_checks := 0
var _analytic_checks := 0
var _sample_offsets := PackedFloat64Array(EDGE_OFFSETS)


func _init() -> void:
	for sample_index in range(SAMPLE_COUNT + 1):
		_sample_offsets.append(float(sample_index) / SAMPLE_COUNT)

	for transition_pair in BEZIER_TRANSITION_PAIRS:
		_compare_bezier_transition(transition_pair[0], transition_pair[1])
	for tween_transition: Tween.TransitionType in ANALYTIC_TRANSITIONS:
		_compare_analytic_transition(tween_transition)
	if FileAccess.file_exists(ROUND_TRIP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUND_TRIP_PATH))

	_finish_with_messages(
		"%d Bézier approximation checks and %d analytic reference checks"
		% [_bezier_checks, _analytic_checks],
		"%d Tween comparison checks exceeded their error limits" % _failures,
	)


func _compare_bezier_transition(
		curve_transition: EasingCurve.TRANS,
		tween_transition: Tween.TransitionType,
) -> void:
	var curve := EasingCurve.new()
	curve.trans_type = curve_transition

	for ease: EasingCurve.EASE in EasingCurve.EASE.values():
		curve.ease_type = ease
		_bezier_checks += 1
		var expected_point_count: int = EXPECTED_POINT_COUNTS[curve_transition][ease]
		if curve.curve_mode != EasingCurve.CurveMode.BEZIER or curve.points.size() != expected_point_count:
			_failures += 1
			push_error("%s/%s does not have the expected %d editable Bézier points" % [
				EasingCurve.TRANS.keys()[curve_transition],
				EasingCurve.EASE.keys()[ease],
				expected_point_count,
			])
			continue

		var label := "%s/%s" % [
			EasingCurve.TRANS.keys()[curve_transition],
			EasingCurve.EASE.keys()[ease],
		]
		_validate_endpoints(curve, label)
		_validate_stored_geometry_path(curve, label)
		if expected_point_count == 3:
			_validate_two_segment_geometry(curve, curve_transition, ease, label)

		var measurement := _measure_curve(curve, tween_transition, ease as Tween.EaseType)
		var error_limit: float = BEZIER_ERROR_LIMITS[curve_transition][ease]
		print(
			"BEZIER %s max_error=%.9f at x=%.8f limit=%.6f"
			% [label, measurement.max_error, measurement.offset, error_limit],
		)
		if measurement.max_error > error_limit:
			_failures += 1


func _validate_endpoints(curve: EasingCurve, label: String) -> void:
	_expect(curve.points[0].position.is_equal_approx(Vector2.ZERO), "%s does not start at (0, 0)" % label)
	_expect(curve.points[-1].position.is_equal_approx(Vector2.ONE), "%s does not end at (1, 1)" % label)
	_expect(is_equal_approx(curve.sample(0.0), 0.0), "%s does not sample to 0 at its start" % label)
	_expect(is_equal_approx(curve.sample(1.0), 1.0), "%s does not sample to 1 at its end" % label)


func _validate_stored_geometry_path(curve: EasingCurve, label: String) -> void:
	var first_point := curve.points[0]
	var next_point := curve.points[1]
	var probe := (first_point.position.x + next_point.position.x) * 0.5
	var original_handle := first_point.right_control_point
	var original_sample := curve.sample(probe)
	first_point.right_control_point.y += 0.01
	var edited_sample := curve.sample(probe)
	first_point.right_control_point = original_handle
	_expect(
		not is_equal_approx(edited_sample, original_sample),
		"%s sampling did not respond to stored Bézier geometry" % label,
	)


func _validate_two_segment_geometry(
		curve: EasingCurve,
		transition: EasingCurve.TRANS,
		ease: EasingCurve.EASE,
		label: String,
) -> void:
	var midpoint := curve.points[1]
	_expect(midpoint.position.is_equal_approx(Vector2(0.5, 0.5)), "%s has the wrong segment boundary" % label)
	_expect(is_equal_approx(curve.sample(0.5), 0.5), "%s is not continuous at its segment boundary" % label)

	# Expo's reference has correction discontinuities, so matching tangents would assert behavior it does not have.
	if transition != EasingCurve.TRANS.EXPO:
		var incoming_tangent := midpoint.position - midpoint.left_control_point
		var outgoing_tangent := midpoint.right_control_point - midpoint.position
		_expect(incoming_tangent.is_equal_approx(outgoing_tangent), "%s has mismatched midpoint tangents" % label)

	_validate_exact_combined_slopes(curve, transition, ease, label)
	_validate_round_trip(curve, label)


func _validate_exact_combined_slopes(
		curve: EasingCurve,
		transition: EasingCurve.TRANS,
		ease: EasingCurve.EASE,
		label: String,
) -> void:
	var expected_slopes := PackedFloat64Array()
	if transition == EasingCurve.TRANS.QUAD and ease == EasingCurve.EASE.IN_OUT:
		expected_slopes = PackedFloat64Array([0.0, 2.0, 0.0])
	elif transition == EasingCurve.TRANS.QUAD and ease == EasingCurve.EASE.OUT_IN:
		expected_slopes = PackedFloat64Array([2.0, 0.0, 2.0])
	elif transition == EasingCurve.TRANS.CUBIC and ease == EasingCurve.EASE.IN_OUT:
		expected_slopes = PackedFloat64Array([0.0, 3.0, 0.0])
	elif transition == EasingCurve.TRANS.BACK and ease == EasingCurve.EASE.IN_OUT:
		expected_slopes = PackedFloat64Array([0.0, 3.0 + 1.70158 * 1.525, 0.0])
	elif transition == EasingCurve.TRANS.BACK and ease == EasingCurve.EASE.OUT_IN:
		expected_slopes = PackedFloat64Array([3.0 + 1.70158, 0.0, 3.0 + 1.70158])
	else:
		return

	var actual_slopes := PackedFloat64Array([
		_control_slope(curve.points[0].position, curve.points[0].right_control_point),
		_control_slope(curve.points[1].left_control_point, curve.points[1].position),
		_control_slope(curve.points[-1].left_control_point, curve.points[-1].position),
	])
	for index in range(expected_slopes.size()):
		_expect(
			is_equal_approx(actual_slopes[index], expected_slopes[index]),
			"%s slope %d is %.8f instead of %.8f" % [label, index, actual_slopes[index], expected_slopes[index]],
		)


func _control_slope(from: Vector2, to: Vector2) -> float:
	return (to.y - from.y) / (to.x - from.x)


func _validate_round_trip(curve: EasingCurve, label: String) -> void:
	var save_error := ResourceSaver.save(curve, ROUND_TRIP_PATH)
	_expect(save_error == OK, "%s could not be saved" % label)
	if save_error != OK:
		return

	var loaded := ResourceLoader.load(ROUND_TRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EasingCurve
	_expect(loaded != null, "%s could not be loaded" % label)
	if loaded == null:
		return
	_expect(loaded.curve_mode == EasingCurve.CurveMode.BEZIER, "%s did not load in Bézier mode" % label)
	_expect(_point_geometry_matches(curve, loaded), "%s changed its point geometry after save/load" % label)

	var original_handle := loaded.points[1].right_control_point
	loaded.points[1].right_control_point += Vector2(0.0001, 0.0)
	_expect(loaded.points[1].right_control_point != original_handle, "%s midpoint handle is not editable" % label)


func _point_geometry_matches(a: EasingCurve, b: EasingCurve) -> bool:
	if a.points.size() != b.points.size():
		return false
	for index in range(a.points.size()):
		if not a.points[index].position.is_equal_approx(b.points[index].position):
			return false
		if not a.points[index].left_control_point.is_equal_approx(b.points[index].left_control_point):
			return false
		if not a.points[index].right_control_point.is_equal_approx(b.points[index].right_control_point):
			return false
	return true


func _compare_analytic_transition(tween_transition: Tween.TransitionType) -> void:
	for ease: Tween.EaseType in TWEEN_EASES:
		_analytic_checks += 1
		var interpolator: Callable = EASING_LIBRARY.interpolators[tween_transition][ease]
		var max_error := 0.0
		var max_error_offset := 0.0
		for offset in _sample_offsets:
			var real_t_offset := Vector2(offset, 0.0).x
			var analytic_value: float = interpolator.call(real_t_offset, 0.0, 1.0, 1.0)
			var tween_value: float = Tween.interpolate_value(
				0.0,
				1.0,
				offset,
				1.0,
				tween_transition,
				ease,
			)
			var error := absf(analytic_value - tween_value)
			if error > max_error:
				max_error = error
				max_error_offset = offset

		var label := "%s/%s" % [
			TWEEN_TRANSITION_NAMES[tween_transition],
			EASE_NAMES[ease],
		]
		print("ANALYTIC %s max_error=%.9f at x=%.8f" % [label, max_error, max_error_offset])
		if max_error > ANALYTIC_ERROR_LIMIT:
			_failures += 1


func _measure_curve(
		curve: EasingCurve,
		tween_transition: Tween.TransitionType,
		ease: Tween.EaseType,
) -> Dictionary:
	var max_error := 0.0
	var max_error_offset := 0.0
	for offset in _sample_offsets:
		var curve_value := curve.sample(offset)
		var tween_value: float = Tween.interpolate_value(
			0.0,
			1.0,
			offset,
			1.0,
			tween_transition,
			ease,
		)
		var error := absf(curve_value - tween_value)
		if error > max_error:
			max_error = error
			max_error_offset = offset
	return {"max_error": max_error, "offset": max_error_offset}

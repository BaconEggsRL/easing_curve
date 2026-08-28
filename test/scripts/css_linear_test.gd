extends SceneTree

const EASING_LIBRARY = preload("res://addons/easing_curve/scripts/runtime/easing.gd")
const ROUND_TRIP_PATH := "res://test/_css_linear_round_trip.tres"

var _failures := 0
var _checks := 0


func _init() -> void:
	_test_parsing()
	_test_position_resolution()
	_test_sampling()
	_test_resource_behavior()

	if _failures == 0:
		print("PASS: %d CSS Linear checks" % _checks)
		quit()
	else:
		push_error("FAIL: %d of %d CSS Linear checks failed" % [_failures, _checks])
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error(message)


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(is_equal_approx(actual, expected), "%s: %f != %f" % [message, actual, expected])


func _expect_points(actual: PackedVector2Array, expected: Array, message: String) -> void:
	_expect(actual.size() == expected.size(), "%s point count changed" % message)
	if actual.size() != expected.size():
		return
	for i in actual.size():
		_expect(
			is_equal_approx(actual[i].x, expected[i].x)
				and is_equal_approx(actual[i].y, expected[i].y),
			"%s point %d changed: %s != %s" % [message, i, actual[i], expected[i]],
		)


func _parse(source: String) -> PackedVector2Array:
	return EASING_LIBRARY.CSSLinear.parse(source)


func _test_parsing() -> void:
	var valid_cases := [
		[
			"linear(0, 1)",
			[Vector2(0.0, 0.0), Vector2(1.0, 1.0)],
		],
		[
			"linear(0 0%, 0.5 25%, 1 100%)",
			[Vector2(0.0, 0.0), Vector2(0.25, 0.5), Vector2(1.0, 1.0)],
		],
		[
			"linear(0, 0.5, 1)",
			[Vector2(0.0, 0.0), Vector2(0.5, 0.5), Vector2(1.0, 1.0)],
		],
		[
			"linear(0 10%, 0.5, 1 90%)",
			[Vector2(0.1, 0.0), Vector2(0.5, 0.5), Vector2(0.9, 1.0)],
		],
		[
			"linear(0 20% 40%, 1 100%)",
			[Vector2(0.2, 0.0), Vector2(0.4, 0.0), Vector2(1.0, 1.0)],
		],
		[
			"linear(0 40%, 1 40%, 0 80%)",
			[Vector2(0.4, 0.0), Vector2(0.4, 1.0), Vector2(0.8, 0.0)],
		],
	]
	for valid_case in valid_cases:
		_expect_points(_parse(valid_case[0]), valid_case[1], "Parsing %s" % valid_case[0])

	var invalid_sources := [
		"linear(0 0% 50% 100%, 1)",
		"linear(0, nope)",
		"linear(0, 1foo)",
		"linear(0 20, 1)",
		"linear(0 20%%, 1)",
		"0, 1",
		"linear(1)",
		"linear()",
	]
	for source in invalid_sources:
		_expect(_parse(source).is_empty(), "CSS Linear accepted invalid input: %s" % source)


func _test_position_resolution() -> void:
	_expect_points(
		_parse("linear(0.2, 1 100%)"),
		[Vector2(0.0, 0.2), Vector2(1.0, 1.0)],
		"First omitted position",
	)
	_expect_points(
		_parse("linear(0 0%, 0.7)"),
		[Vector2(0.0, 0.0), Vector2(1.0, 0.7)],
		"Last omitted position",
	)
	_expect_points(
		_parse("linear(0 0%, 0.2, 0.6, 1 100%)"),
		[
			Vector2(0.0, 0.0),
			Vector2(1.0 / 3.0, 0.2),
			Vector2(2.0 / 3.0, 0.6),
			Vector2(1.0, 1.0),
		],
		"Omitted positions",
	)
	_expect_points(
		_parse("linear(0 60%, 0.5, 1 20%, 2 80%)"),
		[
			Vector2(0.6, 0.0),
			Vector2(0.6, 0.5),
			Vector2(0.6, 1.0),
			Vector2(0.8, 2.0),
		],
		"Backward explicit position",
	)
	_expect_points(
		_parse("linear(0 40%, 1 40%, 0 80%)"),
		[Vector2(0.4, 0.0), Vector2(0.4, 1.0), Vector2(0.8, 0.0)],
		"Duplicate positions",
	)


func _test_sampling() -> void:
	var points := _parse("linear(0 0%, 1 50%, 0 100%)")
	_expect_approx(EASING_LIBRARY.CSSLinear.sample(0.25, points), 0.5, "Interpolation before midpoint")
	_expect_approx(EASING_LIBRARY.CSSLinear.sample(0.75, points), 0.5, "Interpolation after midpoint")
	_expect_approx(EASING_LIBRARY.CSSLinear.sample(0.0, points), 0.0, "First endpoint")
	_expect_approx(EASING_LIBRARY.CSSLinear.sample(1.0, points), 0.0, "Last endpoint")
	_expect_approx(EASING_LIBRARY.CSSLinear.sample(-0.25, points), -0.5, "Before-first extrapolation")
	_expect_approx(EASING_LIBRARY.CSSLinear.sample(1.25, points), -0.5, "After-last extrapolation")

	var duplicate_points := _parse("linear(0 50%, 1 50%)")
	_expect_approx(
		EASING_LIBRARY.CSSLinear.sample(0.5, duplicate_points),
		1.0,
		"Duplicate-position lookup uses the last matching point",
	)
	var single_point := PackedVector2Array([Vector2(0.5, 0.75)])
	_expect_approx(EASING_LIBRARY.CSSLinear.sample(0.0, single_point), 0.75, "Single-point sampling")


func _test_resource_behavior() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CSS_LINEAR
	var valid_source := "linear(0 0%, 0.75 50%, 1 100%)"
	curve.css_linear = valid_source
	var valid_points := _parse(valid_source)
	_expect_points(curve._css_linear_points, [Vector2(0.0, 0.0), Vector2(0.5, 0.75), Vector2(1.0, 1.0)], "Valid resource update")
	_expect_points(curve._css_linear_points, valid_points, "Parsed resource points")
	var valid_sample := curve.sample(0.25)
	_expect_approx(valid_sample, 0.375, "Valid resource sample")

	var invalid_source := "linear(0 20, 1)"
	curve.css_linear = invalid_source
	_expect(curve.css_linear == invalid_source, "Invalid CSS Linear source was not retained")
	_expect_points(curve._css_linear_points, valid_points, "Invalid resource update corrupted parsed points")
	_expect_approx(curve.sample(0.25), valid_sample, "Invalid resource update changed parsed sampling")

	var transform_source := "linear(0 0%, 1 50%, 0.25 100%)"
	curve.css_linear = transform_source
	curve.reverse = false
	curve.invert = false
	var raw_sample := curve.sample(0.25)
	_expect_approx(raw_sample, 0.5, "Untransformed CSS Linear sample")
	curve.reverse = true
	_expect_approx(curve.sample(0.25), 0.625, "Reverse CSS Linear sample")
	curve.reverse = false
	curve.invert = true
	_expect_approx(curve.sample(0.25), 0.5, "Invert CSS Linear sample")
	curve.reverse = true
	_expect_approx(curve.sample(0.25), 0.375, "Combined CSS Linear transforms")

	var save_error := ResourceSaver.save(curve, ROUND_TRIP_PATH)
	_expect(save_error == OK, "CSS Linear curve could not be saved")
	if save_error == OK:
		var loaded := ResourceLoader.load(
			ROUND_TRIP_PATH,
			"",
			ResourceLoader.CACHE_MODE_IGNORE,
		) as EasingCurve
		_expect(loaded != null, "CSS Linear curve could not be loaded")
		if loaded != null:
			_expect(loaded.css_linear == transform_source, "CSS Linear source changed after save/load")
			for offset in [0.0, 0.25, 0.5, 0.75, 1.0]:
				_expect_approx(
					loaded.sample(offset),
					curve.sample(offset),
					"CSS Linear sample changed after save/load at %.2f" % offset,
				)

	if FileAccess.file_exists(ROUND_TRIP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUND_TRIP_PATH))

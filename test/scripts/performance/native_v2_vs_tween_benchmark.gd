extends SceneTree

const LEGACY_CURVE_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve.gd"
)
const LEGACY_POINT_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/point.gd"
)
const SAMPLE_ITERATIONS := 200000
const CUSTOM_SAMPLE_ITERATIONS := 50000
const MUTATION_ITERATIONS := 4000
const COPY_ITERATIONS := 500
const TRIAL_COUNT := 9
const CUSTOM_POINT_COUNTS := [2, 9, 65]
const BUILTIN_CASES := [
	["linear_out", NativeEasingCurve.TRANS_LINEAR, Tween.TRANS_LINEAR],
	["sine_out", NativeEasingCurve.TRANS_SINE, Tween.TRANS_SINE],
	["quint_out", NativeEasingCurve.TRANS_QUINT, Tween.TRANS_QUINT],
	["quart_out", NativeEasingCurve.TRANS_QUART, Tween.TRANS_QUART],
	["quad_out", NativeEasingCurve.TRANS_QUAD, Tween.TRANS_QUAD],
	["expo_out", NativeEasingCurve.TRANS_EXPO, Tween.TRANS_EXPO],
	["elastic_out", NativeEasingCurve.TRANS_ELASTIC, Tween.TRANS_ELASTIC],
	["cubic_out", NativeEasingCurve.TRANS_CUBIC, Tween.TRANS_CUBIC],
	["circ_out", NativeEasingCurve.TRANS_CIRC, Tween.TRANS_CIRC],
	["bounce_out", NativeEasingCurve.TRANS_BOUNCE, Tween.TRANS_BOUNCE],
	["back_out", NativeEasingCurve.TRANS_BACK, Tween.TRANS_BACK],
	["spring_out", NativeEasingCurve.TRANS_SPRING, Tween.TRANS_SPRING],
]
const FUNCTION_CASES := [
	["constant", NativeEasingCurve.TRANS_CONSTANT, EasingCurve.TRANS.CONSTANT, {&"constant_value": 0.37}],
	["step", NativeEasingCurve.TRANS_STEP, EasingCurve.TRANS.STEP, {&"steps": 7, &"from_start": true, &"y_offset": 0.08}],
	["power", NativeEasingCurve.TRANS_POWER, EasingCurve.TRANS.POWER, {&"power": 3.25}],
	["physics_spring", NativeEasingCurve.TRANS_PHYSICS_SPRING, EasingCurve.TRANS.PHYSICS_SPRING, {&"stiffness": 180.0, &"damping": 14.0, &"mass": 1.8, &"velocity": -0.75}],
]

var _sequential_offsets := PackedFloat64Array()
var _reverse_offsets := PackedFloat64Array()
var _random_offsets := PackedFloat64Array()
var _sink := 0.0


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		push_error("NativeEasingCurve is not registered; build the native extension first")
		quit(1)
		return

	_build_offsets()
	print("NATIVE_V2_VS_TWEEN|godot=%s|samples=%d|custom_samples=%d|trials=%d" % [
		Engine.get_version_info()["string"],
		SAMPLE_ITERATIONS,
		CUSTOM_SAMPLE_ITERATIONS,
		TRIAL_COUNT,
	])
	for benchmark_case in BUILTIN_CASES:
		_benchmark_builtin(benchmark_case[0], benchmark_case[1], benchmark_case[2])
	for benchmark_case in FUNCTION_CASES:
		_benchmark_function(benchmark_case)
	for point_count in CUSTOM_POINT_COUNTS:
		_benchmark_custom_curve(point_count)
	_benchmark_mutation_and_copy()
	print("SINK|%.9f" % _sink)
	print("BENCHMARK_COMPLETE|cases=%d" % (BUILTIN_CASES.size() + FUNCTION_CASES.size() + CUSTOM_POINT_COUNTS.size() * 3 + 2))
	quit()


func _build_offsets() -> void:
	for index in range(SAMPLE_ITERATIONS):
		_sequential_offsets.append(float(index & 1023) / 1023.0)
	for index in range(CUSTOM_SAMPLE_ITERATIONS):
		_reverse_offsets.append(float((CUSTOM_SAMPLE_ITERATIONS - index - 1) & 1023) / 1023.0)
	var random := RandomNumberGenerator.new()
	random.seed = 0xE451C
	for _index in range(CUSTOM_SAMPLE_ITERATIONS):
		_random_offsets.append(random.randf())


func _benchmark_builtin(label: String, native_transition: int, tween_transition: int) -> void:
	var curve := _new_native_curve(native_transition)
	_benchmark_pair(
		label,
		_sample_native_curve.bind(curve, _sequential_offsets),
		_sample_tween.bind(tween_transition),
		"native",
		"tween",
	)


func _benchmark_function(benchmark_case: Array) -> void:
	var native_curve := _new_native_curve(benchmark_case[1])
	var legacy_curve := LEGACY_CURVE_SCRIPT.new() as EasingCurve
	legacy_curve.trans_type = benchmark_case[2]
	legacy_curve.ease_type = EasingCurve.EASE.OUT
	for property_name: StringName in benchmark_case[3]:
		native_curve.set(property_name, benchmark_case[3][property_name])
		legacy_curve.set(property_name, benchmark_case[3][property_name])
	var offsets := _sequential_offsets.slice(0, CUSTOM_SAMPLE_ITERATIONS)
	_benchmark_pair(
		"function_%s" % benchmark_case[0],
		_sample_native_curve.bind(native_curve, offsets),
		_sample_legacy_curve.bind(legacy_curve, offsets),
		"native",
		"legacy",
	)


func _benchmark_custom_curve(point_count: int) -> void:
	var native_curve := _make_native_custom_curve(point_count)
	var legacy_curve := _make_legacy_custom_curve(point_count)
	var orders := [
		["sequential", _sequential_offsets.slice(0, CUSTOM_SAMPLE_ITERATIONS)],
		["reverse", _reverse_offsets],
		["random", _random_offsets],
	]
	for order in orders:
		_benchmark_pair(
			"custom_%d_%s" % [point_count, order[0]],
			_sample_native_curve.bind(native_curve, order[1]),
			_sample_legacy_curve.bind(legacy_curve, order[1]),
			"native",
			"legacy",
		)


func _benchmark_mutation_and_copy() -> void:
	var native_curve := _make_native_custom_curve(65)
	var legacy_curve := _make_legacy_custom_curve(65)
	_benchmark_pair(
		"mutate_control_and_sample_65",
		_mutate_native_curve.bind(native_curve),
		_mutate_legacy_curve.bind(legacy_curve),
		"native",
		"legacy",
	)
	_benchmark_pair(
		"deep_runtime_copy_65",
		_copy_native_curve.bind(native_curve),
		_copy_legacy_curve.bind(legacy_curve),
		"native",
		"legacy",
	)


func _benchmark_pair(
		label: String,
		first_workload: Callable,
		second_workload: Callable,
		first_name: String,
		second_name: String,
) -> void:
	first_workload.call()
	second_workload.call()
	var first_samples: Array[float] = []
	var second_samples: Array[float] = []
	for trial in range(TRIAL_COUNT):
		if trial % 2 == 0:
			first_samples.append(_measure(first_workload))
			second_samples.append(_measure(second_workload))
		else:
			second_samples.append(_measure(second_workload))
			first_samples.append(_measure(first_workload))
	first_samples.sort()
	second_samples.sort()
	var first_median := first_samples[TRIAL_COUNT / 2]
	var second_median := second_samples[TRIAL_COUNT / 2]
	var first_mad := _median_absolute_deviation(first_samples, first_median)
	var second_mad := _median_absolute_deviation(second_samples, second_median)
	print("COMPARE|%s|%s_usec=%.1f|%s_mad=%.1f|%s_usec=%.1f|%s_mad=%.1f|%s_over_%s=%.3f|%s_trials=%s|%s_trials=%s" % [
		label,
		first_name,
		first_median,
		first_name,
		first_mad,
		second_name,
		second_median,
		second_name,
		second_mad,
		first_name,
		second_name,
		first_median / maxf(second_median, 1.0),
		first_name,
		str(first_samples),
		second_name,
		str(second_samples),
	])


func _measure(workload: Callable) -> float:
	var started := Time.get_ticks_usec()
	workload.call()
	return float(Time.get_ticks_usec() - started)


func _median_absolute_deviation(samples: Array[float], median: float) -> float:
	var deviations: Array[float] = []
	for sample in samples:
		deviations.append(absf(sample - median))
	deviations.sort()
	return deviations[deviations.size() / 2]


func _sample_native_curve(curve: NativeEasingCurve, offsets: PackedFloat64Array) -> void:
	var total := 0.0
	for offset in offsets:
		total += curve.sample(offset)
	_sink += total


func _sample_legacy_curve(curve: EasingCurve, offsets: PackedFloat64Array) -> void:
	var total := 0.0
	for offset in offsets:
		total += curve.sample(offset)
	_sink += total


func _sample_tween(transition: int) -> void:
	var total := 0.0
	for offset in _sequential_offsets:
		total += Tween.interpolate_value(0.0, 1.0, offset, 1.0, transition, Tween.EASE_OUT)
	_sink += total


func _mutate_native_curve(curve: NativeEasingCurve) -> void:
	var point: NativeEasingCurvePoint = curve.get_point(32)
	var total := 0.0
	for index in range(MUTATION_ITERATIONS):
		var direction := -1.0 if index % 2 == 0 else 1.0
		point.right_control_point = point.position + Vector2(0.001 * direction, 0.002 * direction)
		total += curve.sample(0.51)
	_sink += total


func _mutate_legacy_curve(curve: EasingCurve) -> void:
	var point: EasingCurvePoint = curve.points[32]
	var total := 0.0
	for index in range(MUTATION_ITERATIONS):
		var direction := -1.0 if index % 2 == 0 else 1.0
		point.right_control_point = point.position + Vector2(0.001 * direction, 0.002 * direction)
		total += curve.sample(0.51)
	_sink += total


func _copy_native_curve(curve: NativeEasingCurve) -> void:
	var total := 0
	for _index in range(COPY_ITERATIONS):
		total += curve.create_runtime_copy().get_point_count()
	_sink += total


func _copy_legacy_curve(curve: EasingCurve) -> void:
	var total := 0
	for _index in range(COPY_ITERATIONS):
		total += curve.duplicate(true).points.size()
	_sink += total


func _make_native_custom_curve(point_count: int) -> NativeEasingCurve:
	var curve := _new_native_curve(NativeEasingCurve.TRANS_CUSTOM)
	var points: Array[NativeEasingCurvePoint] = []
	for index in range(point_count):
		var x := float(index) / float(point_count - 1)
		var point := NativeEasingCurvePoint.new()
		point.position = Vector2(x, x * x)
		var segment_width := 1.0 / float(point_count - 1)
		point.left_control_point = point.position - Vector2(segment_width / 3.0, segment_width / 3.0)
		point.right_control_point = point.position + Vector2(segment_width / 3.0, segment_width / 3.0)
		points.append(point)
	curve.points = points
	return curve


func _make_legacy_custom_curve(point_count: int) -> EasingCurve:
	var curve := LEGACY_CURVE_SCRIPT.new() as EasingCurve
	var points: Array[EasingCurvePoint] = []
	for index in range(point_count):
		var x := float(index) / float(point_count - 1)
		var point := LEGACY_POINT_SCRIPT.new(Vector2(x, x * x)) as EasingCurvePoint
		var segment_width := 1.0 / float(point_count - 1)
		point.left_control_point = point.position - Vector2(segment_width / 3.0, segment_width / 3.0)
		point.right_control_point = point.position + Vector2(segment_width / 3.0, segment_width / 3.0)
		points.append(point)
	curve.points = points
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	return curve


func _new_native_curve(transition: int) -> NativeEasingCurve:
	var curve := NativeEasingCurve.new()
	curve.transition = transition
	curve.ease_type = NativeEasingCurve.EASE_OUT
	return curve

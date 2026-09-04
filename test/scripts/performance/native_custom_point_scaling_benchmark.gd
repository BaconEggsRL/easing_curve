extends SceneTree
## Standalone large-custom-curve characterization. This intentionally remains
## outside the historical Native runtime baseline.

const LEGACY_CURVE_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve.gd"
)
const LEGACY_POINT_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/point.gd"
)
const POINT_COUNTS := [65, 129, 257, 513, 1025]
const SAMPLE_ITERATIONS := 50000
const TRIAL_COUNT := 5
const FRAME_BUDGET_USEC := 16667.0

var _sink := 0.0


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		push_error("NativeEasingCurve is not registered; build the native extension first")
		quit(1)
		return
	var offsets := _build_offsets()
	print("NATIVE_POINT_SCALING_ENV|godot=%s|samples=%d|trials=%d|frame_budget_us=%.0f" % [
		Engine.get_version_info()["string"],
		SAMPLE_ITERATIONS,
		TRIAL_COUNT,
		FRAME_BUDGET_USEC,
	])
	for point_count in POINT_COUNTS:
		var native_curve := _make_native_curve(point_count)
		var legacy_curve := _make_legacy_curve(point_count)
		for order_name: String in offsets:
			_benchmark_pair(
				point_count,
				order_name,
				native_curve,
				legacy_curve,
				offsets[order_name],
			)
	print("NATIVE_POINT_SCALING_SINK|%.9f" % _sink)
	print("NATIVE_POINT_SCALING_COMPLETE|cases=%d" % (POINT_COUNTS.size() * offsets.size()))
	quit()


func _build_offsets() -> Dictionary:
	var sequential := PackedFloat64Array()
	for index in range(SAMPLE_ITERATIONS):
		sequential.append(float(index) / float(SAMPLE_ITERATIONS - 1))
	var reverse := sequential.duplicate()
	reverse.reverse()
	var random := PackedFloat64Array()
	var generator := RandomNumberGenerator.new()
	generator.seed = 0xEC081025
	for _index in range(SAMPLE_ITERATIONS):
		random.append(generator.randf())
	return {
		"sequential": sequential,
		"reverse": reverse,
		"random": random,
	}


func _benchmark_pair(
	point_count: int,
	order_name: String,
	native_curve: NativeEasingCurve,
	legacy_curve: EasingCurve,
	offsets: PackedFloat64Array,
) -> void:
	var native_workload := _sample_native.bind(native_curve, offsets)
	var legacy_workload := _sample_legacy.bind(legacy_curve, offsets)
	native_workload.call()
	legacy_workload.call()
	var native_samples: Array[float] = []
	var legacy_samples: Array[float] = []
	for trial in range(TRIAL_COUNT):
		if trial % 2 == 0:
			native_samples.append(_measure(native_workload))
			legacy_samples.append(_measure(legacy_workload))
		else:
			legacy_samples.append(_measure(legacy_workload))
			native_samples.append(_measure(native_workload))
	native_samples.sort()
	legacy_samples.sort()
	var native_median := native_samples[TRIAL_COUNT / 2]
	var legacy_median := legacy_samples[TRIAL_COUNT / 2]
	var native_mad := _median_absolute_deviation(native_samples, native_median)
	var legacy_mad := _median_absolute_deviation(legacy_samples, legacy_median)
	var native_frame_samples := SAMPLE_ITERATIONS * FRAME_BUDGET_USEC / native_median
	var legacy_frame_samples := SAMPLE_ITERATIONS * FRAME_BUDGET_USEC / legacy_median
	print("NATIVE_POINT_SCALING|points=%d|order=%s|samples=%d|native_usec=%.1f|native_mad=%.1f|legacy_usec=%.1f|legacy_mad=%.1f|advantage=%.3f|native_samples_per_frame=%.0f|legacy_samples_per_frame=%.0f" % [
		point_count,
		order_name,
		SAMPLE_ITERATIONS,
		native_median,
		native_mad,
		legacy_median,
		legacy_mad,
		legacy_median / maxf(native_median, 1.0),
		native_frame_samples,
		legacy_frame_samples,
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


func _sample_native(curve: NativeEasingCurve, offsets: PackedFloat64Array) -> void:
	var total := 0.0
	for offset in offsets:
		total += curve.sample(offset)
	_sink += total


func _sample_legacy(curve: EasingCurve, offsets: PackedFloat64Array) -> void:
	var total := 0.0
	for offset in offsets:
		total += curve.sample(offset)
	_sink += total


func _make_native_curve(point_count: int) -> NativeEasingCurve:
	var curve := NativeEasingCurve.new()
	curve.transition = NativeEasingCurve.TRANS_CUSTOM
	var points: Array[NativeEasingCurvePoint] = []
	for index in range(point_count):
		var point := NativeEasingCurvePoint.new()
		_initialize_point(point, index, point_count)
		points.append(point)
	curve.points = points
	return curve


func _make_legacy_curve(point_count: int) -> EasingCurve:
	var curve := LEGACY_CURVE_SCRIPT.new() as EasingCurve
	var points: Array[EasingCurvePoint] = []
	for index in range(point_count):
		var point := LEGACY_POINT_SCRIPT.new() as EasingCurvePoint
		_initialize_point(point, index, point_count)
		points.append(point)
	curve.points = points
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	return curve


func _initialize_point(point: Resource, index: int, point_count: int) -> void:
	var x := float(index) / float(point_count - 1)
	var position := Vector2(x, x * x)
	var handle_width := 1.0 / float(point_count - 1) / 3.0
	point.set(&"position", position)
	point.set(&"left_control_point", position - Vector2(handle_width, handle_width))
	point.set(&"right_control_point", position + Vector2(handle_width, handle_width))

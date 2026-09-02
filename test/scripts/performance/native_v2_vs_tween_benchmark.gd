extends SceneTree

const LEGACY_CURVE_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve.gd"
)
const SAMPLE_ITERATIONS := 200000
const TRIAL_COUNT := 9
const TRANS_SINE := 1
const TRANS_CUBIC := 2
const TRANS_ELASTIC := 3
const EASE_OUT := 1

var _offsets := PackedFloat64Array()
var _sink := 0.0


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		push_error("NativeEasingCurve is not registered; build the native spike first")
		quit(1)
		return
	for index in range(SAMPLE_ITERATIONS):
		_offsets.append(float(index & 1023) / 1023.0)

	print("NATIVE_V2_VS_TWEEN|godot=%s|samples=%d|trials=%d" % [
		Engine.get_version_info()["string"],
		SAMPLE_ITERATIONS,
		TRIAL_COUNT,
	])
	_benchmark_builtin("cubic_out", TRANS_CUBIC, Tween.TRANS_CUBIC)
	_benchmark_builtin("sine_out", TRANS_SINE, Tween.TRANS_SINE)
	_benchmark_builtin("elastic_out", TRANS_ELASTIC, Tween.TRANS_ELASTIC)
	_benchmark_custom_bezier()
	print("SINK|%.9f" % _sink)
	quit()


func _benchmark_builtin(label: String, native_transition: int, tween_transition: int) -> void:
	var curve := _new_native_curve(native_transition)
	_benchmark_pair(
		label,
		_sample_native_curve.bind(curve),
		_sample_tween.bind(tween_transition),
		"native",
		"tween",
	)


func _benchmark_custom_bezier() -> void:
	var native_curve := _new_native_curve(TRANS_CUBIC)
	native_curve.cubic_bezier(0.42, 0.0, 0.58, 1.0)
	var legacy_curve := LEGACY_CURVE_SCRIPT.new()
	legacy_curve.cubic_bezier(0.42, 0.0, 0.58, 1.0)
	_benchmark_pair(
		"custom_bezier_0.42_0_0.58_1",
		_sample_native_curve.bind(native_curve),
		_sample_legacy_curve.bind(legacy_curve),
		"native",
		"gdscript",
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
	print("COMPARE|%s|%s_usec=%.1f|%s_usec=%.1f|%s_over_%s=%.3f" % [
		label,
		first_name,
		first_median,
		second_name,
		second_median,
		first_name,
		second_name,
		first_median / second_median,
	])


func _measure(workload: Callable) -> float:
	var started := Time.get_ticks_usec()
	workload.call()
	return float(Time.get_ticks_usec() - started)


func _sample_native_curve(curve: NativeEasingCurve) -> void:
	var total := 0.0
	for offset in _offsets:
		total += curve.sample(offset)
	_sink += total


func _sample_legacy_curve(curve: EasingCurve) -> void:
	var total := 0.0
	for offset in _offsets:
		total += curve.sample(offset)
	_sink += total


func _sample_tween(transition: int) -> void:
	var total := 0.0
	for offset in _offsets:
		total += Tween.interpolate_value(
			0.0,
			1.0,
			offset,
			1.0,
			transition,
			Tween.EASE_OUT,
		)
	_sink += total


func _new_native_curve(transition: int) -> NativeEasingCurve:
	var curve := NativeEasingCurve.new()
	curve.transition = transition
	curve.ease_type = EASE_OUT
	return curve

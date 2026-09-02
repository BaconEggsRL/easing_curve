extends SceneTree
## Manual runtime benchmark for comparing EasingCurve implementations.
##
## Run this same script against each version in an isolated project. Results are
## medians in microseconds; the full sorted trial list is printed for context.

const CURVE_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve.gd"
)
const POINT_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/point.gd"
)
const SAMPLE_ITERATIONS := 200000
const SNAPSHOT_ITERATIONS := 3000
const REBUILD_ITERATIONS := 4000
const TRIAL_COUNT := 9

var _two_point_curve: Resource
var _many_point_curve: Resource
var _rebuild_curve: Resource
var _edited_point: Resource
var _sink := 0.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_two_point_curve = CURVE_SCRIPT.new()
	_many_point_curve = _make_many_point_curve(65)
	_rebuild_curve = _make_many_point_curve(65)
	_edited_point = _rebuild_curve.get(&"points")[32]

	_benchmark("sample_bezier_2", _sample_two_points)
	_benchmark("sample_bezier_65", _sample_many_points)
	_benchmark("get_point_snapshot_65", _get_many_point_snapshot)
	_benchmark("rebuild_and_sample_65", _rebuild_and_sample)
	print("SINK|", _sink)
	quit()


func _make_many_point_curve(count: int) -> Resource:
	var curve := CURVE_SCRIPT.new()
	var point_values: Array[EasingCurvePoint] = []
	for i in range(count):
		var x := float(i) / float(count - 1)
		point_values.append(POINT_SCRIPT.new(Vector2(x, x * x)))
	curve.set(&"points", point_values)
	return curve


func _benchmark(label: String, workload: Callable) -> void:
	workload.call()
	var samples: Array[float] = []
	for _trial in range(TRIAL_COUNT):
		var started := Time.get_ticks_usec()
		workload.call()
		samples.append(float(Time.get_ticks_usec() - started))
	samples.sort()
	print(
		"BENCH|%s|%.1f|%s"
		% [label, samples[TRIAL_COUNT / 2], samples]
	)


func _sample_two_points() -> void:
	var total := 0.0
	for i in range(SAMPLE_ITERATIONS):
		total += _two_point_curve.sample(float(i & 1023) / 1023.0)
	_sink += total


func _sample_many_points() -> void:
	var total := 0.0
	for i in range(SAMPLE_ITERATIONS):
		total += _many_point_curve.sample(float(i & 1023) / 1023.0)
	_sink += total


func _get_many_point_snapshot() -> void:
	var size_total := 0
	for _i in range(SNAPSHOT_ITERATIONS):
		size_total += _many_point_curve.get_point_snapshot().size()
	_sink += size_total


func _rebuild_and_sample() -> void:
	var total := 0.0
	for i in range(REBUILD_ITERATIONS):
		var direction := -1.0 if i % 2 == 0 else 1.0
		_edited_point.right_control_point = (
			_edited_point.position
			+ Vector2(0.001 * direction, 0.002 * direction)
		)
		total += _rebuild_curve.sample(0.51)
	_sink += total

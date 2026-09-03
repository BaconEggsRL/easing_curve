extends SceneTree

const BackendFactory := preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_editor_backend_factory.gd"
)
const POINT_COUNT := 65
const PREVIEW_STEPS := 120
const PREVIEW_ITERATIONS := 1000
const POINT_READ_ITERATIONS := 2000
const SNAPSHOT_ITERATIONS := 300
const MUTATION_ITERATIONS := 1000
const TRIAL_COUNT := 9

var _sink := 0.0


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		push_error("NativeEasingCurve is not registered")
		quit(1)
		return
	print("CURVE_EDITOR_BACKEND_BENCH|godot=%s|points=%d|trials=%d" % [
		Engine.get_version_info()["string"],
		POINT_COUNT,
		TRIAL_COUNT,
	])
	_benchmark_curve("legacy", _make_legacy_curve())
	_benchmark_curve("native", _make_native_curve())
	print("SINK|%.9f" % _sink)
	print("BACKEND_BENCHMARK_COMPLETE|cases=8")
	quit()


func _benchmark_curve(label: String, curve: Resource) -> void:
	var backend := BackendFactory.create(curve)
	_benchmark_pair(
		"%s_preview_sampling" % label,
		_preview_backend.bind(backend),
		_preview_direct.bind(curve),
	)
	_benchmark_pair(
		"%s_point_read_%d" % [label, POINT_COUNT],
		_point_read_backend.bind(backend),
		_point_read_direct.bind(curve),
	)
	_benchmark_pair(
		"%s_snapshot_capture" % label,
		_snapshot_backend.bind(backend),
		_snapshot_direct.bind(curve),
	)
	_benchmark_pair(
		"%s_compile_invalidation" % label,
		_mutate_backend.bind(backend),
		_mutate_direct.bind(curve),
	)


func _benchmark_pair(label: String, adapter_workload: Callable, direct_workload: Callable) -> void:
	adapter_workload.call()
	direct_workload.call()
	var adapter_samples: Array[float] = []
	var direct_samples: Array[float] = []
	for trial in range(TRIAL_COUNT):
		if trial % 2 == 0:
			adapter_samples.append(_measure(adapter_workload))
			direct_samples.append(_measure(direct_workload))
		else:
			direct_samples.append(_measure(direct_workload))
			adapter_samples.append(_measure(adapter_workload))
	adapter_samples.sort()
	direct_samples.sort()
	var adapter_median := adapter_samples[TRIAL_COUNT / 2]
	var direct_median := direct_samples[TRIAL_COUNT / 2]
	var adapter_mad := _median_absolute_deviation(adapter_samples, adapter_median)
	var direct_mad := _median_absolute_deviation(direct_samples, direct_median)
	print("BACKEND_COMPARE|%s|adapter_usec=%.1f|adapter_mad=%.1f|direct_usec=%.1f|direct_mad=%.1f|adapter_over_direct=%.3f" % [
		label,
		adapter_median,
		adapter_mad,
		direct_median,
		direct_mad,
		adapter_median / maxf(direct_median, 1.0),
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


func _preview_backend(backend: RefCounted) -> void:
	var total := 0.0
	for _iteration in range(PREVIEW_ITERATIONS):
		for step in range(PREVIEW_STEPS + 1):
			total += backend.sample(float(step) / PREVIEW_STEPS)
	_sink += total


func _preview_direct(curve: Resource) -> void:
	var total := 0.0
	for _iteration in range(PREVIEW_ITERATIONS):
		for step in range(PREVIEW_STEPS + 1):
			total += float(curve.call(&"sample", float(step) / PREVIEW_STEPS))
	_sink += total


func _point_read_backend(backend: RefCounted) -> void:
	var total := 0.0
	for _iteration in range(POINT_READ_ITERATIONS):
		var points: Array[Resource] = backend.get_points()
		for point: Resource in points:
			total += (point.get(&"position") as Vector2).x
	_sink += total


func _point_read_direct(curve: Resource) -> void:
	var total := 0.0
	for _iteration in range(POINT_READ_ITERATIONS):
		var points := curve.get(&"points") as Array
		for point: Resource in points:
			total += (point.get(&"position") as Vector2).x
	_sink += total


func _snapshot_backend(backend: RefCounted) -> void:
	var total := 0
	for _iteration in range(SNAPSHOT_ITERATIONS):
		var snapshot: Variant = backend.capture_snapshot()
		total += snapshot.size()
	_sink += total


func _snapshot_direct(curve: Resource) -> void:
	var total := 0
	for _iteration in range(SNAPSHOT_ITERATIONS):
		var snapshot: Variant = (
			curve.call(&"capture_point_states")
			if curve.get_class() == &"NativeEasingCurve"
			else curve.call(&"get_point_snapshot")
		)
		total += snapshot.size()
	_sink += total


func _mutate_backend(backend: RefCounted) -> void:
	var point := backend.get_point(POINT_COUNT / 2) as Resource
	var total := 0.0
	for index in range(MUTATION_ITERATIONS):
		var direction := -1.0 if index % 2 == 0 else 1.0
		var target := (point.get(&"position") as Vector2) + Vector2(0.001, 0.002) * direction
		backend.apply_point_property(POINT_COUNT / 2, &"right_control_point", target)
		total += backend.sample(0.51)
	_sink += total


func _mutate_direct(curve: Resource) -> void:
	var points := curve.get(&"points") as Array
	var point := points[POINT_COUNT / 2] as Resource
	var total := 0.0
	for index in range(MUTATION_ITERATIONS):
		var direction := -1.0 if index % 2 == 0 else 1.0
		point.set(
			&"right_control_point",
			(point.get(&"position") as Vector2) + Vector2(0.001, 0.002) * direction,
		)
		total += float(curve.call(&"sample", 0.51))
	_sink += total


func _make_legacy_curve() -> EasingCurve:
	var curve := EasingCurve.new()
	var points: Array[EasingCurvePoint] = []
	for index in range(POINT_COUNT):
		var point := EasingCurvePoint.new(_point_position(index))
		point.left_control_point = point.position - Vector2(0.005, 0.005)
		point.right_control_point = point.position + Vector2(0.005, 0.005)
		points.append(point)
	curve.points = points
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	return curve


func _make_native_curve() -> Resource:
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	var points: Array[Resource] = []
	for index in range(POINT_COUNT):
		var point := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
		point.set(&"position", _point_position(index))
		point.set(&"left_control_point", point.get(&"position") - Vector2(0.005, 0.005))
		point.set(&"right_control_point", point.get(&"position") + Vector2(0.005, 0.005))
		points.append(point)
	curve.set(&"points", points)
	curve.set(&"transition", 100)
	return curve


func _point_position(index: int) -> Vector2:
	var x := float(index) / float(POINT_COUNT - 1)
	return Vector2(x, x * x)

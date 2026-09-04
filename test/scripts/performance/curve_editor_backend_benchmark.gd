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
const GESTURE_ITERATIONS := 200
const GESTURE_MOTIONS := 12
const TOPOLOGY_ITERATIONS := 32
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
	var topology_passed := _benchmark_topology_comparison()
	print("SINK|%.9f" % _sink)
	print("BACKEND_BENCHMARK_COMPLETE|cases=14|signal_cases=2|topology_cases=4")
	quit(0 if topology_passed else 1)


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
	_benchmark_pair(
		"%s_gesture_transaction" % label,
		_gesture_backend.bind(backend),
		_gesture_direct.bind(curve),
	)
	_measure_gesture_signal_count(label, curve, backend)


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


func _gesture_backend(backend: RefCounted) -> void:
	var point := backend.get_point(POINT_COUNT / 2) as Resource
	var total := 0.0
	for iteration in range(GESTURE_ITERATIONS):
		var before: Variant = backend.capture_snapshot()
		var origin := point.get(&"right_control_point") as Vector2
		backend.begin_point_edit()
		for motion in range(GESTURE_MOTIONS):
			var phase := float(motion + 1) / GESTURE_MOTIONS
			var direction := -1.0 if iteration % 2 == 0 else 1.0
			backend.apply_point_property(
				POINT_COUNT / 2,
				&"right_control_point",
				origin + Vector2(0.002, 0.003) * phase * direction,
				true,
			)
		backend.finish_point_edit()
		var after: Variant = backend.capture_snapshot()
		total += after.size()
		backend.apply_snapshot(before)
	_sink += total


func _gesture_direct(curve: Resource) -> void:
	var point := (curve.get(&"points") as Array)[POINT_COUNT / 2] as Resource
	var total := 0.0
	for iteration in range(GESTURE_ITERATIONS):
		var before: Variant = _capture_direct_snapshot(curve)
		var origin := point.get(&"right_control_point") as Vector2
		for motion in range(GESTURE_MOTIONS):
			var phase := float(motion + 1) / GESTURE_MOTIONS
			var direction := -1.0 if iteration % 2 == 0 else 1.0
			point.set(
				&"right_control_point",
				origin + Vector2(0.002, 0.003) * phase * direction,
			)
		var after: Variant = _capture_direct_snapshot(curve)
		total += after.size()
		_apply_direct_snapshot(curve, before)
	_sink += total


func _measure_gesture_signal_count(label: String, curve: Resource, backend: RefCounted) -> void:
	var before: Variant = backend.capture_snapshot()
	var point := backend.get_point(POINT_COUNT / 2) as Resource
	var origin := point.get(&"right_control_point") as Vector2
	var changes := [0]
	var on_changed := func() -> void: changes[0] += 1
	curve.changed.connect(on_changed)
	backend.begin_point_edit()
	for motion in range(GESTURE_MOTIONS):
		var phase := float(motion + 1) / GESTURE_MOTIONS
		backend.apply_point_property(
			POINT_COUNT / 2,
			&"right_control_point",
			origin + Vector2(0.002, 0.003) * phase,
			true,
		)
	backend.finish_point_edit()
	curve.changed.disconnect(on_changed)
	print("BACKEND_SIGNAL|%s_gesture|motions=%d|curve_changes=%d|changes_per_motion=%.3f" % [
		label,
		GESTURE_MOTIONS,
		changes[0],
		float(changes[0]) / GESTURE_MOTIONS,
	])
	backend.apply_snapshot(before)


func _benchmark_topology_comparison() -> bool:
	var legacy_backend := BackendFactory.create(_make_legacy_curve())
	var native_backend := BackendFactory.create(_make_native_curve())
	var workloads := [
		["add_65", Callable(self, "_topology_add")],
		["remove_65", Callable(self, "_topology_remove")],
		["reorder_65", Callable(self, "_topology_reorder")],
		["snapshot_65", Callable(self, "_topology_snapshot")],
	]
	var passed := true
	for workload: Array in workloads:
		var legacy_workload: Callable = workload[1].bind(legacy_backend)
		var native_workload: Callable = workload[1].bind(native_backend)
		legacy_workload.call()
		native_workload.call()
		var legacy_samples: Array[float] = []
		var native_samples: Array[float] = []
		for trial in range(TRIAL_COUNT):
			if trial % 2 == 0:
				legacy_samples.append(_measure(legacy_workload))
				native_samples.append(_measure(native_workload))
			else:
				native_samples.append(_measure(native_workload))
				legacy_samples.append(_measure(legacy_workload))
		legacy_samples.sort()
		native_samples.sort()
		var legacy_median := legacy_samples[TRIAL_COUNT / 2]
		var native_median := native_samples[TRIAL_COUNT / 2]
		var legacy_mad := _median_absolute_deviation(legacy_samples, legacy_median)
		var native_mad := _median_absolute_deviation(native_samples, native_median)
		var limit := legacy_median + 3.0 * (legacy_mad + native_mad)
		var status := "PASS" if native_median <= limit else "REGRESSION"
		print("TOPOLOGY_COMPARE|%s|%s|legacy_usec=%.1f|legacy_mad=%.1f|native_usec=%.1f|native_mad=%.1f|limit=%.1f" % [
			status,
			workload[0],
			legacy_median,
			legacy_mad,
			native_median,
			native_mad,
			limit,
		])
		if status == "REGRESSION":
			push_error("Native topology workload %s exceeded the combined MAD envelope" % workload[0])
			passed = false
	return passed


func _topology_add(backend: RefCounted) -> void:
	var before: Variant = backend.capture_snapshot()
	for iteration in range(TOPOLOGY_ITERATIONS):
		var x := (float(iteration) + 0.5) / TOPOLOGY_ITERATIONS
		var point: Resource = backend.create_point(Vector2(x, 0.25 + x * 0.5))
		_sink += backend.add_point(point)
	backend.apply_snapshot(before)


func _topology_remove(backend: RefCounted) -> void:
	var before: Variant = backend.capture_snapshot()
	for _iteration in range(TOPOLOGY_ITERATIONS):
		_sink += 1.0 if backend.remove_point(backend.get_point_count() / 2) else 0.0
	backend.apply_snapshot(before)


func _topology_reorder(backend: RefCounted) -> void:
	var before: Variant = backend.capture_snapshot()
	var point_order: Array[Resource] = backend.get_points()
	for iteration in range(TOPOLOGY_ITERATIONS):
		var left := 1 + iteration % (point_order.size() - 2)
		var swap := point_order[left]
		point_order[left] = point_order[left + 1]
		point_order[left + 1] = swap
		_sink += backend.apply_point_order(point_order)
	backend.apply_snapshot(before)


func _topology_snapshot(backend: RefCounted) -> void:
	var before: Variant = backend.capture_snapshot()
	var point_order: Array[Resource] = backend.get_points()
	point_order.reverse()
	backend.apply_point_order(point_order)
	var reversed: Variant = backend.capture_snapshot()
	for iteration in range(TOPOLOGY_ITERATIONS):
		_sink += 1.0 if backend.apply_snapshot(before if iteration % 2 == 0 else reversed) else 0.0
	backend.apply_snapshot(before)


func _capture_direct_snapshot(curve: Resource) -> Variant:
	return (
		curve.call(&"capture_point_states")
		if curve.get_class() == &"NativeEasingCurve"
		else curve.call(&"get_point_snapshot")
	)


func _apply_direct_snapshot(curve: Resource, snapshot: Variant) -> void:
	if curve.get_class() == &"NativeEasingCurve":
		curve.call(&"apply_point_states", snapshot)
	else:
		curve.call(&"set_point_snapshot", snapshot)


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

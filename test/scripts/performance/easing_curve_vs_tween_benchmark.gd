extends SceneTree
## Compares EasingCurve with Godot's Tween using equivalent CPU workloads.
##
## The 100-property and 1,000-method cases are adapted from:
## https://github.com/godotengine/godot-benchmarks/blob/main/benchmarks/animation/tween.gd
##
## Setup and stepping are measured separately because Tween owns animation
## scheduling while EasingCurve supplies reusable interpolation values.

const CURVE_SCRIPT := preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve.gd"
)
const SAMPLE_ITERATIONS := 200000
const PROPERTY_COUNT := 100
const METHOD_COUNT := 1000
const STEP_COUNT := 300
const DURATION_SECONDS := 5.0
const STEP_DELTA := DURATION_SECONDS / STEP_COUNT
const TRIAL_COUNT := 9
const TARGET_ANGLE := 0.01

var _viewport_size := Vector2(
	ProjectSettings.get_setting("display/window/size/viewport_width"),
	ProjectSettings.get_setting("display/window/size/viewport_height"),
)
var _target_position := _viewport_size / 2.0
var _sample_offsets := PackedFloat64Array()
var _cubic_curve: Resource
var _sine_curve: Resource
var _custom_bezier_curve: Resource
var _function_curve: Resource
var _function_callable: Callable
var _function_amplitude := 1.0
var _function_period := 0.3
var _exposed_points_curve: Resource
var _sink := 0.0


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	for index in range(SAMPLE_ITERATIONS):
		_sample_offsets.append(float(index & 1023) / 1023.0)
	_cubic_curve = _new_curve(EasingCurve.TRANS.CUBIC, EasingCurve.EASE.OUT)
	_sine_curve = _new_curve(EasingCurve.TRANS.SINE, EasingCurve.EASE.OUT)
	_custom_bezier_curve = _new_custom_bezier_curve()
	_function_curve = _new_curve(EasingCurve.TRANS.ELASTIC, EasingCurve.EASE.OUT)
	_function_callable = _function_curve.get(&"function_callable")
	_function_amplitude = float(_function_curve.get(&"amplitude"))
	_function_period = float(_function_curve.get(&"period"))
	_exposed_points_curve = _new_curve(EasingCurve.TRANS.CUBIC, EasingCurve.EASE.OUT)
	_sink += float(_exposed_points_curve.points.size())

	print("EASING_CURVE_VS_TWEEN|godot=%s|trials=%d" % [
		Engine.get_version_info()["string"],
		TRIAL_COUNT,
	])
	print(
		"WORKLOAD_MODEL|samples=%d|manual_custom_step=true|easing_curve_shared_sample_per_step=true"
		% SAMPLE_ITERATIONS
	)
	_benchmark_pair(
		"interpolate_cubic_out_%d" % SAMPLE_ITERATIONS,
		_sample_easing_curve.bind(_cubic_curve),
		_sample_tween.bind(Tween.TRANS_CUBIC, Tween.EASE_OUT),
	)
	_benchmark_pair(
		"interpolate_sine_out_%d" % SAMPLE_ITERATIONS,
		_sample_easing_curve.bind(_sine_curve),
		_sample_tween.bind(Tween.TRANS_SINE, Tween.EASE_OUT),
	)
	_benchmark_variant_pair(
		"interpolate_custom_bezier_%d" % SAMPLE_ITERATIONS,
		"cubic_out",
		_sample_easing_curve.bind(_cubic_curve),
		"custom_bezier_0.42_0_0.58_1",
		_sample_easing_curve.bind(_custom_bezier_curve),
	)
	_benchmark_pair(
		"interpolate_function_elastic_out_%d" % SAMPLE_ITERATIONS,
		_sample_easing_curve.bind(_function_curve),
		_sample_tween.bind(Tween.TRANS_ELASTIC, Tween.EASE_OUT),
	)
	_benchmark_variant_pair(
		"interpolate_function_mode_dispatch_elastic_out_%d" % SAMPLE_ITERATIONS,
		"direct_callable",
		_sample_function_callable,
		"easing_curve_sample",
		_sample_easing_curve.bind(_function_curve),
	)
	_benchmark_variant_pair(
		"interpolate_exposed_points_cubic_out_%d" % SAMPLE_ITERATIONS,
		"cubic_out_unexposed",
		_sample_easing_curve.bind(_cubic_curve),
		"cubic_out_exposed_points",
		_sample_easing_curve.bind(_exposed_points_curve),
	)
	_benchmark_setup_pair(
		"setup_properties_%d" % PROPERTY_COUNT,
		_prepare_easing_properties,
		_prepare_tween_properties,
	)
	_benchmark_step_pair(
		"step_properties_%d_x_%d" % [PROPERTY_COUNT, STEP_COUNT],
		_prepare_easing_properties,
		_step_easing_properties,
		_prepare_tween_properties,
		_step_tween_properties,
	)
	_benchmark_setup_pair(
		"setup_methods_%d" % METHOD_COUNT,
		_prepare_easing_methods,
		_prepare_tween_methods,
	)
	_benchmark_step_pair(
		"step_methods_%d_x_%d" % [METHOD_COUNT, STEP_COUNT],
		_prepare_easing_methods,
		_step_easing_methods,
		_prepare_tween_methods,
		_step_tween_methods,
	)
	print("SINK|%.9f" % _sink)
	quit()


func _benchmark_pair(
		label: String,
		easing_workload: Callable,
		tween_workload: Callable,
) -> void:
	easing_workload.call()
	tween_workload.call()

	var easing_samples: Array[float] = []
	var tween_samples: Array[float] = []
	for trial in range(TRIAL_COUNT):
		if trial % 2 == 0:
			easing_samples.append(_measure_workload(easing_workload))
			tween_samples.append(_measure_workload(tween_workload))
		else:
			tween_samples.append(_measure_workload(tween_workload))
			easing_samples.append(_measure_workload(easing_workload))
	_report_comparison(label, easing_samples, tween_samples)


func _benchmark_setup_pair(
		label: String,
		prepare_easing: Callable,
		prepare_tween: Callable,
) -> void:
	_cleanup_fixture(prepare_easing.call())
	_cleanup_fixture(prepare_tween.call())

	var easing_samples: Array[float] = []
	var tween_samples: Array[float] = []
	for trial in range(TRIAL_COUNT):
		if trial % 2 == 0:
			easing_samples.append(_measure_preparation(prepare_easing))
			tween_samples.append(_measure_preparation(prepare_tween))
		else:
			tween_samples.append(_measure_preparation(prepare_tween))
			easing_samples.append(_measure_preparation(prepare_easing))
	_report_comparison(label, easing_samples, tween_samples)


func _benchmark_variant_pair(
		label: String,
		baseline_name: String,
		baseline_workload: Callable,
		variant_name: String,
		variant_workload: Callable,
) -> void:
	baseline_workload.call()
	variant_workload.call()

	var baseline_samples: Array[float] = []
	var variant_samples: Array[float] = []
	for trial in range(TRIAL_COUNT):
		if trial % 2 == 0:
			baseline_samples.append(_measure_workload(baseline_workload))
			variant_samples.append(_measure_workload(variant_workload))
		else:
			variant_samples.append(_measure_workload(variant_workload))
			baseline_samples.append(_measure_workload(baseline_workload))
	_report_variant(
		label,
		baseline_name,
		baseline_samples,
		variant_name,
		variant_samples,
	)


func _benchmark_step_pair(
		label: String,
		prepare_easing: Callable,
		step_easing: Callable,
		prepare_tween: Callable,
		step_tween: Callable,
) -> void:
	var easing_fixture := prepare_easing.call() as Dictionary
	step_easing.call(easing_fixture)
	_cleanup_fixture(easing_fixture)
	var tween_fixture := prepare_tween.call() as Dictionary
	step_tween.call(tween_fixture)
	_cleanup_fixture(tween_fixture)

	var easing_samples: Array[float] = []
	var tween_samples: Array[float] = []
	for trial in range(TRIAL_COUNT):
		if trial % 2 == 0:
			easing_samples.append(_measure_steps(prepare_easing, step_easing))
			tween_samples.append(_measure_steps(prepare_tween, step_tween))
		else:
			tween_samples.append(_measure_steps(prepare_tween, step_tween))
			easing_samples.append(_measure_steps(prepare_easing, step_easing))
	_report_comparison(label, easing_samples, tween_samples)


func _measure_workload(workload: Callable) -> float:
	var started := Time.get_ticks_usec()
	workload.call()
	return float(Time.get_ticks_usec() - started)


func _measure_preparation(prepare: Callable) -> float:
	var started := Time.get_ticks_usec()
	var fixture := prepare.call() as Dictionary
	var elapsed := float(Time.get_ticks_usec() - started)
	_cleanup_fixture(fixture)
	return elapsed


func _measure_steps(prepare: Callable, step: Callable) -> float:
	var fixture := prepare.call() as Dictionary
	var started := Time.get_ticks_usec()
	step.call(fixture)
	var elapsed := float(Time.get_ticks_usec() - started)
	_cleanup_fixture(fixture)
	return elapsed


func _report_comparison(
		label: String,
		easing_samples: Array[float],
		tween_samples: Array[float],
) -> void:
	easing_samples.sort()
	tween_samples.sort()
	var easing_median := easing_samples[TRIAL_COUNT / 2]
	var tween_median := tween_samples[TRIAL_COUNT / 2]
	print(
		"COMPARE|%s|easing_curve_usec=%.1f|tween_usec=%.1f|easing_over_tween=%.3f"
		% [label, easing_median, tween_median, easing_median / tween_median]
	)
	print("TRIALS|%s|easing_curve=%s|tween=%s" % [
		label,
		easing_samples,
		tween_samples,
	])


func _report_variant(
		label: String,
		baseline_name: String,
		baseline_samples: Array[float],
		variant_name: String,
		variant_samples: Array[float],
) -> void:
	baseline_samples.sort()
	variant_samples.sort()
	var baseline_median := baseline_samples[TRIAL_COUNT / 2]
	var variant_median := variant_samples[TRIAL_COUNT / 2]
	print(
		(
			"VARIANT|%s|baseline=%s|baseline_usec=%.1f|variant=%s"
			+ "|variant_usec=%.1f|variant_over_baseline=%.3f"
		)
		% [
			label,
			baseline_name,
			baseline_median,
			variant_name,
			variant_median,
			variant_median / baseline_median,
		]
	)
	print("TRIALS|%s|%s=%s|%s=%s" % [
		label,
		baseline_name,
		baseline_samples,
		variant_name,
		variant_samples,
	])


func _new_curve(transition: EasingCurve.TRANS, ease: EasingCurve.EASE) -> Resource:
	var curve := CURVE_SCRIPT.new()
	curve.set(&"trans_type", transition)
	curve.set(&"ease_type", ease)
	return curve


func _new_custom_bezier_curve() -> Resource:
	var curve := _new_curve(EasingCurve.TRANS.CUSTOM, EasingCurve.EASE.IN)
	curve.cubic_bezier(0.42, 0.0, 0.58, 1.0)
	return curve


func _sample_easing_curve(curve: Resource) -> void:
	var total := 0.0
	for offset in _sample_offsets:
		total += curve.sample(offset)
	_sink += total


func _sample_tween(transition: int, ease: int) -> void:
	var total := 0.0
	for offset in _sample_offsets:
		total += Tween.interpolate_value(
			0.0,
			1.0,
			offset,
			1.0,
			transition,
			ease,
		)
	_sink += total


func _sample_function_callable() -> void:
	var total := 0.0
	for offset in _sample_offsets:
		total += _function_callable.call(
			offset,
			0.0,
			1.0,
			1.0,
			_function_amplitude,
			_function_period,
		)
	_sink += total


func _prepare_easing_properties() -> Dictionary:
	var host := Node.new()
	var nodes: Array[Node2D] = []
	var start_positions := PackedVector2Array()
	get_root().add_child(host)
	for index in range(PROPERTY_COUNT):
		var node := Node2D.new()
		var start_position := _initial_position(index)
		node.position = start_position
		host.add_child(node)
		nodes.append(node)
		start_positions.append(start_position)
	return {
		&"host": host,
		&"curve": _new_curve(EasingCurve.TRANS.CUBIC, EasingCurve.EASE.OUT),
		&"nodes": nodes,
		&"start_positions": start_positions,
	}


func _prepare_tween_properties() -> Dictionary:
	var host := Node.new()
	var tween := host.create_tween().set_parallel(true)
	get_root().add_child(host)
	for index in range(PROPERTY_COUNT):
		var node := Node2D.new()
		node.position = _initial_position(index)
		host.add_child(node)
		tween.tween_property(
			node,
			^"position",
			_target_position,
			DURATION_SECONDS,
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return {&"host": host, &"tween": tween}


func _step_easing_properties(fixture: Dictionary) -> void:
	var curve: Resource = fixture[&"curve"]
	var nodes: Array[Node2D] = fixture[&"nodes"]
	var start_positions: PackedVector2Array = fixture[&"start_positions"]
	for step_index in range(STEP_COUNT):
		var eased: float = curve.sample(float(step_index + 1) / STEP_COUNT)
		for node_index in range(nodes.size()):
			nodes[node_index].position = start_positions[node_index].lerp(
				_target_position,
				eased,
			)
	_sink += nodes[-1].position.x


func _step_tween_properties(fixture: Dictionary) -> void:
	var tween: Tween = fixture[&"tween"]
	for _step_index in range(STEP_COUNT):
		tween.custom_step(STEP_DELTA)
	_sink += float(tween.is_valid())


func _prepare_easing_methods() -> Dictionary:
	var host := Node.new()
	var nodes: Array[Node2D] = []
	get_root().add_child(host)
	for index in range(METHOD_COUNT):
		var node := Node2D.new()
		node.position = _initial_position(index)
		host.add_child(node)
		nodes.append(node)
	return {
		&"host": host,
		&"curve": _new_curve(EasingCurve.TRANS.CUBIC, EasingCurve.EASE.OUT),
		&"nodes": nodes,
	}


func _prepare_tween_methods() -> Dictionary:
	var host := Node.new()
	var tweens: Array[Tween] = []
	get_root().add_child(host)
	for index in range(METHOD_COUNT):
		var node := Node2D.new()
		node.position = _initial_position(index)
		host.add_child(node)
		var tween := host.create_tween()
		tween.tween_method(
			node.rotate,
			0.0,
			TARGET_ANGLE,
			DURATION_SECONDS,
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tweens.append(tween)
	return {&"host": host, &"tweens": tweens}


func _step_easing_methods(fixture: Dictionary) -> void:
	var curve: Resource = fixture[&"curve"]
	var nodes: Array[Node2D] = fixture[&"nodes"]
	for step_index in range(STEP_COUNT):
		var angle: float = (
			curve.sample(float(step_index + 1) / STEP_COUNT) * TARGET_ANGLE
		)
		for node in nodes:
			node.rotate(angle)
	_sink += nodes[-1].rotation


func _step_tween_methods(fixture: Dictionary) -> void:
	var tweens: Array[Tween] = fixture[&"tweens"]
	for _step_index in range(STEP_COUNT):
		for tween in tweens:
			tween.custom_step(STEP_DELTA)
	_sink += float(tweens[-1].is_valid())


func _initial_position(index: int) -> Vector2:
	return Vector2(
		fmod(float(index) * 73.0, _viewport_size.x),
		fmod(float(index) * 151.0, _viewport_size.y),
	)


func _cleanup_fixture(fixture: Dictionary) -> void:
	var tween: Tween = fixture.get(&"tween") as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	if fixture.has(&"tweens"):
		var tweens: Array[Tween] = fixture[&"tweens"]
		for method_tween in tweens:
			if method_tween.is_valid():
				method_tween.kill()
	var host: Node = fixture[&"host"]
	host.free()

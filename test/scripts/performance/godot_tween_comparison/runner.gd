extends SceneTree
## Timing equations mirror the pinned upstream manager.gd; no addon UI is loaded.

const CASES := {
	"tween_properties": &"benchmark_tween_100_properties",
	"native_properties": &"benchmark_native_100_properties",
	"legacy_properties": &"benchmark_legacy_100_properties",
	"tween_methods": &"benchmark_animate_1000_tween_methods",
	"native_methods": &"benchmark_native_1000_methods",
	"legacy_methods": &"benchmark_legacy_1000_methods",
}
const WORKLOAD := preload("res://curve_cases.gd")
const UPSTREAM_COMMIT := "ef3a94f131552c9c5aa040c985185de705068eda"
const RANDOM_SEED := 0x60d07
const MEASURE_USEC := 5000000

var _failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		push_error("Tween comparison requires the Native extension")
		quit(1)
		return
	var case_name := ""
	var output_path := ""
	var validate_only := false
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--validate-only":
			validate_only = true
		elif argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
		elif argument.begins_with("--save-json="):
			output_path = argument.trim_prefix("--save-json=")
		else:
			push_error("Unknown benchmark argument: " + argument)
			quit(1)
			return
	if validate_only:
		await _validate_workloads()
		if _failures == 0:
			print("PASS: all six Tween comparison workloads have matching counts, seeded positions and deterministic motion")
		quit(_failures)
		return
	if not CASES.has(case_name) or output_path.is_empty():
		push_error("Supply --case=<case> and --save-json=<path>, or --validate-only")
		quit(1)
		return
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await process_frame
	if root.get_visible_rect().size != Vector2(1920, 1080):
		push_error("Tween comparison requires a 1920x1080 logical viewport")
		quit(1)
		return
	var workload := WORKLOAD.new()
	seed(RANDOM_SEED)
	var start := Time.get_ticks_usec()
	var node: Node = workload.call(CASES[case_name])
	var setup_ms := (Time.get_ticks_usec() - start) * 0.001
	root.add_child(node)
	for _frame in 3:
		await process_frame
	var render_cpu := 0.0
	var idle := 0.0
	var frames := 0
	start = Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < MEASURE_USEC:
		await process_frame
		render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu()
		idle = maxf(idle, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		frames += 1
	var elapsed_ms := (Time.get_ticks_usec() - start) * 0.001
	var headless := DisplayServer.get_name() == "headless"
	var backend := case_name.get_slice("_", 0)
	var methods := case_name.ends_with("methods")
	var metrics := {"time": setup_ms}
	if not headless:
		metrics["render_cpu"] = render_cpu / maxf(1.0, float(frames))
	var version := Engine.get_version_info()
	var result := {
		"engine": {"version": "v%d.%d.%d.%s.%s" % [version.major, version.minor, version.patch, version.status, version.build], "version_hash": version.hash},
		"system": {"os": OS.get_name(), "cpu_name": OS.get_processor_name(), "cpu_count": OS.get_processor_count(), "cpu_architecture": Engine.get_architecture_name(), "gpu": RenderingServer.get_video_adapter_name()},
		"benchmarks": [{
			"category": "Animation > Tween" if backend == "tween" else "Animation > %s Easing Curve" % backend.capitalize(),
			"name": "Animate 1000 Tween Methods" if methods else "Tween 100 Properties",
			"results": metrics,
		}],
		"comparison": {
			"case": case_name, "upstream_commit": UPSTREAM_COMMIT,
			"headless": headless, "renderer": RenderingServer.get_current_rendering_method(),
			"viewport": [1920, 1080], "window_size": [root.size.x, root.size.y],
			"seed": RANDOM_SEED, "duration_seconds": 5,
			"warmup_frames": 3, "frames_captured": frames, "elapsed_ms": elapsed_ms,
			"idle_max_ms": idle, "supplemental_metrics": "idle_max_ms is additional; upstream Tween enables only render_cpu and setup time",
		},
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot save benchmark JSON: " + output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("BENCHMARK_COMPLETE|%s|frames=%d|time_ms=%.6f|render_cpu_ms=%.6f" % [case_name, frames, setup_ms, render_cpu / maxf(1.0, float(frames))])
	for tween: Tween in get_processed_tweens():
		tween.kill()
	node.free()
	quit()


func _validate_workloads() -> void:
	var starting_positions := {}
	for case_name: String in CASES:
		seed(RANDOM_SEED)
		var workload := WORKLOAD.new()
		var node: Node = workload.call(CASES[case_name])
		root.add_child(node)
		var methods := case_name.ends_with("methods")
		var expected_count := 1000 if methods else 100
		var tweens: Array[Tween] = []
		for tween: Tween in get_processed_tweens():
			if tween.is_valid():
				tweens.append(tween)
		_expect(node.get_child_count() == expected_count, case_name + ": sprite count")
		_expect(tweens.size() == (1000 if methods else 1), case_name + ": Tween count")
		var positions := PackedVector2Array()
		for child: Sprite2D in node.get_children():
			positions.append(child.position)
			_expect(child.texture == workload.ICON, case_name + ": texture differs")
		if case_name.begins_with("tween_"):
			starting_positions[methods] = positions
		else:
			_expect(positions == starting_positions[methods], case_name + ": RNG workload differs")
		for tween: Tween in tweens:
			tween.pause()
		var elapsed := 0.0
		var rotation := 0.0
		for delta: float in [0.0, 0.25, 0.75, 1.5, 2.5]:
			elapsed += delta
			rotation += 0.01 * elapsed / 5.0
			for tween: Tween in tweens:
				tween.custom_step(delta)
			for index in node.get_child_count():
				var sprite := node.get_child(index) as Sprite2D
				if methods:
					_expect(absf(sprite.rotation - rotation) <= 0.000001, case_name + ": rotate increment differs")
				else:
					_expect(sprite.position.distance_to(positions[index].lerp(workload.half_viewport_size, elapsed / 5.0)) <= 0.002, case_name + ": position interpolation differs")
		for tween: Tween in tweens:
			tween.kill()
		node.free()
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

@tool
extends SceneTree
## Editor-host benchmark for Inspector construction and live graph dragging.
##
## Run with a rendering-capable editor host so CanvasItem draw notifications are
## included:
## godot --editor --path . --script res://test/scripts/performance/easing_curve_editor_host_benchmark.gd \
##   --log-file test/_temp/easing_curve_editor_host_benchmark.log

const INSPECTOR_PLUGIN = preload(
	"res://addons/easing_curve/scripts/editor/inspector/easing_curve_editor_inspector_plugin.gd"
)
const PLUGIN_CONFIG_PATH := "res://addons/easing_curve/plugin.cfg"
const POINT_COUNTS := [9, 65]
const BUILD_WARMUP_COUNT := 2
const BUILD_TRIAL_COUNT := 7
const DRAG_WARMUP_STEPS := 8
const DRAG_STEPS_PER_TRIAL := 40
const DRAG_TRIAL_COUNT := 7
const MAX_DRAW_WAIT_FRAMES := 8
const EDITOR_SIZE := Vector2(800.0, 420.0)


class MeasuredCurveEditor extends EasingCurveEditor:
	var draw_count := 0
	var last_draw_usec := 0.0
	var last_draw_finished_usec := 0


	func _draw() -> void:
		var started := Time.get_ticks_usec()
		super()
		last_draw_usec = float(Time.get_ticks_usec() - started)
		last_draw_finished_usec = Time.get_ticks_usec()
		draw_count += 1


func _init() -> void:
	if not Engine.is_editor_hint():
		push_error(
			"Editor-host benchmark requires --editor."
		)
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error(
			"Editor-host benchmark requires a rendering-capable display server."
		)
		quit(1)
		return
	call_deferred(&"_run")


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	OS.low_processor_usage_mode = false
	var version := _plugin_version()
	print("EDITOR_BENCH_ENV|%s|%s|%s" % [
		version,
		DisplayServer.get_name(),
		RenderingServer.get_video_adapter_name(),
	])

	for point_count in POINT_COUNTS:
		await _benchmark_inspector_build(version, point_count)
		await _benchmark_drag(version, point_count)

	for _frame in range(3):
		await process_frame
	quit()


func _benchmark_inspector_build(version: String, point_count: int) -> void:
	var cpu_samples: Array[float] = []
	var frame_samples: Array[float] = []
	var total_trials := BUILD_WARMUP_COUNT + BUILD_TRIAL_COUNT

	for trial in range(total_trials):
		var curve := _make_curve(point_count)
		var host := VBoxContainer.new()
		host.position = Vector2(12.0, 12.0)
		host.size = Vector2(820.0, 900.0)
		get_root().add_child(host)

		var started := Time.get_ticks_usec()
		var inspector := INSPECTOR_PLUGIN.new()
		inspector.set(&"curve", curve)
		var curve_content := inspector.call(
			&"handle_easing_curve_editor",
			curve,
		) as Control
		var points_content := inspector.call(&"handle_points", curve) as Control
		host.add_child(curve_content)
		host.add_child(points_content)
		var cpu_elapsed := float(Time.get_ticks_usec() - started)

		await RenderingServer.frame_post_draw
		var frame_elapsed := float(Time.get_ticks_usec() - started)
		if trial >= BUILD_WARMUP_COUNT:
			cpu_samples.append(cpu_elapsed)
			frame_samples.append(frame_elapsed)

		host.free()
		await process_frame

	_report(version, "inspector_build_cpu", point_count, cpu_samples)
	_report(version, "inspector_build_to_frame", point_count, frame_samples)


func _benchmark_drag(version: String, point_count: int) -> void:
	var fixture := await _create_drag_fixture(point_count)
	var curve: EasingCurve = fixture[&"curve"]
	var editor: MeasuredCurveEditor = fixture[&"editor"]
	var host: Control = fixture[&"host"]
	var point_index := point_count / 2
	var cpu_samples: Array[float] = []
	var draw_samples: Array[float] = []
	var to_draw_samples: Array[float] = []
	var commit_cpu_samples: Array[float] = []
	var commit_to_draw_samples: Array[float] = []

	for trial in range(DRAG_TRIAL_COUNT):
		var point := curve.points[point_index]
		var start_world := point.position
		editor.update_view_transform()
		editor._gui_input(_mouse_button(
			MOUSE_BUTTON_LEFT,
			editor.get_view_pos(start_world),
			true,
		))
		if editor.dragging_point == -1:
			push_error("Benchmark could not begin a point drag")
			host.free()
			quit(1)
			return

		for step in range(DRAG_WARMUP_STEPS + DRAG_STEPS_PER_TRIAL):
			var direction := -1.0 if step % 2 == 0 else 1.0
			var target_world := Vector2(
				start_world.x,
				clampf(start_world.y + direction * 0.02, 0.05, 0.95),
			)
			var sample := await _drag_step(
				editor,
				editor.get_view_pos(target_world),
			)
			if step >= DRAG_WARMUP_STEPS:
				cpu_samples.append(sample[&"cpu_usec"])
				draw_samples.append(sample[&"draw_usec"])
				to_draw_samples.append(sample[&"to_draw_usec"])

		var draw_count_before_commit := editor.draw_count
		var commit_started := Time.get_ticks_usec()
		editor._gui_input(_mouse_button(
			MOUSE_BUTTON_LEFT,
			editor.get_view_pos(curve.points[point_index].position),
			false,
		))
		commit_cpu_samples.append(
			float(Time.get_ticks_usec() - commit_started)
		)
		var commit_drew := await _wait_for_draw(
			editor,
			draw_count_before_commit,
		)
		if not commit_drew:
			push_error("Timed out waiting for the committed drag to redraw")
			quit(1)
			return
		commit_to_draw_samples.append(
			float(editor.last_draw_finished_usec - commit_started)
		)

	_report(version, "drag_update_cpu", point_count, cpu_samples)
	_report(version, "graph_draw_cpu", point_count, draw_samples)
	_report(version, "drag_update_to_draw", point_count, to_draw_samples)
	_report(version, "drag_commit_cpu", point_count, commit_cpu_samples)
	_report(version, "drag_commit_to_draw", point_count, commit_to_draw_samples)
	host.free()
	await process_frame


func _create_drag_fixture(point_count: int) -> Dictionary:
	var curve := _make_curve(point_count)
	var inspector := INSPECTOR_PLUGIN.new()
	var editor := MeasuredCurveEditor.new()
	var host := VBoxContainer.new()

	host.position = Vector2(12.0, 12.0)
	host.size = Vector2(820.0, 900.0)
	get_root().add_child(host)

	inspector.set(&"curve", curve)
	inspector.set(&"easing_curve_editor", editor)
	editor.custom_minimum_size = EDITOR_SIZE
	editor.size = EDITOR_SIZE
	editor.set_curve(curve)
	editor.point_property_change_requested.connect(
		Callable(inspector, &"_apply_point_property_change")
	)
	editor.point_edit_finished.connect(
		Callable(inspector, &"_commit_point_edit")
	)
	editor.point_changed.connect(
		Callable(inspector, &"_on_curve_editor_point_changed")
	)

	host.add_child(editor)
	host.add_child(inspector.call(&"handle_points", curve) as Control)
	await process_frame
	editor.queue_redraw()
	await _wait_for_draw(editor, editor.draw_count)

	return {
		&"curve": curve,
		&"editor": editor,
		&"host": host,
		&"inspector": inspector,
	}


func _drag_step(editor: MeasuredCurveEditor, view_position: Vector2) -> Dictionary:
	var draw_count_before := editor.draw_count
	var started := Time.get_ticks_usec()
	var motion := InputEventMouseMotion.new()
	motion.position = view_position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	editor._gui_input(motion)
	var cpu_elapsed := float(Time.get_ticks_usec() - started)
	var drew := await _wait_for_draw(editor, draw_count_before)
	if not drew:
		push_error("Timed out waiting for the curve editor to redraw")
		quit(1)
	return {
		&"cpu_usec": cpu_elapsed,
		&"draw_usec": editor.last_draw_usec,
		&"to_draw_usec": float(editor.last_draw_finished_usec - started),
	}


func _wait_for_draw(editor: MeasuredCurveEditor, previous_count: int) -> bool:
	for _frame in range(MAX_DRAW_WAIT_FRAMES):
		if editor.draw_count > previous_count:
			return true
		await RenderingServer.frame_post_draw
	return editor.draw_count > previous_count


func _make_curve(point_count: int) -> EasingCurve:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var point_values: Array[EasingCurvePoint] = []
	for index in range(point_count):
		var x := float(index) / float(point_count - 1)
		var y := 0.15 + 0.7 * x
		var point := EasingCurvePoint.new(Vector2(x, y))
		point.left_control_point = Vector2(maxf(0.0, x - 0.01), y - 0.08)
		point.right_control_point = Vector2(minf(1.0, x + 0.01), y + 0.08)
		point_values.append(point)
	curve.points = point_values
	return curve


func _mouse_button(
	button: MouseButton,
	position: Vector2,
	pressed: bool,
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.pressed = pressed
	return event


func _report(
	version: String,
	metric: String,
	point_count: int,
	samples: Array[float],
) -> void:
	samples.sort()
	var median := _percentile(samples, 0.5)
	var p95 := _percentile(samples, 0.95)
	print("EDITOR_BENCH|%s|%s|%d|%.1f|%.1f|%d" % [
		version,
		metric,
		point_count,
		median,
		p95,
		samples.size(),
	])


func _percentile(samples: Array[float], percentile: float) -> float:
	if samples.is_empty():
		return 0.0
	var index := ceili(percentile * samples.size()) - 1
	return samples[clampi(index, 0, samples.size() - 1)]


func _plugin_version() -> String:
	var config := ConfigFile.new()
	if config.load(PLUGIN_CONFIG_PATH) != OK:
		return "unknown"
	return str(config.get_value("plugin", "version", "unknown"))

@tool
extends SceneTree
## Interactive Curve Editor benchmark focused on perceived drag responsiveness.
##
## This is intentionally a Level-2/Level-3 harness, not a claim of native
## Inspector-dock input fidelity. It constructs the real EasingCurve editor and
## point-list controls, drives the real Inspector callbacks, and measures bursts
## of mouse motion without forcing one rendered frame per event.

const INSPECTOR_PLUGIN = preload(
	"res://addons/easing_curve/scripts/editor/inspector/easing_curve_editor_inspector_plugin.gd"
)
const PLUGIN_CONFIG_PATH := "res://addons/easing_curve/plugin.cfg"
const ORDINARY_POINT_COUNTS := [3, 5, 9]
const ORDINARY_BURSTS := [1, 4, 8]
const CROSSING_CASES := [
	[3, 1], [3, 4],
	[5, 1], [5, 4],
	[9, 1], [9, 4],
	[17, 4], [65, 4],
]
const POINT_SCALING_CASES := [
	[9, 1], [9, 4],
	[13, 1], [13, 4],
	[17, 1], [17, 4],
	[25, 1], [25, 4],
	[33, 1], [33, 4],
	[49, 1], [49, 4],
	[65, 1], [65, 4],
]
const ORDINARY_EVENTS_PER_TRIAL := 48
const CROSSING_EVENTS_PER_DIRECTION := 48
const WARMUP_TRIALS := 1
const MEASURED_TRIALS := 5
const CROSSING_MEASURED_TRIALS := 3
const MAX_DRAW_WAIT_FRAMES := 10
const EDITOR_SIZE := Vector2(800.0, 420.0)
const LEFT_X := 0.04
const RIGHT_X := 0.96


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


class SignalCounters extends RefCounted:
	var curve_changed := 0
	var point_resource_changed := 0
	var property_change_requested := 0
	var graph_point_changed := 0
	var edit_finished := 0

	func reset() -> void:
		curve_changed = 0
		point_resource_changed = 0
		property_change_requested = 0
		graph_point_changed = 0
		edit_finished = 0

	func on_curve_changed() -> void:
		curve_changed += 1

	func on_point_resource_changed() -> void:
		point_resource_changed += 1

	func on_property_change_requested(
		_i: int,
		_property_name: StringName,
		_value: Variant,
		_changing: bool,
	) -> void:
		property_change_requested += 1

	func on_graph_point_changed(_i: int, _point: EasingCurvePoint) -> void:
		graph_point_changed += 1

	func on_edit_finished(_point_order: Array[EasingCurvePoint]) -> void:
		edit_finished += 1

	func as_dictionary() -> Dictionary:
		return {
			&"curve_changed": curve_changed,
			&"point_resource_changed": point_resource_changed,
			&"property_change_requested": property_change_requested,
			&"graph_point_changed": graph_point_changed,
			&"edit_finished": edit_finished,
		}


func _init() -> void:
	if not Engine.is_editor_hint():
		push_error("Interaction benchmark requires --editor.")
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Interaction benchmark requires a rendering-capable display server.")
		quit(1)
		return
	call_deferred(&"_run")


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	OS.low_processor_usage_mode = false

	var version := _plugin_version()
	print("INTERACTION_ENV|%s|%s|%s" % [
		version,
		DisplayServer.get_name(),
		RenderingServer.get_video_adapter_name(),
	])
	print("INTERACTION_FIDELITY|level=2|real_editor_controls=true|native_inspector_dock=false")

	if OS.get_environment("EASING_CURVE_POINT_SCALING_ONLY") == "1":
		print("INTERACTION_POINT_SCALING|enabled=true|frame_budget_us=16667")
		for case_value in POINT_SCALING_CASES:
			await _benchmark_crossing(
				version,
				int(case_value[0]),
				int(case_value[1]),
			)
		for _frame in range(3):
			await process_frame
		quit()
		return

	await _viewport_dispatch_smoke(version)

	for point_count in ORDINARY_POINT_COUNTS:
		for burst_size in ORDINARY_BURSTS:
			await _benchmark_ordinary_x(version, point_count, burst_size)

	await _benchmark_vertical_control(version, 5, 4)

	for case_value in CROSSING_CASES:
		await _benchmark_crossing(
			version,
			int(case_value[0]),
			int(case_value[1]),
		)

	for _frame in range(3):
		await process_frame
	quit()


func _benchmark_ordinary_x(
	version: String,
	point_count: int,
	burst_size: int,
) -> void:
	var fixture := await _create_fixture(point_count)
	var curve: EasingCurve = fixture[&"curve"]
	var editor: MeasuredCurveEditor = fixture[&"editor"]
	var host: Control = fixture[&"host"]
	var counters: SignalCounters = fixture[&"counters"]
	var point_index := point_count / 2
	var dragged_point := curve.points[point_index]
	var left_x := curve.points[point_index - 1].position.x
	var right_x := curve.points[point_index + 1].position.x
	var half_gap := minf(
		dragged_point.position.x - left_x,
		right_x - dragged_point.position.x,
	)
	var amplitude := maxf(0.001, half_gap * 0.22)

	var event_cpu: Array[float] = []
	var burst_cpu: Array[float] = []
	var to_draw: Array[float] = []
	var draw_cpu: Array[float] = []
	var commit_cpu: Array[float] = []
	var commit_to_draw: Array[float] = []
	var total_counts := _empty_counts()
	var measured_event_count := 0

	for trial in range(WARMUP_TRIALS + MEASURED_TRIALS):
		var start_world := dragged_point.position
		await _begin_drag(editor, start_world, curve.points.find(dragged_point))
		counters.reset()
		var positions: Array[Vector2] = []
		for event_index in range(ORDINARY_EVENTS_PER_TRIAL):
			var phase := TAU * float(event_index) / float(ORDINARY_EVENTS_PER_TRIAL)
			positions.append(Vector2(
				start_world.x + sin(phase) * amplitude,
				start_world.y,
			))
		var measured := trial >= WARMUP_TRIALS
		await _run_motion_sequence(
			editor,
			positions,
			burst_size,
			measured,
			event_cpu,
			burst_cpu,
			to_draw,
			draw_cpu,
		)
		var commit_sample := await _finish_drag(editor, editor.get_view_pos(dragged_point.position))
		if measured:
			commit_cpu.append(commit_sample[&"cpu_usec"])
			commit_to_draw.append(commit_sample[&"to_draw_usec"])
			measured_event_count += positions.size()
			_accumulate_counts(total_counts, counters.as_dictionary())

	_report_workload(version, "ordinary_x", point_count, burst_size, "event_cpu", event_cpu)
	_report_workload(version, "ordinary_x", point_count, burst_size, "burst_cpu", burst_cpu)
	_report_workload(version, "ordinary_x", point_count, burst_size, "update_to_draw", to_draw)
	_report_workload(version, "ordinary_x", point_count, burst_size, "graph_draw_cpu", draw_cpu)
	_report_workload(version, "ordinary_x", point_count, burst_size, "commit_cpu", commit_cpu)
	_report_workload(version, "ordinary_x", point_count, burst_size, "commit_to_draw", commit_to_draw)
	_report_counts(version, "ordinary_x", point_count, burst_size, total_counts, measured_event_count)

	host.free()
	await process_frame


func _benchmark_vertical_control(
	version: String,
	point_count: int,
	burst_size: int,
) -> void:
	var fixture := await _create_fixture(point_count)
	var curve: EasingCurve = fixture[&"curve"]
	var editor: MeasuredCurveEditor = fixture[&"editor"]
	var host: Control = fixture[&"host"]
	var counters: SignalCounters = fixture[&"counters"]
	var dragged_point := curve.points[point_count / 2]

	var event_cpu: Array[float] = []
	var burst_cpu: Array[float] = []
	var to_draw: Array[float] = []
	var draw_cpu: Array[float] = []
	var commit_cpu: Array[float] = []
	var commit_to_draw: Array[float] = []
	var total_counts := _empty_counts()
	var measured_event_count := 0

	for trial in range(WARMUP_TRIALS + MEASURED_TRIALS):
		var start_world := dragged_point.position
		await _begin_drag(editor, start_world, curve.points.find(dragged_point))
		counters.reset()
		var positions: Array[Vector2] = []
		for event_index in range(ORDINARY_EVENTS_PER_TRIAL):
			var phase := TAU * float(event_index) / float(ORDINARY_EVENTS_PER_TRIAL)
			positions.append(Vector2(
				start_world.x,
				clampf(start_world.y + sin(phase) * 0.04, 0.05, 0.95),
			))
		var measured := trial >= WARMUP_TRIALS
		await _run_motion_sequence(
			editor,
			positions,
			burst_size,
			measured,
			event_cpu,
			burst_cpu,
			to_draw,
			draw_cpu,
		)
		var commit_sample := await _finish_drag(editor, editor.get_view_pos(dragged_point.position))
		if measured:
			commit_cpu.append(commit_sample[&"cpu_usec"])
			commit_to_draw.append(commit_sample[&"to_draw_usec"])
			measured_event_count += positions.size()
			_accumulate_counts(total_counts, counters.as_dictionary())

	_report_workload(version, "vertical_control", point_count, burst_size, "event_cpu", event_cpu)
	_report_workload(version, "vertical_control", point_count, burst_size, "burst_cpu", burst_cpu)
	_report_workload(version, "vertical_control", point_count, burst_size, "update_to_draw", to_draw)
	_report_workload(version, "vertical_control", point_count, burst_size, "graph_draw_cpu", draw_cpu)
	_report_workload(version, "vertical_control", point_count, burst_size, "commit_cpu", commit_cpu)
	_report_workload(version, "vertical_control", point_count, burst_size, "commit_to_draw", commit_to_draw)
	_report_counts(version, "vertical_control", point_count, burst_size, total_counts, measured_event_count)

	host.free()
	await process_frame


func _benchmark_crossing(
	version: String,
	point_count: int,
	burst_size: int,
) -> void:
	var fixture := await _create_fixture(point_count)
	var curve: EasingCurve = fixture[&"curve"]
	var editor: MeasuredCurveEditor = fixture[&"editor"]
	var host: Control = fixture[&"host"]
	var counters: SignalCounters = fixture[&"counters"]
	var dragged_point := curve.points[1]

	var event_cpu: Array[float] = []
	var burst_cpu: Array[float] = []
	var to_draw: Array[float] = []
	var draw_cpu: Array[float] = []
	var commit_cpu: Array[float] = []
	var commit_to_draw: Array[float] = []
	var total_counts := _empty_counts()
	var measured_event_count := 0

	for trial in range(WARMUP_TRIALS + CROSSING_MEASURED_TRIALS):
		var start_index := curve.points.find(dragged_point)
		var start_world := dragged_point.position
		await _begin_drag(editor, start_world, start_index)
		counters.reset()

		var first_target_x := RIGHT_X if start_world.x < 0.5 else LEFT_X
		var second_target_x := LEFT_X if first_target_x == RIGHT_X else RIGHT_X
		var first_positions: Array[Vector2] = []
		for event_index in range(CROSSING_EVENTS_PER_DIRECTION):
			var progress := float(event_index + 1) / float(CROSSING_EVENTS_PER_DIRECTION)
			first_positions.append(Vector2(
				lerpf(start_world.x, first_target_x, progress),
				start_world.y,
			))
		var second_positions: Array[Vector2] = []
		for event_index in range(CROSSING_EVENTS_PER_DIRECTION):
			var progress := float(event_index + 1) / float(CROSSING_EVENTS_PER_DIRECTION)
			second_positions.append(Vector2(
				lerpf(first_target_x, second_target_x, progress),
				start_world.y,
			))

		var measured := trial >= WARMUP_TRIALS
		await _run_motion_sequence(
			editor,
			first_positions,
			burst_size,
			measured,
			event_cpu,
			burst_cpu,
			to_draw,
			draw_cpu,
		)
		var preview_distance := absi(
			EasingCurve.build_ordered_points_with_endpoint_takeover(
				curve.points,
				dragged_point,
			).find(dragged_point) - start_index
		)
		if measured:
			print("INTERACTION_CROSS_DISTANCE|%s|%d|%d|%d" % [
				version,
				point_count,
				burst_size,
				preview_distance,
			])
		await _run_motion_sequence(
			editor,
			second_positions,
			burst_size,
			measured,
			event_cpu,
			burst_cpu,
			to_draw,
			draw_cpu,
		)

		var commit_sample := await _finish_drag(editor, editor.get_view_pos(dragged_point.position))
		if measured:
			commit_cpu.append(commit_sample[&"cpu_usec"])
			commit_to_draw.append(commit_sample[&"to_draw_usec"])
			measured_event_count += first_positions.size() + second_positions.size()
			_accumulate_counts(total_counts, counters.as_dictionary())

	_report_workload(version, "crossing", point_count, burst_size, "event_cpu", event_cpu)
	_report_workload(version, "crossing", point_count, burst_size, "burst_cpu", burst_cpu)
	_report_workload(version, "crossing", point_count, burst_size, "update_to_draw", to_draw)
	_report_workload(version, "crossing", point_count, burst_size, "graph_draw_cpu", draw_cpu)
	_report_workload(version, "crossing", point_count, burst_size, "commit_cpu", commit_cpu)
	_report_workload(version, "crossing", point_count, burst_size, "commit_to_draw", commit_to_draw)
	_report_counts(version, "crossing", point_count, burst_size, total_counts, measured_event_count)

	host.free()
	await process_frame


func _run_motion_sequence(
	editor: MeasuredCurveEditor,
	world_positions: Array[Vector2],
	burst_size: int,
	measured: bool,
	event_cpu_samples: Array[float],
	burst_cpu_samples: Array[float],
	to_draw_samples: Array[float],
	draw_cpu_samples: Array[float],
) -> void:
	var offset := 0
	while offset < world_positions.size():
		var count := mini(burst_size, world_positions.size() - offset)
		var draw_count_before := editor.draw_count
		var burst_started := Time.get_ticks_usec()
		for local_index in range(count):
			var event_started := Time.get_ticks_usec()
			var motion := InputEventMouseMotion.new()
			motion.position = editor.get_view_pos(world_positions[offset + local_index])
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			editor._gui_input(motion)
			if measured:
				event_cpu_samples.append(float(Time.get_ticks_usec() - event_started))
		var burst_elapsed := float(Time.get_ticks_usec() - burst_started)
		var drew := await _wait_for_draw(editor, draw_count_before)
		if not drew:
			push_error("Timed out waiting for drag burst redraw")
			quit(1)
			return
		if measured:
			burst_cpu_samples.append(burst_elapsed)
			to_draw_samples.append(float(editor.last_draw_finished_usec - burst_started))
			draw_cpu_samples.append(editor.last_draw_usec)
		offset += count


func _begin_drag(
	editor: MeasuredCurveEditor,
	world_position: Vector2,
	expected_index: int,
) -> void:
	editor.update_view_transform()
	editor._gui_input(_mouse_button(
		MOUSE_BUTTON_LEFT,
		editor.get_view_pos(world_position),
		true,
	))
	if editor.dragging_point != expected_index:
		push_error("Could not begin expected point drag: expected=%d actual=%d" % [
			expected_index,
			editor.dragging_point,
		])
		quit(1)
		return
	await process_frame


func _finish_drag(
	editor: MeasuredCurveEditor,
	view_position: Vector2,
) -> Dictionary:
	var draw_count_before := editor.draw_count
	var started := Time.get_ticks_usec()
	editor._gui_input(_mouse_button(MOUSE_BUTTON_LEFT, view_position, false))
	var cpu_elapsed := float(Time.get_ticks_usec() - started)
	var drew := await _wait_for_draw(editor, draw_count_before)
	if not drew:
		push_error("Timed out waiting for drag commit redraw")
		quit(1)
	return {
		&"cpu_usec": cpu_elapsed,
		&"to_draw_usec": float(editor.last_draw_finished_usec - started),
	}


func _create_fixture(point_count: int) -> Dictionary:
	var curve := _make_curve(point_count)
	var inspector := INSPECTOR_PLUGIN.new()
	var editor := MeasuredCurveEditor.new()
	var host := VBoxContainer.new()
	var counters := SignalCounters.new()

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

	curve.changed.connect(counters.on_curve_changed)
	editor.point_property_change_requested.connect(counters.on_property_change_requested)
	editor.point_changed.connect(counters.on_graph_point_changed)
	editor.point_edit_finished.connect(counters.on_edit_finished)
	for point in curve.points:
		point.changed.connect(counters.on_point_resource_changed)

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
		&"counters": counters,
	}


func _viewport_dispatch_smoke(version: String) -> void:
	var fixture := await _create_fixture(5)
	var curve: EasingCurve = fixture[&"curve"]
	var editor: MeasuredCurveEditor = fixture[&"editor"]
	var host: Control = fixture[&"host"]
	var point := curve.points[2]
	editor.update_view_transform()
	var local_position := editor.get_view_pos(point.position)
	var viewport_position := editor.get_global_transform_with_canvas() * local_position
	var press := _mouse_button(MOUSE_BUTTON_LEFT, viewport_position, true)
	get_root().push_input(press, false)
	await process_frame
	var started := editor.dragging_point == 2
	if started:
		var target_world := Vector2(point.position.x + 0.01, point.position.y)
		var motion := InputEventMouseMotion.new()
		motion.position = editor.get_global_transform_with_canvas() * editor.get_view_pos(target_world)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_root().push_input(motion, false)
		await process_frame
		var release := _mouse_button(MOUSE_BUTTON_LEFT, motion.position, false)
		get_root().push_input(release, false)
		await process_frame
	print("INTERACTION_VIEWPORT_DISPATCH|%s|%s" % [version, "available" if started else "unavailable"])
	host.free()
	await process_frame


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


func _report_workload(
	version: String,
	workload: String,
	point_count: int,
	burst_size: int,
	metric: String,
	samples: Array[float],
) -> void:
	if samples.is_empty():
		return
	var sorted := samples.duplicate()
	sorted.sort()
	var p50 := _percentile(sorted, 0.50)
	var p95 := _percentile(sorted, 0.95)
	var p99 := _percentile(sorted, 0.99)
	var maximum: float = float(sorted[sorted.size() - 1])
	var over_8 := _count_over(sorted, 8333.0)
	var over_16 := _count_over(sorted, 16667.0)
	var over_25 := _count_over(sorted, 25000.0)
	var over_33 := _count_over(sorted, 33333.0)
	print("INTERACTION_BENCH|%s|%s|%d|%d|%s|%.1f|%.1f|%.1f|%.1f|%d|%d|%d|%d|%d" % [
		version,
		workload,
		point_count,
		burst_size,
		metric,
		p50,
		p95,
		p99,
		maximum,
		sorted.size(),
		over_8,
		over_16,
		over_25,
		over_33,
	])


func _empty_counts() -> Dictionary:
	return {
		&"curve_changed": 0,
		&"point_resource_changed": 0,
		&"property_change_requested": 0,
		&"graph_point_changed": 0,
		&"edit_finished": 0,
	}


func _accumulate_counts(total: Dictionary, sample: Dictionary) -> void:
	for key in total.keys():
		total[key] = int(total[key]) + int(sample.get(key, 0))


func _report_counts(
	version: String,
	workload: String,
	point_count: int,
	burst_size: int,
	counts: Dictionary,
	event_count: int,
) -> void:
	var divisor := maxf(1.0, float(event_count))
	print("INTERACTION_COUNTS|%s|%s|%d|%d|%d|%.4f|%.4f|%.4f|%.4f|%.4f" % [
		version,
		workload,
		point_count,
		burst_size,
		event_count,
		float(counts[&"curve_changed"]) / divisor,
		float(counts[&"point_resource_changed"]) / divisor,
		float(counts[&"property_change_requested"]) / divisor,
		float(counts[&"graph_point_changed"]) / divisor,
		float(counts[&"edit_finished"]) / divisor,
	])


func _count_over(samples: Array[float], threshold_usec: float) -> int:
	var count := 0
	for sample in samples:
		if sample > threshold_usec:
			count += 1
	return count


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

@tool
extends EditorPlugin
## Native Inspector benchmark for horizontal point-crossing gestures.
##
## This runs as a temporary EditorPlugin in a real Godot editor process. The
## runner enables it only inside an isolated test project, so the benchmark uses
## the registered Easing Curve Inspector plugin without shipping instrumentation
## in the addon itself.

const POINT_COUNTS := [5, 9]
const BURST_SIZE := 4
const EVENTS_PER_DIRECTION := 48
const WARMUP_TRIALS := 1
const MEASURED_TRIALS := 4
const GRAPH_WAIT_FRAMES := 60
const LEFT_X := 0.04
const RIGHT_X := 0.96
const LOG_PATH := "res://test/_temp/native_inspector_crossing_benchmark.log"

var _version := "unknown"
var _log: FileAccess


func _enter_tree() -> void:
	_version = _plugin_version()
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_write("NATIVE_INSPECTOR_ENV|%s|%s|%s" % [
		_version,
		DisplayServer.get_name(),
		RenderingServer.get_video_adapter_name(),
	])
	call_deferred(&"_run")


func _run() -> void:
	var passed := true
	for point_count in POINT_COUNTS:
		passed = await _run_crossing_case(point_count) and passed
	_write("NATIVE_INSPECTOR_DONE|%s|%s" % [
		_version,
		"PASS" if passed else "FAIL",
	])
	if _log != null:
		_log.flush()
	get_tree().quit(0 if passed else 1)


func _run_crossing_case(point_count: int) -> bool:
	var curve := _make_curve(point_count)
	EditorInterface.edit_resource(curve)
	var graph := await _wait_for_graph(curve)
	if graph == null:
		_write("NATIVE_INSPECTOR_ERROR|%s|%d|graph_not_found" % [
			_version,
			point_count,
		])
		return false

	var target := curve.points[1]
	var event_cpu: Array[float] = []
	var burst_to_draw: Array[float] = []
	var crossing_distances: Array[int] = []

	for trial in range(WARMUP_TRIALS + MEASURED_TRIALS):
		graph = await _wait_for_graph(curve)
		if graph == null:
			_write("NATIVE_INSPECTOR_ERROR|%s|%d|graph_lost_before_trial" % [
				_version,
				point_count,
			])
			return false

		var start_index := curve.points.find(target)
		if start_index < 0:
			_write("NATIVE_INSPECTOR_ERROR|%s|%d|target_resource_lost" % [
				_version,
				point_count,
			])
			return false

		graph.update_view_transform()
		var start_world: Vector2 = target.position
		var press_position := graph.get_view_pos(start_world)
		graph._gui_input(_mouse_button(press_position, true))
		if graph.dragging_point != start_index:
			var point_hit := graph.get_point_at(press_position)
			var control_hit := graph.get_control_at(press_position)
			_write(
				"NATIVE_INSPECTOR_ERROR|%s|%d|drag_start_failed|expected=%d|actual=%d|point_hit=%d|control_hit=%s"
				% [
					_version,
					point_count,
					start_index,
					graph.dragging_point,
					point_hit,
					str(control_hit),
				]
			)
			return false

		var measured := trial >= WARMUP_TRIALS
		if not await _run_motion_sequence(
			graph,
			_make_horizontal_positions(start_world, RIGHT_X),
			measured,
			event_cpu,
			burst_to_draw,
		):
			return false

		if measured:
			var preview_order := EasingCurve.build_ordered_points_with_endpoint_takeover(
				curve.points,
				target,
			)
			crossing_distances.append(absi(preview_order.find(target) - start_index))

		if not await _run_motion_sequence(
			graph,
			_make_horizontal_positions(target.position, LEFT_X),
			measured,
			event_cpu,
			burst_to_draw,
		):
			return false

		graph._gui_input(_mouse_button(graph.get_view_pos(target.position), false))
		await get_tree().process_frame
		await get_tree().process_frame

	_report_samples(point_count, "event_cpu", event_cpu)
	_report_samples(point_count, "input_to_postdraw", burst_to_draw)
	var min_crossing: int = (
		int(crossing_distances.min())
		if not crossing_distances.is_empty()
		else 0
	)
	_write("NATIVE_INSPECTOR_CROSSING|%s|%d|burst=%d|min_distance=%d|trials=%d" % [
		_version,
		point_count,
		BURST_SIZE,
		min_crossing,
		MEASURED_TRIALS,
	])
	return min_crossing >= maxi(1, point_count - 3)


func _run_motion_sequence(
	graph: EasingCurveEditor,
	world_positions: Array[Vector2],
	measured: bool,
	event_cpu: Array[float],
	burst_to_draw: Array[float],
) -> bool:
	var offset := 0
	while offset < world_positions.size():
		if not is_instance_valid(graph):
			_write("NATIVE_INSPECTOR_ERROR|%s|graph_rebuilt_during_active_drag" % _version)
			return false

		var count := mini(BURST_SIZE, world_positions.size() - offset)
		var burst_started := Time.get_ticks_usec()
		for local_index in range(count):
			var event_started := Time.get_ticks_usec()
			var motion := InputEventMouseMotion.new()
			motion.position = graph.get_view_pos(world_positions[offset + local_index])
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			graph._gui_input(motion)
			if measured:
				event_cpu.append(float(Time.get_ticks_usec() - event_started))
		await RenderingServer.frame_post_draw
		if measured:
			burst_to_draw.append(float(Time.get_ticks_usec() - burst_started))
		offset += count
	return true


func _make_horizontal_positions(
	start_world: Vector2,
	target_x: float,
) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for event_index in range(EVENTS_PER_DIRECTION):
		var progress := float(event_index + 1) / float(EVENTS_PER_DIRECTION)
		positions.append(Vector2(
			lerpf(start_world.x, target_x, progress),
			start_world.y,
		))
	return positions


func _wait_for_graph(curve: EasingCurve) -> EasingCurveEditor:
	for _frame in range(GRAPH_WAIT_FRAMES):
		var graph := _find_graph(EditorInterface.get_inspector())
		if graph != null and graph.get_curve() == curve:
			return graph
		await get_tree().process_frame
	return null


func _find_graph(root: Node) -> EasingCurveEditor:
	if root is EasingCurveEditor:
		return root
	for child in root.get_children():
		var graph := _find_graph(child)
		if graph != null:
			return graph
	return null


func _make_curve(point_count: int) -> EasingCurve:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var points: Array[EasingCurvePoint] = []
	for index in range(point_count):
		var x := float(index) / float(point_count - 1)
		var y := 0.15 + 0.70 * x
		var point := EasingCurvePoint.new(Vector2(x, y))
		# Keep synthetic handles well away from neighboring point hit targets.
		# The native Inspector can be narrow enough that the denser 9-point
		# fixture otherwise gives a neighboring handle precedence over P2.
		point.left_control_point = Vector2(x - 0.02, y - 0.35)
		point.right_control_point = Vector2(x + 0.02, y + 0.35)
		points.append(point)
	curve.points = points
	return curve


func _mouse_button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	return event


func _report_samples(
	point_count: int,
	metric: String,
	samples: Array[float],
) -> void:
	if samples.is_empty():
		return
	var sorted := samples.duplicate()
	sorted.sort()
	_write("NATIVE_INSPECTOR_BENCH|%s|crossing|%d|burst=%d|%s|p50=%.1f|p95=%.1f|p99=%.1f|max=%.1f|n=%d" % [
		_version,
		point_count,
		BURST_SIZE,
		metric,
		_percentile(sorted, 0.50),
		_percentile(sorted, 0.95),
		_percentile(sorted, 0.99),
		sorted.back(),
		sorted.size(),
	])


func _percentile(samples: Array[float], percentile: float) -> float:
	var index := ceili(percentile * samples.size()) - 1
	return samples[clampi(index, 0, samples.size() - 1)]


func _plugin_version() -> String:
	var config := ConfigFile.new()
	if config.load("res://addons/easing_curve/plugin.cfg") != OK:
		return "unknown"
	return str(config.get_value("plugin", "version", "unknown"))


func _write(line: String) -> void:
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()

@tool
extends EditorPlugin
## Interactive physical-input probe for Easing Curve editor responsiveness.
##
## This script is copied into a temporary addon by the A/B runner. It opens a
## 9-point EasingCurve through the real Inspector, listens to the graph's actual
## gui_input signal, groups delivered mouse-motion events by rendered frame, and
## writes a CSV + summary when the user clicks Save & Close.

const DEFAULT_POINT_COUNT := 9
const POINT_COUNT_PATH := "res://test/_temp/point_count.txt"
const CSV_PATH := "res://test/_temp/physical_input_profile.csv"
const SUMMARY_PATH := "res://test/_temp/physical_input_summary.txt"
const GRAPH_WAIT_MESSAGE := "Waiting for EasingCurveEditor in the native Inspector..."
const PROFILER_CONTROL_PATH := "res://test/_temp/profiler_control.txt"
const WPR_START_REQUEST_PATH := "res://test/_temp/wpr_start.request"
const WPR_START_ACK_PATH := "res://test/_temp/wpr_start.ack"
const WPR_STOP_REQUEST_PATH := "res://test/_temp/wpr_stop.request"
const WPR_STOP_ACK_PATH := "res://test/_temp/wpr_stop.ack"

var _version := "unknown"
var _point_count := DEFAULT_POINT_COUNT
var _curve: EasingCurve
var _graph: EasingCurveEditor
var _panel: HBoxContainer
var _status_label: Label
var _start_button: Button
var _close_button: Button
var _rows: Array[String] = []
var _event_id := 0
var _left_pressed := false
var _pending_drag_event_ids: Array[int] = []
var _pending_drag_event_times: Array[int] = []
var _frame_burst_sizes: Array[int] = []
var _oldest_to_draw_usec: Array[float] = []
var _newest_to_draw_usec: Array[float] = []
var _total_motion_events := 0
var _total_drag_motion_events := 0
var _graph_rebuilds := 0
var _capturing := false
var _external_profiler := false
var _start_pending := false
var _stop_pending := false
var _capture_started_usec := 0
var _capture_ended_usec := 0
var _finalized := false


func _enter_tree() -> void:
	_version = _plugin_version()
	var configured_point_count := _read_text(POINT_COUNT_PATH).strip_edges().to_int()
	if configured_point_count >= 3:
		_point_count = clampi(configured_point_count, 3, 65)
	_external_profiler = _read_text(PROFILER_CONTROL_PATH).strip_edges() == "external"
	_clear_profiler_markers()
	_curve = _make_curve()
	_create_probe_panel()
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	set_process(true)
	EditorInterface.edit_resource(_curve)
	DisplayServer.window_move_to_foreground()
	print("PHYSICAL_INPUT_PROBE_START|version=%s|pid=%d|points=%d" % [
		_version,
		OS.get_process_id(),
		_point_count,
	])
	print("Warm up with P2 first. Then click 'Start Capture'; synchronized WPR capture begins only after profiler acknowledgment. Perform the measured drag cycles, then click 'Save & Close'.")


func _exit_tree() -> void:
	_finalize_capture()
	_disconnect_graph()
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	if is_instance_valid(_panel):
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()


func _process(_delta: float) -> void:
	_poll_profiler_handshake()
	var next_graph := _find_graph(EditorInterface.get_inspector())
	if next_graph == _graph:
		return
	_disconnect_graph()
	_graph = next_graph
	if _graph == null or _graph.get_curve() != _curve:
		_graph = null
		_update_buttons()
		_set_status(GRAPH_WAIT_MESSAGE)
		return
	_graph_rebuilds += 1
	_graph.gui_input.connect(_on_graph_gui_input)
	_graph.point_changed.connect(_on_graph_point_changed)
	_update_buttons()
	_set_status(
		(
			"Capturing — drag P2 horizontally across points and back. Events: %d | frames: %d"
			% [_total_drag_motion_events, _frame_burst_sizes.size()]
		)
		if _capturing
		else "Warm up P2, then click Start / Reset Capture."
	)
	print("PHYSICAL_INPUT_GRAPH_READY|version=%s|pid=%d|graph_id=%d|rebuild=%d" % [
		_version,
		OS.get_process_id(),
		_graph.get_instance_id(),
		_graph_rebuilds,
	])


func _create_probe_panel() -> void:
	_panel = HBoxContainer.new()
	_panel.add_theme_constant_override(&"separation", 12)
	_status_label = Label.new()
	_status_label.text = GRAPH_WAIT_MESSAGE
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(_status_label)
	_start_button = Button.new()
	_start_button.text = "Start Capture"
	_start_button.tooltip_text = "Start the synchronized measured physical-input capture after warm-up."
	_start_button.disabled = true
	_start_button.pressed.connect(_on_start_capture_pressed)
	_panel.add_child(_start_button)
	_close_button = Button.new()
	_close_button.text = "Save & Close"
	_close_button.tooltip_text = "Stop the synchronized capture, write results, and close this isolated editor."
	_close_button.disabled = true
	_close_button.pressed.connect(_on_save_and_close_pressed)
	_panel.add_child(_close_button)
	add_control_to_bottom_panel(_panel, "Easing Curve Input Probe")


func _on_start_capture_pressed() -> void:
	if _capturing or _start_pending or _stop_pending or not is_instance_valid(_graph):
		return
	_reset_capture_data()
	if _external_profiler:
		_start_pending = true
		_update_buttons()
		_set_status("Starting WPR CPU sampling — capture will begin after profiler acknowledgment...")
		_write_marker(WPR_START_REQUEST_PATH)
		print("PHYSICAL_INPUT_WPR_START_REQUEST|version=%s|pid=%d" % [_version, OS.get_process_id()])
	else:
		_begin_capture()


func _on_save_and_close_pressed() -> void:
	if not _capturing or _start_pending or _stop_pending:
		return
	_capturing = false
	_capture_ended_usec = Time.get_ticks_usec()
	if not _pending_drag_event_times.is_empty():
		_on_frame_post_draw()
	if _external_profiler:
		_stop_pending = true
		_update_buttons()
		_set_status("Stopping WPR CPU sampling and saving capture...")
		_write_marker(WPR_STOP_REQUEST_PATH)
		print("PHYSICAL_INPUT_WPR_STOP_REQUEST|version=%s|pid=%d" % [_version, OS.get_process_id()])
	else:
		_finalize_capture()
		get_tree().quit()


func _on_graph_gui_input(event: InputEvent) -> void:
	if not _capturing:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_left_pressed = button.pressed
			_event_id += 1
			_append_row([
				"BUTTON",
				_version,
				str(Time.get_ticks_usec()),
				str(Engine.get_process_frames()),
				str(_event_id),
				"1" if _left_pressed else "0",
				str(_graph.dragging_point if is_instance_valid(_graph) else -1),
				_num(button.position.x),
				_num(button.position.y),
				"", "", "", "", "", "", "", "",
				"", "", "", "", "",
			])
		return

	if not event is InputEventMouseMotion:
		return
	var motion := event as InputEventMouseMotion
	_total_motion_events += 1
	_event_id += 1
	var received_usec := Time.get_ticks_usec()
	var dragging := _left_pressed or bool(motion.button_mask & MOUSE_BUTTON_MASK_LEFT)
	if dragging:
		_total_drag_motion_events += 1
		_pending_drag_event_ids.append(_event_id)
		_pending_drag_event_times.append(received_usec)
	_append_row([
		"MOTION",
		_version,
		str(received_usec),
		str(Engine.get_process_frames()),
		str(_event_id),
		"1" if dragging else "0",
		str(_graph.dragging_point if is_instance_valid(_graph) else -1),
		_num(motion.position.x),
		_num(motion.position.y),
		_num(motion.relative.x),
		_num(motion.relative.y),
		_num(motion.screen_relative.x),
		_num(motion.screen_relative.y),
		_num(motion.velocity.x),
		_num(motion.velocity.y),
		_num(motion.screen_velocity.x),
		_num(motion.screen_velocity.y),
		"", "", "", "", "",
	])


func _on_graph_point_changed(point_index: int, _point: EasingCurvePoint) -> void:
	if not _capturing:
		return
	_append_row([
		"POINT_CHANGED",
		_version,
		str(Time.get_ticks_usec()),
		str(Engine.get_process_frames()),
		str(_event_id),
		"1" if _left_pressed else "0",
		str(point_index),
		"", "", "", "", "", "", "", "", "", "",
		"", "", "", "", "",
	])


func _on_frame_post_draw() -> void:
	if _pending_drag_event_times.is_empty():
		return
	var draw_usec := Time.get_ticks_usec()
	var burst_count := _pending_drag_event_times.size()
	var first_id: int = int(_pending_drag_event_ids.front())
	var last_id: int = int(_pending_drag_event_ids.back())
	var oldest_latency := float(draw_usec - _pending_drag_event_times.front())
	var newest_latency := float(draw_usec - _pending_drag_event_times.back())
	_frame_burst_sizes.append(burst_count)
	_oldest_to_draw_usec.append(oldest_latency)
	_newest_to_draw_usec.append(newest_latency)
	_append_row([
		"FRAME",
		_version,
		str(draw_usec),
		str(Engine.get_process_frames()),
		str(last_id),
		"1" if _left_pressed else "0",
		str(_graph.dragging_point if is_instance_valid(_graph) else -1),
		"", "", "", "", "", "", "", "", "", "",
		str(burst_count),
		str(first_id),
		str(last_id),
		_num(oldest_latency),
		_num(newest_latency),
	])
	_pending_drag_event_ids.clear()
	_pending_drag_event_times.clear()
	_set_status(
		"Capturing — drag P2 horizontally across points and back. Events: %d | frames: %d | max burst: %d"
		% [
			_total_drag_motion_events,
			_frame_burst_sizes.size(),
			_max_int(_frame_burst_sizes),
		]
	)


func _disconnect_graph() -> void:
	if not is_instance_valid(_graph):
		_graph = null
		return
	if _graph.gui_input.is_connected(_on_graph_gui_input):
		_graph.gui_input.disconnect(_on_graph_gui_input)
	if _graph.point_changed.is_connected(_on_graph_point_changed):
		_graph.point_changed.disconnect(_on_graph_point_changed)
	_graph = null


func _finalize_capture() -> void:
	if _finalized:
		return
	_finalized = true
	_capturing = false
	if _capture_ended_usec == 0:
		_capture_ended_usec = Time.get_ticks_usec()
	if not _pending_drag_event_times.is_empty():
		_on_frame_post_draw()
	var csv := FileAccess.open(CSV_PATH, FileAccess.WRITE)
	if csv != null:
		csv.store_line(
			"kind,version,usec,process_frame,event_id,left_down,dragging_point,x,y,relative_x,relative_y,screen_relative_x,screen_relative_y,velocity_x,velocity_y,screen_velocity_x,screen_velocity_y,burst_count,first_event_id,last_event_id,oldest_to_draw_us,newest_to_draw_us"
		)
		for row in _rows:
			csv.store_line(row)
		csv.flush()

	var summary := FileAccess.open(SUMMARY_PATH, FileAccess.WRITE)
	if summary != null:
		summary.store_line("version=%s" % _version)
		summary.store_line("point_count=%d" % _point_count)
		summary.store_line("pid=%d" % OS.get_process_id())
		summary.store_line("profiler_synchronized=%s" % str(_external_profiler))
		summary.store_line("capture_duration_us=%d" % maxi(0, _capture_ended_usec - _capture_started_usec))
		summary.store_line("total_motion_events=%d" % _total_motion_events)
		summary.store_line("drag_motion_events=%d" % _total_drag_motion_events)
		summary.store_line("frames_with_drag_motion=%d" % _frame_burst_sizes.size())
		summary.store_line("graph_instances_seen=%d" % _graph_rebuilds)
		summary.store_line("max_events_per_frame=%d" % _max_int(_frame_burst_sizes))
		_write_percentiles(summary, "events_per_frame", _to_float_array(_frame_burst_sizes))
		_write_percentiles(summary, "oldest_event_to_draw_us", _oldest_to_draw_usec)
		_write_percentiles(summary, "newest_event_to_draw_us", _newest_to_draw_usec)
		summary.flush()
	print("PHYSICAL_INPUT_PROBE_SAVED|version=%s|events=%d|drag_events=%d|frames=%d|max_burst=%d" % [
		_version,
		_total_motion_events,
		_total_drag_motion_events,
		_frame_burst_sizes.size(),
		_max_int(_frame_burst_sizes),
	])


func _poll_profiler_handshake() -> void:
	if _start_pending and FileAccess.file_exists(WPR_START_ACK_PATH):
		_start_pending = false
		_capturing = true
		_capture_started_usec = Time.get_ticks_usec()
		_update_buttons()
		_set_status("Capturing — perform 10 left/right crossing cycles with P2, then Save & Close.")
		print("PHYSICAL_INPUT_CAPTURE_STARTED|version=%s|pid=%d|profiler_synced=true" % [_version, OS.get_process_id()])
	if _stop_pending and FileAccess.file_exists(WPR_STOP_ACK_PATH):
		_stop_pending = false
		_finalize_capture()
		get_tree().quit()


func _begin_capture() -> void:
	_capturing = true
	_capture_started_usec = Time.get_ticks_usec()
	_update_buttons()
	_set_status("Capturing — perform 10 left/right crossing cycles with P2, then Save & Close.")
	print("PHYSICAL_INPUT_CAPTURE_STARTED|version=%s|pid=%d|profiler_synced=false" % [_version, OS.get_process_id()])


func _reset_capture_data() -> void:
	_rows.clear()
	_event_id = 0
	_left_pressed = false
	_pending_drag_event_ids.clear()
	_pending_drag_event_times.clear()
	_frame_burst_sizes.clear()
	_oldest_to_draw_usec.clear()
	_newest_to_draw_usec.clear()
	_total_motion_events = 0
	_total_drag_motion_events = 0
	_graph_rebuilds = 1 if is_instance_valid(_graph) else 0
	_capture_started_usec = 0
	_capture_ended_usec = 0
	_finalized = false


func _update_buttons() -> void:
	if is_instance_valid(_start_button):
		_start_button.disabled = not is_instance_valid(_graph) or _capturing or _start_pending or _stop_pending
		_start_button.text = "Capturing..." if _capturing else "Start Capture"
	if is_instance_valid(_close_button):
		_close_button.disabled = not _capturing or _start_pending or _stop_pending


func _write_marker(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_line(str(Time.get_ticks_usec()))
		file.flush()


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _clear_profiler_markers() -> void:
	for path in [
		WPR_START_REQUEST_PATH,
		WPR_START_ACK_PATH,
		WPR_STOP_REQUEST_PATH,
		WPR_STOP_ACK_PATH,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_percentiles(file: FileAccess, label: String, values: Array[float]) -> void:
	if values.is_empty():
		file.store_line("%s_p50=0" % label)
		file.store_line("%s_p95=0" % label)
		file.store_line("%s_p99=0" % label)
		file.store_line("%s_max=0" % label)
		return
	var sorted := values.duplicate()
	sorted.sort()
	file.store_line("%s_p50=%.1f" % [label, _percentile(sorted, 0.50)])
	file.store_line("%s_p95=%.1f" % [label, _percentile(sorted, 0.95)])
	file.store_line("%s_p99=%.1f" % [label, _percentile(sorted, 0.99)])
	file.store_line("%s_max=%.1f" % [label, sorted.back()])


func _percentile(values: Array[float], percentile: float) -> float:
	var index := ceili(percentile * values.size()) - 1
	return values[clampi(index, 0, values.size() - 1)]


func _append_row(values: Array[String]) -> void:
	_rows.append(",".join(values))


func _set_status(text: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = text


func _make_curve() -> EasingCurve:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var points: Array[EasingCurvePoint] = []
	for index in range(_point_count):
		var x := float(index) / float(_point_count - 1)
		var y := 0.15 + 0.70 * x
		var point := EasingCurvePoint.new(Vector2(x, y))
		point.left_control_point = Vector2(x - 0.02, y - 0.35)
		point.right_control_point = Vector2(x + 0.02, y + 0.35)
		points.append(point)
	curve.points = points
	return curve


func _find_graph(root: Node) -> EasingCurveEditor:
	if root is EasingCurveEditor:
		return root
	for child in root.get_children():
		var graph := _find_graph(child)
		if graph != null:
			return graph
	return null


func _plugin_version() -> String:
	var config := ConfigFile.new()
	if config.load("res://addons/easing_curve/plugin.cfg") != OK:
		return "unknown"
	return str(config.get_value("plugin", "version", "unknown"))


func _to_float_array(values: Array[int]) -> Array[float]:
	var result: Array[float] = []
	for value in values:
		result.append(float(value))
	return result


func _max_int(values: Array[int]) -> int:
	var maximum := 0
	for value in values:
		maximum = maxi(maximum, value)
	return maximum


func _num(value: float) -> String:
	return "%.3f" % value

@tool
extends SceneTree
## Real-Inspector topology benchmark. Counts always denote STARTING point counts.
## All instrumentation lives in these test subclasses, never in the shipped addon.
const Context = preload("res://addons/easing_curve/scripts/editor/inspector/inspector_curve_context.gd")
const Plugin = preload("res://addons/easing_curve/scripts/editor/inspector/easing_curve_editor_inspector_plugin.gd")
const Factory = preload("res://addons/easing_curve/scripts/editor/backend/curve_editor_backend_factory.gd")
const COUNTS := [9, 65, 129, 257]
const WORKLOADS := ["graph_add", "list_add", "remove", "reorder", "undo_add", "redo_add", "takeover"]
const WARMUPS := 2
const TRIALS := 7

class ProbeContext extends Context:
	static var generation := 0
	static var panels_built := 0
	static var ui_usec := 0
	static var completed_usec := 0
	static var measure_costs := true
	var point_list: Control

	func _create_native_point_panel(point: Resource, index: int, count: int) -> Control:
		if measure_costs:
			panels_built += 1
		return super(point, index, count)

	func handle_points(target: EasingCurve) -> VBoxContainer:
		if measure_costs:
			panels_built += target.points.size()
		point_list = super(target)
		return point_list

	func _refresh_native_point_list(target: Resource) -> void:
		var started := Time.get_ticks_usec()
		super(target)
		if measure_costs:
			ui_usec += Time.get_ticks_usec() - started
		if not _native_points_refresh_queued and not disposed:
			generation += 1
			completed_usec = Time.get_ticks_usec()

class ProbePlugin extends Plugin:
	var current: ProbeContext
	var parse_started := 0
	var parses := 0

	func _parse_begin(object: Object) -> void:
		parse_started = Time.get_ticks_usec()
		parses += 1
		current = ProbeContext.new()
		_construction_context = current
		current.editor_undo_redo = editor_undo_redo
		current._initial_autofit_resource_ids = _initial_autofit_resource_ids
		current._autofit_rebuild_resources = _autofit_rebuild_resources
		current._legacy_selection_by_resource = _legacy_selection_by_resource
		current._parse_begin(object)

	func _parse_end(object: Object) -> void:
		super(object)
		if ProbeContext.measure_costs:
			ProbeContext.ui_usec += Time.get_ticks_usec() - parse_started
		ProbeContext.generation += 1
		ProbeContext.completed_usec = Time.get_ticks_usec()

var plugin: ProbePlugin
var undo_plugin: EditorPlugin
var inspector: EditorInspector
var window: Window
var failed := false

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	if not Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		push_error("Topology benchmark requires a rendering-capable --editor host")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	ProbeContext.measure_costs = "--cost-hooks-off" not in OS.get_cmdline_user_args()
	undo_plugin = EditorPlugin.new()
	plugin = ProbePlugin.new()
	plugin.editor_undo_redo = undo_plugin.get_undo_redo()
	undo_plugin.add_inspector_plugin(plugin)
	window = Window.new()
	window.size = Vector2i(820, 900)
	window.title = "Easing Curve topology benchmark"
	root.add_child(window)
	inspector = EditorInspector.new()
	inspector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(inspector)
	print("TOPOLOGY_ENV|", JSON.stringify({"godot": Engine.get_version_info(), "renderer": DisplayServer.get_name(), "gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(), "starting_counts": COUNTS, "warmups": WARMUPS, "trials": TRIALS, "size": window.size}))
	for native in [true, false]:
		if ("--native-only" in OS.get_cmdline_user_args() and not native) or ("--legacy-only" in OS.get_cmdline_user_args() and native):
			continue
		for count in COUNTS:
			var requested_count := _argument_value("--count=")
			if not requested_count.is_empty() and count != requested_count.to_int():
				continue
			if "--large-only" in OS.get_cmdline_user_args() and count < 129:
				continue
			await _benchmark(native, count)
			if failed:
				break
		if failed:
			break
	inspector.edit(null)
	window.free()
	undo_plugin.remove_inspector_plugin(plugin)
	undo_plugin.free()
	await process_frame
	quit(1 if failed else 0)

func _curve(native: bool, count: int) -> Resource:
	var target: Resource = ClassDB.instantiate(&"NativeEasingCurve") if native else EasingCurve.new()
	target.set(&"transition" if native else &"trans_type", 100 if native else EasingCurve.TRANS.CUSTOM)
	var backend := Factory.create(target)
	var points: Array[Resource] = []
	for index in range(count):
		var x := float(index) / float(count - 1)
		points.append(backend.create_point(Vector2(x, 0.15 + 0.7 * x)))
	if native:
		target.set(&"points", points)
	else:
		var typed: Array[EasingCurvePoint] = []
		typed.assign(points)
		target.set(&"points", typed)
	return target


func _argument_value(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""

func _history(target: Resource) -> UndoRedo:
	var manager := plugin.editor_undo_redo
	return manager.get_history_undo_redo(manager.get_object_history_id(target))

func _panel_ids(context: ProbeContext) -> Dictionary:
	var result := {}
	var list: Control = context.point_list if context.curve != null else context._native_points_content
	if is_instance_valid(list):
		for child in list.get_children():
			if not child.has_meta(&"point_resource"):
				continue
			var point: Resource = child.get_meta(&"point_resource", null)
			if point != null:
				result[point.get_instance_id()] = child.get_instance_id()
	return result

func _wait_generation(target: Resource, previous: int) -> bool:
	for frame in range(120):
		if ProbeContext.generation > previous and plugin.current != null and plugin.current.resource == target and not plugin.current.disposed:
			var backend := Factory.create(target)
			var list: Control = plugin.current.point_list if target is EasingCurve else plugin.current._native_points_content
			var actual: Array[Resource] = []
			if is_instance_valid(list):
				for child in list.get_children():
					if child.has_meta(&"point_resource"):
						actual.append(child.get_meta(&"point_resource"))
			if actual == backend.get_display_points():
				# Register only AFTER the expected generation and topology are installed.
				await RenderingServer.frame_post_draw
				return true
		await process_frame
	push_error("Timed out waiting for topology generation %d" % (previous + 1))
	failed = true
	return false

func _perform(target: Resource, workload: String) -> void:
	var context := plugin.current
	var backend := Factory.create(target)
	var middle: int = backend.get_point_count() / 2
	match workload:
		"graph_add", "takeover":
			var x: float = 0.0 if workload == "takeover" else (middle + 0.5) / float(backend.get_point_count() - 1)
			context.easing_curve_editor._request_point_add(backend.create_point(Vector2(x, 0.6)))
		"list_add":
			context._on_add_point_btn_pressed()
		"remove":
			if target is EasingCurve:
				context._remove_point(backend.get_point(middle))
			else:
				context._remove_native_point(backend.get_point(middle))
		"reorder":
			context._move_point_relative(backend.get_point(middle), 1)
		"undo_add":
			_history(target).undo()
		"redo_add":
			_history(target).redo()

func _benchmark(native: bool, count: int) -> void:
	for workload in ["build"] + WORKLOADS:
		var requested_workload := _argument_value("--workload=")
		if not requested_workload.is_empty() and workload != requested_workload:
			continue
		if "--build-only" in OS.get_cmdline_user_args() and workload != "build":
			continue
		if "--add-only" in OS.get_cmdline_user_args() and workload not in ["build", "graph_add", "list_add"]:
			continue
		for trial in range(WARMUPS + TRIALS):
			# Undo Add starts at count and removes the prepared addition.
			var target := _curve(native, count - 1 if workload == "undo_add" else count)
			var generation := ProbeContext.generation
			var build_ui_before := ProbeContext.ui_usec
			var build_panels_before := ProbeContext.panels_built
			var started := Time.get_ticks_usec()
			inspector.edit(target)
			var build_cpu := Time.get_ticks_usec() - started
			if not await _wait_generation(target, generation):
				return
			var build_frame := Time.get_ticks_usec() - started
			var build_post_completion := Time.get_ticks_usec() - ProbeContext.completed_usec
			var build_ui := ProbeContext.ui_usec - build_ui_before
			var build_panels := ProbeContext.panels_built - build_panels_before
			if workload in ["undo_add", "redo_add"]:
				generation = ProbeContext.generation
				_perform(target, "graph_add")
				if not await _wait_generation(target, generation):
					return
				if workload == "redo_add":
					generation = ProbeContext.generation
					_history(target).undo()
					if not await _wait_generation(target, generation):
						return
			var before := _panel_ids(plugin.current)
			var context_id := plugin.current.get_instance_id()
			var graph_id := plugin.current.easing_curve_editor.get_instance_id()
			var built := ProbeContext.panels_built
			var ui := ProbeContext.ui_usec
			var parses := plugin.parses
			generation = ProbeContext.generation
			started = Time.get_ticks_usec()
			if workload != "build":
				_perform(target, workload)
			var request_cpu := Time.get_ticks_usec() - started
			var expected_count := count
			if workload in ["graph_add", "list_add", "redo_add"]:
				expected_count += 1
			elif workload in ["remove", "undo_add"]:
				expected_count -= 1
			if Factory.create(target).get_point_count() != expected_count:
				push_error("%s did not produce expected count %d" % [workload, expected_count])
				failed = true
				return
			if workload != "build" and not await _wait_generation(target, generation):
				return
			var frame_usec := Time.get_ticks_usec() - started
			var post_completion := Time.get_ticks_usec() - ProbeContext.completed_usec
			var after := _panel_ids(plugin.current)
			var retained := 0
			for id in before:
				if after.get(id) == before[id]:
					retained += 1
			if trial >= WARMUPS:
				print("TOPOLOGY_SAMPLE|", JSON.stringify({"backend": "native" if native else "legacy", "count": count, "workload": workload, "trial": trial - WARMUPS, "request_usec": build_cpu if workload == "build" else request_cpu, "to_frame_usec": build_frame if workload == "build" else frame_usec, "ui_usec": build_ui if workload == "build" else ProbeContext.ui_usec - ui, "constructed": build_panels if workload == "build" else ProbeContext.panels_built - built, "retained": retained, "removed_panels": before.size() - retained, "parses": plugin.parses - parses, "context_replaced": plugin.current.get_instance_id() != context_id, "graph_replaced": plugin.current.easing_curve_editor.get_instance_id() != graph_id, "post_completion_to_frame_usec": build_post_completion if workload == "build" else post_completion}))
			# Isolate the engine's move_child CPU after the timed topology sample.
			# Restore order immediately; this excludes model, matching and layout.
			if native and workload == "reorder":
				var list := plugin.current._native_points_content
				var middle := count / 2
				var child := list.get_child(middle)
				var move_started := Time.get_ticks_usec()
				list.move_child(child, middle + 1)
				var move_usec := Time.get_ticks_usec() - move_started
				list.move_child(child, middle)
				if trial >= WARMUPS:
					print("TOPOLOGY_CHILD_MOVEMENT|", JSON.stringify({"backend": "native", "count": count, "workload": "adjacent_move", "usec": move_usec}))
			inspector.edit(null)
			plugin.editor_undo_redo.clear_history()
			await process_frame
		# Separate model mutation uses no Inspector and excludes fixture setup.
		if workload in ["graph_add", "remove", "reorder"]:
			for trial in range(WARMUPS + TRIALS):
				var target := _curve(native, count)
				var backend := Factory.create(target)
				var point: Resource = backend.create_point(Vector2(0.503, 0.6))
				var started := Time.get_ticks_usec()
				match workload:
					"graph_add": backend.add_point(point)
					"remove": backend.remove_point(count / 2)
					"reorder": backend.swap_points(count / 2, count / 2 + 1)
				if trial >= WARMUPS:
					print("TOPOLOGY_MODEL|", JSON.stringify({"backend": "native" if native else "legacy", "count": count, "workload": workload, "usec": Time.get_ticks_usec() - started}))

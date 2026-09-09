@tool
extends VBoxContainer

const DEBUG_POINT_LIST_DRAG := false
const EDITOR_THEME_CACHE = preload(
	"res://addons/easing_curve/scripts/editor/inspector/editor_theme_cache.gd"
)

signal point_swap_requested(from_index: int, to_index: int)

var drop_index := -1
var drop_after := false

var _debug_drag_id := 0
var _pending_swap_from := -1
var _pending_swap_to := -1
var _pending_source: Resource
var _pending_target: Resource
var _quarantined_controls: Dictionary[int, Dictionary] = {}


func _debug_drag_event(event: String, details: String = "") -> void:
	if not DEBUG_POINT_LIST_DRAG:
		return

	print(
		"[EC LIST DRAG] frame=%d usec=%d list=%d event=%s %s"
		% [
			Engine.get_process_frames(),
			Time.get_ticks_usec(),
			get_instance_id(),
			event,
			details,
		]
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_debug_drag_id += 1
		_debug_drag_event(
			"DRAG_BEGIN",
			"drag=%d" % _debug_drag_id,
		)

	elif what == NOTIFICATION_DRAG_END:
		_debug_drag_event(
			"DRAG_END",
			"drag=%d pending=%d->%d"
			% [
				_debug_drag_id,
				_pending_swap_from,
				_pending_swap_to,
			],
		)

		if _pending_swap_from >= 0 and _pending_swap_to >= 0:
			_debug_drag_event(
				"MOUSE_QUARANTINE",
				"drag=%d" % _debug_drag_id,
			)

			if _quarantined_controls.is_empty():
				_disable_mouse_for_subtree(self)

			call_deferred(
				"_arm_pending_point_swap_next_frame",
				_debug_drag_id,
			)


func _exit_tree() -> void:
	_restore_mouse_filters()
	_pending_source = null
	_pending_target = null
	_pending_swap_from = -1
	_pending_swap_to = -1
	_debug_drag_event(
		"TREE_EXIT",
		"drag=%d" % _debug_drag_id,
	)


func _disable_mouse_for_subtree(control: Control) -> void:
	_quarantine_mouse(control)

	for child in control.get_children():
		if child is Control:
			_disable_mouse_for_subtree(child)


func _quarantine_mouse(control: Control) -> void:
	var id := control.get_instance_id()
	if not _quarantined_controls.has(id):
		_quarantined_controls[id] = {"control": weakref(control), "filter": control.mouse_filter}
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _restore_mouse_filters() -> void:
	for entry in _quarantined_controls.values():
		var control := entry.control.get_ref() as Control
		if is_instance_valid(control):
			control.mouse_filter = entry.filter
	_quarantined_controls.clear()


func get_point_panel_index(panel: Control) -> int:
	var index := 0
	for child in get_children():
		if child is PanelContainer:
			if child == panel:
				return index
			index += 1
	return -1


func enable_drop_forwarding(control: Control) -> void:
	# A topology change during a pending drop may introduce new Controls.
	if not _quarantined_controls.is_empty():
		_quarantine_mouse(control)
	control.set_drag_forwarding(
		Callable(),
		_forward_can_drop_data,
		_forward_drop_data
	)

	for child in control.get_children():
		if child is Control:
			enable_drop_forwarding(child)


func _forward_can_drop_data(_position: Vector2, data) -> bool:
	return _can_drop_data(get_local_mouse_position(), data)


func _forward_drop_data(_position: Vector2, data) -> void:
	_drop_data(get_local_mouse_position(), data)


func _get_drop_target_index(mouse_y: float, point_panels: Array[Control]) -> int:
	for i in point_panels.size():
		var panel := point_panels[i]
		var top := panel.position.y
		var bottom := panel.position.y + panel.size.y

		if mouse_y >= top and mouse_y <= bottom:
			return i

		if i < point_panels.size() - 1:
			var next_panel := point_panels[i + 1]
			var gap_midpoint := (bottom + next_panel.position.y) * 0.5

			if mouse_y > bottom and mouse_y < gap_midpoint:
				return i

			if mouse_y >= gap_midpoint and mouse_y < next_panel.position.y:
				return i + 1

	return -1


func _can_drop_data(position: Vector2, data) -> bool:
	if not data is Dictionary or not data.has("index") or not data.has("point"):
		return false

	var source_panel = data["point"]
	if not is_instance_valid(source_panel) or source_panel.get_parent() != self:
		return false

	var point_panels: Array[Control] = []

	for child in get_children():
		if child is PanelContainer:
			point_panels.append(child)

	if point_panels.is_empty():
		return false

	var from_index: int = point_panels.find(source_panel)
	var to_index := _get_drop_target_index(position.y, point_panels)

	if to_index < 0:
		return false

	var target := point_panels[to_index]
	var mouse_y := position.y
	var midpoint := target.position.y + target.size.y * 0.5
	var dead_zone := 3.0

	var after: bool

	if drop_index != to_index:
		after = mouse_y >= midpoint
	elif mouse_y < midpoint - dead_zone:
		after = false
	elif mouse_y > midpoint + dead_zone:
		after = true
	else:
		after = drop_after

	set_drop_index(to_index, after)
	return true


func _drop_data(position: Vector2, data) -> void:
	if not data is Dictionary or not data.has("point") or not data.has("index"):
		return
	var source_panel = data["point"]
	if not is_instance_valid(source_panel) or source_panel.get_parent() != self:
		return
	var point_panels: Array[Control] = []

	for child in get_children():
		if child is PanelContainer:
			point_panels.append(child)

	var from_index: int = point_panels.find(source_panel)
	var to_index := _get_drop_target_index(position.y, point_panels)

	_debug_drag_event(
		"DROP_DATA",
		"drag=%d from=%d to=%d"
		% [_debug_drag_id, from_index, to_index],
	)

	clear_drop_index()

	if from_index >= 0 and to_index >= 0 and from_index != to_index:
		_pending_swap_from = from_index
		_pending_swap_to = to_index
		_pending_source = source_panel.get_meta(&"point_resource", null)
		_pending_target = point_panels[to_index].get_meta(&"point_resource", null)

		_debug_drag_event(
			"PENDING_SWAP",
			"drag=%d from=%d to=%d"
			% [_debug_drag_id, from_index, to_index],
		)


func _arm_pending_point_swap_next_frame(drag_id: int) -> void:
	if not is_inside_tree() or _pending_swap_from < 0 or _pending_swap_to < 0:
		_restore_mouse_filters()
		return

	_debug_drag_event(
		"ARM_NEXT_FRAME",
		"drag=%d pending=%d->%d"
		% [
			drag_id,
			_pending_swap_from,
			_pending_swap_to,
		],
	)

	get_tree().process_frame.connect(
		_emit_pending_point_swap.bind(drag_id),
		CONNECT_ONE_SHOT,
	)


func _emit_pending_point_swap(drag_id: int) -> void:
	if not is_inside_tree() or drag_id != _debug_drag_id:
		_restore_mouse_filters()
		_pending_swap_from = -1
		_pending_swap_to = -1
		_pending_source = null
		_pending_target = null
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var hover_is_inside_list := (
		hovered == self
		or (
			hovered != null
			and is_ancestor_of(hovered)
		)
	)

	if hover_is_inside_list:
		_debug_drag_event(
			"WAIT_HOVER_CLEAR",
			"drag=%d hovered=%d"
			% [drag_id, hovered.get_instance_id()],
		)

		get_tree().process_frame.connect(
			_emit_pending_point_swap.bind(drag_id),
			CONNECT_ONE_SHOT,
		)
		return

	_debug_drag_event(
		"HOVER_CLEAR",
		"drag=%d hovered=%d"
		% [
			drag_id,
			hovered.get_instance_id() if hovered != null else 0,
		],
	)

	var from_index := _pending_swap_from
	var to_index := _pending_swap_to
	if _pending_source != null or _pending_target != null:
		from_index = -1
		to_index = -1
		var index := 0
		for child in get_children():
			if child is PanelContainer:
				var point: Resource = child.get_meta(&"point_resource", null)
				if point == _pending_source:
					from_index = index
				if point == _pending_target:
					to_index = index
				index += 1

	_pending_swap_from = -1
	_pending_swap_to = -1
	_pending_source = null
	_pending_target = null
	# Restore before emission: listeners may synchronously dispose this list.
	_restore_mouse_filters()

	if from_index < 0 or to_index < 0:
		return

	_debug_drag_event(
		"EMIT_SWAP",
		"drag=%d from=%d to=%d"
		% [drag_id, from_index, to_index],
	)

	point_swap_requested.emit(from_index, to_index)


func set_drop_index(to_index: int, after: bool) -> void:
	if drop_index == to_index and drop_after == after:
		return
	drop_index = to_index
	drop_after = after
	queue_redraw()


func clear_drop_index() -> void:
	if drop_index == -1:
		return
	drop_index = -1
	drop_after = false
	queue_redraw()

func _draw() -> void:
	if drop_index < 0:
		return

	var point_panels: Array[Control] = []

	for child in get_children():
		if child is PanelContainer:
			point_panels.append(child)

	if drop_index >= point_panels.size():
		return

	var target := point_panels[drop_index]
	var y := target.position.y + target.size.y if drop_after else target.position.y

	var color := EDITOR_THEME_CACHE.get_color(
		&"accent_color",
		&"Editor",
		Color(0.3, 0.6, 1.0),
	)

	var line_width := 4.0

	if drop_after:
		y += line_width * 0.5
	else:
		y -= line_width * 0.5

	draw_line(
		Vector2(0.0, y),
		Vector2(size.x, y),
		color,
		line_width
	)

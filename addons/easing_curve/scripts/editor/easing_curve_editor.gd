@tool
class_name EasingCurveEditor
extends Control
## Easing Curve Editor
##
## Graph editor for interactive EasingCurve point and control-handle editing.

const SELECTION_TOOLBAR_HEIGHT := 32.0
const EDITOR_THEME_CACHE = preload(
	"res://addons/easing_curve/scripts/editor/inspector/editor_theme_cache.gd"
)
const BEZIER_SOLVER = preload(
	"res://addons/easing_curve/scripts/runtime/bezier_solver.gd"
)
const BackendFactory := preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_editor_backend_factory.gd"
)

var use_pending_add := true
# True: hide the point-selection toolbar in Function mode and reclaim its height.
# False: keep the toolbar row visible, with point-only controls inactive.
var hide_selection_toolbar_for_functions := true
# True: reorder through the Inspector. False: change graph selection only.
var point_move_buttons_reorder_points := false

static var _selected_index_by_curve: Dictionary[int, int] = {}
static var _right_delete_drag_state_by_curve: Dictionary[int, Dictionary] = {}

signal point_changed
signal point_property_change_requested(index: int, property_name: StringName, value: Variant, changing: bool)
signal point_add_requested(point: EasingCurvePoint)
signal point_remove_requested(point: EasingCurvePoint)
signal point_move_up_requested(index: int)
signal point_move_down_requested(index: int)
signal point_edit_finished(point_order: Array[EasingCurvePoint])
signal point_selection_changed(point: Resource)
signal slider_changed
signal zoom_changed
signal pan_changed

enum GrabMode { NONE, ADD, MOVE }
enum ControlIndex { NONE = -1, LEFT = 0, RIGHT = 1 }

const ZOOM_SLIDER_CONTAINER = preload(
	"res://addons/easing_curve/scripts/editor/widgets/zoom_slider_container.tscn"
)
const ZOOM_MIN := EasingCurve.ZOOM_MIN
const ZOOM_MAX := EasingCurve.ZOOM_MAX
const ZOOM_FACTOR := EasingCurve.ZOOM_FACTOR
const ZOOM_STEPS := EasingCurve.ZOOM_STEPS
const DEFAULT_SLIDER_VALUE := EasingCurve.DEFAULT_SLIDER_VALUE
const ASPECT_RATIO: float = 6. / 13.
const MIN_GRAPH_HEIGHT := 135.0
const MIN_X: float = 0.0
const MAX_X: float = 1.0
const MIN_Y: float = 0.0
const MAX_Y: float = 1.0
const BASE_POINT_RADIUS = 4
const BASE_HOVER_RADIUS = 10
const BASE_CONTROL_RADIUS = 3
const BASE_CONTROL_HOVER_RADIUS = 8
const BASE_CONTROL_LENGTH = 36
const LINE_COLOR = Color(1, 1, 1)
const CONTROL_LINE_COLOR = Color(1, 1, 1, 0.4)
const BEZIER_DRAW_TOLERANCE_PIXELS := 0.75
const BEZIER_DRAW_MAX_DEPTH := 12
const AUTOFIT_PADDING_RATIO := 0.10
const FUNCTION_DRAW_STEPS := 120

var editor_undo_redo: Object
var committed_change_publisher: Callable
var pan_offset := Vector2.ZERO
var is_panning := false
var last_mouse_pos := Vector2.ZERO
var slider_value := 0.0:
	set = set_slider_value
var point_radius: int = BASE_POINT_RADIUS
var hover_radius: int = BASE_HOVER_RADIUS
var control_radius: int = BASE_CONTROL_RADIUS
var control_hover_radius: int = BASE_CONTROL_HOVER_RADIUS
var control_length: int = BASE_CONTROL_LENGTH

var selected_index: int = -1:
	set(value):
		selected_index = value
		var resource := get_curve()
		if resource != null:
			_selected_index_by_curve[resource.get_instance_id()] = value
		_update_point_toolbar()
		queue_redraw()
		point_selection_changed.emit(_selected_point_resource())

var hovered_index: int = -1
var selected_control_index: ControlIndex = ControlIndex.NONE
var hovered_control_index: ControlIndex = ControlIndex.NONE

var dragging_point: int = -1
var dragging_control: ControlIndex = ControlIndex.NONE
var pending_add_point: Resource
var position_x_order_preview_point: Resource
var is_right_delete_dragging := false
var _right_delete_requires_exit := false
var _right_delete_blocked_position := Vector2.ZERO
var _axis_drag_origin_view := Vector2.ZERO
var _axis_drag_origin_world := Vector2.ZERO
var _axis_drag_shift_blocked := false

var grabbing: GrabMode = GrabMode.NONE
var initial_grab_pos: Vector2
var initial_grab_index: int
var initial_grab_left_control: Vector2
var initial_grab_right_control: Vector2
var snap_enabled: bool = false
var snap_count: int = 10
var _zoom_x: float = 1.0 # horizontal zoom
var _zoom_y: float = 1.0 # vertical zoom
var _zoom_step := 0
var _curve: EasingCurve
var _backend: RefCounted
var _slider: EasingCurveZoomSliderContainer:
	set = set_slider_container
var _world_to_view: Transform2D
var _editor_scale: float = 1.0

var _point_toolbar_panel: VBoxContainer
var _point_toolbar: GridContainer
var _point_label: Label
var _point_reorder_buttons: HBoxContainer
var _point_move_left_button: Button
var _point_move_right_button: Button
var _point_toolbar_controls: HBoxContainer
var _point_handle_mode: OptionButton
var _point_left_state_label: Label
var _point_left_state: OptionButton
var _point_right_state_label: Label
var _point_right_state: OptionButton
var _point_reset_button: Button
var _updating_point_toolbar := false
var _graph_render_suppressed := false
var _backend_point_edit_active := false
var _backend_point_edit_before: Variant
var _backend_point_edit_action_name := "Edit Easing Curve Point"
var _backend_point_edit_selected_before: Resource


func _ready() -> void:
	custom_minimum_size = Vector2.ZERO
	focus_mode = Control.FOCUS_ALL
	clip_contents = true

	if Engine.is_editor_hint():
		_editor_scale = EditorInterface.get_editor_scale()
	update_minimum_size()

	if _backend == null:
		set_curve(EasingCurve.new())

	_create_point_toolbar()
	_update_point_toolbar()


# =========================
# GUI INPUT (DRAGGING)
# =========================
func _gui_input(event: InputEvent) -> void:
	if _backend == null:
		return

	if event is InputEventMouseButton:
		if _handle_mouse_button_prepass(event):
			return

	if event is InputEventMouseMotion:
		_handle_pan_motion(event)
		_handle_mouse_motion(event)
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event)


func _handle_mouse_button_prepass(event: InputEventMouseButton) -> bool:
	# Always end an RMB delete gesture before any later button branch can return.
	if not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_set_right_delete_dragging(false)
		return true

	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			is_panning = true
			last_mouse_pos = event.position
			get_viewport().set_input_as_handled() # stop editor from stealing input
		else:
			is_panning = false
			get_viewport().set_input_as_handled()
	return false


func _handle_pan_motion(event: InputEventMouseMotion) -> void:
	if not is_panning:
		return
	var delta = event.position - last_mouse_pos
	pan_offset += delta
	last_mouse_pos = event.position
	queue_redraw()
	get_viewport().set_input_as_handled()
	pan_changed.emit(pan_offset)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _is_point_graph():
		return
	if not _supports_point_geometry():
		_update_hover_from_mouse(event.position)
		return

	if is_right_delete_dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_try_remove_point_at(event.position)
			return
		_set_right_delete_dragging(false)

	if pending_add_point != null:
		_handle_pending_add_motion(event)
		return

	if dragging_point != -1:
		_handle_drag_motion(event)

	if dragging_point == -1:
		_update_hover_from_mouse(event.position)


func _handle_pending_add_motion(event: InputEventMouseMotion) -> void:
	var world_pos := get_world_pos(event.position)
	if not world_pos.is_finite():
		return
	world_pos = _backend.display_to_curve_position(world_pos)
	var value_range := _value_range()
	var clamped_pos := world_pos.clamp(
		Vector2(0, value_range.x),
		Vector2(1.0, value_range.y),
	)
	pending_add_point.set(&"position", clamped_pos)
	queue_redraw()


func _begin_axis_drag(
	event: InputEventMouseButton,
	point: Resource,
	control: ControlIndex,
) -> void:
	_axis_drag_origin_view = event.position
	match control:
		ControlIndex.LEFT:
			_axis_drag_origin_world = point.get(&"left_control_point")
		ControlIndex.RIGHT:
			_axis_drag_origin_world = point.get(&"right_control_point")
		ControlIndex.NONE:
			_axis_drag_origin_world = point.get(&"position")
	_axis_drag_shift_blocked = event.shift_pressed


func _clear_axis_drag() -> void:
	_axis_drag_origin_view = Vector2.ZERO
	_axis_drag_origin_world = Vector2.ZERO
	_axis_drag_shift_blocked = false


func _apply_axis_drag_constraint(
	event: InputEventMouseMotion,
	world_pos: Vector2,
) -> Vector2:
	if _axis_drag_shift_blocked:
		if not event.shift_pressed:
			_axis_drag_shift_blocked = false
		return world_pos
	if not event.shift_pressed:
		return world_pos

	var view_delta := event.position - _axis_drag_origin_view
	if absf(view_delta.x) > absf(view_delta.y):
		world_pos.y = _axis_drag_origin_world.y
	else:
		world_pos.x = _axis_drag_origin_world.x
	return world_pos


func _handle_drag_motion(event: InputEventMouseMotion) -> void:
	var p := _point(dragging_point)
	if p == null:
		return
	if dragging_control != ControlIndex.NONE:
		_backend.prepare_point_control_drag(dragging_point, get_world_to_view_scale())
	var world_pos = get_world_pos(event.position)
	if not world_pos.is_finite():
		return
	world_pos = _backend.display_to_curve_position(world_pos)
	if dragging_control == ControlIndex.NONE and _backend.is_point_property_locked(dragging_point, &"position"):
		return
	if dragging_control == ControlIndex.LEFT and _backend.is_point_property_locked(dragging_point, &"left_control_point"):
		return
	if dragging_control == ControlIndex.RIGHT and _backend.is_point_property_locked(dragging_point, &"right_control_point"):
		return

	world_pos = _apply_axis_drag_constraint(event, world_pos)

	match dragging_control:
		ControlIndex.LEFT:
			if dragging_point != 0:
				_request_point_property_change(dragging_point, &"left_control_point", world_pos, true)
		ControlIndex.RIGHT:
			if dragging_point != _point_count() - 1:
				_request_point_property_change(dragging_point, &"right_control_point", world_pos, true)
		ControlIndex.NONE:
			var value_range := _value_range()
			var clamped_pos = world_pos.clamp(Vector2(0, value_range.x), Vector2(1.0, value_range.y))
			var point_position := p.get(&"position") as Vector2
			var delta = clamped_pos - point_position
			var left_control := p.get(&"left_control_point") as Vector2
			var right_control := p.get(&"right_control_point") as Vector2
			_request_point_property_change(dragging_point, &"position", clamped_pos, true)
			if not _backend.is_point_property_locked(dragging_point, &"left_control_point"):
				_request_point_property_change(dragging_point, &"left_control_point", left_control + delta, true)
			if not _backend.is_point_property_locked(dragging_point, &"right_control_point"):
				_request_point_property_change(dragging_point, &"right_control_point", right_control + delta, true)

	point_changed.emit(dragging_point, p)
	queue_redraw()


func _update_hover_from_mouse(position: Vector2) -> void:
	var control = get_control_at(position)
	if control[0] != -1:
		hovered_index = control[0]
		hovered_control_index = control[1]
	else:
		hovered_control_index = ControlIndex.NONE
		hovered_index = get_point_at(position)
	queue_redraw()
	if hovered_control_index != ControlIndex.NONE:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	elif hovered_index != -1:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if _handle_wheel(event):
		return
	if not _is_point_graph():
		return
	if not _supports_point_geometry():
		_handle_read_only_point_button(event)
		return
	if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_pressed(event)
	elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_pressed(event)
	elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_released()


func _handle_read_only_point_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		selected_index = get_point_at(event.position)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		selected_index = -1
	selected_control_index = ControlIndex.NONE
	queue_redraw()


func _handle_wheel(event: InputEventMouseButton) -> bool:
	if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at_view_pos(1, event.position)
		accept_event()
		return true
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at_view_pos(-1, event.position)
		accept_event()
		return true
	return false


func _handle_left_pressed(event: InputEventMouseButton) -> void:
	var control = get_control_at(event.position)
	var point_idx = get_point_at(event.position)
	if (
		control[0] != -1
		and int(_point(control[0]).get(&"handle_mode"))
		== EasingCurvePoint.HandleMode.LINEAR
	):
		point_idx = control[0]
		control = [-1, ControlIndex.NONE]
	if control[0] != -1:
		var p := _point(control[0])
		var can_drag_control := false
		match control[1]:
			ControlIndex.LEFT:
				can_drag_control = not _backend.is_point_property_locked(
					control[0],
					&"left_control_point",
				)
			ControlIndex.RIGHT:
				can_drag_control = not _backend.is_point_property_locked(
					control[0],
					&"right_control_point",
				)
		selected_index = control[0]
		if can_drag_control:
			dragging_point = control[0]
			dragging_control = control[1]
			_begin_axis_drag(event, p, dragging_control)
		elif (
			point_idx != -1
			and not _backend.is_point_property_locked(point_idx, &"position")
		):
			dragging_point = point_idx
			dragging_control = ControlIndex.NONE
			_begin_axis_drag(event, _point(point_idx), dragging_control)
		queue_redraw()
		return
	if point_idx != -1:
		var p := _point(point_idx)
		if not _backend.is_point_property_locked(point_idx, &"position"):
			dragging_point = point_idx
			dragging_control = ControlIndex.NONE
			_begin_axis_drag(event, p, dragging_control)
		selected_index = point_idx
		queue_redraw()
		return
	if not _supports_point_topology():
		selected_index = -1
		selected_control_index = ControlIndex.NONE
		queue_redraw()
		return

	var world_pos := get_world_pos(event.position)
	if not world_pos.is_finite():
		return
	world_pos = _backend.display_to_curve_position(world_pos)
	var value_range := _value_range()
	var clamped_pos := world_pos.clamp(Vector2(0, value_range.x), Vector2(1.0, value_range.y))
	if use_pending_add:
		pending_add_point = _backend.create_point(clamped_pos)
		if pending_add_point == null:
			return
		queue_redraw()
		accept_event()
		return
	var new_point: Resource = _backend.create_point(clamped_pos)
	if new_point == null:
		return
	selected_index = _request_point_add(new_point)
	if selected_index != -1:
		dragging_point = selected_index
		dragging_control = ControlIndex.NONE
	queue_redraw()


func _handle_right_pressed(event: InputEventMouseButton) -> void:
	if pending_add_point != null:
		_cancel_pending_add()
		accept_event()
		return
	if not _supports_point_topology():
		selected_index = -1
		selected_control_index = ControlIndex.NONE
		queue_redraw()
		return
	_right_delete_requires_exit = false
	_set_right_delete_dragging(true)
	if _try_remove_point_at(event.position):
		return
	selected_index = -1
	selected_control_index = ControlIndex.NONE
	queue_redraw()


func _handle_left_released() -> void:
	if pending_add_point != null:
		var point := pending_add_point
		pending_add_point = null
		selected_index = _request_point_add(point)
		dragging_point = -1
		dragging_control = ControlIndex.NONE
		_clear_axis_drag()
		queue_redraw()
		return
	var finish_point_edit := dragging_point != -1
	var point_order: Array[Resource] = []
	var dragged_point: Resource
	if finish_point_edit and dragging_control == ControlIndex.NONE:
		dragged_point = _point(dragging_point)
		point_order = _get_ordered_points()
		if _curve == null:
			_backend.apply_point_order(point_order)
		selected_index = _backend.find_point(dragged_point)
	dragging_point = -1
	dragging_control = ControlIndex.NONE
	_clear_axis_drag()
	if finish_point_edit:
		if _curve != null and point_edit_finished.has_connections():
			var legacy_order: Array[EasingCurvePoint] = []
			legacy_order.assign(point_order)
			point_edit_finished.emit(legacy_order)
		else:
			_finish_backend_point_edit()
	queue_redraw()


func _request_point_property_change(index: int, property_name: StringName, value: Variant, changing: bool = false) -> void:
	if point_property_change_requested.has_connections():
		point_property_change_requested.emit(index, property_name, value, changing)
		return
	if _backend == null:
		return
	if changing and not _backend_point_edit_active:
		_backend_point_edit_before = _duplicate_snapshot(_backend.capture_snapshot())
		_backend_point_edit_action_name = _point_edit_action_name(property_name)
		_backend_point_edit_selected_before = _selected_point_resource()
		_backend_point_edit_active = true
		_backend.begin_point_edit()

	var before: Variant
	var selected_before: Resource
	if not changing and not _backend_point_edit_active:
		before = _duplicate_snapshot(_backend.capture_snapshot())
		selected_before = _selected_point_resource()
	if not _backend.apply_point_property(index, property_name, value, changing):
		return
	if property_name == &"position":
		position_x_order_preview_point = _point(index) if changing else null
	queue_redraw()
	if changing:
		return
	if _backend_point_edit_active:
		if property_name == &"position":
			var active_point := _point(index)
			_backend.apply_point_order(_backend.get_ordered_points(active_point))
			selected_index = _backend.find_point(active_point)
		_finish_backend_point_edit()
		return
	if property_name == &"position":
		var active_point := _point(index)
		_backend.apply_point_order(_backend.get_ordered_points(active_point))
		selected_index = _backend.find_point(active_point)
	var after: Variant = _duplicate_snapshot(_backend.capture_snapshot())
	if before == after:
		return
	_commit_backend_snapshot_action(
		_point_edit_action_name(property_name),
		before,
		after,
		selected_before,
		_selected_point_resource(),
	)


func _finish_backend_point_edit() -> void:
	if not _backend_point_edit_active:
		return
	var before := _backend_point_edit_before
	var action_name := _backend_point_edit_action_name
	_backend_point_edit_active = false
	_backend_point_edit_before = null
	_backend_point_edit_action_name = "Edit Easing Curve Point"
	var selected_before := _backend_point_edit_selected_before
	_backend_point_edit_selected_before = null
	_backend.finish_point_edit()
	var after: Variant = _duplicate_snapshot(_backend.capture_snapshot())
	if before == after:
		return
	_commit_backend_snapshot_action(
		action_name,
		before,
		after,
		selected_before,
		_selected_point_resource(),
	)


func _commit_backend_snapshot_action(
	action_name: String,
	before: Variant,
	after: Variant,
	selected_before: Resource = null,
	selected_after: Resource = null,
) -> void:
	if editor_undo_redo == null:
		_publish_backend_change()
		return
	var resource := get_curve()
	var native_live_edit: bool = (
		editor_undo_redo is EditorUndoRedoManager
		and get_backend_id() == &"native"
		and resource != null
		and resource.has_method(&"_apply_live_editor_snapshot")
		and before is Dictionary
		and after is Dictionary
		and before.has(&"live_state")
		and after.has(&"live_state")
	)
	var selected_before_id := selected_before.get_instance_id() if selected_before != null else 0
	var selected_after_id := selected_after.get_instance_id() if selected_after != null else 0
	if native_live_edit:
		editor_undo_redo.create_action(
			action_name,
			UndoRedo.MERGE_DISABLE,
			resource,
		)
	else:
		editor_undo_redo.create_action(action_name)
	if editor_undo_redo is EditorUndoRedoManager:
		editor_undo_redo.add_do_method(self, &"_apply_backend_snapshot_and_selection", after, selected_after_id)
		editor_undo_redo.add_do_method(self, &"_publish_backend_change")
		editor_undo_redo.add_undo_method(self, &"_apply_backend_snapshot_and_selection", before, selected_before_id)
		editor_undo_redo.add_undo_method(self, &"_publish_backend_change")
		if native_live_edit:
			editor_undo_redo.add_do_method(
				resource,
				&"_apply_live_editor_snapshot",
				(after[&"live_state"] as Dictionary).duplicate(true),
			)
			editor_undo_redo.add_undo_method(
				resource,
				&"_apply_live_editor_snapshot",
				(before[&"live_state"] as Dictionary).duplicate(true),
			)
	else:
		editor_undo_redo.add_do_method(
			Callable(self, &"_apply_backend_snapshot_and_selection").bind(after, selected_after_id),
		)
		editor_undo_redo.add_undo_method(
			Callable(self, &"_apply_backend_snapshot_and_selection").bind(before, selected_before_id),
		)
		editor_undo_redo.add_do_method(Callable(self, &"_publish_backend_change"))
		editor_undo_redo.add_undo_method(Callable(self, &"_publish_backend_change"))
	editor_undo_redo.commit_action(native_live_edit)
	if not native_live_edit:
		_publish_backend_change()


func _publish_backend_change() -> void:
	if committed_change_publisher.is_valid():
		committed_change_publisher.call()


func edit_point_property(
	index: int,
	property_name: StringName,
	value: Variant,
	changing := false,
) -> void:
	_request_point_property_change(index, property_name, value, changing)


func finish_point_list_edit(point: Resource, property_name: StringName) -> void:
	if not _backend_point_edit_active or point == null:
		return
	if property_name == &"position":
		_backend.apply_point_order(_backend.get_ordered_points(point))
		selected_index = _backend.find_point(point)
		position_x_order_preview_point = null
	_finish_backend_point_edit()
	queue_redraw()


func add_point_from_list() -> Resource:
	if _backend == null:
		return null
	var points := _points()
	var position := Vector2.ZERO
	if points.is_empty():
		position = Vector2.ZERO
	elif not _has_endpoint_at(0.0):
		position = Vector2(0.0, 0.0)
	elif not _has_endpoint_at(1.0):
		position = Vector2(1.0, 1.0)
	else:
		var largest_gap := -1.0
		for index in range(points.size() - 1):
			var left: Vector2 = points[index].get(&"position")
			var right: Vector2 = points[index + 1].get(&"position")
			var gap := right.x - left.x
			if gap > largest_gap:
				largest_gap = gap
				position.x = (left.x + right.x) * 0.5
		position.y = _backend.sample(position.x)
	var point: Resource = _backend.create_point(position)
	if point == null:
		return null
	_request_point_add(point)
	selected_index = _backend.find_point(point)
	return point


func remove_point_from_list(point: Resource) -> void:
	_request_point_remove(point)


func move_point_from_list(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= _point_count() or to_index < 0 or to_index >= _point_count():
		return
	selected_index = from_index
	_reorder_selected_point(to_index)


func select_point_resource(point: Resource) -> void:
	selected_index = _backend.find_point(point) if _backend != null else -1


func get_selected_point_resource() -> Resource:
	return _selected_point_resource()


func reset_native_preset() -> void:
	var resource := get_curve()
	if _backend == null or resource == null or not resource.has_method(&"reset_selected_preset"):
		return
	var before := _duplicate_snapshot(_backend.capture_snapshot())
	var selected_before := _selected_point_resource()
	resource.call(&"reset_selected_preset")
	var after := _duplicate_snapshot(_backend.capture_snapshot())
	if before == after:
		return
	_commit_backend_snapshot_action(
		"Reset Easing Curve Preset",
		before,
		after,
		selected_before,
		null,
	)


func _has_endpoint_at(x: float) -> bool:
	for point in _points():
		var position: Vector2 = point.get(&"position")
		if is_equal_approx(position.x, x):
			return true
	return false


func _apply_backend_snapshot_and_selection(snapshot: Variant, selected_point_id: int) -> void:
	if _backend == null or not _backend.apply_snapshot(snapshot):
		return
	selected_index = -1
	if selected_point_id != 0:
		for index in range(_point_count()):
			var point := _point(index)
			if point != null and point.get_instance_id() == selected_point_id:
				selected_index = index
				break
	if selected_index == -1:
		selected_control_index = ControlIndex.NONE


func _duplicate_snapshot(snapshot: Variant) -> Variant:
	if snapshot is Dictionary or snapshot is Array:
		return snapshot.duplicate(true)
	return snapshot


func _point_edit_action_name(property_name: StringName) -> String:
	match property_name:
		&"position":
			return "Move Easing Curve Point"
		&"left_control_point", &"right_control_point":
			return "Move Easing Curve Handle"
		&"left_control_state", &"right_control_state":
			return "Change Easing Curve Handle State"
		&"toolbar_options_reset":
			return "Reset Easing Curve Point Options"
		&"handle_mode":
			return "Change Easing Curve Handle Mode"
	return "Edit Easing Curve Point"


func _request_point_add(point: Resource) -> int:
	if _curve != null and point is EasingCurvePoint and point_add_requested.has_connections():
		point_add_requested.emit(point)
		return _backend.find_point(point)
	var before := _duplicate_snapshot(_backend.capture_snapshot())
	var selected_before := _selected_point_resource()
	var result: int = _backend.add_point(point)
	if result < 0:
		return -1
	var after := _duplicate_snapshot(_backend.capture_snapshot())
	_commit_backend_snapshot_action(
		"Add Easing Curve Point",
		before,
		after,
		selected_before,
		point,
	)
	return result


func _request_point_remove(point: Resource) -> bool:
	if _curve != null and point is EasingCurvePoint and point_remove_requested.has_connections():
		point_remove_requested.emit(point)
		return true
	var index: int = _backend.find_point(point)
	if index < 0:
		return false
	var before := _duplicate_snapshot(_backend.capture_snapshot())
	var selected_before := _selected_point_resource()
	var selected_after := selected_before if selected_before != point else null
	if not _backend.remove_point(index):
		return false
	selected_index = _backend.find_point(selected_after) if selected_after != null else -1
	var after := _duplicate_snapshot(_backend.capture_snapshot())
	_commit_backend_snapshot_action(
		"Remove Easing Curve Point",
		before,
		after,
		selected_before,
		selected_after,
	)
	return true


func _request_point_move_up() -> void:
	if not _can_use_point_move_buttons():
		return
	if point_move_buttons_reorder_points:
		if _curve != null:
			point_move_up_requested.emit(selected_index)
		else:
			_reorder_selected_point(_get_display_neighbor_index(-1))
	else:
		selected_index = _get_display_neighbor_index(-1)


func _request_point_move_down() -> void:
	if not _can_use_point_move_buttons():
		return
	if point_move_buttons_reorder_points:
		if _curve != null:
			point_move_down_requested.emit(selected_index)
		else:
			_reorder_selected_point(_get_display_neighbor_index(1))
	else:
		selected_index = _get_display_neighbor_index(1)


func _can_use_point_move_buttons() -> bool:
	return (
		_backend != null
		and _is_point_graph()
		and selected_index >= 0
		and selected_index < _point_count()
		and _point_count() >= 2
	)


func _get_display_neighbor_index(offset: int) -> int:
	var selected_point := _selected_point_resource()
	var display_points := _get_display_points()
	var display_index := display_points.find(selected_point)
	if display_index == -1:
		return selected_index
	var neighbor: Resource = display_points[
		wrapi(display_index + offset, 0, display_points.size())
	]
	return _backend.find_point(neighbor)


func _reorder_selected_point(to_index: int) -> void:
	var selected_point := _selected_point_resource()
	if selected_point == null or to_index < 0 or to_index >= _point_count():
		return
	var before := _duplicate_snapshot(_backend.capture_snapshot())
	if not _backend.swap_points(selected_index, to_index):
		return
	selected_index = _backend.find_point(selected_point)
	var after := _duplicate_snapshot(_backend.capture_snapshot())
	_commit_backend_snapshot_action(
		"Reorder Easing Curve Point",
		before,
		after,
		selected_point,
		selected_point,
	)


func _cancel_pending_add() -> void:
	pending_add_point = null
	_set_right_delete_dragging(false)
	queue_redraw()


func _try_remove_point_at(view_pos: Vector2) -> bool:
	if _right_delete_requires_exit:
		if view_pos.distance_squared_to(_right_delete_blocked_position) < point_radius * point_radius:
			return false
		_right_delete_requires_exit = false

	var point_idx := get_point_at(view_pos)
	if point_idx == -1:
		return false

	var point := _point(point_idx)
	_right_delete_requires_exit = true
	_right_delete_blocked_position = get_view_pos(
		_backend.curve_to_display_position(point.get(&"position") as Vector2)
	)
	_store_right_delete_drag_state()

	_request_point_remove(point)
	queue_redraw()
	return true


func _set_right_delete_dragging(enabled: bool) -> void:
	is_right_delete_dragging = enabled
	if not enabled:
		_right_delete_requires_exit = false
		_right_delete_blocked_position = Vector2.ZERO
		var resource := get_curve()
		if resource != null:
			_right_delete_drag_state_by_curve.erase(resource.get_instance_id())
		return
	_store_right_delete_drag_state()


func _store_right_delete_drag_state() -> void:
	var resource := get_curve()
	if resource == null or not is_right_delete_dragging:
		return
	_right_delete_drag_state_by_curve[resource.get_instance_id()] = {
		"requires_exit": _right_delete_requires_exit,
		"blocked_position": _right_delete_blocked_position,
	}


func _restore_right_delete_drag_state() -> void:
	var resource := get_curve()
	if resource == null:
		return

	var curve_id := resource.get_instance_id()
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_right_delete_drag_state_by_curve.erase(curve_id)
		return

	var state: Dictionary = _right_delete_drag_state_by_curve.get(curve_id, {})
	if state.is_empty():
		return

	is_right_delete_dragging = true
	_right_delete_requires_exit = bool(state.get("requires_exit", false))
	_right_delete_blocked_position = state.get("blocked_position", Vector2.ZERO)


# =========================
# DRAWING POINTS & CONTROLS
# =========================
func _draw():
	if _backend == null or _graph_render_suppressed:
		return

	update_view_transform()
	var value_range := _value_range()

	# --- Draw Grid ---
	var grid_color_primary: Color = Color(0.3, 0.3, 0.3, 0.8)
	var grid_color: Color = Color(0.2, 0.2, 0.2, 0.3)

	var grid_steps: Vector2 = Vector2i(4, 2)
	var step_size: Vector2 = Vector2(1, value_range.y - value_range.x) / grid_steps

	# Primary borders
	draw_line(
		get_view_pos(Vector2(MIN_X, value_range.x)),
		get_view_pos(Vector2(MAX_X, value_range.x)),
		grid_color_primary,
	)
	draw_line(
		get_view_pos(Vector2(MAX_X, value_range.y)),
		get_view_pos(Vector2(MIN_X, value_range.y)),
		grid_color_primary,
	)
	draw_line(
		get_view_pos(Vector2(MIN_X, value_range.x)),
		get_view_pos(Vector2(MIN_X, value_range.y)),
		grid_color_primary,
	)
	draw_line(
		get_view_pos(Vector2(MAX_X, value_range.x)),
		get_view_pos(Vector2(MAX_X, value_range.y)),
		grid_color_primary,
	)

	# Internal grid
	for i in range(1, grid_steps.x):
		var x = MIN_X + i * step_size.x
		draw_line(
			get_view_pos(Vector2(x, value_range.x)),
			get_view_pos(Vector2(x, value_range.y)),
			grid_color,
		)
	for i in range(1, grid_steps.y):
		var y = value_range.x + i * step_size.y
		draw_line(
			get_view_pos(Vector2(MIN_X, y)),
			get_view_pos(Vector2(MAX_X, y)),
			grid_color,
		)

	# --- Draw function or point-backed curve ---
	if not _is_point_graph():
		_draw_sampled_curve()
		return

	var display_points: Array[Resource] = _get_display_points()
	var selected_point := _point(selected_index) if selected_index >= 0 else null
	var hovered_point := _point(hovered_index) if hovered_index >= 0 else null

	# --- Draw curve using the same X-to-Y evaluation as EasingCurve.sample() ---
	_draw_bezier_curve(display_points)

	# --- Draw points and control points ---
	for i in range(display_points.size()):
		var p: Resource = display_points[i]
		var pos_view = get_view_pos(_backend.curve_to_display_position(p.position))

		var is_selected: bool = p == pending_add_point or (
			selected_point != null and p == selected_point
		)
		var is_hovered: bool = (
			hovered_point != null and p == hovered_point
		)

		# Slightly dim when not selected/hovered
		var alpha := 1.0 if (is_hovered) else 0.5

		# ----- Colors -----
		var point_color = Color(1, 0.5, 0, alpha) if is_selected else Color(1, 0, 0, alpha)

		# ----- Main Point -----
		draw_circle(pos_view, point_radius, point_color)

		# ----- Control Points -----
		# LEFT
		if i != 0:
			var left_view = get_view_pos(
				_backend.get_display_control_point(p, EasingCurvePoint.ControlSide.LEFT)
			)

			var left_hovered = (
				is_hovered and
				hovered_control_index
				== _backend.display_control_side_to_curve(ControlIndex.LEFT)
			)

			var left_alpha = 1.0 if left_hovered else alpha
			var left_radius = control_radius

			var left_color = Color(0, 1, 0, left_alpha)
			var left_line_color = Color(
				CONTROL_LINE_COLOR.r,
				CONTROL_LINE_COLOR.g,
				CONTROL_LINE_COLOR.b,
				left_alpha,
			)

			draw_line(pos_view, left_view, left_line_color)
			draw_circle(left_view, left_radius, left_color)

		# RIGHT
		if i != display_points.size() - 1:
			var right_view = get_view_pos(
				_backend.get_display_control_point(p, EasingCurvePoint.ControlSide.RIGHT)
			)

			var right_hovered = (
				is_hovered and
				hovered_control_index
				== _backend.display_control_side_to_curve(ControlIndex.RIGHT)
			)

			var right_alpha = 1.0 if right_hovered else alpha
			var right_radius = control_radius

			var right_color = Color(0, 0, 1, right_alpha)
			var right_line_color = Color(
				CONTROL_LINE_COLOR.r,
				CONTROL_LINE_COLOR.g,
				CONTROL_LINE_COLOR.b,
				right_alpha,
			)

			draw_line(pos_view, right_view, right_line_color)
			draw_circle(right_view, right_radius, right_color)

func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER:
		queue_redraw()
	elif what == NOTIFICATION_FOCUS_EXIT:
		if pending_add_point != null:
			_cancel_pending_add()
		queue_redraw()


func step_to_zoom(step: int) -> float:
	return ZOOM_MIN * pow(ZOOM_FACTOR, step)


func zoom_to_step(zoom: float) -> int:
	return int(round(log(zoom / ZOOM_MIN) / log(ZOOM_FACTOR)))


func set_slider_container(value: EasingCurveZoomSliderContainer) -> void:
	_slider = value

	_slider.slider.min_value = 0
	_slider.slider.max_value = ZOOM_STEPS
	_slider.slider.step = 1

	_slider.slider_changed.connect(_on_slider_changed)
	_slider.autofit_pressed.connect(_on_autofit_pressed)


func set_slider_value(value: float) -> void:
	_on_slider_changed(value)


func set_pan(pan: Vector2) -> void:
	pan_offset = pan


func set_zoom(zoom: Vector2) -> void:
	_zoom_x = zoom.x
	_zoom_y = zoom.y


func set_curve(resource: Resource) -> void:
	if get_curve() == resource:
		return
	if _backend != null and _backend_point_edit_active:
		_backend.finish_point_edit()
	_backend_point_edit_active = false
	_backend_point_edit_before = null
	_backend_point_edit_action_name = "Edit Easing Curve Point"
	_backend_point_edit_selected_before = null
	var previous := get_curve()
	if previous != null and previous.changed.is_connected(_on_curve_changed):
		previous.changed.disconnect(_on_curve_changed)

	_backend = BackendFactory.create(resource)
	_curve = resource as EasingCurve
	var current := get_curve()
	if current != null:
		current.changed.connect(_on_curve_changed)
		selected_index = _selected_index_by_curve.get(
			current.get_instance_id(),
			-1,
		)
		_restore_right_delete_drag_state()
	else:
		selected_index = -1
	_update_point_toolbar()
	queue_redraw()


func get_curve() -> Resource:
	return _backend.curve if _backend != null else null


func get_backend_id() -> StringName:
	return _backend.get_backend_id() if _backend != null else &""


func _point_count() -> int:
	return _backend.get_point_count() if _backend != null else 0


func _point(index: int) -> Resource:
	return _backend.get_point(index) if _backend != null else null


func _points() -> Array[Resource]:
	return _backend.get_points() if _backend != null else []


func _selected_point_resource() -> Resource:
	return _point(selected_index) if selected_index >= 0 else null


func _is_point_graph() -> bool:
	return _backend != null and _backend.is_point_graph()


func _supports_point_geometry() -> bool:
	return (
		_backend != null
		and bool(_backend.get_capabilities().get(&"point_geometry", false))
	)


func _supports_point_topology() -> bool:
	return (
		_backend != null
		and bool(_backend.get_capabilities().get(&"point_topology", false))
	)


func _value_range() -> Vector2:
	return _backend.get_value_range() if _backend != null else Vector2(0.0, 1.0)


func _sample_curve(offset: float) -> float:
	return _backend.sample(offset) if _backend != null else 0.0


func set_graph_render_suppressed(suppressed: bool) -> void:
	if _graph_render_suppressed == suppressed:
		return
	_graph_render_suppressed = suppressed
	queue_redraw()


func is_graph_render_suppressed() -> bool:
	return _graph_render_suppressed


func is_autofit_ready() -> bool:
	return _backend != null and is_instance_valid(_slider)


func select_point(point: Resource) -> bool:
	if _backend == null:
		return false
	var point_index: int = _backend.find_point(point)
	if point_index == -1:
		return false
	selected_index = point_index
	return true


func _is_point_toolbar_hidden() -> bool:
	return (
		hide_selection_toolbar_for_functions
		and _backend != null
		and not _is_point_graph()
	)


func update_view_transform() -> void:
	var margin := 4.0 * _editor_scale
	var toolbar_height := (
		0.0
		if _is_point_toolbar_hidden()
		else SELECTION_TOOLBAR_HEIGHT * _editor_scale
	)

	var auto_range := Vector2(0.0, 1.0)

	var auto_min_y = auto_range.x
	var auto_max_y = auto_range.y
	var auto_height = auto_max_y - auto_min_y

	# Apply Y zoom (zoom in reduces visible height)
	var zoomed_height = auto_height / _zoom_y
	var center_y = (auto_min_y + auto_max_y) * 0.5

	var min_y = center_y - zoomed_height * 0.5
	var max_y = center_y + zoomed_height * 0.5

	# Apply X zoom (zoomed width)
	var zoomed_width = (MAX_X - MIN_X) / _zoom_x
	var center_x = (MIN_X + MAX_X) * 0.5
	var min_x = center_x - zoomed_width * 0.5
	var max_x = center_x + zoomed_width * 0.5

	# Get world rect
	var world_rect = Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
	var view_origin := Vector2(
		margin,
		toolbar_height + margin,
	)
	var view_size := Vector2(
		maxf(size.x - margin * 2.0, 1.0),
		maxf(size.y - toolbar_height - margin * 2.0, 1.0),
	)
	var view_scale = view_size / world_rect.size

	var world_trans: Transform2D
	world_trans = world_trans.translated_local(-world_rect.position - Vector2(0, world_rect.size.y))
	world_trans = world_trans.scaled(Vector2(view_scale.x, -view_scale.y))

	var view_trans: Transform2D
	view_trans = view_trans.translated_local(view_origin)

	_world_to_view = view_trans * world_trans


func get_view_pos(world_pos: Vector2) -> Vector2:
	return (_world_to_view * world_pos) + pan_offset


func get_world_pos(view_pos: Vector2) -> Vector2:
	if (
		not _world_to_view.is_finite()
		or is_zero_approx(_world_to_view.determinant())
	):
		return Vector2(NAN, NAN)

	return _world_to_view.affine_inverse() * (view_pos - pan_offset)


func get_point_at(pos: Vector2) -> int:
	if _backend == null:
		return -1

	var closest_idx = -1
	var closest_dist_squared: float = point_radius * point_radius * 4
	for point in _get_display_points():
		var view_p = get_view_pos(
			_backend.curve_to_display_position(point.get(&"position") as Vector2)
		)
		var dist_sq = view_p.distance_squared_to(pos)
		if dist_sq < closest_dist_squared:
			closest_dist_squared = dist_sq
			closest_idx = _backend.find_point(point)
	return closest_idx if closest_dist_squared < point_radius * point_radius else -1


# =========================
# CONTROL POINT FILTERING
# =========================
# Only allow valid control points
func get_control_at(pos: Vector2) -> Array: # [point_index, ControlIndex]
	if _backend == null:
		return [-1, ControlIndex.NONE]

	var display_points := _get_display_points()
	for display_index in range(display_points.size()):
		var point: Resource = display_points[display_index]
		var point_index: int = _backend.find_point(point)

		# LEFT (only if not first and not locked)
		if (
			display_index != 0
			and not _backend.is_point_control_force_linear(
				point_index,
				_backend.display_control_side_to_curve(EasingCurvePoint.ControlSide.LEFT),
			)
		):
			var left_view = get_view_pos(
				_backend.get_display_control_point(
					point,
					EasingCurvePoint.ControlSide.LEFT,
				)
			)
			if left_view.distance_squared_to(pos) < control_hover_radius * control_hover_radius:
				return [
					point_index,
					_backend.display_control_side_to_curve(ControlIndex.LEFT),
				]

		# RIGHT (only if not last and not locked)
		if (
			display_index != display_points.size() - 1
			and not _backend.is_point_control_force_linear(
				point_index,
				_backend.display_control_side_to_curve(EasingCurvePoint.ControlSide.RIGHT),
			)
		):
			var right_view = get_view_pos(
				_backend.get_display_control_point(
					point,
					EasingCurvePoint.ControlSide.RIGHT,
				)
			)
			if right_view.distance_squared_to(pos) < control_hover_radius * control_hover_radius:
				return [
					point_index,
					_backend.display_control_side_to_curve(ControlIndex.RIGHT),
				]

	return [-1, ControlIndex.NONE]


func _zoom_at_view_pos(step_delta: int, view_pos: Vector2) -> void:
	var world_before := get_world_pos(view_pos)

	if not world_before.is_finite():
		return

	var new_step := clamp(
		_zoom_step + step_delta,
		0,
		ZOOM_STEPS,
	)

	if new_step == _zoom_step:
		return

	_zoom_step = new_step
	_apply_zoom_from_step()

	# _apply_zoom_from_step() changes zoom values, but the transform
	# normally isn't rebuilt until the next draw.
	update_view_transform()

	var view_after := get_view_pos(world_before)

	pan_offset += view_pos - view_after

	pan_changed.emit(pan_offset)
	queue_redraw()


func _on_autofit_pressed() -> void:
	autofit()


func autofit() -> void:
	if _backend == null:
		return

	var bounds := _get_autofit_world_bounds()
	var padded_size := bounds.size * (1.0 + AUTOFIT_PADDING_RATIO)
	padded_size.x = maxf(padded_size.x, 0.001)
	padded_size.y = maxf(padded_size.y, 0.001)

	var target_zoom := minf(
		1.0 / padded_size.x,
		1.0 / padded_size.y,
	)
	var fit_step := 0
	for step in range(ZOOM_STEPS + 1):
		if step_to_zoom(step) <= target_zoom + 0.000001:
			fit_step = step
		else:
			break

	_zoom_step = fit_step
	_apply_zoom_from_step()
	pan_offset = Vector2.ZERO
	update_view_transform()

	var graph_rect := _get_graph_view_rect()
	var bounds_center_view := _world_to_view * bounds.get_center()
	pan_offset = graph_rect.get_center() - bounds_center_view
	pan_changed.emit(pan_offset)
	queue_redraw()


func _get_autofit_world_bounds() -> Rect2:
	var value_range := _value_range()
	var min_bound := Vector2(MIN_X, value_range.x)
	var max_bound := Vector2(MAX_X, value_range.y)

	if not _is_point_graph():
		for i in range(FUNCTION_DRAW_STEPS + 1):
			var x := float(i) / FUNCTION_DRAW_STEPS
			var sample_point := Vector2(x, _sample_curve(x))
			min_bound = min_bound.min(sample_point)
			max_bound = max_bound.max(sample_point)
		return Rect2(min_bound, max_bound - min_bound)

	var display_points := _get_display_points()
	for i in range(display_points.size()):
		var point: Resource = display_points[i]
		var position: Vector2 = _backend.curve_to_display_position(
			point.get(&"position") as Vector2
		)
		min_bound = min_bound.min(position)
		max_bound = max_bound.max(position)

		if i > 0:
			var left_control: Vector2 = _backend.get_display_control_point(
				point,
				EasingCurvePoint.ControlSide.LEFT,
			)
			min_bound = min_bound.min(left_control)
			max_bound = max_bound.max(left_control)
		if i < display_points.size() - 1:
			var right_control: Vector2 = _backend.get_display_control_point(
				point,
				EasingCurvePoint.ControlSide.RIGHT,
			)
			min_bound = min_bound.min(right_control)
			max_bound = max_bound.max(right_control)

	for i in range(display_points.size() - 1):
		var controls := _get_effective_segment_controls(
			display_points[i],
			display_points[i + 1],
		)
		min_bound = min_bound.min(controls[0]).min(controls[1])
		max_bound = max_bound.max(controls[0]).max(controls[1])

	return Rect2(min_bound, max_bound - min_bound)


func _get_graph_view_rect() -> Rect2:
	var margin := 4.0 * _editor_scale
	var toolbar_height := (
		0.0
		if _is_point_toolbar_hidden()
		else SELECTION_TOOLBAR_HEIGHT * _editor_scale
	)
	return Rect2(
		Vector2(margin, toolbar_height + margin),
		Vector2(
			maxf(size.x - margin * 2.0, 1.0),
			maxf(size.y - toolbar_height - margin * 2.0, 1.0),
		),
	)


func _on_slider_changed(value: float) -> void:
	_zoom_step = int(value)
	_apply_zoom_from_step()


func _apply_zoom_from_step():
	var zoom := step_to_zoom(_zoom_step)
	_zoom_x = zoom
	_zoom_y = zoom
	slider_changed.emit(_zoom_step)
	_slider.slider.value = _zoom_step
	queue_redraw()
	zoom_changed.emit(Vector2(zoom, zoom))


func _on_curve_changed() -> void:
	if pending_add_point != null:
		pending_add_point = null
	if (
		position_x_order_preview_point != null
		and (_backend == null or _backend.find_point(position_x_order_preview_point) == -1)
	):
		position_x_order_preview_point = null
	var point_count := _point_count()
	if selected_index >= point_count:
		selected_index = -1
		selected_control_index = ControlIndex.NONE
	if hovered_index >= point_count:
		hovered_index = -1
		hovered_control_index = ControlIndex.NONE
	if dragging_point >= point_count:
		dragging_point = -1
		dragging_control = ControlIndex.NONE
		_clear_axis_drag()
	_update_point_toolbar()
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var graph_height := maxf(
		MIN_GRAPH_HEIGHT,
		size.x * ASPECT_RATIO,
	)

	# Keep the overall editor section height stable across Bezier/Function
	# mode changes. When the selection toolbar is hidden, the graph simply
	# expands into this reserved height instead of shrinking the Inspector.
	return Vector2(
		64.0,
		graph_height + SELECTION_TOOLBAR_HEIGHT,
	) * _editor_scale


func _get_display_points() -> Array[Resource]:
	if _backend == null:
		return []
	var active_point: Resource
	if pending_add_point != null or (
		dragging_point != -1
		and dragging_control == ControlIndex.NONE
	) or position_x_order_preview_point != null:
		if pending_add_point != null:
			active_point = pending_add_point
		elif dragging_point != -1 and dragging_control == ControlIndex.NONE:
			active_point = _point(dragging_point)
		else:
			active_point = position_x_order_preview_point
	return _backend.get_display_points(active_point)


func _get_ordered_points() -> Array[Resource]:
	if _backend == null:
		return []
	var active_point: Resource
	if dragging_point != -1 and dragging_control == ControlIndex.NONE:
		active_point = _point(dragging_point)
	return _backend.get_ordered_points(active_point)


func set_position_x_order_preview(point: Resource) -> void:
	position_x_order_preview_point = point
	queue_redraw()


func clear_position_x_order_preview() -> void:
	position_x_order_preview_point = null
	queue_redraw()


func _draw_bezier_curve(point_list: Array[Resource]) -> void:
	var fallback_y: float = _backend.curve_to_display_position(
		Vector2(0.0, EasingCurve.get_bezier_fallback_value(0.0))
	).y
	if point_list.size() < 2:
		draw_line(
			get_view_pos(Vector2(0.0, fallback_y)),
			get_view_pos(Vector2(1.0, fallback_y)),
			LINE_COLOR,
			2,
		)
		return

	var first_point: Resource = point_list.front()
	var last_point: Resource = point_list.back()
	var first_position: Vector2 = _backend.curve_to_display_position(
		first_point.get(&"position") as Vector2
	)
	var last_position: Vector2 = _backend.curve_to_display_position(
		last_point.get(&"position") as Vector2
	)

	if not EasingCurve.is_left_endpoint_x(first_position.x):
		draw_line(
			get_view_pos(Vector2(0.0, fallback_y)),
			get_view_pos(Vector2(first_position.x, fallback_y)),
			LINE_COLOR,
			2,
		)
		draw_line(
			get_view_pos(Vector2(first_position.x, fallback_y)),
			get_view_pos(first_position),
			LINE_COLOR,
			2,
		)

	var visible_x_bounds := _get_visible_world_x_bounds()
	for i in range(point_list.size() - 1):
		_draw_bezier_segment(
			point_list[i],
			point_list[i + 1],
			visible_x_bounds.x,
			visible_x_bounds.y,
		)

	if not EasingCurve.is_right_endpoint_x(last_position.x):
		draw_line(
			get_view_pos(last_position),
			get_view_pos(Vector2(last_position.x, fallback_y)),
			LINE_COLOR,
			2,
		)
		draw_line(
			get_view_pos(Vector2(last_position.x, fallback_y)),
			get_view_pos(Vector2(1.0, fallback_y)),
			LINE_COLOR,
			2,
		)


func _get_visible_world_x_bounds() -> Vector2:
	var left_x := get_world_pos(Vector2(0.0, 0.0)).x
	var right_x := get_world_pos(Vector2(size.x, 0.0)).x
	if not is_finite(left_x) or not is_finite(right_x):
		return Vector2(MIN_X, MAX_X)
	return Vector2(minf(left_x, right_x), maxf(left_x, right_x))


func _draw_bezier_segment(
		a: Resource,
		b: Resource,
		visible_min_x: float,
		visible_max_x: float,
) -> void:
	var a_position: Vector2 = _backend.curve_to_display_position(
		a.get(&"position") as Vector2
	)
	var b_position: Vector2 = _backend.curve_to_display_position(
		b.get(&"position") as Vector2
	)
	var segment_width := b_position.x - a_position.x
	if absf(segment_width) <= EasingCurve.SEGMENT_X_EPSILON:
		if a_position.x >= visible_min_x and a_position.x <= visible_max_x:
			draw_line(get_view_pos(a_position), get_view_pos(b_position), LINE_COLOR, 2)
		return

	var segment_min_x := minf(a_position.x, b_position.x)
	var segment_max_x := maxf(a_position.x, b_position.x)
	var start_x := maxf(segment_min_x, visible_min_x)
	var end_x := minf(segment_max_x, visible_max_x)
	if start_x > end_x:
		return

	var controls := _get_effective_segment_controls(a, b)
	var start_t := BEZIER_SOLVER.solve_monotonic_t(
		start_x,
		a_position.x,
		controls[0].x,
		controls[1].x,
		b_position.x,
	)
	var end_t := BEZIER_SOLVER.solve_monotonic_t(
		end_x,
		a_position.x,
		controls[0].x,
		controls[1].x,
		b_position.x,
	)
	if start_t > end_t:
		var swap_t := start_t
		start_t = end_t
		end_t = swap_t

	var start_world := _bezier_world_position(a, b, controls[0], controls[1], start_t)
	var end_world := _bezier_world_position(a, b, controls[0], controls[1], end_t)
	var interval_control_scale := (end_t - start_t) / 3.0
	var interval_out_control := start_world + _bezier_world_derivative(
		a,
		b,
		controls[0],
		controls[1],
		start_t,
	) * interval_control_scale
	var interval_in_control := end_world - _bezier_world_derivative(
		a,
		b,
		controls[0],
		controls[1],
		end_t,
	) * interval_control_scale
	var start_view := get_view_pos(start_world)
	var end_view := get_view_pos(end_world)
	var polyline := PackedVector2Array([start_view])
	_append_adaptive_bezier_points(
		start_view,
		get_view_pos(interval_out_control),
		get_view_pos(interval_in_control),
		end_view,
		0,
		polyline,
	)
	draw_polyline(polyline, LINE_COLOR, 2.0)


func _append_adaptive_bezier_points(
		start_point: Vector2,
		out_control: Vector2,
		in_control: Vector2,
		end_point: Vector2,
		depth: int,
		polyline: PackedVector2Array,
) -> void:
	if depth >= BEZIER_DRAW_MAX_DEPTH:
		polyline.append(end_point)
		return

	var flatness := maxf(
		_point_to_line_distance(out_control, start_point, end_point),
		_point_to_line_distance(in_control, start_point, end_point),
	)

	if flatness <= BEZIER_DRAW_TOLERANCE_PIXELS * _editor_scale:
		polyline.append(end_point)
		return

	var start_out_midpoint := (start_point + out_control) * 0.5
	var control_midpoint := (out_control + in_control) * 0.5
	var in_end_midpoint := (in_control + end_point) * 0.5
	var left_control_midpoint := (start_out_midpoint + control_midpoint) * 0.5
	var right_control_midpoint := (control_midpoint + in_end_midpoint) * 0.5
	var curve_midpoint := (left_control_midpoint + right_control_midpoint) * 0.5
	_append_adaptive_bezier_points(
		start_point,
		start_out_midpoint,
		left_control_midpoint,
		curve_midpoint,
		depth + 1,
		polyline,
	)
	_append_adaptive_bezier_points(
		curve_midpoint,
		right_control_midpoint,
		in_end_midpoint,
		end_point,
		depth + 1,
		polyline,
	)


func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line := line_end - line_start
	var line_length := line.length()
	if is_zero_approx(line_length):
		return point.distance_to(line_start)
	return absf(line.cross(point - line_start)) / line_length


func _bezier_world_position(
		a: Resource,
		b: Resource,
		out_control: Vector2,
		in_control: Vector2,
		t: float,
) -> Vector2:
	var a_position: Vector2 = _backend.curve_to_display_position(
		a.get(&"position") as Vector2
	)
	var b_position: Vector2 = _backend.curve_to_display_position(
		b.get(&"position") as Vector2
	)
	return Vector2(
		BEZIER_SOLVER.bezier_interpolate(
			a_position.x,
			out_control.x,
			in_control.x,
			b_position.x,
			t,
		),
		BEZIER_SOLVER.bezier_interpolate(
			a_position.y,
			out_control.y,
			in_control.y,
			b_position.y,
			t,
		),
	)


func _bezier_world_derivative(
		a: Resource,
		b: Resource,
		out_control: Vector2,
		in_control: Vector2,
		t: float,
) -> Vector2:
	var a_position: Vector2 = _backend.curve_to_display_position(
		a.get(&"position") as Vector2
	)
	var b_position: Vector2 = _backend.curve_to_display_position(
		b.get(&"position") as Vector2
	)
	return Vector2(
		BEZIER_SOLVER.bezier_derivative(
			a_position.x,
			out_control.x,
			in_control.x,
			b_position.x,
			t,
		),
		BEZIER_SOLVER.bezier_derivative(
			a_position.y,
			out_control.y,
			in_control.y,
			b_position.y,
			t,
		),
	)


func _get_effective_segment_controls(a: Resource, b: Resource) -> Array[Vector2]:
	var a_position: Vector2 = _backend.curve_to_display_position(
		a.get(&"position") as Vector2
	)
	var b_position: Vector2 = _backend.curve_to_display_position(
		b.get(&"position") as Vector2
	)
	var out_control: Vector2 = _backend.get_display_control_point(
		a,
		EasingCurvePoint.ControlSide.RIGHT,
	)
	var in_control: Vector2 = _backend.get_display_control_point(
		b,
		EasingCurvePoint.ControlSide.LEFT,
	)
	var min_x := minf(a_position.x, b_position.x)
	var max_x := maxf(a_position.x, b_position.x)
	out_control.x = clampf(out_control.x, min_x, max_x)
	in_control.x = clampf(in_control.x, min_x, max_x)
	var increasing: bool = b_position.x >= a_position.x
	if (
		(increasing and out_control.x > in_control.x)
		or (not increasing and out_control.x < in_control.x)
	):
		var shared_x: float = (out_control.x + in_control.x) * 0.5
		out_control.x = shared_x
		in_control.x = shared_x
	return [out_control, in_control]


func _draw_sampled_curve() -> void:
	var prev: Vector2

	for i in range(FUNCTION_DRAW_STEPS + 1):
		var x = float(i) / FUNCTION_DRAW_STEPS
		var y := _sample_curve(x)
		var pt = get_view_pos(Vector2(x, y))

		if i > 0:
			draw_line(prev, pt, LINE_COLOR, 2)

		prev = pt


func _create_point_toolbar() -> void:
	_point_toolbar_panel = VBoxContainer.new()
	_point_toolbar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_point_toolbar_panel.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_WIDE
	)

	_point_toolbar_panel.custom_minimum_size.y = (
		SELECTION_TOOLBAR_HEIGHT * _editor_scale
	)

	add_child(_point_toolbar_panel)

	_point_toolbar = GridContainer.new()
	_point_toolbar.columns = 3
	_point_toolbar.add_theme_constant_override(
		"h_separation",
		maxi(1, roundi(2.0 * _editor_scale)),
	)
	_point_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_toolbar.custom_minimum_size.y = (
		SELECTION_TOOLBAR_HEIGHT * _editor_scale
	)

	_point_toolbar_panel.add_child(_point_toolbar)

	var point_label_row := HBoxContainer.new()
	point_label_row.add_theme_constant_override("separation", 0)
	point_label_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	point_label_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_point_toolbar.add_child(point_label_row)

	_point_reorder_buttons = HBoxContainer.new()
	_point_reorder_buttons.add_theme_constant_override("separation", 0)
	_point_reorder_buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	point_label_row.add_child(_point_reorder_buttons)

	var reorder_button_size := 16.0 * _editor_scale

	_point_move_left_button = Button.new()
	_point_move_left_button.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_MOVE_LEFT
	)
	_point_move_left_button.flat = true
	_point_move_left_button.custom_minimum_size = Vector2(
		reorder_button_size,
		reorder_button_size,
	)
	_point_move_left_button.tooltip_text = "Move Point Left"
	_point_move_left_button.pressed.connect(_request_point_move_up)
	for style_name in [&"normal", &"hover", &"pressed", &"focus"]:
		_point_move_left_button.add_theme_stylebox_override(
			style_name,
			StyleBoxEmpty.new(),
		)
	_point_reorder_buttons.add_child(_point_move_left_button)

	_point_label = Label.new()
	_point_label.text = "No Selection"
	_point_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_point_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_point_reorder_buttons.add_child(_point_label)
	_reserve_point_toolbar_label_column_width()

	_point_move_right_button = Button.new()
	_point_move_right_button.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_MOVE_RIGHT
	)
	_point_move_right_button.flat = true
	_point_move_right_button.custom_minimum_size = Vector2(
		reorder_button_size,
		reorder_button_size,
	)
	_point_move_right_button.tooltip_text = "Move Point Right"
	_point_move_right_button.pressed.connect(_request_point_move_down)
	for style_name in [&"normal", &"hover", &"pressed", &"focus"]:
		_point_move_right_button.add_theme_stylebox_override(
			style_name,
			StyleBoxEmpty.new(),
		)
	_point_reorder_buttons.add_child(_point_move_right_button)

	_point_toolbar_controls = HBoxContainer.new()
	_point_toolbar_controls.add_theme_constant_override(
		"separation",
		maxi(1, roundi(2.0 * _editor_scale)),
	)
	_point_toolbar_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_toolbar.add_child(_point_toolbar_controls)

	_point_handle_mode = OptionButton.new()
	_point_handle_mode.fit_to_longest_item = false
	_point_handle_mode.clip_text = true
	_point_handle_mode.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_point_handle_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_handle_mode.size_flags_stretch_ratio = 1.2

	_point_handle_mode.add_item(
		"Free",
		EasingCurvePoint.HandleMode.FREE,
	)
	_point_handle_mode.add_item(
		"Linear",
		EasingCurvePoint.HandleMode.LINEAR,
	)
	_point_handle_mode.add_item(
		"Balanced",
		EasingCurvePoint.HandleMode.BALANCED,
	)
	_point_handle_mode.add_item(
		"Mirrored",
		EasingCurvePoint.HandleMode.MIRRORED,
	)
	_point_handle_mode.add_item(
		"Linked",
		EasingCurvePoint.HandleMode.LINKED,
	)

	_point_handle_mode.item_selected.connect(
		_on_point_toolbar_handle_mode_selected
	)

	_point_toolbar_controls.add_child(_point_handle_mode)

	_point_left_state_label = Label.new()
	_point_left_state_label.text = "L"
	_point_toolbar_controls.add_child(_point_left_state_label)
	_point_left_state = _create_point_toolbar_control_state_option(
		EasingCurvePoint.ControlSide.LEFT
	)
	_point_toolbar_controls.add_child(_point_left_state)

	_point_right_state_label = Label.new()
	_point_right_state_label.text = "R"
	_point_toolbar_controls.add_child(_point_right_state_label)
	_reserve_point_toolbar_control_side_label_width()
	_point_right_state = _create_point_toolbar_control_state_option(
		EasingCurvePoint.ControlSide.RIGHT
	)
	_point_toolbar_controls.add_child(_point_right_state)

	_point_reset_button = Button.new()
	_point_reset_button.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_RELOAD
	)
	_point_reset_button.flat = true
	_point_reset_button.tooltip_text = "Reset Point Options"
	_point_reset_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_point_reset_button.pressed.connect(_on_point_toolbar_reset_pressed)
	_point_toolbar.add_child(_point_reset_button)


	var toolbar_row_height := SELECTION_TOOLBAR_HEIGHT * _editor_scale
	for toolbar_control: Control in [
		_point_handle_mode,
		_point_left_state,
		_point_right_state,
		_point_reset_button,
	]:
		toolbar_row_height = maxf(
			toolbar_row_height,
			toolbar_control.get_combined_minimum_size().y,
		)
	_point_toolbar.custom_minimum_size.y = toolbar_row_height
	_point_toolbar_panel.custom_minimum_size.y = toolbar_row_height

	_set_point_toolbar_reset_available(false)


func _reserve_point_toolbar_label_column_width() -> void:
	var original_text := _point_label.text
	_point_label.text = "P99"
	_point_label.custom_minimum_size.x = (
		_point_label.get_combined_minimum_size().x
	)
	_point_label.text = original_text


func _reserve_point_toolbar_control_side_label_width() -> void:
	var label_width := maxf(
		_point_left_state_label.get_combined_minimum_size().x,
		_point_right_state_label.get_combined_minimum_size().x,
	)
	_point_left_state_label.custom_minimum_size.x = label_width
	_point_right_state_label.custom_minimum_size.x = label_width


func _create_point_toolbar_control_state_option(
	side: EasingCurvePoint.ControlSide,
) -> OptionButton:
	var option := OptionButton.new()
	option.fit_to_longest_item = false
	option.clip_text = true
	option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.size_flags_stretch_ratio = 1.0
	option.add_item("Free", EasingCurvePoint.ControlState.FREE)
	option.add_item("Linear", EasingCurvePoint.ControlState.LINEAR)
	option.add_item("Locked", EasingCurvePoint.ControlState.LOCKED)
	option.item_selected.connect(_on_point_toolbar_control_state_selected.bind(side))
	return option




func _update_point_toolbar() -> void:
	if _point_toolbar == null:
		return

	var hide_toolbar := _is_point_toolbar_hidden()
	_point_toolbar_panel.visible = not hide_toolbar

	if hide_toolbar:
		_set_point_toolbar_reorder_available(false, false)
		_set_point_toolbar_reset_available(false)
		return

	var valid_selection := (
		_backend != null
		and selected_index >= 0
		and selected_index < _point_count()
	)

	_point_toolbar.visible = true
	_point_move_left_button.tooltip_text = (
		"Move Point Left"
		if point_move_buttons_reorder_points
		else "Select Previous Point"
	)
	_point_move_right_button.tooltip_text = (
		"Move Point Right"
		if point_move_buttons_reorder_points
		else "Select Next Point"
	)

	if not valid_selection:
		_point_label.text = (
			""
			if _backend != null and not _is_point_graph()
			else "No Selection"
		)
		_point_label.modulate.a = 0.6
		_set_point_toolbar_reorder_available(
			false,
			_backend == null or _is_point_graph(),
		)
		_point_handle_mode.visible = true
		_point_handle_mode.self_modulate.a = 0.0
		_point_handle_mode.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_point_handle_mode.disabled = true
		_set_point_toolbar_reset_available(false)
		_set_point_toolbar_control_state_visible(
			EasingCurvePoint.ControlSide.LEFT,
			false,
		)
		_set_point_toolbar_control_state_visible(
			EasingCurvePoint.ControlSide.RIGHT,
			false,
		)
		return

	var point := _point(selected_index)

	_point_label.text = "P%d" % selected_index
	_point_label.modulate.a = 1.0
	_point_handle_mode.visible = true
	_point_handle_mode.self_modulate.a = 1.0
	_point_handle_mode.mouse_filter = Control.MOUSE_FILTER_STOP
	_point_handle_mode.disabled = false
	_set_point_toolbar_reorder_available(
		_can_use_point_move_buttons(),
		_is_point_graph(),
	)

	_updating_point_toolbar = true

	for index in range(_point_handle_mode.item_count):
		if (
			_point_handle_mode.get_item_id(index)
			== int(point.get(&"handle_mode"))
		):
			_point_handle_mode.select(index)
			break

	_update_point_toolbar_control_state(
		point,
		EasingCurvePoint.ControlSide.LEFT,
		selected_index > 0 and _backend.point_supports_control_state(selected_index),
	)
	_update_point_toolbar_control_state(
		point,
		EasingCurvePoint.ControlSide.RIGHT,
		selected_index < _point_count() - 1
		and _backend.point_supports_control_state(selected_index),
	)
	_set_point_toolbar_reset_available(
		not _point_toolbar_options_are_default(point)
	)

	_updating_point_toolbar = false


func _set_point_toolbar_control_state_visible(
	side: EasingCurvePoint.ControlSide,
	visible: bool,
) -> void:
	var label := (
		_point_left_state_label
		if side == EasingCurvePoint.ControlSide.LEFT
		else _point_right_state_label
	)
	var option := (
		_point_left_state
		if side == EasingCurvePoint.ControlSide.LEFT
		else _point_right_state
	)
	label.visible = visible
	option.visible = visible


func _set_point_toolbar_reorder_available(
	available: bool,
	visible: bool = true,
) -> void:
	for button in [_point_move_left_button, _point_move_right_button]:
		if button == null:
			continue
		button.self_modulate.a = 1.0 if visible else 0.0
		button.mouse_filter = (
			Control.MOUSE_FILTER_STOP
			if available
			else Control.MOUSE_FILTER_IGNORE
		)
		button.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
		button.disabled = not available


func _set_point_toolbar_reset_available(available: bool) -> void:
	var tint := _point_reset_button.self_modulate
	tint.a = 1.0 if available else 0.0
	_point_reset_button.self_modulate = tint
	_point_reset_button.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if available
		else Control.MOUSE_FILTER_IGNORE
	)
	_point_reset_button.focus_mode = (
		Control.FOCUS_ALL if available else Control.FOCUS_NONE
	)
	_point_reset_button.disabled = not available


func _point_toolbar_options_are_default(point: Resource) -> bool:
	var locks := point.get(&"locked") as Dictionary
	return (
		int(point.get(&"handle_mode")) == EasingCurvePoint.HandleMode.FREE
		and not bool(point.get(&"left_force_linear"))
		and not bool(point.get(&"right_force_linear"))
		and not locks.get(&"left_control_point", false)
		and not locks.get(&"right_control_point", false)
	)


func _update_point_toolbar_control_state(
	_point: Resource,
	side: EasingCurvePoint.ControlSide,
	visible: bool,
) -> void:
	_set_point_toolbar_control_state_visible(side, visible)
	if not visible:
		return

	var option := (
		_point_left_state
		if side == EasingCurvePoint.ControlSide.LEFT
		else _point_right_state
	)
	var control_state := _get_point_toolbar_control_state(selected_index, side)
	for index in range(option.item_count):
		if option.get_item_id(index) == control_state:
			option.select(index)
			break


func _get_point_toolbar_control_state(
	point_index: int,
	side: EasingCurvePoint.ControlSide,
) -> EasingCurvePoint.ControlState:
	return _backend.get_point_control_state(
		point_index,
		_backend.display_control_side_to_curve(side),
	)


func _on_point_toolbar_handle_mode_selected(index: int) -> void:
	if _updating_point_toolbar:
		return

	if (
		_backend == null
		or selected_index < 0
		or selected_index >= _point_count()
	):
		return

	_request_point_property_change(
		selected_index,
		&"handle_mode",
		_point_handle_mode.get_item_id(index),
	)


func _on_point_toolbar_control_state_selected(
	index: int,
	side: EasingCurvePoint.ControlSide,
) -> void:
	if _updating_point_toolbar:
		return

	if (
		_backend == null
		or selected_index < 0
		or selected_index >= _point_count()
	):
		return

	var curve_side: int = _backend.display_control_side_to_curve(side)
	var property_name := (
		&"left_control_state"
		if curve_side == EasingCurvePoint.ControlSide.LEFT
		else &"right_control_state"
	)
	var option := (
		_point_left_state
		if side == EasingCurvePoint.ControlSide.LEFT
		else _point_right_state
	)
	_request_point_property_change(
		selected_index,
		property_name,
		option.get_item_id(index),
	)


func _on_point_toolbar_reset_pressed() -> void:
	if (
		_backend == null
		or selected_index < 0
		or selected_index >= _point_count()
	):
		return

	_request_point_property_change(
		selected_index,
		&"toolbar_options_reset",
		true,
	)


func get_world_to_view_scale() -> Vector2:
	return Vector2(
		_world_to_view.x.length(),
		_world_to_view.y.length()
	)

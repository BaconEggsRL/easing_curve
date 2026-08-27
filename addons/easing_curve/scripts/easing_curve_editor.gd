@tool
class_name EasingCurveEditor
extends Control
## Easing Curve Editor
##
## Graph editor for interactive EasingCurve point and control-handle editing.

const SELECTION_TOOLBAR_HEIGHT := 32.0
const RELOAD_ICON = preload("res://addons/easing_curve/assets/icons/Reload.svg")

var use_pending_add := true
var hide_point_toolbar_for_functions := false

static var _selected_index_by_curve: Dictionary[int, int] = {}
static var _right_delete_drag_state_by_curve: Dictionary[int, Dictionary] = {}

signal point_changed
signal point_property_change_requested(index: int, property_name: StringName, value: Variant, changing: bool)
signal point_add_requested(point: EasingCurvePoint)
signal point_remove_requested(point: EasingCurvePoint)
signal point_edit_finished(point_order: Array[EasingCurvePoint])
signal slider_changed
signal zoom_changed
signal pan_changed

enum GrabMode { NONE, ADD, MOVE }
enum ControlIndex { NONE = -1, LEFT = 0, RIGHT = 1 }

const ZOOM_SLIDER_CONTAINER = preload("uid://r1ymwr6nae")
const EASING_CURVE_EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")
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

var editor_undo_redo: EditorUndoRedoManager
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
		if _curve != null:
			_selected_index_by_curve[_curve.get_instance_id()] = value
		_update_point_toolbar()
		queue_redraw()

var hovered_index: int = -1
var selected_control_index: ControlIndex = ControlIndex.NONE
var hovered_control_index: ControlIndex = ControlIndex.NONE

var dragging_point: int = -1
var dragging_control: ControlIndex = ControlIndex.NONE
var pending_add_point: EasingCurvePoint
var position_x_order_preview_point: EasingCurvePoint
var is_right_delete_dragging := false
var _right_delete_requires_exit := false
var _right_delete_blocked_position := Vector2.ZERO

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
var _slider: EasingCurveZoomSliderContainer:
	set = set_slider_container
var _world_to_view: Transform2D
var _editor_scale: float = 1.0

var _point_toolbar_panel: VBoxContainer
var _point_toolbar: GridContainer
var _point_label: Label
var _point_toolbar_controls: HBoxContainer
var _point_handle_mode: OptionButton
var _point_left_state_label: Label
var _point_left_state: OptionButton
var _point_right_state_label: Label
var _point_right_state: OptionButton
var _point_reset_button: Button
var _updating_point_toolbar := false


func _ready() -> void:
	custom_minimum_size = Vector2.ZERO
	focus_mode = Control.FOCUS_ALL
	clip_contents = true

	if Engine.is_editor_hint():
		_editor_scale = EditorInterface.get_editor_scale()
	update_minimum_size()

	if _curve == null:
		_curve = EasingCurve.new()
		_curve.changed.connect(_on_curve_changed)

	_create_point_toolbar()
	_update_point_toolbar()


# =========================
# GUI INPUT (DRAGGING)
# =========================
func _gui_input(event: InputEvent) -> void:
	if _curve == null:
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
	if _curve.curve_mode == EasingCurve.CurveMode.FUNCTION:
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
	var clamped_pos := world_pos.clamp(
		Vector2(0, _curve.min_value),
		Vector2(1.0, _curve.max_value),
	)
	pending_add_point.position = clamped_pos
	queue_redraw()


func _handle_drag_motion(event: InputEventMouseMotion) -> void:
	var p = _curve.points[dragging_point]
	if dragging_control != ControlIndex.NONE:
		p.set_handle_display_scale(get_world_to_view_scale())
	var world_pos = get_world_pos(event.position)
	if not world_pos.is_finite():
		return
	if dragging_control == ControlIndex.NONE and p.is_lock_active(&"position"):
		return
	if dragging_control == ControlIndex.LEFT and p.is_lock_active(&"left_control_point"):
		return
	if dragging_control == ControlIndex.RIGHT and p.is_lock_active(&"right_control_point"):
		return

	match dragging_control:
		ControlIndex.LEFT:
			if dragging_point != 0:
				_request_point_property_change(dragging_point, &"left_control_point", world_pos, true)
		ControlIndex.RIGHT:
			if dragging_point != _curve.points.size() - 1:
				_request_point_property_change(dragging_point, &"right_control_point", world_pos, true)
		ControlIndex.NONE:
			var clamped_pos = world_pos.clamp(Vector2(0, _curve.min_value), Vector2(1.0, _curve.max_value))
			var delta = clamped_pos - p.position
			var left_control: Vector2 = p.left_control_point
			var right_control: Vector2 = p.right_control_point
			_request_point_property_change(dragging_point, &"position", clamped_pos, true)
			if not p.is_lock_active(&"left_control_point"):
				_request_point_property_change(dragging_point, &"left_control_point", left_control + delta, true)
			if not p.is_lock_active(&"right_control_point"):
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
	if _curve.curve_mode == EasingCurve.CurveMode.FUNCTION:
		return
	if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_pressed(event)
	elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_pressed(event)
	elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_released()


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
	if control[0] != -1 and _curve.points[control[0]].handle_mode == EasingCurvePoint.HandleMode.LINEAR:
		point_idx = control[0]
		control = [-1, ControlIndex.NONE]
	if control[0] != -1:
		var p = _curve.points[control[0]]
		var can_drag_control := false
		match control[1]:
			ControlIndex.LEFT:
				can_drag_control = not p.is_lock_active(&"left_control_point")
			ControlIndex.RIGHT:
				can_drag_control = not p.is_lock_active(&"right_control_point")
		selected_index = control[0]
		if can_drag_control:
			dragging_point = control[0]
			dragging_control = control[1]
		elif point_idx != -1 and not _curve.points[point_idx].is_lock_active(&"position"):
			dragging_point = point_idx
			dragging_control = ControlIndex.NONE
		queue_redraw()
		return
	if point_idx != -1:
		var p = _curve.points[point_idx]
		if not p.is_lock_active(&"position"):
			dragging_point = point_idx
			dragging_control = ControlIndex.NONE
		selected_index = point_idx
		queue_redraw()
		return

	var world_pos := get_world_pos(event.position)
	if not world_pos.is_finite():
		return
	var clamped_pos := world_pos.clamp(Vector2(0, _curve.min_value), Vector2(1.0, _curve.max_value))
	if use_pending_add:
		pending_add_point = EasingCurvePoint.new()
		pending_add_point.position = clamped_pos
		pending_add_point.left_control_point = clamped_pos + Vector2(-0.1, 0.0)
		pending_add_point.right_control_point = clamped_pos + Vector2(0.1, 0.0)
		queue_redraw()
		accept_event()
		return
	var new_point := EasingCurvePoint.new()
	new_point.position = clamped_pos
	new_point.left_control_point = clamped_pos + Vector2(-0.1, 0.0)
	new_point.right_control_point = clamped_pos + Vector2(0.1, 0.0)
	_request_point_add(new_point)
	selected_index = -1
	for i in range(_curve.points.size()):
		if _curve.points[i].position == clamped_pos:
			selected_index = i
			break
	if selected_index != -1:
		dragging_point = selected_index
		dragging_control = ControlIndex.NONE
	queue_redraw()


func _handle_right_pressed(event: InputEventMouseButton) -> void:
	if pending_add_point != null:
		_cancel_pending_add()
		accept_event()
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
		var point_position := point.position
		pending_add_point = null
		_request_point_add(point)
		selected_index = -1
		for i in range(_curve.points.size()):
			if _curve.points[i].position == point_position:
				selected_index = i
				break
		dragging_point = -1
		dragging_control = ControlIndex.NONE
		queue_redraw()
		return
	var finish_point_edit := dragging_point != -1
	var point_order: Array[EasingCurvePoint] = []
	if finish_point_edit and dragging_control == ControlIndex.NONE:
		var dragged_point := _curve.points[dragging_point]
		point_order = _get_display_points()
		selected_index = point_order.find(dragged_point)
	dragging_point = -1
	dragging_control = ControlIndex.NONE
	if finish_point_edit:
		point_edit_finished.emit(point_order)
	queue_redraw()


func _request_point_property_change(index: int, property_name: StringName, value: Variant, changing: bool = false) -> void:
	if point_property_change_requested.has_connections():
		point_property_change_requested.emit(index, property_name, value, changing)
	else:
		_curve.set_point_property(index, property_name, value)


func _request_point_add(point: EasingCurvePoint) -> void:
	if point_add_requested.has_connections():
		point_add_requested.emit(point)
	else:
		EASING_CURVE_EDITOR_UNDO.apply_action(
			editor_undo_redo,
			_curve,
			"Add Easing Curve Point",
			_curve.add_point.bind(point),
		)


func _request_point_remove(point: EasingCurvePoint) -> void:
	if point_remove_requested.has_connections():
		point_remove_requested.emit(point)
	else:
		EASING_CURVE_EDITOR_UNDO.apply_action(
			editor_undo_redo,
			_curve,
			"Remove Easing Curve Point",
			_curve.remove_point.bind(point),
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

	var point := _curve.points[point_idx]
	_right_delete_requires_exit = true
	_right_delete_blocked_position = get_view_pos(point.position)
	_store_right_delete_drag_state()

	if selected_index == point_idx:
		selected_index = -1
	elif selected_index > point_idx:
		selected_index -= 1

	_request_point_remove(point)
	queue_redraw()
	return true


func _set_right_delete_dragging(enabled: bool) -> void:
	is_right_delete_dragging = enabled
	if not enabled:
		_right_delete_requires_exit = false
		_right_delete_blocked_position = Vector2.ZERO
		if _curve != null:
			_right_delete_drag_state_by_curve.erase(_curve.get_instance_id())
		return
	_store_right_delete_drag_state()


func _store_right_delete_drag_state() -> void:
	if _curve == null or not is_right_delete_dragging:
		return
	_right_delete_drag_state_by_curve[_curve.get_instance_id()] = {
		"requires_exit": _right_delete_requires_exit,
		"blocked_position": _right_delete_blocked_position,
	}


func _restore_right_delete_drag_state() -> void:
	if _curve == null:
		return

	var curve_id := _curve.get_instance_id()
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
	if _curve == null:
		return

	update_view_transform()

	# --- Draw Grid ---
	var grid_color_primary: Color = Color(0.3, 0.3, 0.3, 0.8)
	var grid_color: Color = Color(0.2, 0.2, 0.2, 0.3)

	var grid_steps: Vector2 = Vector2i(4, 2)
	var step_size: Vector2 = Vector2(1, (_curve.max_value - _curve.min_value)) / grid_steps

	# Primary borders
	draw_line(
		get_view_pos(Vector2(MIN_X, _curve.min_value)),
		get_view_pos(Vector2(MAX_X, _curve.min_value)),
		grid_color_primary,
	)
	draw_line(
		get_view_pos(Vector2(MAX_X, _curve.max_value)),
		get_view_pos(Vector2(MIN_X, _curve.max_value)),
		grid_color_primary,
	)
	draw_line(
		get_view_pos(Vector2(MIN_X, _curve.min_value)),
		get_view_pos(Vector2(MIN_X, _curve.max_value)),
		grid_color_primary,
	)
	draw_line(
		get_view_pos(Vector2(MAX_X, _curve.min_value)),
		get_view_pos(Vector2(MAX_X, _curve.max_value)),
		grid_color_primary,
	)

	# Internal grid
	for i in range(1, grid_steps.x):
		var x = MIN_X + i * step_size.x
		draw_line(
			get_view_pos(Vector2(x, _curve.min_value)),
			get_view_pos(Vector2(x, _curve.max_value)),
			grid_color,
		)
	for i in range(1, grid_steps.y):
		var y = _curve.min_value + i * step_size.y
		draw_line(
			get_view_pos(Vector2(MIN_X, y)),
			get_view_pos(Vector2(MAX_X, y)),
			grid_color,
		)

	# --- Draw function instead of bezier curve ---
	if _curve.curve_mode == EasingCurve.CurveMode.FUNCTION:
		_draw_function_curve()

	var display_points := _get_display_points()

	# --- Draw curve using the same X-to-Y evaluation as EasingCurve.sample() ---
	if _curve.curve_mode != EasingCurve.CurveMode.FUNCTION:
		_draw_bezier_curve(display_points)

	# --- Draw points and control points ---
	for i in range(display_points.size()):
		var p := display_points[i]
		var pos_view = get_view_pos(p.position)

		var is_selected := p == pending_add_point or (
			selected_index >= 0
			and selected_index < _curve.points.size()
			and p == _curve.points[selected_index]
		)
		var is_hovered := (
			hovered_index >= 0
			and hovered_index < _curve.points.size()
			and p == _curve.points[hovered_index]
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
			var left_view = get_view_pos(p.left_control_point)

			var left_hovered = (
				is_hovered and
				hovered_control_index == ControlIndex.LEFT
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
			var right_view = get_view_pos(p.right_control_point)

			var right_hovered = (
				is_hovered and
				hovered_control_index == ControlIndex.RIGHT
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


func set_curve(easing_curve: EasingCurve):
	if _curve != easing_curve:
		if _curve != null:
			_curve.changed.disconnect(_on_curve_changed)

		_curve = easing_curve

		if _curve != null:
			_curve.changed.connect(_on_curve_changed)

			selected_index = _selected_index_by_curve.get(
				_curve.get_instance_id(),
				-1,
			)
			_restore_right_delete_drag_state()
		else:
			selected_index = -1

		queue_redraw()


func get_curve() -> EasingCurve:
	return _curve


func select_point(point: EasingCurvePoint) -> bool:
	if _curve == null:
		return false
	var point_index := _curve.points.find(point)
	if point_index == -1:
		return false
	selected_index = point_index
	return true


func update_view_transform() -> void:
	var margin := 4.0 * _editor_scale
	var toolbar_height := (
		0.0
		if hide_point_toolbar_for_functions
		and _curve != null
		and _curve.curve_mode == EasingCurve.CurveMode.FUNCTION
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
	if _curve == null:
		return -1

	var closest_idx = -1
	var closest_dist_squared: float = point_radius * point_radius * 4
	for i in range(_curve.points.size()):
		var p = _curve.points[i]
		var view_p = get_view_pos(p.position)
		var dist_sq = view_p.distance_squared_to(pos)
		if dist_sq < closest_dist_squared:
			closest_dist_squared = dist_sq
			closest_idx = i
	return closest_idx if closest_dist_squared < point_radius * point_radius else -1


# =========================
# CONTROL POINT FILTERING
# =========================
# Only allow valid control points
func get_control_at(pos: Vector2) -> Array: # [point_index, ControlIndex]
	if _curve == null:
		return [-1, ControlIndex.NONE]

	for i in range(_curve.points.size()):
		var p = _curve.points[i]

		# LEFT (only if not first and not locked)
		if (
			i != 0
			and not p.is_control_force_linear_active(
				EasingCurvePoint.ControlSide.LEFT
			)
		):
			var left_view = get_view_pos(p.left_control_point)
			if left_view.distance_squared_to(pos) < control_hover_radius * control_hover_radius:
				return [i, ControlIndex.LEFT]

		# RIGHT (only if not last and not locked)
		if (
			i != _curve.points.size() - 1
			and not p.is_control_force_linear_active(
				EasingCurvePoint.ControlSide.RIGHT
			)
		):
			var right_view = get_view_pos(p.right_control_point)
			if right_view.distance_squared_to(pos) < control_hover_radius * control_hover_radius:
				return [i, ControlIndex.RIGHT]

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
	set_slider_value(DEFAULT_SLIDER_VALUE)
	pan_offset = Vector2.ZERO
	pan_changed.emit(pan_offset)
	queue_redraw()


func _on_slider_changed(value: float) -> void:
	_zoom_step = int(value)
	_apply_zoom_from_step()


func _apply_zoom_from_step():
	var zoom := step_to_zoom(_zoom_step)
	_zoom_x = zoom
	_zoom_y = zoom
	_curve._last_slider_value = _zoom_step
	_slider.slider.value = _zoom_step
	queue_redraw()
	zoom_changed.emit(Vector2(zoom, zoom))


func _on_curve_changed() -> void:
	var point_count := _curve.points.size() if _curve != null else 0
	if selected_index >= point_count:
		selected_index = -1
		selected_control_index = ControlIndex.NONE
	if hovered_index >= point_count:
		hovered_index = -1
		hovered_control_index = ControlIndex.NONE
	if dragging_point >= point_count:
		dragging_point = -1
		dragging_control = ControlIndex.NONE
	_update_point_toolbar()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var graph_height := maxf(
		MIN_GRAPH_HEIGHT,
		size.x * ASPECT_RATIO,
	)

	return Vector2(
		64.0,
		graph_height + SELECTION_TOOLBAR_HEIGHT,
	) * _editor_scale


func _get_display_points() -> Array[EasingCurvePoint]:
	var display_points: Array[EasingCurvePoint] = _curve.points.duplicate()
	var active_point: EasingCurvePoint

	if pending_add_point != null or (
		dragging_point != -1
		and dragging_control == ControlIndex.NONE
	) or position_x_order_preview_point != null:
		if pending_add_point != null:
			display_points.append(pending_add_point)
			active_point = pending_add_point
		elif dragging_point != -1 and dragging_control == ControlIndex.NONE:
			active_point = _curve.points[dragging_point]
		else:
			active_point = position_x_order_preview_point
		return EasingCurve.build_ordered_points_with_endpoint_takeover(
			display_points,
			active_point,
		)

	return display_points


func _set_position_x_order_preview(point: EasingCurvePoint) -> void:
	position_x_order_preview_point = point
	queue_redraw()


func _clear_position_x_order_preview() -> void:
	position_x_order_preview_point = null
	queue_redraw()


func _draw_bezier_curve(point_list: Array[EasingCurvePoint]) -> void:
	var fallback_y := EasingCurve.get_bezier_fallback_value(0.0)
	if point_list.size() < 2:
		draw_line(
			get_view_pos(Vector2(0.0, fallback_y)),
			get_view_pos(Vector2(1.0, fallback_y)),
			LINE_COLOR,
			2,
		)
		return

	var first_point: EasingCurvePoint = point_list.front()
	var last_point: EasingCurvePoint = point_list.back()

	if not EasingCurve.is_left_endpoint_x(first_point.position.x):
		draw_line(
			get_view_pos(Vector2(0.0, fallback_y)),
			get_view_pos(Vector2(first_point.position.x, fallback_y)),
			LINE_COLOR,
			2,
		)
		draw_line(
			get_view_pos(Vector2(first_point.position.x, fallback_y)),
			get_view_pos(first_point.position),
			LINE_COLOR,
			2,
		)

	for i in range(point_list.size() - 1):
		_draw_bezier_segment(point_list[i], point_list[i + 1], 0.0, 1.0)

	if not EasingCurve.is_right_endpoint_x(last_point.position.x):
		draw_line(
			get_view_pos(last_point.position),
			get_view_pos(Vector2(last_point.position.x, fallback_y)),
			LINE_COLOR,
			2,
		)
		draw_line(
			get_view_pos(Vector2(last_point.position.x, fallback_y)),
			get_view_pos(Vector2(1.0, fallback_y)),
			LINE_COLOR,
			2,
		)


func _draw_bezier_segment(
		a: EasingCurvePoint,
		b: EasingCurvePoint,
		visible_min_x: float,
		visible_max_x: float,
) -> void:
	var segment_width := b.position.x - a.position.x
	if absf(segment_width) <= EasingCurve.SEGMENT_X_EPSILON:
		if a.position.x >= visible_min_x and a.position.x <= visible_max_x:
			draw_line(get_view_pos(a.position), get_view_pos(b.position), LINE_COLOR, 2)
		return

	var segment_min_x := minf(a.position.x, b.position.x)
	var segment_max_x := maxf(a.position.x, b.position.x)
	var start_x := maxf(segment_min_x, visible_min_x)
	var end_x := minf(segment_max_x, visible_max_x)
	if start_x > end_x:
		return

	var start_view_x := get_view_pos(Vector2(start_x, 0.0)).x
	var end_view_x := get_view_pos(Vector2(end_x, 0.0)).x
	var steps := max(1, ceili(absf(end_view_x - start_view_x)))
	var previous := Vector2.ZERO

	for i in range(steps + 1):
		var x := lerpf(start_x, end_x, i / float(steps))
		var y := (
			a.position.y
			if i == 0 and is_equal_approx(x, a.position.x)
			else b.position.y
			if i == steps and is_equal_approx(x, b.position.x)
			else EasingCurve.sample_bezier_segment(a, b, x)
		)
		var current := get_view_pos(Vector2(x, y))
		if i > 0:
			draw_line(previous, current, LINE_COLOR, 2)
		previous = current


func _draw_function_curve():
	var steps := 120
	var prev: Vector2

	for i in range(steps + 1):
		var x = float(i) / steps
		var y = _curve.sample(x)
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

	_point_toolbar_panel.add_child(_point_toolbar)

	_point_label = Label.new()
	_point_label.text = "No Selection"
	_point_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_point_toolbar.add_child(_point_label)
	_reserve_point_toolbar_label_column_width()

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
	_point_reset_button.icon = RELOAD_ICON
	_point_reset_button.flat = true
	_point_reset_button.tooltip_text = "Reset Point Options"
	_point_reset_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_point_reset_button.pressed.connect(_on_point_toolbar_reset_pressed)
	_point_toolbar.add_child(_point_reset_button)
	_set_point_toolbar_reset_available(false)


func _reserve_point_toolbar_label_column_width() -> void:
	var original_text := _point_label.text
	var label_column_width := 0.0

	for label_text in ["Ease", "Trans"]:
		_point_label.text = label_text
		label_column_width = maxf(
			label_column_width,
			_point_label.get_combined_minimum_size().x,
		)

	_point_label.text = original_text
	_point_label.custom_minimum_size.x = label_column_width


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

	var hide_toolbar := (
		hide_point_toolbar_for_functions
		and _curve != null
		and _curve.curve_mode == EasingCurve.CurveMode.FUNCTION
	)
	_point_toolbar_panel.visible = not hide_toolbar

	if hide_toolbar:
		return

	var valid_selection := (
		_curve != null
		and selected_index >= 0
		and selected_index < _curve.points.size()
	)

	_point_toolbar.visible = true

	if not valid_selection:
		_point_label.text = (
			""
			if _curve != null
			and _curve.curve_mode == EasingCurve.CurveMode.FUNCTION
			else "No Selection"
		)
		_point_label.modulate.a = 0.6
		_point_handle_mode.visible = false
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

	var point := _curve.points[selected_index]

	_point_label.text = "P%d" % selected_index
	_point_label.modulate.a = 1.0
	_point_handle_mode.visible = true

	_updating_point_toolbar = true

	for index in range(_point_handle_mode.item_count):
		if (
			_point_handle_mode.get_item_id(index)
			== point.handle_mode
		):
			_point_handle_mode.select(index)
			break

	_update_point_toolbar_control_state(
		point,
		EasingCurvePoint.ControlSide.LEFT,
		selected_index > 0 and point.supports_control_state(),
	)
	_update_point_toolbar_control_state(
		point,
		EasingCurvePoint.ControlSide.RIGHT,
		selected_index < _curve.points.size() - 1 and point.supports_control_state(),
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


func _point_toolbar_options_are_default(point: EasingCurvePoint) -> bool:
	return (
		point.handle_mode == EasingCurvePoint.HandleMode.FREE
		and not point.left_force_linear
		and not point.right_force_linear
		and not point.locked.get(&"left_control_point", false)
		and not point.locked.get(&"right_control_point", false)
	)


func _update_point_toolbar_control_state(
	point: EasingCurvePoint,
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
	var control_state := _get_point_toolbar_control_state(point, side)
	for index in range(option.item_count):
		if option.get_item_id(index) == control_state:
			option.select(index)
			break


func _get_point_toolbar_control_state(
	point: EasingCurvePoint,
	side: EasingCurvePoint.ControlSide,
) -> EasingCurvePoint.ControlState:
	if point.handle_mode == EasingCurvePoint.HandleMode.LINKED:
		if (
			point.locked.get(&"left_control_point", false)
			or point.locked.get(&"right_control_point", false)
		):
			return EasingCurvePoint.ControlState.LOCKED
		if point.is_control_force_linear_active(side):
			return EasingCurvePoint.ControlState.LINEAR
		return EasingCurvePoint.ControlState.FREE

	var lock_property := (
		&"left_control_point"
		if side == EasingCurvePoint.ControlSide.LEFT
		else &"right_control_point"
	)
	if point.locked.get(lock_property, false):
		return EasingCurvePoint.ControlState.LOCKED
	if point.is_control_force_linear_active(side):
		return EasingCurvePoint.ControlState.LINEAR
	return EasingCurvePoint.ControlState.FREE


func _on_point_toolbar_handle_mode_selected(index: int) -> void:
	if _updating_point_toolbar:
		return

	if (
		_curve == null
		or selected_index < 0
		or selected_index >= _curve.points.size()
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
		_curve == null
		or selected_index < 0
		or selected_index >= _curve.points.size()
	):
		return

	var property_name := (
		&"left_control_state"
		if side == EasingCurvePoint.ControlSide.LEFT
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
		_curve == null
		or selected_index < 0
		or selected_index >= _curve.points.size()
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

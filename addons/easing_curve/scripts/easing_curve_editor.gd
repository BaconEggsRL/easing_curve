@tool
class_name EasingCurveEditor
extends Control
## Easing Curve Editor
##
## Main script for editing the EasingCurve resource.
## More info here to come.

const SELECTION_TOOLBAR_HEIGHT := 32.0
var _drag_auto_range := Vector2.ZERO
var _has_drag_auto_range := false

var use_pending_add := false

static var _selected_index_by_curve: Dictionary[int, int] = {}

signal point_changed
signal point_property_change_requested(index: int, property_name: StringName, value: Variant, changing: bool)
signal point_add_requested(point: EasingCurvePoint)
signal point_remove_requested(point: EasingCurvePoint)
signal point_edit_finished
signal slider_changed
signal zoom_changed
signal pan_changed

enum GrabMode { NONE, ADD, MOVE }
enum ControlIndex { NONE = -1, LEFT = 0, RIGHT = 1 }

const ZOOM_SLIDER_CONTAINER = preload("uid://r1ymwr6nae")
const EASING_CURVE_EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")
const ZOOM_MIN := 0.1
const ZOOM_MAX := 10.0
const ZOOM_FACTOR := 1.2 # same as wheel multiplier
const ZOOM_STEPS := int(round(log(ZOOM_MAX / ZOOM_MIN) / log(ZOOM_FACTOR)))
const DEFAULT_SLIDER_VALUE := floor(ZOOM_STEPS / 2.0)
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

var _point_toolbar_panel: PanelContainer
var _point_toolbar: HBoxContainer
var _point_label: Label
var _point_handle_mode: OptionButton
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
		# _curve.range_changed.connect(_on_curve_changed)
		_curve.changed.connect(_on_curve_changed)

	_create_point_toolbar()
	_update_point_toolbar()


# =========================
# GUI INPUT (DRAGGING)
# =========================
func _gui_input(event: InputEvent) -> void:
	if _curve == null:
		return

	# Middle mouse pressed → start panning
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_panning = true
				last_mouse_pos = event.position
				get_viewport().set_input_as_handled() # stop editor from stealing input
			else:
				is_panning = false
				get_viewport().set_input_as_handled()
	# Mouse motion → pan
	elif event is InputEventMouseMotion and is_panning:
		var delta = event.position - last_mouse_pos
		pan_offset += delta
		last_mouse_pos = event.position
		# _user_panned = true
		queue_redraw()
		get_viewport().set_input_as_handled()
		pan_changed.emit(pan_offset)

	# =========================
	# MOUSE MOTION (drag points/controls)
	# =========================
	if event is InputEventMouseMotion:
		if _curve.curve_mode == EasingCurve.CurveMode.FUNCTION:
			return

		# ----- DRAGGING -----
		if dragging_point != -1:
			var p = _curve.points[dragging_point]
			if dragging_control != ControlIndex.NONE:
				p.set_handle_display_scale(
					get_world_to_view_scale()
				)
			var world_pos = get_world_pos(event.position)

			if not world_pos.is_finite():
				return

			# Block main point movement
			if dragging_control == ControlIndex.NONE and p.is_lock_active(&"position"):
				return

			# Block left control
			if dragging_control == ControlIndex.LEFT and p.is_lock_active(&"left_control_point"):
				return

			# Block right control
			if dragging_control == ControlIndex.RIGHT and p.is_lock_active(&"right_control_point"):
				return

			match dragging_control:
				ControlIndex.LEFT:
					if dragging_point != 0: # ignore left control for first point
						_request_point_property_change(dragging_point, &"left_control_point", world_pos, true)
				ControlIndex.RIGHT:
					if dragging_point != _curve.points.size() - 1: # ignore right control for last point
						_request_point_property_change(dragging_point, &"right_control_point", world_pos, true)
				ControlIndex.NONE: # dragging main point
					var clamped_pos = world_pos.clamp(Vector2(0, _curve.min_value), Vector2(1.0, _curve.max_value))

					var delta = clamped_pos - p.position
					var left_control: Vector2 = p.left_control_point
					var right_control: Vector2 = p.right_control_point
					_request_point_property_change(dragging_point, &"position", clamped_pos, true)

					# Only move controls if they are NOT locked
					if not p.is_lock_active(&"left_control_point"):
						_request_point_property_change(dragging_point, &"left_control_point", left_control + delta, true)

					if not p.is_lock_active(&"right_control_point"):
						_request_point_property_change(dragging_point, &"right_control_point", right_control + delta, true)

			point_changed.emit(dragging_point, p)
			queue_redraw()

		# ----- HOVER DETECTION -----
		if dragging_point == -1:
			var control = get_control_at(event.position)

			if control[0] != -1:
				hovered_index = control[0]
				hovered_control_index = control[1]
			else:
				hovered_control_index = ControlIndex.NONE
				hovered_index = get_point_at(event.position)

			queue_redraw()

			# Cursor feedback
			if hovered_control_index != ControlIndex.NONE:
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			elif hovered_index != -1:
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			else:
				mouse_default_cursor_shape = Control.CURSOR_ARROW

	# =========================
	# MOUSE BUTTONS
	# =========================
	if event is InputEventMouseButton:
		# --- Mouse Wheel Zoom ---
		if (
			event.pressed
			and event.button_index == MOUSE_BUTTON_WHEEL_UP
		):
			_zoom_at_view_pos(1, event.position)
			accept_event()
			return

		elif (
			event.pressed
			and event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			_zoom_at_view_pos(-1, event.position)
			accept_event()
			return

		if _curve.curve_mode == EasingCurve.CurveMode.FUNCTION:
			return

		# --- LEFT CLICK ---
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var control = get_control_at(event.position)
			var point_idx = get_point_at(event.position)

			if (
				control[0] != -1
				and _curve.points[control[0]].handle_mode
					== EasingCurvePoint.HandleMode.LINEAR
			):
				point_idx = control[0]
				control = [-1, ControlIndex.NONE]

			# --- If we hit a control ---
			if control[0] != -1:
				var p = _curve.points[control[0]]
				var can_drag_control := false

				match control[1]:
					ControlIndex.LEFT:
						can_drag_control = not p.is_lock_active(&"left_control_point")
					ControlIndex.RIGHT:
						can_drag_control = not p.is_lock_active(&"right_control_point")

				# Always select the point
				selected_index = control[0]

				# Only allow dragging if the control is not locked
				if can_drag_control:
					dragging_point = control[0]
					dragging_control = control[1]
					_drag_auto_range = _compute_auto_y_range()
					_has_drag_auto_range = true
				else:
					# Try dragging main point if under cursor
					if point_idx != -1 and not _curve.points[point_idx].is_lock_active(&"position"):
						dragging_point = point_idx
						dragging_control = ControlIndex.NONE

				queue_redraw()
				return

			# --- If we hit only a main point ---
			if point_idx != -1:
				var p = _curve.points[point_idx]
				if not p.is_lock_active(&"position"):
					dragging_point = point_idx
					dragging_control = ControlIndex.NONE
					_drag_auto_range = _compute_auto_y_range()
					_has_drag_auto_range = true
				selected_index = point_idx
				queue_redraw()
				return


			# --- If we hit nothing, add a new point ---
			var world_pos := get_world_pos(event.position)

			if not world_pos.is_finite():
				return

			var clamped_pos := world_pos.clamp(
				Vector2(0, _curve.min_value),
				Vector2(1.0, _curve.max_value),
			)

			if use_pending_add:
				var new_point := EasingCurvePoint.new()

				new_point.position = clamped_pos
				new_point.left_control_point = (
					clamped_pos + Vector2(-0.1, 0.0)
				)
				new_point.right_control_point = (
					clamped_pos + Vector2(0.1, 0.0)
				)

				_request_point_add(new_point)

				selected_index = -1

				for i in range(_curve.points.size()):
					if _curve.points[i].position == clamped_pos:
						selected_index = i
						break

				if selected_index != -1:
					dragging_point = selected_index
					dragging_control = ControlIndex.NONE
					_drag_auto_range = _compute_auto_y_range()
					_has_drag_auto_range = true

				queue_redraw()
				accept_event()
				return

			var new_point := EasingCurvePoint.new()

			new_point.position = clamped_pos
			new_point.left_control_point = (
				clamped_pos + Vector2(-0.1, 0.0)
			)
			new_point.right_control_point = (
				clamped_pos + Vector2(0.1, 0.0)
			)

			_request_point_add(new_point)

			selected_index = -1

			for i in range(_curve.points.size()):
				if _curve.points[i].position == clamped_pos:
					selected_index = i
					break

			if selected_index != -1:
				dragging_point = selected_index
				dragging_control = ControlIndex.NONE
				_drag_auto_range = _compute_auto_y_range()
				_has_drag_auto_range = true

			queue_redraw()
			return


		# --- RIGHT CLICK ---
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:

			var point_idx = get_point_at(event.position)

			if point_idx != -1:
				_request_point_remove(_curve.points[point_idx])

				if selected_index == point_idx:
					selected_index = -1
				elif selected_index > point_idx:
					selected_index -= 1

				queue_redraw()
				return

			# Right-clicking empty graph space clears the point selection.
			selected_index = -1
			selected_control_index = ControlIndex.NONE
			queue_redraw()
			return


		# Reset dragging state only when left mouse button is released.
		elif (
			not event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		):

			if dragging_point != -1:
				point_edit_finished.emit()

			dragging_point = -1
			dragging_control = ControlIndex.NONE

			_has_drag_auto_range = false
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

	# --- Draw curve segments ---
	for i in range(_curve.points.size() - 1):
		var a = _curve.points[i]
		var b = _curve.points[i + 1]
		_draw_bezier_segment(a, b)

	# --- Draw points and control points ---
	for i in range(_curve.points.size()):
		var p = _curve.points[i]
		var pos_view = get_view_pos(p.position)

		# var is_selected = (i == selected_index)
		var is_hovered = (i == hovered_index)

		# Slightly dim when not selected/hovered
		var alpha := 1.0 if (is_hovered) else 0.5

		# ----- Colors -----
		var point_color = Color(1, 0.5, 0, alpha) if i == selected_index else Color(1, 0, 0, alpha)

		# ----- Main Point -----
		draw_circle(pos_view, point_radius, point_color)

		# ----- Control Points -----
		# LEFT
		if i != 0:
			var left_view = get_view_pos(p.left_control_point)

			var left_hovered = (
				i == hovered_index and
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
		if i != _curve.points.size() - 1:
			var right_view = get_view_pos(p.right_control_point)

			var right_hovered = (
				i == hovered_index and
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
	# print("_slider = ", _slider)

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
		else:
			selected_index = -1

		queue_redraw()


func get_curve() -> EasingCurve:
	return _curve


func update_view_transform() -> void:
	var margin := 4.0 * _editor_scale
	var toolbar_height := SELECTION_TOOLBAR_HEIGHT * _editor_scale

	# Auto range looks kinda bad; turning off for now
	#var auto_range = _compute_auto_y_range()
	var auto_range := Vector2(0.0, 1.0)
	#var auto_range := (
		#_drag_auto_range
		#if _has_drag_auto_range
		#else _compute_auto_y_range()
	#)

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
	# print("slider changed to: ", value)
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


func _draw_bezier_segment(a: EasingCurvePoint, b: EasingCurvePoint) -> void:
	var steps = 20
	var prev = get_view_pos(a.position)
	for j in range(1, steps + 1):
		var t = j / float(steps)
		var pt = _bezier(a.position, a.right_control_point, b.left_control_point, b.position, t)
		var pt_view = get_view_pos(pt)
		draw_line(prev, pt_view, LINE_COLOR, 2)
		prev = pt_view


func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var omt = 1.0 - t
	return omt * omt * omt * p0 + 3 * omt * omt * t * p1 + 3 * omt * t * t * p2 + t * t * t * p3


func _compute_auto_y_range() -> Vector2:
	if _curve.curve_mode == EasingCurve.CurveMode.FUNCTION:
		var min_y := 0.0
		var max_y := 1.0
		var steps := 200

		for i in range(steps + 1):
			var x = float(i) / steps
			var y = _curve.sample(x)
			min_y = min(min_y, y)
			max_y = max(max_y, y)

		var padding := (max_y - min_y) * 0.1
		return Vector2(min_y - padding, max_y + padding)

	if _curve == null or _curve.points.size() < 2:
		return Vector2(0.0, 1.0)

	var min_y := 0.0
	var max_y := 1.0

	var steps := 40

	for i in range(_curve.points.size() - 1):
		var a = _curve.points[i]
		var b = _curve.points[i + 1]

		for j in range(steps + 1):
			var t = j / float(steps)
			var pt = _bezier(
				a.position,
				a.right_control_point,
				b.left_control_point,
				b.position,
				t,
			)

			# Expand only if overshooting
			if pt.y < min_y:
				min_y = pt.y
			elif pt.y > max_y:
				max_y = pt.y

	# If still inside [0,1], keep default range
	if min_y >= 0.0 and max_y <= 1.0:
		min_y = 0.0
		max_y = 1.0

	# Add padding
	var padding := (max_y - min_y) * 0.1
	min_y -= padding
	max_y += padding

	return Vector2(min_y, max_y)


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
	_point_toolbar_panel = PanelContainer.new()
	_point_toolbar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_point_toolbar_panel.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_WIDE
	)

	_point_toolbar_panel.custom_minimum_size.y = (
		SELECTION_TOOLBAR_HEIGHT * _editor_scale
	)

	add_child(_point_toolbar_panel)

	_point_toolbar = HBoxContainer.new()
	_point_toolbar.alignment = BoxContainer.ALIGNMENT_BEGIN
	_point_toolbar.add_theme_constant_override(
		"separation",
		int(6 * _editor_scale),
	)

	_point_toolbar_panel.add_child(_point_toolbar)

	_point_label = Label.new()
	_point_label.text = "No Selection"
	_point_toolbar.add_child(_point_label)

	_point_handle_mode = OptionButton.new()
	_point_handle_mode.fit_to_longest_item = false

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

	_point_toolbar.add_child(_point_handle_mode)




func _update_point_toolbar() -> void:
	if _point_toolbar == null:
		return

	var valid_selection := (
		_curve != null
		and selected_index >= 0
		and selected_index < _curve.points.size()
	)

	_point_toolbar.visible = true

	if not valid_selection:
		_point_label.text = "No Selection"
		_point_label.modulate.a = 0.6
		_point_handle_mode.visible = false
		return

	var point := _curve.points[selected_index]

	_point_label.text = "Point %d" % selected_index
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

	_updating_point_toolbar = false


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


func get_world_to_view_scale() -> Vector2:
	return Vector2(
		_world_to_view.x.length(),
		_world_to_view.y.length()
	)

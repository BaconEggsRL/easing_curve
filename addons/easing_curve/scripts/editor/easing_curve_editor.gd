@tool
class_name EasingCurveEditor
extends Control
## Easing Curve Editor
##
## Graph editor for interactive EasingCurve point and control-handle editing.

const SELECTION_TOOLBAR_HEIGHT := 32.0
const SNAP_TOOLBAR_HEIGHT := 32.0
const CONTROL_ROW_INSET := 8.0
const SNAP_ENABLED_META := &"_easing_curve_snap_enabled"
const SNAP_COUNT_META := &"_easing_curve_snap_count"
const EDITOR_THEME_CACHE = preload(
	"res://addons/easing_curve/scripts/editor/inspector/editor_theme_cache.gd"
)
const BEZIER_SOLVER = preload(
	"res://addons/easing_curve/scripts/runtime/bezier_solver.gd"
)
const BackendFactory := preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_editor_backend_factory.gd"
)
const CurveEditorSettings := preload(
	"res://addons/easing_curve/scripts/editor/curve_editor_settings.gd"
)


# The field's native minimum must not become an Inspector width requirement.
class PointToolbarOptionSlot:
	extends Container

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL


	func _get_minimum_size() -> Vector2:
		if get_child_count() == 0:
			return Vector2.ZERO
		return Vector2(0.0, get_child(0).get_combined_minimum_size().y)


	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN and get_child_count():
			fit_child_in_rect(get_child(0), Rect2(Vector2.ZERO, size))


enum ControlsLayout { CURRENT_TWO_ROW, COMPACT_TWO_ROW, DEV_SINGLE_ROW }

# Reopen the curve Inspector after changing the layout.
var controls_layout: ControlsLayout = ControlsLayout.DEV_SINGLE_ROW
# COMPACT_TWO_ROW only. Reset buttons retain their reserved space in visible rows.
var hide_unused_controls := true

var use_pending_add := true
# True: hide point controls and snapping in Function mode.
# False: show those rows with point-only controls inactive.
var hide_selection_toolbar_for_functions := true
# True: reorder through the Inspector. False: change graph selection only.
var point_move_buttons_reorder_points := false
# Hide the viewport borders, ticks, and labels; keep the world-space reference box.
@export var hide_graph_background := true:
	set(value):
		hide_graph_background = value
		queue_redraw()

static var _selected_index_by_curve: Dictionary[int, int] = {}
static var _right_delete_drag_state_by_curve: Dictionary[int, Dictionary] = {}

signal point_changed
signal point_property_change_requested(index: int, property_name: StringName, value: Variant, changing: bool)
signal point_add_requested(point: EasingCurvePoint)
signal point_remove_requested(point: EasingCurvePoint)
signal point_move_up_requested(index: int)
signal point_move_down_requested(index: int)
signal point_swap_requested(point: Resource, offset: int)
signal point_edit_finished(point_order: Array[EasingCurvePoint])
signal point_edit_cancelled
signal point_selection_changed(point: Resource)
signal default_new_point_handle_mode_changed(handle_mode: int)
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
const PREFERRED_GRAPH_HEIGHT := 180.0
const GRAPH_EDGE_PADDING := 4.0
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
const GRAPH_GRID_DIVISIONS := Vector2i(4, 2)

var presentation_owned := false
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
		if resource != null and not presentation_owned:
			_selected_index_by_curve[resource.get_instance_id()] = value
		_update_point_toolbar()
		queue_redraw()
		point_selection_changed.emit(_selected_point_resource())

var hovered_index: int = -1
var selected_control_index: ControlIndex = ControlIndex.NONE
var hovered_control_index: ControlIndex = ControlIndex.NONE

var dragging_point: int = -1
var dragging_control: ControlIndex = ControlIndex.NONE
var _drag_coordinates_suppressed := true
var _point_list_coordinate_input: WeakRef
var _point_list_coordinate_point: WeakRef
var _point_list_coordinate_property := StringName()
var pending_add_point: Resource
var position_x_order_preview_point: Resource
var is_right_delete_dragging := false
var _right_delete_requires_exit := false
var _right_delete_blocked_position := Vector2.ZERO
var _axis_drag_reference_active := false
var _axis_drag_origin_view := Vector2.ZERO
var _axis_drag_last_cursor := Vector2.ZERO
var _axis_drag_origin_world := Vector2.ZERO
var _drag_existing_point := false

var grabbing: GrabMode = GrabMode.NONE
var initial_grab_pos: Vector2
var initial_grab_index: int
var initial_grab_left_control: Vector2
var initial_grab_right_control: Vector2
var snap_enabled: bool = false:
	set(value):
		snap_enabled = value
		_sync_snap_controls()
var snap_count: int = 10:
	set(value):
		snap_count = clampi(value, 2, 100)
		_sync_snap_controls()
var _snap_button: Button
var _snap_toolbar_margin: MarginContainer
var _snap_count_input: EditorSpinSlider
var _coordinate_readout: Control
var _zoom_x: float = 1.0 # horizontal zoom
var _zoom_y: float = 1.0 # vertical zoom
var _zoom_step := 0
var _curve: EasingCurve
var _backend: RefCounted
var _slider: EasingCurveZoomSliderContainer:
	set = set_slider_container
var _world_to_view: Transform2D
var _editor_scale: float = 1.0
var _layout_queued := false
var _layout: VBoxContainer
var _graph_canvas: Control
var _graph_ink: Control
var _zoom_row: HBoxContainer
var _zoom_row_slider: EasingCurveZoomSliderContainer

var _point_toolbar_panel: VBoxContainer
var _point_toolbar: VBoxContainer
var _point_mode_row: HBoxContainer
var _point_states_row: HBoxContainer
var _point_label: Label
var _point_reorder_buttons: HBoxContainer
var _point_move_left_button: Button
var _point_move_right_button: Button
var _point_left_group: HBoxContainer
var _point_right_group: HBoxContainer
var _point_handle_mode: OptionButton
var _point_left_state_label: Label
var _point_left_state: OptionButton
var _point_right_state_label: Label
var _point_right_state: OptionButton
var _point_reset_button: Button
var _point_states_reset_button: Button
var _updating_point_toolbar := false
var _graph_render_suppressed := false
var _backend_point_edit_active := false
var _backend_point_edit_before: Variant
var _backend_point_edit_action_name := "Edit Easing Curve Point"
var _backend_point_edit_selected_before: Resource
var _backend_point_edit_point: Resource
var _backend_point_edit_property := StringName()
var _backend_point_edit_from_point_list := false
var _default_new_point_handle_mode := EasingCurvePoint.HandleMode.FREE


func _init(layout_override: int = -1) -> void:
	if layout_override in ControlsLayout.values():
		controls_layout = layout_override as ControlsLayout


func _ready() -> void:
	custom_minimum_size = Vector2.ZERO
	# The graph has no keyboard actions. Taking mouse focus makes the outer
	# Inspector ScrollContainer follow the graph when a point or handle is
	# clicked, producing a small and distracting vertical scroll jump.
	focus_mode = Control.FOCUS_NONE
	# Let unmodified wheel events continue to the Inspector ScrollContainer.
	# Intentional graph zoom is accepted explicitly in _handle_wheel().
	mouse_force_pass_scroll_events = true
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if Engine.is_editor_hint():
		_editor_scale = EditorInterface.get_editor_scale()
		CurveEditorSettings.setup()
		var settings := EditorInterface.get_editor_settings()
		if not settings.settings_changed.is_connected(
			_on_editor_settings_changed
		):
			settings.settings_changed.connect(_on_editor_settings_changed)
		_sync_default_new_point_handle_mode()
	update_minimum_size()

	if _backend == null:
		set_curve(EasingCurve.new())

	_ensure_layout()
	_create_point_toolbar()
	_create_snap_toolbar()
	_graph_canvas = Control.new()
	_graph_canvas.name = &"GraphCanvas"
	_graph_canvas.clip_contents = true
	_graph_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_graph_canvas.mouse_force_pass_scroll_events = true
	_layout.add_child(_graph_canvas)
	if _zoom_row != null:
		_layout.move_child(_zoom_row, -1)
	_graph_canvas.gui_input.connect(_on_graph_gui_input)
	_graph_canvas.resized.connect(queue_redraw)
	_layout.sort_children.connect(_on_layout_sorted)
	_graph_ink = Control.new()
	_graph_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph_canvas.add_child(_graph_ink)
	_graph_ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_graph_ink.draw.connect(_draw_graph)
	_coordinate_readout = Control.new()
	_coordinate_readout.name = "DragCoordinates"
	_coordinate_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coordinate_readout.z_index = 1
	_graph_canvas.add_child(_coordinate_readout)
	_coordinate_readout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_coordinate_readout.draw.connect(_draw_drag_coordinates)
	_point_toolbar_panel.sort_children.connect(_coordinate_readout.queue_redraw)
	_point_toolbar_panel.minimum_size_changed.connect(_queue_layout)
	resized.connect(_queue_layout)
	theme_changed.connect(_queue_layout)
	_update_layout()
	_update_point_toolbar()


func _ensure_layout() -> void:
	if _layout != null:
		return
	_layout = VBoxContainer.new()
	_layout.name = &"EditorLayout"
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layout)
	_layout.minimum_size_changed.connect(update_minimum_size)


func _on_layout_sorted() -> void:
	update_view_transform()
	queue_redraw()


func _queue_layout() -> void:
	if _layout_queued or not is_node_ready():
		return
	_layout_queued = true
	_update_layout.call_deferred()


func _update_layout() -> void:
	_layout_queued = false
	if not is_inside_tree():
		return
	if _layout == null or _graph_canvas == null:
		return
	var inset := CONTROL_ROW_INSET * _editor_scale
	_reserve_point_toolbar_label_column_width()
	_reserve_point_toolbar_control_side_label_width()
	_update_point_toolbar_spacing()
	_layout.size.x = size.x
	_graph_canvas.custom_minimum_size.y = _get_graph_size().y + 2.0 * GRAPH_EDGE_PADDING * _editor_scale
	for side: StringName in [&"margin_left", &"margin_right"]:
		if _snap_toolbar_margin.get_theme_constant(side) != roundi(inset):
			_snap_toolbar_margin.add_theme_constant_override(side, roundi(inset))
	update_minimum_size()
	queue_redraw()
	_coordinate_readout.queue_redraw()


func setup_zoom_row() -> void:
	if _zoom_row != null:
		return
	_ensure_layout()
	_zoom_row = HBoxContainer.new()
	_zoom_row.name = &"ZoomRow"
	_zoom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout.add_child(_zoom_row)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = 0.6
	_zoom_row.add_child(spacer)
	_zoom_row_slider = ZOOM_SLIDER_CONTAINER.instantiate() as EasingCurveZoomSliderContainer
	_zoom_row_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_row_slider.size_flags_stretch_ratio = 0.4
	_zoom_row.add_child(_zoom_row_slider)
	set_slider_container(_zoom_row_slider)
	_zoom_row.minimum_size_changed.connect(_queue_layout)
	_queue_layout()
	update_minimum_size()


func _exit_tree() -> void:
	_clear_axis_drag()
	_update_point_navigation_tooltips(true)
	_drag_coordinates_suppressed = true
	finish_active_point_edit()
	if not Engine.is_editor_hint():
		return
	var settings := EditorInterface.get_editor_settings()
	if settings == null:
		return
	if settings.settings_changed.is_connected(_on_editor_settings_changed):
		settings.settings_changed.disconnect(_on_editor_settings_changed)


func get_default_new_point_handle_mode() -> int:
	return _default_new_point_handle_mode


func set_default_new_point_handle_mode(handle_mode: int) -> void:
	CurveEditorSettings.set_default_new_point_handle_mode(handle_mode)
	_sync_default_new_point_handle_mode()


func _on_editor_settings_changed() -> void:
	_sync_default_new_point_handle_mode()


func _sync_default_new_point_handle_mode() -> void:
	var current := CurveEditorSettings.get_default_new_point_handle_mode()
	if current == _default_new_point_handle_mode:
		return
	_default_new_point_handle_mode = current
	default_new_point_handle_mode_changed.emit(current)


# =========================
# GUI INPUT (DRAGGING)
# =========================
func _on_graph_gui_input(event: InputEvent) -> void:
	var editor_event := event.duplicate() as InputEvent
	if editor_event is InputEventMouse:
		editor_event.position += _graph_canvas.position
	_gui_input(editor_event)


func _input(event: InputEvent) -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	if event is InputEventWithModifiers:
		_update_point_navigation_tooltips()
		if event is InputEventKey:
			_update_axis_drag_reference(Input.is_key_pressed(KEY_SHIFT), get_local_mouse_position())


func _gui_input(event: InputEvent) -> void:
	# The canvas retains mouse capture across sibling controls until release.
	if _backend == null:
		return

	if event is InputEventMouseButton:
		if _handle_mouse_button_prepass(event):
			return

	if event is InputEventMouseMotion:
		_handle_pan_motion(event)
		_handle_mouse_motion(event)
		_axis_drag_last_cursor = event.position
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event)


func _handle_mouse_button_prepass(event: InputEventMouseButton) -> bool:
	if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drag_coordinates_suppressed = true
		queue_redraw()
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
	_update_axis_drag_reference(event.shift_pressed, _axis_drag_last_cursor)
	var world_pos := get_world_pos(event.position)
	if not world_pos.is_finite():
		return
	world_pos = _snap_graph_position(world_pos, event.is_command_or_control_pressed())
	world_pos = _backend.display_to_curve_position(world_pos)
	world_pos = _apply_axis_drag_constraint(event, world_pos)
	var value_range := _value_range()
	var clamped_pos := world_pos.clamp(
		Vector2(0, value_range.x),
		Vector2(1.0, value_range.y),
	)
	pending_add_point.set(&"position", clamped_pos)
	queue_redraw()


func _begin_axis_drag(event: InputEventMouseButton) -> void:
	_drag_existing_point = true
	end_point_list_coordinate_drag()
	_drag_coordinates_suppressed = false
	_clear_axis_drag()
	_axis_drag_last_cursor = event.position
	_update_axis_drag_reference(event.shift_pressed, event.position)


func _update_axis_drag_reference(shift_pressed: bool, cursor_position: Vector2) -> void:
	var point := pending_add_point if pending_add_point != null else _point(dragging_point)
	if not shift_pressed or point == null:
		_clear_axis_drag()
		return
	if _axis_drag_reference_active:
		return
	_axis_drag_origin_view = cursor_position
	var control := ControlIndex.NONE if pending_add_point != null else dragging_control
	match control:
		ControlIndex.LEFT:
			_axis_drag_origin_world = point.get(&"left_control_point")
		ControlIndex.RIGHT:
			_axis_drag_origin_world = point.get(&"right_control_point")
		ControlIndex.NONE:
			_axis_drag_origin_world = point.get(&"position")
	_axis_drag_reference_active = true


func _clear_axis_drag() -> void:
	_axis_drag_reference_active = false
	_axis_drag_origin_view = Vector2.ZERO
	_axis_drag_origin_world = Vector2.ZERO


func _apply_axis_drag_constraint(event: InputEventMouseMotion, world_pos: Vector2) -> Vector2:
	if not event.shift_pressed or not _axis_drag_reference_active:
		return world_pos
	var view_delta := event.position - _axis_drag_origin_view
	if absf(view_delta.x) > absf(view_delta.y):
		world_pos.y = _axis_drag_origin_world.y
	else:
		world_pos.x = _axis_drag_origin_world.x
	return world_pos


func _handle_drag_motion(event: InputEventMouseMotion) -> void:
	_update_axis_drag_reference(event.shift_pressed, _axis_drag_last_cursor)
	var p := _point(dragging_point)
	if p == null:
		return
	if dragging_control != ControlIndex.NONE:
		_backend.prepare_point_control_drag(dragging_point, get_world_to_view_scale())
	var world_pos = get_world_pos(event.position)
	if not world_pos.is_finite():
		return
	if dragging_control == ControlIndex.NONE:
		world_pos = _snap_graph_position(world_pos, event.is_command_or_control_pressed())
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
	if not event.is_command_or_control_pressed():
		return false
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
	end_point_list_coordinate_drag()
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
			_begin_axis_drag(event)
		elif (
			point_idx != -1
			and not _backend.is_point_property_locked(point_idx, &"position")
		):
			dragging_point = point_idx
			dragging_control = ControlIndex.NONE
			_begin_axis_drag(event)
		queue_redraw()
		return
	if point_idx != -1:
		var p := _point(point_idx)
		if not _backend.is_point_property_locked(point_idx, &"position"):
			dragging_point = point_idx
			dragging_control = ControlIndex.NONE
			_begin_axis_drag(event)
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
	world_pos = _snap_graph_position(world_pos, event.is_command_or_control_pressed())
	world_pos = _backend.display_to_curve_position(world_pos)
	var value_range := _value_range()
	var clamped_pos := world_pos.clamp(Vector2(0, value_range.x), Vector2(1.0, value_range.y))
	if use_pending_add:
		pending_add_point = _create_point_with_default_handle_mode(clamped_pos)
		if pending_add_point == null:
			return
		_clear_axis_drag()
		_axis_drag_last_cursor = event.position
		_update_axis_drag_reference(event.shift_pressed, event.position)
		_drag_coordinates_suppressed = false
		queue_redraw()
		accept_event()
		return
	var new_point := _create_point_with_default_handle_mode(clamped_pos)
	if new_point == null:
		return
	var added_index := _request_point_add(new_point)
	if _curve == null or selected_index != added_index:
		selected_index = added_index
	if added_index != -1:
		dragging_point = added_index
		dragging_control = ControlIndex.NONE
		_begin_axis_drag(event)
		_drag_existing_point = false
	queue_redraw()


func _handle_right_pressed(event: InputEventMouseButton) -> void:
	if pending_add_point != null:
		_cancel_pending_add()
		accept_event()
		return
	if dragging_point != -1 and _drag_existing_point:
		_cancel_point_drag()
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


func _cancel_point_drag() -> void:
	var point := _point(dragging_point)
	dragging_point = -1
	dragging_control = ControlIndex.NONE
	position_x_order_preview_point = null
	_drag_coordinates_suppressed = true
	_clear_axis_drag()
	_set_right_delete_dragging(false)
	_drag_existing_point = false
	if _curve != null and point_edit_cancelled.has_connections():
		point_edit_cancelled.emit()
	elif _backend_point_edit_active:
		# Restore the transaction's own snapshot, then finish with no net change.
		_backend.apply_snapshot(_backend_point_edit_before)
		_finish_backend_point_edit()
	selected_index = _backend.find_point(point)
	queue_redraw()


func _handle_left_released() -> void:
	_drag_existing_point = false
	_drag_coordinates_suppressed = true
	if pending_add_point != null:
		var point := pending_add_point
		pending_add_point = null
		var added_index := _request_point_add(point)
		if _curve == null or selected_index != added_index:
			selected_index = added_index
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


func _request_point_property_change(
	index: int,
	property_name: StringName,
	value: Variant,
	changing: bool = false,
	from_point_list: bool = false,
) -> void:
	if point_property_change_requested.has_connections():
		point_property_change_requested.emit(index, property_name, value, changing)
		return
	if _backend == null:
		return
	var edited_point := _point(index)
	if (
		_backend_point_edit_active
		and (
			from_point_list != _backend_point_edit_from_point_list
			or (
				from_point_list
				and (
					edited_point != _backend_point_edit_point
					or property_name != _backend_point_edit_property
				)
			)
		)
	):
		finish_active_point_edit()
	if changing and not _backend_point_edit_active:
		_backend_point_edit_before = _duplicate_snapshot(_backend.capture_snapshot())
		_backend_point_edit_action_name = _point_edit_action_name(property_name)
		_backend_point_edit_selected_before = _selected_point_resource()
		_backend_point_edit_point = edited_point
		_backend_point_edit_property = property_name
		_backend_point_edit_from_point_list = from_point_list
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
	_backend_point_edit_point = null
	_backend_point_edit_property = StringName()
	_backend_point_edit_from_point_list = false
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
		if native_live_edit:
			# Inspector controls are rebuilt when the transition changes.
			editor_undo_redo.add_do_method(_backend, &"apply_editor_snapshot", after, weakref(self), selected_after_id)
			editor_undo_redo.add_undo_method(_backend, &"apply_editor_snapshot", before, weakref(self), selected_before_id)
		else:
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
	_request_point_property_change(index, property_name, value, changing, true)


func edit_curve_property(property_name: StringName, value: Variant) -> void:
	var resource := get_curve()
	if _backend == null or resource == null or resource.get(property_name) == value:
		return
	finish_active_point_edit()
	var before := _duplicate_snapshot(_backend.capture_snapshot())
	var selected_before := _selected_point_resource()
	resource.set(property_name, value)
	var selected_after := (
		selected_before
		if selected_before != null and _backend.find_point(selected_before) >= 0
		else null
	)
	selected_index = (
		_backend.find_point(selected_after)
		if selected_after != null
		else -1
	)
	var after := _duplicate_snapshot(_backend.capture_snapshot())
	if before == after:
		return
	_commit_backend_snapshot_action(
		"Change Easing Curve Ease"
			if property_name == &"ease_type"
			else "Change Easing Curve Transition",
		before,
		after,
		selected_before,
		selected_after,
	)
	queue_redraw()


func finish_point_list_edit(point: Resource, property_name: StringName) -> void:
	if not _backend_point_edit_active or point == null:
		return
	if point != _backend_point_edit_point or property_name != _backend_point_edit_property:
		return
	finish_active_point_edit()


func prepare_point_list_edit(
	point: Resource,
	property_name: StringName,
) -> bool:
	if not _backend_point_edit_active:
		return false
	if (
		_backend_point_edit_from_point_list
		and point == _backend_point_edit_point
		and property_name == _backend_point_edit_property
	):
		return false
	finish_active_point_edit()
	return true


func finish_active_point_edit() -> void:
	if not _backend_point_edit_active:
		return
	var edited_point := _backend_point_edit_point
	if (
		_backend_point_edit_property == &"position"
		and edited_point != null
		and _backend.find_point(edited_point) >= 0
	):
		_backend.apply_point_order(_backend.get_ordered_points(edited_point))
		selected_index = _backend.find_point(edited_point)
	position_x_order_preview_point = null
	_finish_backend_point_edit()
	queue_redraw()


func add_point_from_list() -> Resource:
	var point := create_point_for_list()
	if point == null:
		return null
	_request_point_add(point)
	selected_index = _backend.find_point(point)
	return point


func create_point_for_list() -> Resource:
	return _backend.create_point_for_list(get_default_new_point_handle_mode()) if _backend != null else null

func _create_point_with_default_handle_mode(position: Vector2) -> Resource:
	if _backend == null:
		return null
	var point: Resource = _backend.create_point(position)
	if point == null:
		return null
	if bool(_backend.get_capabilities().get(&"handle_modes", false)):
		point.set(&"handle_mode", get_default_new_point_handle_mode())
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
	finish_active_point_edit()
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


func generate_native_irregular() -> void:
	var resource := get_curve()
	if (
		_backend == null
		or _backend.get_backend_id() != &"native"
		or resource == null
		or not resource.has_method(&"generate_irregular")
	):
		return
	finish_active_point_edit()
	var before := _duplicate_snapshot(_backend.capture_snapshot())
	resource.call(&"generate_irregular")
	var after := _duplicate_snapshot(_backend.capture_snapshot())
	if before == after:
		return
	_commit_backend_snapshot_action("Generate Easing Curve", before, after)
	queue_redraw()


func _has_endpoint_at(x: float) -> bool:
	for point in _points():
		var position: Vector2 = point.get(&"position")
		if is_equal_approx(position.x, x):
			return true
	return false


func _apply_backend_snapshot_and_selection(snapshot: Variant, selected_point_id: int) -> void:
	if _backend == null or not _backend.apply_snapshot(snapshot):
		return
	_restore_backend_selection(selected_point_id)


func _restore_backend_selection(selected_point_id: int) -> void:
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
		&"left_control_state_reset":
			return "Reset Easing Curve Left Handle State"
		&"right_control_state_reset":
			return "Reset Easing Curve Right Handle State"
		&"control_states_reset":
			return "Reset Easing Curve Handle States"
		&"toolbar_options_reset":
			return "Reset Easing Curve Point Options"
		&"handle_mode":
			return "Change Easing Curve Handle Mode"
	return "Edit Easing Curve Point"


func _request_point_add(point: Resource) -> int:
	if _curve != null and point is EasingCurvePoint and point_add_requested.has_connections():
		point_add_requested.emit(point)
		# Legacy snapshots reconstruct point Resources. The Inspector add handler
		# selects the committed replacement synchronously, so return that index
		# instead of looking up the transient request Resource.
		return selected_index
	finish_active_point_edit()
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
	finish_active_point_edit()
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
	elif Input.is_key_pressed(KEY_SHIFT):
		_request_point_swap(-1)
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
	elif Input.is_key_pressed(KEY_SHIFT):
		_request_point_swap(1)
	else:
		selected_index = _get_display_neighbor_index(1)


func _request_point_swap(offset: int) -> void:
	var point := _selected_point_resource()
	if point_swap_requested.has_connections():
		point_swap_requested.emit(point, offset)
	else:
		# Standalone graphs use the same resource-order operation as the list.
		var index: int = _backend.find_point(point)
		var target := wrapi(index + offset, 0, _point_count())
		if _curve != null:
			var transaction := preload("res://addons/easing_curve/scripts/editor/inspector/point_edit_transaction_controller.gd").new()
			transaction.setup(editor_undo_redo, Callable())
			transaction.setup_point_edit_callbacks(
				_capture_swap_selection,
				Callable(get_script(), &"_restore_swap_selection").bind(weakref(self), weakref(_curve)),
				Callable(),
			)
			transaction.swap_points(_curve, index, target, select_point_resource)
		else:
			move_point_from_list(index, target)


func _capture_swap_selection() -> Dictionary:
	var point := _selected_point_resource()
	return {"point_resource_id": point.get_instance_id() if point != null else 0}


static func _restore_swap_selection(selection: Dictionary, graph_ref: WeakRef, curve_ref: WeakRef) -> void:
	var graph := graph_ref.get_ref() as EasingCurveEditor
	if graph == null or graph.get_curve() != curve_ref.get_ref():
		return
	var point := instance_from_id(int(selection["point_resource_id"])) as Resource
	graph.select_point_resource(point)


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
	finish_active_point_edit()
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
	_clear_axis_drag()
	_drag_coordinates_suppressed = true
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
		if resource != null and not presentation_owned:
			_right_delete_drag_state_by_curve.erase(resource.get_instance_id())
		return
	_store_right_delete_drag_state()


func _store_right_delete_drag_state() -> void:
	if presentation_owned:
		return
	var resource := get_curve()
	if resource == null or not is_right_delete_dragging:
		return
	_right_delete_drag_state_by_curve[resource.get_instance_id()] = {
		"requires_exit": _right_delete_requires_exit,
		"blocked_position": _right_delete_blocked_position,
	}


func _restore_right_delete_drag_state() -> void:
	if presentation_owned:
		return
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
	if _graph_ink != null:
		_graph_ink.queue_redraw()
	if _coordinate_readout != null:
		_coordinate_readout.queue_redraw()


func _draw_graph() -> void:
	if _backend == null or _graph_render_suppressed:
		return
	_graph_ink.draw_set_transform(-_graph_canvas.position)

	update_view_transform()
	_draw_graph_grid()

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
		_graph_ink.draw_circle(pos_view, point_radius, point_color)

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

			_graph_ink.draw_line(pos_view, left_view, left_line_color)
			_graph_ink.draw_circle(left_view, left_radius, left_color)

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

			_graph_ink.draw_line(pos_view, right_view, right_line_color)
			_graph_ink.draw_circle(right_view, right_radius, right_color)


func begin_point_list_coordinate_drag(input: Control, point: Resource, property_name: StringName) -> void:
	if _backend == null or _backend.find_point(point) < 0:
		return
	# Presentation references only: list callbacks still own the edit lifecycle.
	_point_list_coordinate_input = weakref(input)
	_point_list_coordinate_point = weakref(point)
	_point_list_coordinate_property = property_name
	_drag_coordinates_suppressed = false
	queue_redraw()


func end_point_list_coordinate_drag(input: Control = null) -> void:
	if _point_list_coordinate_input == null:
		return
	if input != null and _point_list_coordinate_input.get_ref() != input:
		return
	_point_list_coordinate_input = null
	_point_list_coordinate_point = null
	_point_list_coordinate_property = &""
	_drag_coordinates_suppressed = true
	queue_redraw()


func _get_drag_coordinate_position() -> Vector2:
	if _drag_coordinates_suppressed or _backend == null or _graph_render_suppressed:
		return Vector2(NAN, NAN)
	if not _is_point_graph():
		return Vector2(NAN, NAN)
	if _point_list_coordinate_input != null:
		var input := _point_list_coordinate_input.get_ref() as Control
		var list_point := _point_list_coordinate_point.get_ref() as Resource
		if input == null or list_point == null or _backend.find_point(list_point) < 0:
			return Vector2(NAN, NAN)
		return _backend.curve_to_display_position(list_point.get(_point_list_coordinate_property) as Vector2)
	var point := pending_add_point if pending_add_point != null else _point(dragging_point)
	if point == null:
		return Vector2(NAN, NAN)
	var property_name := &"position"
	if pending_add_point == null:
		match dragging_control:
			ControlIndex.LEFT:
				property_name = &"left_control_point"
			ControlIndex.RIGHT:
				property_name = &"right_control_point"
	# All three properties are absolute curve coordinates. Pending-add press/motion
	# already convert display input to curve space; apply Native transforms only once.
	return _backend.curve_to_display_position(point.get(property_name) as Vector2)


func _get_grid_tick_position(axis: int, index: int, rect: Rect2) -> Vector2:
	var fraction := float(index) / GRAPH_GRID_DIVISIONS[axis]
	if axis == Vector2.AXIS_X:
		return Vector2(lerpf(rect.position.x, rect.end.x, fraction), rect.end.y)
	return Vector2(rect.position.x, lerpf(rect.end.y, rect.position.y, fraction))


func _format_grid_label(value: float) -> String:
	var text := "%.1f" % value
	return "0.0" if text == "-0.0" else text


func _get_grid_labels(rect: Rect2, font: Font, font_size: int) -> Array[Dictionary]:
	var labels: Array[Dictionary] = []
	var padding := 4.0 * _editor_scale
	var available := rect.grow(-padding)
	if available.size.x <= 0.0 or available.size.y <= 0.0:
		return labels
	for axis in [Vector2.AXIS_X, Vector2.AXIS_Y]:
		for index in range(GRAPH_GRID_DIVISIONS[axis] + 1):
			var anchor := _get_grid_tick_position(axis, index, rect)
			var value := get_world_pos(anchor)[axis]
			if not is_finite(value):
				continue
			var text := _format_grid_label(value)
			var extent := Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, font.get_height(font_size))
			if extent.x > available.size.x or extent.y > available.size.y:
				continue
			var position := anchor - Vector2(0, extent.y + padding)
			if axis == Vector2.AXIS_X:
				# Interior labels have fixed left anchors; the right endpoint is
				# right-aligned so changing text widths never move its tick.
				position.x += padding
				if index == GRAPH_GRID_DIVISIONS.x:
					position.x = available.end.x - extent.x
			else:
				position.x = available.position.x
			position.y = clampf(position.y, available.position.y, available.end.y - extent.y)
			var bounds := Rect2(position, extent)
			if not available.encloses(bounds):
				continue
			var overlaps := false
			for previous: Dictionary in labels:
				if bounds.grow(padding * 0.5).intersects(previous.bounds):
					overlaps = true
					break
			if not overlaps:
				labels.append({"text": text, "bounds": bounds, "axis": axis, "index": index})
	return labels


func _get_reference_box_lines(rect: Rect2) -> PackedVector2Array:
	var lines := PackedVector2Array()
	var first := get_view_pos(Vector2.ZERO)
	var last := get_view_pos(Vector2.ONE)
	if not first.is_finite() or not last.is_finite():
		return lines
	var minimum := first.min(last)
	var maximum := first.max(last)
	# Clip each original edge separately: outlining the intersection would
	# incorrectly turn viewport boundaries into reference-box edges.
	var top := maxf(minimum.y, rect.position.y)
	var bottom := minf(maximum.y, rect.end.y)
	if bottom > top:
		for x: float in [minimum.x, maximum.x]:
			if x >= rect.position.x and x <= rect.end.x:
				lines.append(Vector2(x, top))
				lines.append(Vector2(x, bottom))
	var left := maxf(minimum.x, rect.position.x)
	var right := minf(maximum.x, rect.end.x)
	if right > left:
		for y: float in [minimum.y, maximum.y]:
			if y >= rect.position.y and y <= rect.end.y:
				lines.append(Vector2(left, y))
				lines.append(Vector2(right, y))
	return lines


func _draw_graph_grid() -> void:
	var rect := _get_graph_view_rect().intersection(Rect2(Vector2.ZERO, size))
	if not rect.has_area() or not get_world_pos(rect.position).is_finite():
		return
	var font := get_theme_font(&"font", &"Label")
	var font_size := get_theme_font_size(&"font_size", &"Label")
	var text_color := EDITOR_THEME_CACHE.get_color(&"font_color", &"Editor", get_theme_color(&"font_color", &"Label"))
	var mono := EDITOR_THEME_CACHE.get_color(&"mono_color", &"Editor", text_color)
	var grid_color := mono * Color(1, 1, 1, 0.1)
	var reference_color := mono * Color(1, 1, 1, 0.25)
	if not hide_graph_background:
		var tick_size := minf(4.0 * _editor_scale, minf(rect.size.x, rect.size.y))
		var bottom_left := Vector2(rect.position.x, rect.end.y)
		_graph_ink.draw_line(rect.position, bottom_left, grid_color)
		_graph_ink.draw_line(bottom_left, rect.end, grid_color)
		for index in range(GRAPH_GRID_DIVISIONS.x + 1):
			var anchor := _get_grid_tick_position(Vector2.AXIS_X, index, rect)
			_graph_ink.draw_line(anchor, anchor - Vector2(0, tick_size), reference_color)
		for index in range(GRAPH_GRID_DIVISIONS.y + 1):
			var anchor := _get_grid_tick_position(Vector2.AXIS_Y, index, rect)
			_graph_ink.draw_line(anchor, anchor + Vector2(tick_size, 0), reference_color)
	var reference_lines := _get_reference_box_lines(rect)
	if not reference_lines.is_empty():
		_graph_ink.draw_multiline(reference_lines, reference_color)
	if hide_graph_background:
		return
	# Labels cover the grid/box, then _draw() paints curve geometry and points.
	for label: Dictionary in _get_grid_labels(rect, font, font_size):
		var baseline: Vector2 = label.bounds.position + Vector2(0, font.get_ascent(font_size))
		_graph_ink.draw_string(font, baseline, label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


func _format_drag_coordinates(position: Vector2) -> String:
	var x := "%.2f" % position.x
	var y := "%.2f" % position.y
	return "(%s, %s)" % ["0.00" if x == "-0.00" else x, "0.00" if y == "-0.00" else y]


func _get_drag_coordinate_label_position(anchor: Vector2, text_size: Vector2) -> Vector2:
	var graph := _get_graph_view_rect()
	var minimum := graph.position
	var maximum := graph.end - text_size
	if maximum.x < minimum.x or maximum.y < minimum.y:
		return Vector2(NAN, NAN)
	var is_point := pending_add_point != null or dragging_control == ControlIndex.NONE
	if _point_list_coordinate_input != null:
		is_point = _point_list_coordinate_property == &"position"
	var radius := point_radius if is_point else control_radius
	var gap := radius + 6.0 * _editor_scale
	var position := anchor - Vector2(text_size.x * 0.5, gap + text_size.y)
	return position.clamp(minimum, maximum)


func _get_coordinate_minimum_y() -> float:
	return _get_graph_view_rect().position.y


func _draw_drag_coordinates() -> void:
	_coordinate_readout.draw_set_transform(-_graph_canvas.position)
	var position := _get_drag_coordinate_position()
	if not position.is_finite():
		return
	var font := get_theme_font(&"font", &"Label")
	var font_size := get_theme_font_size(&"font_size", &"Label")
	var text := _format_drag_coordinates(position)
	var text_size := Vector2(
		font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x,
		font.get_height(font_size),
	)
	var label_position := _get_drag_coordinate_label_position(get_view_pos(position), text_size)
	if not label_position.is_finite():
		return
	var color := EDITOR_THEME_CACHE.get_color(
		&"font_color", &"Editor", get_theme_color(&"font_color", &"Label")
	)
	color.a *= 0.8
	var outline := get_theme_color(&"font_outline_color", &"Label")
	if is_zero_approx(outline.a):
		outline = Color.BLACK if color.get_luminance() > 0.5 else Color.WHITE
	var baseline := label_position + Vector2(0, font.get_ascent(font_size))
	_coordinate_readout.draw_string_outline(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		maxi(1, roundi(2.0 * _editor_scale)), outline,
	)
	_coordinate_readout.draw_string(
		font, baseline, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color,
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_axis_drag()
		_update_point_navigation_tooltips(true)
		_drag_coordinates_suppressed = true
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_clear_axis_drag()
		_update_point_navigation_tooltips(true)
		_drag_coordinates_suppressed = true
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_point_navigation_tooltips()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_refresh_point_navigation_tooltips_after_focus.call_deferred()
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
	if _slider == value:
		return
	if is_instance_valid(_slider):
		_slider.slider_changed.disconnect(_on_slider_changed)
		_slider.autofit_pressed.disconnect(_on_autofit_pressed)
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
	_update_point_navigation_tooltips()
	if get_curve() == resource:
		return
	_clear_axis_drag()
	end_point_list_coordinate_drag()
	_drag_coordinates_suppressed = true
	if _backend != null and _backend_point_edit_active:
		_backend.finish_point_edit()
	_backend_point_edit_active = false
	_backend_point_edit_before = null
	_backend_point_edit_action_name = "Edit Easing Curve Point"
	_backend_point_edit_selected_before = null
	_backend_point_edit_point = null
	_backend_point_edit_property = StringName()
	_backend_point_edit_from_point_list = false
	var previous := get_curve()
	if previous != null and previous.changed.is_connected(_on_curve_changed):
		previous.changed.disconnect(_on_curve_changed)

	_backend = BackendFactory.create(resource)
	_curve = resource as EasingCurve
	var current := get_curve()
	snap_enabled = bool(current.get_meta(SNAP_ENABLED_META, false)) if current != null else false
	snap_count = int(current.get_meta(SNAP_COUNT_META, 10)) if current != null else 10
	if current != null:
		current.changed.connect(_on_curve_changed)
		selected_index = -1 if presentation_owned else _selected_index_by_curve.get(
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
	var graph_rect := _get_graph_view_rect()
	var view_scale = graph_rect.size / world_rect.size

	var world_trans: Transform2D
	world_trans = world_trans.translated_local(-world_rect.position - Vector2(0, world_rect.size.y))
	world_trans = world_trans.scaled(Vector2(view_scale.x, -view_scale.y))

	var view_trans: Transform2D
	view_trans = view_trans.translated_local(graph_rect.position)

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

	var target_zoom := minf(1.0 / padded_size.x, 1.0 / padded_size.y)
	_zoom_step = 0
	for step in range(ZOOM_STEPS + 1):
		if step_to_zoom(step) > target_zoom + 0.000001:
			break
		_zoom_step = step
	_apply_zoom_from_step()
	update_view_transform()
	pan_offset = _world_to_view.basis_xform(Vector2(0.5, 0.5) - bounds.get_center())
	pan_changed.emit(pan_offset)
	queue_redraw()


func _get_autofit_view_rect() -> Rect2:
	return _get_graph_view_rect()


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
	var origin := _graph_canvas.position if _graph_canvas != null else Vector2.ZERO
	return Rect2(origin + Vector2.ONE * GRAPH_EDGE_PADDING * _editor_scale, _get_graph_size())


func _get_graph_size() -> Vector2:
	# Width is already in scaled pixels; remove edge padding exactly once here.
	var usable_width := maxf(size.x - 2.0 * GRAPH_EDGE_PADDING * _editor_scale, 1.0)
	return Vector2(usable_width, clampf(PREFERRED_GRAPH_HEIGHT * _editor_scale, usable_width / 2.0, usable_width))


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
		_clear_axis_drag()
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
	var height := _get_graph_size().y + 2.0 * GRAPH_EDGE_PADDING * _editor_scale
	if _layout != null:
		var visible_rows := 0
		for row: Control in _layout.get_children():
			if not row.visible:
				continue
			visible_rows += 1
			if row != _graph_canvas:
				height += row.get_combined_minimum_size().y
		height += maxi(0, visible_rows - 1) * _layout.get_theme_constant(&"separation")
	return Vector2(64.0 * _editor_scale, height)


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
		_graph_ink.draw_line(
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
		_graph_ink.draw_line(
			get_view_pos(Vector2(0.0, fallback_y)),
			get_view_pos(Vector2(first_position.x, fallback_y)),
			LINE_COLOR,
			2,
		)
		_graph_ink.draw_line(
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
		_graph_ink.draw_line(
			get_view_pos(last_position),
			get_view_pos(Vector2(last_position.x, fallback_y)),
			LINE_COLOR,
			2,
		)
		_graph_ink.draw_line(
			get_view_pos(Vector2(last_position.x, fallback_y)),
			get_view_pos(Vector2(1.0, fallback_y)),
			LINE_COLOR,
			2,
		)


func _get_visible_world_x_bounds() -> Vector2:
	var graph := _get_graph_view_rect()
	var left_x := get_world_pos(graph.position).x
	var right_x := get_world_pos(graph.end).x
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
			_graph_ink.draw_line(get_view_pos(a_position), get_view_pos(b_position), LINE_COLOR, 2)
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
	_graph_ink.draw_polyline(polyline, LINE_COLOR, 2.0)


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
			_graph_ink.draw_line(prev, pt, LINE_COLOR, 2)

		prev = pt


func _snap_graph_position(position: Vector2, temporary_snap := false) -> Vector2:
	if not snap_enabled and not temporary_snap:
		return position
	# Snap in visible graph space before Reverse/Invert and axis constraints.
	return position.snapped(Vector2.ONE / float(snap_count))


func _create_snap_toolbar() -> void:
	_snap_toolbar_margin = MarginContainer.new()
	_snap_toolbar_margin.name = &"GridSnapMargin"
	_snap_toolbar_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout.add_child(_snap_toolbar_margin)
	var toolbar := HBoxContainer.new()
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar.custom_minimum_size.y = SNAP_TOOLBAR_HEIGHT * _editor_scale
	_snap_toolbar_margin.add_child(toolbar)
	_snap_button = Button.new()
	_snap_button.icon = EDITOR_THEME_CACHE.get_icon(&"SnapGrid")
	if _snap_button.icon == null:
		_snap_button.text = "Snap"
	_snap_button.toggle_mode = true
	_snap_button.tooltip_text = "Toggle Grid Snap (points only; Ctrl/Cmd temporarily enables snapping)"
	_snap_button.toggled.connect(_on_snap_toggled)
	toolbar.add_child(_snap_button)
	var separator := VSeparator.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar.add_child(separator)
	_snap_count_input = EditorSpinSlider.new()
	_snap_count_input.min_value = 2
	_snap_count_input.max_value = 100
	_snap_count_input.step = 1
	_snap_count_input.custom_minimum_size.x = 65.0 * _editor_scale
	_snap_count_input.tooltip_text = "Grid subdivisions on both X and Y (2–100)"
	_snap_count_input.value_changed.connect(_on_snap_count_changed)
	toolbar.add_child(_snap_count_input)
	_sync_snap_controls()


func _sync_snap_controls() -> void:
	if _snap_button == null or _snap_count_input == null:
		return
	_snap_button.set_pressed_no_signal(snap_enabled)
	_snap_count_input.set_value_no_signal(snap_count)
	_snap_count_input.visible = snap_enabled


func _on_snap_toggled(enabled: bool) -> void:
	snap_enabled = enabled
	var resource := get_curve()
	if resource != null:
		if enabled:
			resource.set_meta(SNAP_ENABLED_META, true)
		else:
			resource.remove_meta(SNAP_ENABLED_META)


func _on_snap_count_changed(value: float) -> void:
	snap_count = roundi(value)
	var resource := get_curve()
	if resource != null:
		if snap_count != 10:
			resource.set_meta(SNAP_COUNT_META, snap_count)
		else:
			resource.remove_meta(SNAP_COUNT_META)


func _create_point_toolbar() -> void:
	_point_toolbar_panel = VBoxContainer.new()
	_point_toolbar_panel.name = &"PointToolbarPanel"
	_point_toolbar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_point_toolbar_panel.custom_minimum_size.y = (
		SELECTION_TOOLBAR_HEIGHT * _editor_scale
	)

	_layout.add_child(_point_toolbar_panel)

	_point_toolbar = VBoxContainer.new()
	_point_toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_point_toolbar.add_theme_constant_override(
		"separation",
		EDITOR_THEME_CACHE.compact_separation(_editor_scale),
	)
	_point_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_toolbar.custom_minimum_size.y = (
		SELECTION_TOOLBAR_HEIGHT * _editor_scale
	)

	_point_toolbar_panel.add_child(_point_toolbar)
	_point_mode_row = HBoxContainer.new()
	_point_mode_row.name = &"PointModeRow"
	_point_mode_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if controls_layout == ControlsLayout.DEV_SINGLE_ROW:
		var row_slot := PointToolbarOptionSlot.new()
		row_slot.add_child(_point_mode_row)
		_point_toolbar.add_child(row_slot)
	else:
		_point_toolbar.add_child(_point_mode_row)
	_point_states_row = HBoxContainer.new()
	_point_states_row.name = &"PointStatesRow"
	_point_states_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if controls_layout == ControlsLayout.COMPACT_TWO_ROW:
		_point_states_row.alignment = BoxContainer.ALIGNMENT_END
	_point_toolbar.add_child(_point_states_row)


	var point_label_row := HBoxContainer.new()
	point_label_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	point_label_row.add_theme_constant_override("separation", 0)
	point_label_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	point_label_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_point_mode_row.add_child(point_label_row)

	_point_reorder_buttons = HBoxContainer.new()
	_point_reorder_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_point_move_left_button.pressed.connect(_request_point_move_up)
	for style_name in [&"normal", &"normal_mirrored", &"hover", &"hover_mirrored", &"pressed", &"pressed_mirrored", &"hover_pressed", &"hover_pressed_mirrored", &"disabled", &"disabled_mirrored", &"focus"]:
		_point_move_left_button.add_theme_stylebox_override(
			style_name,
			StyleBoxEmpty.new(),
		)
	_point_reorder_buttons.add_child(_point_move_left_button)

	_point_label = Label.new()
	_point_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_point_label.clip_text = true
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
	_point_move_right_button.pressed.connect(_request_point_move_down)
	for style_name in [&"normal", &"normal_mirrored", &"hover", &"hover_mirrored", &"pressed", &"pressed_mirrored", &"hover_pressed", &"hover_pressed_mirrored", &"disabled", &"disabled_mirrored", &"focus"]:
		_point_move_right_button.add_theme_stylebox_override(
			style_name,
			StyleBoxEmpty.new(),
		)
	_point_reorder_buttons.add_child(_point_move_right_button)

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

	_add_point_toolbar_option(_point_mode_row, _point_handle_mode)

	_point_left_state_label = Label.new()
	_point_left_state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_point_left_state_label.text = "L"
	_point_left_state_label.add_theme_stylebox_override(&"normal", StyleBoxEmpty.new())
	_point_left_group = HBoxContainer.new()
	_point_left_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var states_parent := _point_mode_row if controls_layout == ControlsLayout.DEV_SINGLE_ROW else _point_states_row
	states_parent.add_child(_point_left_group)
	_point_left_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_left_group.add_child(_point_left_state_label)
	_point_left_state = _create_point_toolbar_control_state_option(
		EasingCurvePoint.ControlSide.LEFT
	)
	_add_point_toolbar_option(_point_left_group, _point_left_state)

	_point_right_state_label = Label.new()
	_point_right_state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_point_right_state_label.text = "R"
	_point_right_state_label.add_theme_stylebox_override(&"normal", StyleBoxEmpty.new())
	_point_right_group = HBoxContainer.new()
	_point_right_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	states_parent.add_child(_point_right_group)
	_point_right_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_right_group.add_child(_point_right_state_label)
	_reserve_point_toolbar_control_side_label_width()
	_point_right_state = _create_point_toolbar_control_state_option(
		EasingCurvePoint.ControlSide.RIGHT
	)
	_add_point_toolbar_option(_point_right_group, _point_right_state)

	_point_reset_button = EDITOR_THEME_CACHE.create_reserved_reset_button("Reset Handle Mode to Free")
	if controls_layout == ControlsLayout.DEV_SINGLE_ROW:
		_point_reset_button.tooltip_text = "Reset Handle Mode and Left/Right states"
		_point_reset_button.pressed.connect(_on_point_toolbar_reset_pressed)
	else:
		_point_reset_button.pressed.connect(_on_point_handle_mode_reset_pressed)
	_point_mode_row.add_child(_point_reset_button)
	_point_states_reset_button = EDITOR_THEME_CACHE.create_reserved_reset_button("Reset Left and Right Force Linear and Lock states")
	_point_states_reset_button.pressed.connect(_on_point_states_reset_pressed)
	_point_states_row.add_child(_point_states_reset_button)
	_update_point_toolbar_spacing()

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
	var font := _point_label.get_theme_font(&"font")
	var font_size := _point_label.get_theme_font_size(&"font_size")
	_point_label.custom_minimum_size.x = ceilf(font.get_string_size("999", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)


func _add_point_toolbar_option(row: Container, option: OptionButton) -> void:
	if controls_layout == ControlsLayout.DEV_SINGLE_ROW:
		row.add_child(option)
		return
	var slot := PointToolbarOptionSlot.new()
	slot.add_child(option)
	row.add_child(slot)


func _update_point_toolbar_spacing() -> void:
	var separation := EDITOR_THEME_CACHE.compact_separation(_editor_scale)
	# Reserve the dropdown height even when it is hidden with no selection.
	_point_mode_row.custom_minimum_size.y = _point_handle_mode.get_combined_minimum_size().y
	if controls_layout == ControlsLayout.COMPACT_TWO_ROW:
		# A reset-only row retains its usual vertical alignment until it collapses.
		_point_states_row.custom_minimum_size.y = maxf(
			_point_left_state.get_combined_minimum_size().y,
			_point_right_state.get_combined_minimum_size().y,
		)
	for button: Button in [_point_move_left_button, _point_move_right_button]:
		var icon_width := roundi(16.0 * _editor_scale)
		button.custom_minimum_size = Vector2.ONE * icon_width
		if button.get_theme_constant(&"icon_max_width") != icon_width:
			button.add_theme_constant_override(&"icon_max_width", icon_width)
	for row: BoxContainer in [_point_toolbar, _point_mode_row, _point_states_row, _point_left_group, _point_right_group]:
		if row.get_theme_constant(&"separation") != separation:
			row.add_theme_constant_override("separation", separation)


func _reserve_point_toolbar_control_side_label_width() -> void:
	var font := _point_left_state_label.get_theme_font(&"font")
	var font_size := _point_left_state_label.get_theme_font_size(&"font_size")
	var label_width := ceilf(maxf(
		font.get_string_size(_point_left_state_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x,
		font.get_string_size("R", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x,
	))
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




func _refresh_point_navigation_tooltips_after_focus() -> void:
	if is_inside_tree() and is_visible_in_tree():
		_update_point_navigation_tooltips()


func _update_point_navigation_tooltips(reset_modifier := false) -> void:
	if not is_instance_valid(_point_move_left_button) or not is_instance_valid(_point_move_right_button):
		return
	var swap := point_move_buttons_reorder_points or (
		not reset_modifier and is_inside_tree() and is_visible_in_tree()
		and Input.is_key_pressed(KEY_SHIFT)
	)
	var previous := "Swap Previous Point" if swap else "Select Previous Point"
	var next := "Swap Next Point" if swap else "Select Next Point"
	if _point_move_left_button.tooltip_text != previous:
		_point_move_left_button.tooltip_text = previous
	if _point_move_right_button.tooltip_text != next:
		_point_move_right_button.tooltip_text = next


func _update_point_toolbar() -> void:
	if _point_toolbar == null:
		return
	_queue_layout()
	_update_point_navigation_tooltips()

	var hide_toolbar := _is_point_toolbar_hidden()
	_point_toolbar_panel.visible = not hide_toolbar
	_snap_toolbar_margin.visible = not hide_toolbar

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
	_point_states_row.visible = valid_selection and controls_layout != ControlsLayout.DEV_SINGLE_ROW

	if not valid_selection:
		_point_label.text = (
			""
			if _backend != null and not _is_point_graph()
			else "0"
		)
		_point_label.modulate.a = 0.6
		_set_point_toolbar_reorder_available(
			false,
			_backend == null or _is_point_graph(),
			true,
		)
		_point_handle_mode.visible = controls_layout != ControlsLayout.DEV_SINGLE_ROW
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
		if controls_layout == ControlsLayout.COMPACT_TWO_ROW:
			_set_reset_button_available(_point_states_reset_button, false)
		return

	var point := _point(selected_index)

	_point_label.text = str(selected_index)
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
	_point_handle_mode.tooltip_text = "Handle Mode: " + _point_handle_mode.get_item_text(_point_handle_mode.selected)

	var supports_states: bool = _backend.point_supports_control_state(selected_index)
	_update_point_toolbar_control_state(
		EasingCurvePoint.ControlSide.LEFT,
		supports_states and selected_index > 0,
		"Left",
	)
	_update_point_toolbar_control_state(
		EasingCurvePoint.ControlSide.RIGHT,
		supports_states and selected_index < _point_count() - 1,
		"Right",
	)
	_set_point_toolbar_reset_available(
		not _point_toolbar_options_are_default(point)
		if controls_layout == ControlsLayout.DEV_SINGLE_ROW
		else int(point.get(&"handle_mode")) != EasingCurvePoint.HandleMode.FREE
	)
	_set_reset_button_available(_point_states_reset_button, not _point_control_states_are_default(point))
	if controls_layout == ControlsLayout.COMPACT_TWO_ROW:
		_point_states_row.visible = (
			not _point_left_state.disabled
			or not _point_right_state.disabled
			or not _point_states_reset_button.disabled
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
	var group := _point_left_group if side == EasingCurvePoint.ControlSide.LEFT else _point_right_group
	group.visible = visible
	label.visible = visible
	option.visible = visible


func _set_point_toolbar_reorder_available(
	available: bool,
	visible: bool = true,
	keep_visible_when_disabled: bool = false,
) -> void:
	for button in [_point_move_left_button, _point_move_right_button]:
		if button == null:
			continue
		button.visible = (
			(available or keep_visible_when_disabled) and visible
			if controls_layout == ControlsLayout.DEV_SINGLE_ROW or (controls_layout == ControlsLayout.COMPACT_TWO_ROW and hide_unused_controls)
			else true
		)
		button.self_modulate.a = 1.0 if visible else 0.0
		button.mouse_filter = (
			Control.MOUSE_FILTER_STOP
			if available
			else Control.MOUSE_FILTER_IGNORE
		)
		button.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
		button.disabled = not available


func _set_point_toolbar_reset_available(available: bool) -> void:
	_set_reset_button_available(_point_reset_button, available)


func _set_reset_button_available(button: Button, available: bool) -> void:
	button.self_modulate.a = 1.0 if available else 0.0
	button.mouse_filter = Control.MOUSE_FILTER_STOP if available else Control.MOUSE_FILTER_IGNORE
	button.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
	button.disabled = not available


func _point_toolbar_options_are_default(point: Resource) -> bool:
	return int(point.get(&"handle_mode")) == EasingCurvePoint.HandleMode.FREE and _point_control_states_are_default(point)


func _point_control_states_are_default(point: Resource) -> bool:
	var locks := point.get(&"locked") as Dictionary
	return (
		not bool(point.get(&"left_force_linear"))
		and not bool(point.get(&"right_force_linear"))
		and not locks.get(&"left_control_point", false)
		and not locks.get(&"right_control_point", false)
	)


func _update_point_toolbar_control_state(
	side: EasingCurvePoint.ControlSide,
	available: bool,
	side_name: String,
) -> void:
	var hide_unavailable := (
		controls_layout == ControlsLayout.DEV_SINGLE_ROW
		or (controls_layout == ControlsLayout.COMPACT_TWO_ROW and hide_unused_controls)
	)
	_set_point_toolbar_control_state_visible(side, available or not hide_unavailable)

	var option := (
		_point_left_state
		if side == EasingCurvePoint.ControlSide.LEFT
		else _point_right_state
	)
	option.disabled = not available
	option.mouse_filter = Control.MOUSE_FILTER_STOP if available else Control.MOUSE_FILTER_IGNORE
	option.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
	var control_state := _get_point_toolbar_control_state(selected_index, side)
	for index in range(option.item_count):
		if option.get_item_id(index) == control_state:
			option.select(index)
			break
	option.tooltip_text = "%s handle: %s%s" % [side_name, option.get_item_text(option.selected), " (unavailable)" if not available else ""]


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


func _on_point_handle_mode_reset_pressed() -> void:
	if _backend == null or selected_index < 0 or selected_index >= _point_count() or _point_reset_button.disabled:
		return
	_request_point_property_change(selected_index, &"handle_mode", EasingCurvePoint.HandleMode.FREE)


func _on_point_states_reset_pressed() -> void:
	if _backend == null or selected_index < 0 or selected_index >= _point_count() or _point_states_reset_button.disabled:
		return
	_request_point_property_change(selected_index, &"control_states_reset", true)


# Shared reset used by the single-row comparison layout and existing callers.
func _on_point_toolbar_reset_pressed() -> void:
	if _backend == null or selected_index < 0 or selected_index >= _point_count():
		return
	_request_point_property_change(selected_index, &"toolbar_options_reset", true)


func get_world_to_view_scale() -> Vector2:
	return Vector2(
		_world_to_view.x.length(),
		_world_to_view.y.length()
	)

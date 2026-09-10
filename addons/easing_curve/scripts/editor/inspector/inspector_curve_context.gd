@tool
class_name InspectorCurveContext
extends RefCounted
## One rendered Easing Curve presentation. All persistent callbacks belong to this owner.
##
## Constructed once per parse pass and retained by its graph/list roots.
## Controllers and UI callbacks are local; history restores selection through a weak reference.

signal native_selection_changed(point: Resource)
signal native_point_display_changed()

const MODE_ICONS = preload("res://addons/easing_curve/scripts/editor/inspector/curve_mode_icons.gd")

const NativePointListEditController = preload(
	"res://addons/easing_curve/scripts/editor/inspector/native_point_list_edit_controller.gd"
)
const CurveEditorSettings = preload(
	"res://addons/easing_curve/scripts/editor/curve_editor_settings.gd"
)
const EDITOR_THEME_CACHE = preload(
	"res://addons/easing_curve/scripts/editor/inspector/editor_theme_cache.gd"
)
const PointEditTransactionController = preload(
	"res://addons/easing_curve/scripts/editor/inspector/point_edit_transaction_controller.gd"
)
const DeferredParameterEditorProperty = preload(
	"res://addons/easing_curve/scripts/editor/inspector/deferred_parameter_editor_property.gd"
)
const NATIVE_DEFERRED_PARAMETERS := [
	&"constant_value",
	&"overshoot",
	&"amplitude",
	&"period",
	&"num_points",
	&"randomness",
	&"steps",
	&"y_offset",
	&"power",
	&"num_bounces",
	&"bounce_damping",
	&"frequency",
	&"decay",
	&"stiffness",
	&"damping",
	&"mass",
	&"velocity",
]
const GenerateFunctionEditorProperty = preload(
	"res://addons/easing_curve/scripts/editor/inspector/generate_function_editor_property.gd"
)
const PointsEditorProperty = preload(
	"res://addons/easing_curve/scripts/editor/inspector/points_editor_property.gd"
)
const PointsFoldableSection = preload(
	"res://addons/easing_curve/scripts/editor/inspector/points_foldable_section.gd"
)
const CurveConversionControl = preload(
	"res://addons/easing_curve/scripts/editor/inspector/curve_conversion_control.gd"
)
const PointPropertyClipboardController = preload(
	"res://addons/easing_curve/scripts/editor/inspector/point_property_clipboard_controller.gd"
)
const PointListController = preload(
	"res://addons/easing_curve/scripts/editor/inspector/point_list_controller.gd"
)
const BackendFactory := preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_editor_backend_factory.gd"
)
# Compatibility/test seam; construction ownership lives in PointListController.
const PointsListContainer = PointListController.PointsListContainer
## Vector2 slider step
const SLIDER_INPUT_STEP = 0.001
const DRAGGING_META := &"_easing_curve_dragging"
const VALUE_EDITING_META := &"_easing_curve_value_editing"
const POSITION_X_EDITING_META := &"_easing_curve_position_x_editing"
# modified preset indicator
const SHOW_MODIFIED_ASTERISK := true
# alignment
const POINT_PROPERTY_HEADER_RATIO := 0.35
const POINT_PROPERTY_VALUE_RATIO := 0.65
# debug
const DEBUG_POINT_LIST_DRAG := false

var _zero_margin_panel_stylebox: StyleBox = (
	EDITOR_THEME_CACHE.make_zero_margin_panel_stylebox()
)
var _point_property_clipboard := PointPropertyClipboardController.new()
var _point_edit_transaction_controller := PointEditTransactionController.new()
var _native_curve: Resource
var _native_points_content: VBoxContainer
var _native_points_refresh_queued := false
var _native_points_generation := 0
var _native_point_identity_signature := PackedInt64Array()
var _native_point_transform_flags := Vector2i.ZERO
var _native_point_storage_indices: Dictionary[int, int] = {}
var _native_panel_reverse := false
var _native_editor_generation := 0
var _native_point_edit_finish_request_id := 0
var _point_edit_finish_request_id := 0
var _conversion_added := false
var resource: Resource
var disposed := false
var _swap_request_graph: WeakRef
var graph_root_ref: WeakRef
var points_root_ref: WeakRef
var _detached_native_editor: NativePointListEditController
var _finishing := false
var registrations: Array[Dictionary] = []


class HorizontallyShrinkableOptionButton:
	extends OptionButton

	func _get_minimum_size() -> Vector2:
		return Vector2.ZERO


class HorizontallyShrinkableButton:
	extends Button

	func _get_minimum_size() -> Vector2:
		return Vector2.ZERO


class HorizontallyShrinkableControlSlot:
	extends Control

	var preferred_width := 0.0
	var preferred_height := 0.0


	func _init() -> void:
		clip_contents = true


	func set_content(content: Control, preferred_size: Vector2) -> void:
		preferred_width = preferred_size.x
		preferred_height = preferred_size.y
		add_child(content)
		_fit_content(content)
		update_minimum_size()


	func _get_minimum_size() -> Vector2:
		return Vector2(0.0, preferred_height)


	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and get_child_count() > 0:
			_fit_content(get_child(0) as Control)


	func _fit_content(content: Control) -> void:
		content.position = Vector2.ZERO
		content.size = size


class CappedHorizontalControlRow:
	extends Container

	var separation := 0.0


	func set_separation(value: float) -> void:
		separation = value
		queue_sort()
		update_minimum_size()


	func _get_minimum_size() -> Vector2:
		var minimum_height := 0.0
		for child: Control in _visible_control_children():
			minimum_height = maxf(
				minimum_height,
				child.get_combined_minimum_size().y,
			)
		return Vector2(0.0, minimum_height)


	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			_layout_children()


	func _layout_children() -> void:
		var controls := _visible_control_children()
		if controls.is_empty():
			return
		var gaps_width := separation * maxf(0.0, controls.size() - 1.0)
		var available_width := maxf(0.0, size.x - gaps_width)
		var preferred_width := 0.0
		for control: Control in controls:
			preferred_width += float(control.get(&"preferred_width"))
		var width_scale := 1.0
		if preferred_width > 0.0:
			width_scale = minf(1.0, available_width / preferred_width)
		var content_width := preferred_width * width_scale + gaps_width
		var offset_x := maxf(0.0, (size.x - content_width) * 0.5)
		for control: Control in controls:
			var control_width := (
				float(control.get(&"preferred_width")) * width_scale
			)
			fit_child_in_rect(
				control,
				Rect2(offset_x, 0.0, control_width, size.y),
			)
			offset_x += control_width + separation


	func _visible_control_children() -> Array[Control]:
		var controls: Array[Control] = []
		for child: Node in get_children():
			if child is Control and child.visible:
				controls.append(child)
		return controls


## Inspector-only transition grouping, ordering, and presentation.
## Runtime transition IDs, behavior, and metadata remain in EasingCurve.
const TRANSITION_PRESENTATION := [
	{
		"name": "Basic",
		"items": [
			{"transition": EasingCurve.TRANS.LINEAR},
			{"transition": EasingCurve.TRANS.CONSTANT},
		],
	},
	{
		"name": "Polynomial",
		"items": [
			{"transition": EasingCurve.TRANS.QUAD},
			{"transition": EasingCurve.TRANS.CUBIC},
			{"transition": EasingCurve.TRANS.QUART},
			{"transition": EasingCurve.TRANS.QUINT},
			{"transition": EasingCurve.TRANS.POWER},
		],
	},
	{
		"name": "Smooth",
		"items": [
			{"transition": EasingCurve.TRANS.SINE},
			{"transition": EasingCurve.TRANS.SMOOTHSTEP},
			{"transition": EasingCurve.TRANS.CIRC},
			{"transition": EasingCurve.TRANS.EXPO},
		],
	},
	{
		"name": "Springy",
		"items": [
			{"transition": EasingCurve.TRANS.BACK},
			{"transition": EasingCurve.TRANS.ELASTIC},
			{"transition": EasingCurve.TRANS.BOUNCE},
			{"transition": EasingCurve.TRANS.SPRING},
			{"transition": EasingCurve.TRANS.PHYSICS_SPRING},
		],
	},
	{
		"name": "Discrete",
		"items": [
			{"transition": EasingCurve.TRANS.STEP},
			{"transition": EasingCurve.TRANS.JITTER},
			{"transition": EasingCurve.TRANS.IRREGULAR},
		],
	},
	{
		"name": "CSS",
		"items": [
			{"transition": EasingCurve.TRANS.CSS_CUBIC_BEZIER},
			{"transition": EasingCurve.TRANS.CSS_LINEAR},
		],
	},
	{
		"name": "Custom",
		"items": [
			{"transition": EasingCurve.TRANS.CUSTOM},
		],
	},
]

const NATIVE_TRANSITION_PRESENTATION := [
	{
		"name": "Basic",
		"items": [
			{"transition": 0, "label": "Linear"},
			{"transition": 101, "label": "Constant"},
		],
	},
	{
		"name": "Polynomial",
		"items": [
			{"transition": 4, "label": "Quad"},
			{"transition": 7, "label": "Cubic"},
			{"transition": 3, "label": "Quart"},
			{"transition": 2, "label": "Quint"},
			{"transition": 105, "label": "Power"},
		],
	},
	{
		"name": "Smooth",
		"items": [
			{"transition": 1, "label": "Sine"},
			{"transition": 109, "label": "Smoothstep"},
			{"transition": 8, "label": "Circ"},
			{"transition": 5, "label": "Expo"},
		],
	},
	{
		"name": "Springy",
		"items": [
			{"transition": 10, "label": "Back"},
			{"transition": 6, "label": "Elastic"},
			{"transition": 9, "label": "Bounce"},
			{"transition": 11, "label": "Spring"},
			{"transition": 106, "label": "Physics Spring"},
		],
	},
	{
		"name": "Discrete",
		"items": [
			{"transition": 104, "label": "Step"},
			{"transition": 102, "label": "Jitter"},
			{"transition": 103, "label": "Irregular"},
		],
	},
	{
		"name": "CSS",
		"items": [
			{"transition": 108, "label": "cubic-bezier()"},
			{"transition": 107, "label": "linear()"},
		],
	},
	{
		"name": "Custom",
		"items": [
			{"transition": 100, "label": "Custom"},
		],
	},
]


func _init() -> void:
	_point_edit_transaction_controller.setup_point_edit_callbacks(
		Callable(self, "_capture_point_selection_state"),
		_selection_restorer(),
		Callable(self, "_reorder_position_edited_point"),
	)


func _parse_begin(object: Object) -> void:
	resource = object as Resource
	if resource is EasingCurve:
		curve = resource
	else:
		_native_curve = resource


func add_property_editor(name: StringName, control: Control, add_to_end := false, label := "") -> void:
	control.set_meta(&"_inspector_context", self)
	registrations.append({"name": name, "control": control, "end": add_to_end, "label": label})


func add_custom_control(control: Control) -> void:
	control.set_meta(&"_inspector_context", self)
	registrations.append({"control": control})


func _retain_presentation_root(control: Control, is_graph := false) -> void:
	control.set_meta(&"_inspector_context", self)
	if is_graph:
		graph_root_ref = weakref(control)
	else:
		points_root_ref = weakref(control)
	control.tree_exiting.connect(_on_presentation_root_exiting.bind(control.get_instance_id(), is_graph))


func _on_presentation_root_exiting(root_id: int, is_graph: bool) -> void:
	var root_ref := graph_root_ref if is_graph else points_root_ref
	if disposed or root_ref == null:
		return
	var presentation_root := root_ref.get_ref() as Control
	if presentation_root == null or presentation_root.get_instance_id() != root_id:
		return
	if is_graph:
		# Commit while the graph and its Undo source are still valid.
		_finish_applied_point_edit()
		_disconnect_graph_swap_request()
		_cancel_autofit()
		graph_root_ref = null
		curve_editor_property = null
		_curve_editor_section = null
		if is_instance_valid(easing_curve_editor):
			easing_curve_editor.committed_change_publisher = Callable()
			easing_curve_editor.set_curve(null)
		easing_curve_editor = null
	else:
		# An active graph gesture belongs to the surviving graph.
		if is_instance_valid(easing_curve_editor):
			easing_curve_editor.end_point_list_coordinate_drag()
		if not is_instance_valid(easing_curve_editor) or easing_curve_editor.dragging_point < 0:
			_finish_applied_point_edit()
		_cancel_pending_native_point_edit_finish()
		_point_edit_finish_request_id += 1
		points_root_ref = null
		_native_points_content = null
		_native_points_refresh_queued = false
		_native_points_generation += 1
		_point_list_controller.clear_input_bindings()
		_detach_selected_point_property_header()
	presentation_root.remove_meta(&"_inspector_context")
	if graph_root_ref == null and points_root_ref == null:
		_dispose_presentation()


func _finish_applied_point_edit() -> void:
	if _finishing:
		return
	_finishing = true
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.finish_active_point_edit()
	if curve != null:
		_commit_point_edit()
	if _detached_native_editor != null:
		_detached_native_editor.finish()
	_cancel_pending_native_point_edit_finish()
	_point_edit_finish_request_id += 1
	_finishing = false


func _dispose_presentation() -> void:
	if disposed or _finishing:
		return
	_finish_applied_point_edit()
	_disconnect_graph_swap_request()
	disposed = true
	_point_list_controller.clear_input_bindings()
	_point_edit_transaction_controller.setup_point_edit_callbacks(Callable(), Callable(), Callable())
	_point_edit_transaction_controller.setup(null, Callable())
	if _detached_native_editor != null:
		_detached_native_editor.dispose()
		_detached_native_editor = null
	_cancel_autofit()


func _disconnect_graph_swap_request() -> void:
	var graph := _swap_request_graph.get_ref() as EasingCurveEditor if _swap_request_graph != null else null
	if is_instance_valid(graph) and graph.point_swap_requested.is_connected(_on_graph_point_swap_requested):
		graph.point_swap_requested.disconnect(_on_graph_point_swap_requested)
	_swap_request_graph = null


func _connect_graph_swap_request() -> void:
	_disconnect_graph_swap_request()
	var graph := easing_curve_editor
	# A reused graph must relinquish its previous Inspector owner first.
	for connection: Dictionary in graph.point_swap_requested.get_connections():
		var callback: Callable = connection["callable"]
		if callback.get_method() == &"_on_graph_point_swap_requested":
			var previous_owner := callback.get_object() as InspectorCurveContext
			if previous_owner != null:
				previous_owner._disconnect_graph_swap_request()
	if not graph.point_swap_requested.is_connected(_on_graph_point_swap_requested):
		graph.point_swap_requested.connect(_on_graph_point_swap_requested)
	_swap_request_graph = weakref(graph)


func _on_graph_point_swap_requested(point: Resource, offset: int) -> void:
	var graph := _swap_request_graph.get_ref() as EasingCurveEditor if _swap_request_graph != null else null
	if disposed or not is_instance_valid(graph) or graph != easing_curve_editor:
		return
	var current := _point_list_curve_resource()
	if graph.get_curve() != current or point == null:
		return
	var backend := BackendFactory.create(current)
	if backend == null or backend.find_point(point) < 0:
		return
	if curve != null:
		_point_list_controller._request_relative_move(point as EasingCurvePoint, curve, offset, _move_point)
	else:
		var index: int = backend.find_point(point)
		_move_native_point(index, wrapi(index + offset, 0, backend.get_point_count()))


func _native_list_editor() -> NativePointListEditController:
	if _detached_native_editor == null:
		_detached_native_editor = NativePointListEditController.new()
		_detached_native_editor.backend = BackendFactory.create(_native_curve)
		_detached_native_editor.undo_redo = editor_undo_redo
		_detached_native_editor.capture_selection = _capture_point_selection_state
		_detached_native_editor.restore_selection = _selection_restorer()
	return _detached_native_editor


func _edit_native_point_property(index: int, property_name: StringName, value: Variant, changing := false) -> void:
	if disposed:
		return
	if property_name == &"position" and value is Vector2:
		value = value.clamp(Vector2.ZERO, Vector2.ONE)
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.edit_point_property(index, property_name, value, changing)
	else:
		_native_list_editor().edit(_point_at(_native_curve, index), property_name, value, changing)


func _select_native_point(point: Resource) -> void:
	var backend := BackendFactory.create(_native_curve)
	_point_list_controller.assign_logical_selection(
		_native_curve, backend.find_point(point), _point_list_controller.selected_point_property_name,
	)
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.select_point_resource(point)
	else:
		native_selection_changed.emit(point)


func _prepare_native_point_edit(point: Resource, property_name: StringName) -> bool:
	property_name = _get_native_point_input_edit_property(point, property_name)
	if is_instance_valid(easing_curve_editor):
		return easing_curve_editor.prepare_point_list_edit(point, property_name)
	return _native_list_editor().prepare(point, property_name)


func _remove_native_point(point: Resource) -> void:
	if disposed:
		return
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.remove_point_from_list(point)
	else:
		var editor := _native_list_editor()
		editor.mutate("Remove Easing Curve Point", func() -> void:
			editor.backend.remove_point(editor.backend.find_point(point))
		)


func _move_native_point(from_index: int, to_index: int) -> void:
	var backend := BackendFactory.create(_native_curve)
	var source: Resource = backend.get_point(from_index)
	var target: Resource = backend.get_point(to_index)
	_finish_applied_point_edit()
	from_index = backend.find_point(source) if source != null else -1
	to_index = backend.find_point(target) if target != null else -1
	if from_index < 0 or to_index < 0:
		return
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.move_point_from_list(from_index, to_index)
	else:
		var editor := _native_list_editor()
		editor.mutate("Reorder Easing Curve Point", editor.backend.swap_points.bind(from_index, to_index))


static func _restore_context_selection(selection: Dictionary, context_ref: WeakRef) -> void:
	var context := context_ref.get_ref() as InspectorCurveContext
	if context != null and not context.disposed:
		context._restore_point_selection_state(selection)


func _selection_restorer() -> Callable:
	return Callable(get_script(), &"_restore_context_selection").bind(weakref(self))


static func _point_property_path(
	point_index: int,
	property_name: StringName,
) -> String:
	return PointPropertyClipboardController.property_path(
		point_index,
		property_name,
	)


func _copy_point_property_value(
	point_index: int,
	property_name: StringName,
) -> void:
	var curve_resource := _point_list_curve_resource()
	_point_property_clipboard.copy_point_value(
		curve_resource,
		_point_at(curve_resource, point_index),
		property_name,
	)


func _paste_point_property_value(
	point_index: int,
	property_name: StringName,
) -> void:
	var curve_resource := _point_list_curve_resource()
	_point_property_clipboard.paste_point_value(
		curve_resource,
		_point_at(curve_resource, point_index),
		property_name,
		Callable(self, "_apply_editor_point_property_change"),
	)


func _apply_pasted_point_property_value(
	point_index: int,
	property_name: StringName,
	value: Variant,
) -> void:
	var curve_resource := _point_list_curve_resource()
	_point_property_clipboard.apply_point_value(
		curve_resource,
		_point_at(curve_resource, point_index),
		property_name,
		value,
		Callable(self, "_apply_editor_point_property_change"),
	)


func _copy_point_property_path(
	point_index: int,
	property_name: StringName,
) -> void:
	var curve_resource := _point_list_curve_resource()
	PointPropertyClipboardController.copy_point_path(
		curve_resource,
		_point_at(curve_resource, point_index),
		property_name,
	)


static func _is_point_property_value_compatible(
	property_name: StringName,
	value: Variant,
) -> bool:
	return PointPropertyClipboardController.is_value_compatible(
		property_name,
		value,
	)


func _clipboard_has_compatible_point_property_value(
	property_name: StringName,
) -> bool:
	return PointPropertyClipboardController.clipboard_has_compatible_value(
		property_name
	)


func _create_point_property_context_menu(
	point_index: int,
	property_name: StringName,
) -> PopupMenu:
	var curve_resource := _point_list_curve_resource()
	return _point_property_clipboard.create_point_context_menu(
		curve_resource,
		_point_at(curve_resource, point_index),
		property_name,
		Callable(self, "_apply_editor_point_property_change"),
	)


func _point_list_curve_resource() -> Resource:
	return _native_curve if is_instance_valid(_native_curve) else curve


static func _point_at(curve_resource: Resource, point_index: int) -> Resource:
	var backend := BackendFactory.create(curve_resource)
	if backend == null or point_index < 0 or point_index >= backend.get_point_count():
		return null
	return backend.get_point(point_index)


func _apply_editor_point_property_change(
	curve_resource: Resource,
	point: Resource,
	_stored_index: int,
	property_name: StringName,
	value: Variant,
) -> void:
	if disposed or curve_resource != _point_list_curve_resource() or not is_instance_valid(point):
		return
	var backend := BackendFactory.create(curve_resource)
	if backend == null:
		return
	var point_index: int = backend.find_point(point)
	if point_index < 0:
		return
	if backend.get_backend_id() == &"legacy":
		_apply_point_property_change(point_index, property_name, value)
		return
	if value is Vector2:
		if not _is_native_point_input_editable(point, property_name):
			return
		property_name = _get_native_point_input_edit_property(point, property_name)
		value = backend.display_to_curve_position(value)
	_point_list_controller.request_selection_refresh_preservation()
	_select_native_point(point)
	_edit_native_point_property(point_index, property_name, value)


func _create_selectable_point_property_header(
	i: int,
	property_name: StringName,
	label_text: String,
	reset_btn: Button,
) -> PanelContainer:
	var point := curve.points[i]
	var property_header := PanelContainer.new()
	property_header.focus_mode = Control.FOCUS_NONE

	var reset_width := 24.0 * EditorInterface.get_editor_scale()
	var reset_gap := float(_compact_separation())

	property_header.custom_minimum_size.x = (
		reset_width
		+ reset_gap * 2.0
	)

	var property_context_menu := _create_point_property_context_menu(
		i,
		property_name,
	)
	property_header.add_child(property_context_menu)

	var property_path := _point_property_path(i, property_name)
	property_header.tooltip_text = property_path
	property_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	property_header.size_flags_vertical = Control.SIZE_EXPAND_FILL
	property_header.add_theme_stylebox_override(
		&"panel",
		StyleBoxEmpty.new(),
	)

	property_header.gui_input.connect(
		func(event: InputEvent):
			if not event is InputEventMouseButton or not event.pressed:
				return

			if event.button_index == MOUSE_BUTTON_LEFT:
				_select_point_property_for_point(
					property_header,
					point,
					property_name,
				)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_select_point_property_for_point(
					property_header,
					point,
					property_name,
				)

				_point_property_clipboard.update_context_menu_paste_enabled(
					property_context_menu,
					property_name,
				)

				property_context_menu.position = (
					DisplayServer.mouse_get_position()
				)
				property_context_menu.popup()
				property_header.accept_event()
	)

	if (
		_point_list_controller.selected_point_index == i
		and _point_list_controller.selected_point_property_name == property_name
	):
		_attach_selected_point_property_header(property_header)

	var overlay_root := Control.new()
	overlay_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	property_header.add_child(overlay_root)

	var property_label := Label.new()
	property_label.text = label_text
	property_label.tooltip_text = property_path
	_configure_compact_label(property_label)
	property_label.custom_minimum_size.x = 0.0
	property_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	property_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.add_child(property_label)

	reset_btn.set_meta(&"point_property_label", property_label)
	reset_btn.set_meta(&"point_reset_width", reset_width)
	reset_btn.set_meta(&"point_reset_gap", reset_gap)


	var reset_clip := Control.new()
	reset_clip.clip_contents = true
	reset_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reset_clip.anchor_left = 1.0
	reset_clip.anchor_right = 1.0
	reset_clip.anchor_top = 0.0
	reset_clip.anchor_bottom = 1.0
	reset_clip.offset_left = -(reset_width + reset_gap)
	reset_clip.offset_right = -reset_gap
	reset_clip.offset_top = 0.0
	reset_clip.offset_bottom = 0.0
	overlay_root.add_child(reset_clip)

	reset_btn.anchor_left = 0.5
	reset_btn.anchor_right = 0.5
	reset_btn.anchor_top = 0.0
	reset_btn.anchor_bottom = 1.0
	reset_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var button_width := reset_btn.get_combined_minimum_size().x
	reset_btn.offset_left = -button_width * 0.5
	reset_btn.offset_right = button_width * 0.5
	reset_btn.offset_top = 0.0
	reset_btn.offset_bottom = 0.0

	reset_clip.add_child(reset_btn)


	_update_point_reset_button_label_margin(reset_btn)

	return property_header


func _create_native_point_property_header(
	point: Resource,
	property_name: StringName,
	label_text: String,
) -> PanelContainer:
	var property_header := PanelContainer.new()
	property_header.focus_mode = Control.FOCUS_NONE
	property_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	property_header.size_flags_vertical = Control.SIZE_EXPAND_FILL
	property_header.size_flags_stretch_ratio = POINT_PROPERTY_HEADER_RATIO
	property_header.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	property_header.set_meta(&"point_resource_id", point.get_instance_id())
	property_header.set_meta(&"point_property_name", property_name)

	var point_index: int = _native_point_storage_indices.get(point.get_instance_id(), -1)
	var property_path := _point_property_path(point_index, property_name)
	property_header.tooltip_text = property_path

	var property_context_menu := (
		_point_property_clipboard.create_point_context_menu(
			_native_curve,
			point,
			property_name,
			Callable(self, "_apply_editor_point_property_change"),
		)
	)
	property_header.add_child(property_context_menu)
	property_header.gui_input.connect(
		func(event: InputEvent) -> void:
			if not event is InputEventMouseButton or not event.pressed:
				return
			if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				return
			_select_native_point_property(property_header, point, property_name)
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_point_property_clipboard.update_context_menu_paste_enabled(
					property_context_menu,
					property_name,
				)
				property_context_menu.position = DisplayServer.mouse_get_position()
				property_context_menu.popup()
				property_header.accept_event()
	)

	if (
		_point_list_controller.selected_point_resource_id == point.get_instance_id()
		and _point_list_controller.selected_point_property_name == property_name
	):
		_attach_selected_point_property_header(property_header)

	var property_label := Label.new()
	property_label.text = label_text
	property_label.tooltip_text = property_path
	property_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	property_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_configure_compact_label(property_label)
	property_header.add_child(property_label)
	property_header.set_meta(&"point_label", property_label)
	return property_header


func _select_native_point_property(
	property_header: PanelContainer,
	point: Resource,
	property_name: StringName,
) -> void:
	var backend := BackendFactory.create(_native_curve)
	var point_index: int = backend.find_point(point) if backend != null else -1
	if point_index < 0:
		return
	if is_instance_valid(_selected_point_property_header):
		_set_point_property_selected(_selected_point_property_header, false)
	_point_list_controller.assign_logical_selection(
		_native_curve,
		point_index,
		property_name,
	)
	_attach_selected_point_property_header(property_header)
	_select_native_point(point)


## Curve
var editor_undo_redo: EditorUndoRedoManager: # assigned from EditorPlugin
	set(value):
		editor_undo_redo = value
		_point_edit_transaction_controller.setup(
			value,
			Callable(self, "_undo_source_property"),
		)
var easing_curve_editor: EasingCurveEditor
var curve_editor_property: EditorProperty
var _curve_editor_section: PointsFoldableSection
var ease_option: OptionButton
var preset_reset_button: Button
var curve: EasingCurve
var _instantiating_default_property := false
var _selected_point_property_header: PanelContainer
var _point_list_controller := PointListController.new()
var _position_x_order_preview_point: EasingCurvePoint
var _initial_autofit_resource_ids: Dictionary[int, bool] = {}
# Shared by Inspector parse contexts through the plugin. Legacy graph selection
# must survive property-list rebuilds caused by add/drag topology publication.
var _legacy_selection_by_resource: Dictionary[int, Dictionary] = {}
var _legacy_delete_drag_by_resource: Dictionary[int, Dictionary] = {}


class AutofitRequest:
	var editor: WeakRef
	var section: WeakRef
	var last_graph_rect := Rect2()


var _autofit_requests: Dictionary[int, AutofitRequest] = {}
var _autofit_request_id := 0
var _autofit_rebuild_resources: Dictionary[int, WeakRef] = {}


func _detach_selected_point_property_header() -> void:
	_selected_point_property_header = null


func _attach_selected_point_property_header(
		property_header: PanelContainer,
) -> void:
	_detach_selected_point_property_header()
	_selected_point_property_header = property_header
	_set_point_property_selected(property_header, true)


func _sync_graph_selected_point_index(point_index: int) -> void:
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.selected_index = point_index
	elif _native_curve != null:
		native_selection_changed.emit(_point_at(_native_curve, point_index))


func _clear_point_property_selection() -> void:
	if is_instance_valid(_selected_point_property_header):
		_set_point_property_selected(
			_selected_point_property_header,
			false
		)

	_detach_selected_point_property_header()
	_point_list_controller.clear_logical_selection()


func _capture_point_selection_state() -> Dictionary:
	var graph_selected_index := -1
	if is_instance_valid(easing_curve_editor):
		graph_selected_index = easing_curve_editor.selected_index
	return _point_list_controller.capture_selection(
		_point_list_curve_resource(),
		graph_selected_index,
	)


func _persist_legacy_selection() -> void:
	if curve == null:
		return
	var curve_id := curve.get_instance_id()
	var selection := _capture_point_selection_state()
	if not bool(selection.get("has_selection", false)):
		_legacy_selection_by_resource.erase(curve_id)
		return
	_legacy_selection_by_resource[curve_id] = {
		"curve": weakref(curve),
		"selection": selection.duplicate(true),
	}


func _restore_persisted_legacy_selection(curve_resource: EasingCurve) -> int:
	if curve_resource == null:
		return -1
	var curve_id := curve_resource.get_instance_id()
	var state: Dictionary = _legacy_selection_by_resource.get(curve_id, {})
	if state.is_empty():
		return -1
	var curve_ref := state.get("curve") as WeakRef
	if curve_ref == null or curve_ref.get_ref() != curve_resource:
		_legacy_selection_by_resource.erase(curve_id)
		return -1
	var selection: Dictionary = state.get("selection", {})
	if selection.is_empty():
		_legacy_selection_by_resource.erase(curve_id)
		return -1
	var point_index := _point_list_controller.restore_selection(curve_resource, selection)
	if point_index == -1:
		_legacy_selection_by_resource.erase(curve_id)
	return point_index


func _on_legacy_graph_selection_changed(point: Resource) -> void:
	if (
		disposed
		or curve == null
		or not is_instance_valid(easing_curve_editor)
		or easing_curve_editor.get_curve() != curve
	):
		return
	if point == null:
		_point_list_controller.clear_logical_selection()
		_persist_legacy_selection()
		return
	var legacy_point := point as EasingCurvePoint
	var point_index := _get_current_point_index(legacy_point) if legacy_point != null else -1
	if point_index < 0:
		return
	_point_list_controller.assign_logical_selection(
		curve,
		point_index,
		_point_list_controller.selected_point_property_name,
	)
	_persist_legacy_selection()


func _restore_point_selection_state(selection: Dictionary) -> void:
	var point_index := _point_list_controller.restore_selection(
		_point_list_curve_resource(),
		selection,
	)
	if point_index == -1:
		if is_instance_valid(_selected_point_property_header):
			_set_point_property_selected(_selected_point_property_header, false)
		_detach_selected_point_property_header()
		_sync_graph_selected_point_index(-1)
		return

	_point_list_controller.request_selection_refresh_preservation()
	_detach_selected_point_property_header()
	_sync_graph_selected_point_index(point_index)

func handle_points(curve: EasingCurve) -> VBoxContainer:
	var list := _point_list_controller.build_point_list(
		curve,
		_compact_separation(),
		_point_separation(),
		Callable(self, "_create_bool_property"),
		Callable(self, "_create_vector2_property"),
		Callable(self, "_create_handle_mode_property"),
		Callable(self, "_move_point"),
		Callable(self, "_on_remove_btn_pressed"),
	)
	list.point_swap_requested.disconnect(_move_point)
	list.point_swap_requested.connect(_on_point_list_swap.bind(list))
	return list


func _create_point_add_controls() -> Control:
	var row := CappedHorizontalControlRow.new()
	row.name = &"PointAddControls"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_separation(_compact_separation())

	var handle_mode := HorizontallyShrinkableOptionButton.new()
	handle_mode.name = &"NewPointHandleMode"
	handle_mode.tooltip_text = (
		"Default handle mode for points created by graph click or Add Point"
	)
	_configure_compact_option(handle_mode)
	handle_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_new_point_handle_mode_items(handle_mode)
	_sync_new_point_handle_mode_option(
		CurveEditorSettings.get_default_new_point_handle_mode(),
		handle_mode,
	)
	handle_mode.item_selected.connect(
		func(index: int) -> void:
			CurveEditorSettings.set_default_new_point_handle_mode(
				handle_mode.get_item_id(index)
			)
	)
	var sync_callback := func(value: int) -> void:
		_sync_new_point_handle_mode_option(value, handle_mode)
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.default_new_point_handle_mode_changed.connect(sync_callback)
		row.tree_exiting.connect(
			_disconnect_new_point_handle_mode_option.bind(
				easing_curve_editor,
				sync_callback,
			)
		)
	var handle_mode_slot := HorizontallyShrinkableControlSlot.new()
	handle_mode_slot.name = &"NewPointHandleModeSlot"
	handle_mode_slot.set_content(
		handle_mode,
		_measure_new_point_handle_mode_size(),
	)
	row.add_child(handle_mode_slot)

	var add_button := HorizontallyShrinkableButton.new()
	_configure_add_point_button(add_button)
	add_button.pressed.connect(_on_add_point_btn_pressed)
	var add_button_slot := HorizontallyShrinkableControlSlot.new()
	add_button_slot.name = &"AddPointSlot"
	add_button_slot.set_content(add_button, _measure_add_point_button_size())
	row.add_child(add_button_slot)
	return row


func _add_new_point_handle_mode_items(option: OptionButton) -> void:
	option.add_icon_item(EDITOR_THEME_CACHE.get_icon(&"BezierHandlesFree"), "Free", EasingCurvePoint.HandleMode.FREE)
	option.add_icon_item(EDITOR_THEME_CACHE.get_icon(&"BezierHandlesLinear"), "Linear", EasingCurvePoint.HandleMode.LINEAR)
	option.add_icon_item(EDITOR_THEME_CACHE.get_icon(&"BezierHandlesBalanced"), "Balanced", EasingCurvePoint.HandleMode.BALANCED)
	option.add_icon_item(EDITOR_THEME_CACHE.get_icon(&"BezierHandlesMirror"), "Mirrored", EasingCurvePoint.HandleMode.MIRRORED)
	option.add_icon_item(load("res://addons/easing_curve/assets/BezierHandlesLinked.svg"), "Linked", EasingCurvePoint.HandleMode.LINKED)


func _measure_new_point_handle_mode_size() -> Vector2:
	var measurement := OptionButton.new()
	measurement.fit_to_longest_item = false
	_add_new_point_handle_mode_items(measurement)
	# Godot 4.4–4.6 defer item sizing; toggle this after population to refresh now.
	measurement.fit_to_longest_item = true
	var preferred_size := measurement.get_combined_minimum_size()
	measurement.free()
	return preferred_size


func _configure_add_point_button(button: Button) -> void:
	button.name = &"AddPoint"
	button.icon = EDITOR_THEME_CACHE.get_icon(EDITOR_THEME_CACHE.ICON_ADD)
	button.text = "Add Point"
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _measure_add_point_button_size() -> Vector2:
	var measurement := Button.new()
	_configure_add_point_button(measurement)
	measurement.clip_text = false
	var preferred_size := measurement.get_combined_minimum_size()
	var font := measurement.get_theme_font(&"font")
	var font_size := measurement.get_theme_font_size(&"font_size")
	var text_size := font.get_string_size(
		measurement.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
	)
	var content_width := text_size.x
	if measurement.icon != null:
		var icon_width := float(measurement.icon.get_width())
		var icon_max_width := measurement.get_theme_constant(&"icon_max_width")
		if icon_max_width > 0:
			icon_width = minf(icon_width, icon_max_width)
		content_width += (
			icon_width + measurement.get_theme_constant(&"h_separation")
		)
	var normal_style := measurement.get_theme_stylebox(&"normal")
	preferred_size.x = maxf(
		preferred_size.x,
		content_width + normal_style.get_minimum_size().x,
	)
	measurement.free()
	return preferred_size


func _sync_new_point_handle_mode_option(
	handle_mode: int,
	option: OptionButton,
) -> void:
	if not is_instance_valid(option):
		return
	for index in range(option.item_count):
		if option.get_item_id(index) == handle_mode:
			option.select(index)
			return


func _disconnect_new_point_handle_mode_option(
	editor,
	callback: Callable,
) -> void:
	if (
		is_instance_valid(editor)
		and editor.default_new_point_handle_mode_changed.is_connected(callback)
	):
		editor.default_new_point_handle_mode_changed.disconnect(callback)


static func _get_normal_point_property_definitions(
		point_index: int,
		point_count: int,
) -> Array[Dictionary]:
	return PointListController.get_normal_point_property_definitions(
		point_index,
		point_count,
	)


func _create_normal_point_property_rows(
		point: EasingCurvePoint,
		point_index: int,
		point_count: int,
		property_grid: GridContainer,
) -> void:
	PointListController.create_normal_point_property_rows(
		point,
		point_index,
		point_count,
		property_grid,
		Callable(self, "_create_bool_property"),
		Callable(self, "_create_vector2_property"),
		Callable(self, "_create_handle_mode_property"),
	)


func handle_easing_curve_editor(object: Resource) -> Control:
	if object == null:
		return null
	resource = object
	var backend := BackendFactory.create(object)
	if backend != null and backend.get_backend_id() == &"native":
		return _handle_native_curve_editor(object)
	if object is EasingCurve:
		var curve_section := VBoxContainer.new()
		curve_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		curve_section.add_theme_constant_override("separation", _compact_separation())

		# Add toolbar
		var _toolbar := GridContainer.new()
		_toolbar.columns = 3
		_toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_toolbar.add_theme_constant_override("h_separation", _compact_separation())
		_toolbar.add_theme_constant_override("v_separation", _compact_separation())
		_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Toolbar setup
		var ease_reset_button := _create_reserved_reset_button("Reset Ease to In")
		preset_reset_button = _create_reserved_reset_button("Restore selected preset geometry")
		ease_option = _create_option(EasingCurve.EASE, object.ease_type)
		var trans_option := _create_transition_option(
			object.trans_type
		)

		# A fixed three-column grid aligns both dropdowns and both trailing reset slots.
		_toolbar.add_child(_create_option_label("Ease"))
		_toolbar.add_child(ease_option)
		_toolbar.add_child(ease_reset_button)
		_toolbar.add_child(_create_option_label("Trans"))
		_toolbar.add_child(trans_option)
		_toolbar.add_child(preset_reset_button)

		# Keep references
		curve_section.add_child(_toolbar)

		var point_toolbar_gap := Control.new()
		point_toolbar_gap.custom_minimum_size.y = _compact_separation()
		curve_section.add_child(point_toolbar_gap)


		var curve_editor_content := VBoxContainer.new()
		curve_editor_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		curve_editor_content.add_theme_constant_override(
			"separation",
			_compact_separation(),
		)
		########################################
		# Add curve editor
		easing_curve_editor = EasingCurveEditor.new()
		easing_curve_editor.ready.connect(_align_preset_label_column.bind(_toolbar, easing_curve_editor))
		easing_curve_editor.presentation_owned = true
		# A Legacy deletion rebuilds this context while RMB is still held.
		easing_curve_editor.right_delete_drag_states = _legacy_delete_drag_by_resource
		easing_curve_editor.editor_undo_redo = editor_undo_redo
		easing_curve_editor.set_curve(object)
		_connect_graph_swap_request()
		var restored_selection := _restore_persisted_legacy_selection(object)
		_sync_graph_selected_point_index(restored_selection)

		# Restore the Resource-owned transient Curve Editor view state. The later
		# slider initialization intentionally remains the canonical zoom source.
		var view_state: Dictionary = object._get_curve_editor_view_state()
		easing_curve_editor.set_zoom(
			view_state[EasingCurve.CURVE_EDITOR_VIEW_ZOOM]
		)
		easing_curve_editor.set_pan(
			view_state[EasingCurve.CURVE_EDITOR_VIEW_PAN]
		)

		# Connect curve editor signals
		easing_curve_editor.slider_changed.connect(object._on_curve_editor_slider_value_changed)
		easing_curve_editor.zoom_changed.connect(object._on_curve_editor_zoom_changed)
		easing_curve_editor.pan_changed.connect(object._on_curve_editor_pan_changed)
		easing_curve_editor.point_changed.connect(_on_curve_editor_point_changed)
		easing_curve_editor.point_selection_changed.connect(_on_legacy_graph_selection_changed)
		easing_curve_editor.point_property_change_requested.connect(_apply_point_property_change)
		easing_curve_editor.point_add_requested.connect(_on_curve_editor_point_add_requested)
		easing_curve_editor.point_remove_requested.connect(_remove_point)
		easing_curve_editor.point_move_up_requested.connect(
			Callable(_point_list_controller, "request_move_up").bind(
				object,
				Callable(self, "_move_point"),
			)
		)
		easing_curve_editor.point_move_down_requested.connect(
			Callable(_point_list_controller, "request_move_down").bind(
				object,
				Callable(self, "_move_point"),
			)
		)
		easing_curve_editor.point_edit_finished.connect(_commit_point_edit)
		easing_curve_editor.point_edit_cancelled.connect(_cancel_point_edit)

		# Store reference to curve resource
		curve = object
		_point_edit_transaction_controller.reset_point_edit()
		# Connect ease/trans preset selected signals
		var resource_ease_option := ease_option
		resource_ease_option.item_selected.connect(
			func(idx):
				_emit_curve_property(&"ease_type", resource_ease_option.get_item_id(idx), object)
		)

		trans_option.item_selected.connect(
			func(idx):
				_emit_curve_property(&"trans_type", trans_option.get_item_id(idx), object)
		)

		ease_reset_button.pressed.connect(_on_reset_ease.bind(object))
		preset_reset_button.pressed.connect(_on_reset_selected_preset.bind(object))
		var preset_state_callback := _on_legacy_preset_state_changed.bind(
			object,
			ease_option,
			trans_option,
			ease_reset_button,
			preset_reset_button,
		)
		object.changed.connect(preset_state_callback)
		curve_section.tree_exiting.connect(
			_disconnect_preset_state_ui.bind(object, preset_state_callback),
		)
		_update_preset_state_ui(
			object,
			ease_option,
			trans_option,
			ease_reset_button,
			preset_reset_button,
		)

		# Add curve editor
		curve_editor_content.add_child(easing_curve_editor)
		easing_curve_editor.resized.connect(easing_curve_editor.update_minimum_size)

		easing_curve_editor.setup_zoom_row()
		easing_curve_editor.set_slider_value(
			view_state[EasingCurve.CURVE_EDITOR_VIEW_SLIDER_VALUE]
		)
		_curve_editor_section = _create_foldable_section(
			"Curve Editor",
			curve_editor_content,
			object,
		) as PointsFoldableSection
		_curve_editor_section.folding_changed.connect(
			_on_curve_editor_section_folding_changed.bind(weakref(easing_curve_editor))
		)
		curve_section.add_child(_curve_editor_section)
		if _consume_rebuild_autofit(object) or _consume_initial_autofit(object):
			_queue_autofit_curve_editor()
		########################################
		_retain_presentation_root(curve_section, true)
		return curve_section
	return null


func _handle_native_curve_editor(
	object: Resource,
	editor_override: EasingCurveEditor = null,
) -> Control:
	if _detached_native_editor != null:
		_finish_applied_point_edit()
	_native_curve = object
	_native_editor_generation += 1
	_cancel_pending_native_point_edit_finish()
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", _compact_separation())
	var backend := BackendFactory.create(object)

	# Mirror the legacy resource header instead of showing Native's internal
	# modified-state label. The asterisk lives in the selected Trans item and
	# the reset action keeps its reserved trailing slot.
	var toolbar := GridContainer.new()
	toolbar.name = &"CurvePresetToolbar"
	toolbar.columns = 3
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_theme_constant_override("h_separation", _compact_separation())
	toolbar.add_theme_constant_override("v_separation", _compact_separation())
	var ease_reset := _create_reserved_reset_button("Reset Ease to In")
	var preset_reset := _create_reserved_reset_button("Restore selected preset geometry")
	var native_ease_option := _create_option(EasingCurve.EASE, int(object.get(&"ease_type")))
	native_ease_option.name = &"CurveEase"
	var native_trans_option := _create_native_transition_option(
		int(object.get(&"transition")),
		backend.get_transition_ids() if backend != null else PackedInt32Array(),
	)
	native_trans_option.name = &"CurveTransition"
	toolbar.add_child(_create_option_label("Ease"))
	toolbar.add_child(native_ease_option)
	toolbar.add_child(ease_reset)
	toolbar.add_child(_create_option_label("Trans"))
	toolbar.add_child(native_trans_option)
	toolbar.add_child(preset_reset)
	root.add_child(toolbar)

	var toolbar_gap := Control.new()
	toolbar_gap.custom_minimum_size.y = _compact_separation()
	root.add_child(toolbar_gap)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", _compact_separation())

	easing_curve_editor = (
		editor_override
		if is_instance_valid(editor_override)
		else EasingCurveEditor.new()
	)
	easing_curve_editor.ready.connect(_align_preset_label_column.bind(toolbar, easing_curve_editor))
	easing_curve_editor.presentation_owned = true
	easing_curve_editor.editor_undo_redo = editor_undo_redo
	easing_curve_editor.set_curve(object)
	_connect_graph_swap_request()
	_sync_graph_selected_point_index(_selected_point_index_for_resource(object))
	easing_curve_editor.point_selection_changed.connect(_on_native_graph_selection_changed)
	var resource_editor := easing_curve_editor
	preset_reset.pressed.connect(easing_curve_editor.reset_native_preset)
	ease_reset.pressed.connect(_queue_autofit_curve_editor)
	ease_reset.pressed.connect(
		easing_curve_editor.edit_curve_property.bind(&"ease_type", EasingCurve.EASE.IN)
	)
	native_ease_option.item_selected.connect(
		func(index: int) -> void:
			_queue_autofit_curve_editor()
			resource_editor.edit_curve_property(
				&"ease_type",
				native_ease_option.get_item_id(index),
			)
	)
	native_trans_option.item_selected.connect(
		func(index: int) -> void:
			if object.get(&"transition") != native_trans_option.get_item_id(index):
				_clear_transition_selection()
			resource_editor.edit_curve_property(
				&"transition",
				native_trans_option.get_item_id(index),
			)
	)
	content.add_child(easing_curve_editor)
	easing_curve_editor.resized.connect(easing_curve_editor.update_minimum_size)

	easing_curve_editor.setup_zoom_row()
	easing_curve_editor.set_slider_value(EasingCurve.DEFAULT_SLIDER_VALUE)

	_curve_editor_section = _create_foldable_section(
		"Curve Editor",
		content,
		object,
	) as PointsFoldableSection
	_curve_editor_section.folding_changed.connect(
		_on_curve_editor_section_folding_changed.bind(weakref(easing_curve_editor))
	)
	root.add_child(_curve_editor_section)

	var changed_callback := _on_native_curve_changed.bind(
		object,
		native_ease_option,
		native_trans_option,
		ease_reset,
		preset_reset,
	)
	object.changed.connect(changed_callback)
	root.tree_exiting.connect(_disconnect_native_curve_changed.bind(object, changed_callback))
	_update_native_preset_state_ui(
		object,
		native_ease_option,
		native_trans_option,
		ease_reset,
		preset_reset,
	)
	_queue_autofit_curve_editor()
	_retain_presentation_root(root, true)
	return root


func _handle_native_points(object: Resource) -> Control:
	_native_points_generation += 1
	_native_points_refresh_queued = false
	_native_points_content = PointsListContainer.new()
	_native_points_content.connect(
		&"point_swap_requested",
		_on_point_list_swap.bind(_native_points_content),
	)
	_native_points_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_native_point_list(object)
	var section := _create_points_section(_native_points_content, object)
	var changed_callback := _on_native_points_changed.bind(object)
	object.changed.connect(changed_callback)
	section.tree_exiting.connect(_disconnect_native_curve_changed.bind(object, changed_callback))
	return section


func _create_points_section(point_list: Control, object: Resource) -> Control:
	var content := VBoxContainer.new()
	content.name = &"PointsContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", _compact_separation())
	content.add_child(_create_point_add_controls())
	content.add_child(point_list)
	var section := _create_inspector_section("Points", content, object)
	_retain_presentation_root(section)
	return section


func _on_native_curve_changed(
	object: Resource,
	ease_control: OptionButton,
	trans_control: OptionButton,
	ease_reset: Button,
	preset_reset: Button,
) -> void:
	_update_native_preset_state_ui(
		object,
		ease_control,
		trans_control,
		ease_reset,
		preset_reset,
	)


func _on_native_points_changed(object: Resource) -> void:
	if disposed:
		return
	var backend := BackendFactory.create(object)
	var identity_signature := (
		_get_native_point_identity_signature(backend.get_display_points())
		if backend != null
		else PackedInt64Array()
	)
	var transform_flags := Vector2i(int(object.get(&"reverse")), int(object.get(&"invert")))
	if (identity_signature != _native_point_identity_signature or bool(transform_flags.x) != _native_panel_reverse) and not _native_points_refresh_queued:
		_native_points_refresh_queued = true
		_refresh_native_point_list_if_current.call_deferred(object, _native_points_generation)
	if transform_flags != _native_point_transform_flags:
		_native_point_transform_flags = transform_flags
		native_point_display_changed.emit()


func _on_native_graph_selection_changed(point: Resource) -> void:
	if disposed or not is_instance_valid(easing_curve_editor) or easing_curve_editor.get_curve() != _native_curve:
		return
	var backend := BackendFactory.create(_native_curve)
	_point_list_controller.assign_logical_selection(
		_native_curve, backend.find_point(point) if point != null else -1,
		_point_list_controller.selected_point_property_name,
	)
	native_selection_changed.emit(point)


func _disconnect_native_curve_changed(object: Resource, callback: Callable) -> void:
	if object != null and object.changed.is_connected(callback):
		object.changed.disconnect(callback)


func _update_native_preset_state_ui(
	object: Resource,
	ease_control: OptionButton,
	trans_control: OptionButton,
	ease_reset: Button,
	reset_button: Button,
) -> void:
	if (
		object == null
		or not is_instance_valid(ease_control)
		or not is_instance_valid(trans_control)
		or not is_instance_valid(ease_reset)
		or not is_instance_valid(reset_button)
	):
		return
	var modified := bool(object.call(&"is_selected_preset_modified"))
	var transition := int(object.get(&"transition"))
	var ease_type := int(object.get(&"ease_type"))
	var ease_index := ease_control.get_item_index(ease_type)
	if ease_index >= 0:
		ease_control.select(ease_index)
	var trans_index := trans_control.get_item_index(transition)
	if trans_index >= 0:
		trans_control.select(trans_index)
	var ease_available := _native_transition_supports_ease(transition) and not modified
	ease_control.disabled = not ease_available
	_set_preset_reset_button_available(
		ease_reset,
		ease_available and ease_type != EasingCurve.EASE.IN,
	)
	_set_native_transition_display(trans_control, transition, modified)
	_set_preset_reset_button_available(reset_button, modified)


func _refresh_native_point_list_if_current(object: Resource, generation: int) -> void:
	if generation == _native_points_generation:
		_refresh_native_point_list(object)


func _refresh_native_point_list(object: Resource) -> void:
	if disposed or not is_instance_valid(_native_points_content) or object != _native_curve:
		return
	# Reverse changes stored-side bindings, so it is an editing boundary.
	if bool(object.get(&"reverse")) != _native_panel_reverse:
		_finish_applied_point_edit()
	_native_points_refresh_queued = false
	# A queued refresh must not end a newer gesture or free its focused inputs.
	if (
		(is_instance_valid(easing_curve_editor) and easing_curve_editor._backend_point_edit_active)
		or (_detached_native_editor != null and not _detached_native_editor._before.is_empty())
	):
		_native_points_refresh_queued = true
		_native_points_content.get_tree().process_frame.connect(
			_refresh_native_point_list_if_current.bind(object, _native_points_generation), CONNECT_ONE_SHOT,
		)
		return
	_reconcile_native_point_panels(object)


func _build_native_point_list(object: Resource) -> void:
	if not is_instance_valid(_native_points_content):
		return
	var backend := BackendFactory.create(object)
	if backend == null:
		return
	var points: Array[Resource] = backend.get_display_points()
	_cache_native_storage_indices(backend.get_points())
	for index in range(points.size()):
		var panel := _create_native_point_panel(points[index], index, points.size())
		_native_points_content.add_child(panel)
		_native_points_content.call(&"enable_drop_forwarding", panel)
	_native_point_identity_signature = _get_native_point_identity_signature(points)
	_native_point_transform_flags = Vector2i(int(object.get(&"reverse")), int(object.get(&"invert")))
	_native_panel_reverse = bool(object.get(&"reverse"))


func _cache_native_storage_indices(points: Array[Resource]) -> void:
	_native_point_storage_indices.clear()
	for index in range(points.size()):
		_native_point_storage_indices[points[index].get_instance_id()] = index


static func _native_panel_shape(index: int, count: int) -> Vector2i:
	return Vector2i(int(index > 0), int(index < count - 1))


func _reconcile_native_point_panels(object: Resource) -> void:
	var backend := BackendFactory.create(object)
	if backend == null:
		return
	var storage_points: Array[Resource] = backend.get_points()
	_cache_native_storage_indices(storage_points)
	# Native's display order is storage order with the Reverse transform applied.
	var points: Array[Resource] = storage_points.duplicate()
	var reverse := bool(object.get(&"reverse"))
	if reverse:
		points.reverse()
	var replace_bindings := reverse != _native_panel_reverse
	var panels: Dictionary[int, Control] = {}
	for child in _native_points_content.get_children():
		var point: Resource = child.get_meta(&"point_resource", null)
		if point == null or replace_bindings or not _native_point_storage_indices.has(point.get_instance_id()):
			_remove_native_point_panel(child)
		else:
			panels[point.get_instance_id()] = child

	var selected_point: Resource
	var selected_index: int = _native_point_storage_indices.get(_point_list_controller.selected_point_resource_id, -1)
	if selected_index >= 0:
		selected_point = storage_points[selected_index]
	var selected_id := selected_point.get_instance_id() if selected_point != null else 0
	_point_list_controller.selected_point_index = _native_point_storage_indices.get(selected_id, -1)
	_point_list_controller.selected_point_resource_id = selected_id
	if is_instance_valid(_selected_point_property_header):
		_set_point_property_selected(_selected_point_property_header, false)
	_detach_selected_point_property_header()

	for index in range(points.size()):
		var point := points[index]
		var id := point.get_instance_id()
		var panel: Control = panels.get(id)
		if panel != null and panel.get_meta(&"point_shape") != _native_panel_shape(index, points.size()):
			_remove_native_point_panel(panel)
			panel = null
		if panel == null:
			panel = _create_native_point_panel(point, index, points.size())
			_native_points_content.add_child(panel)
			_native_points_content.enable_drop_forwarding(panel)
		if panel.get_index() != index:
			_native_points_content.move_child(panel, index)
		_refresh_native_point_panel_metadata(panel, index, _native_point_storage_indices[id])
	_native_point_identity_signature = _get_native_point_identity_signature(points)
	_native_panel_reverse = reverse
	_native_point_transform_flags = Vector2i(int(reverse), int(object.get(&"invert")))
	# Neighbor changes can affect Linear aliases without changing a point's stored state.
	native_point_display_changed.emit()
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.selected_index = selected_index
	else:
		native_selection_changed.emit(selected_point)


func _remove_native_point_panel(panel: Control) -> void:
	if is_instance_valid(_selected_point_property_header) and panel.is_ancestor_of(_selected_point_property_header):
		_detach_selected_point_property_header()
	_disconnect_native_panel_callbacks(panel)
	if panel.get_parent() != null:
		panel.get_parent().remove_child(panel)
	panel.free()


func _disconnect_native_panel_callbacks(panel: Control) -> void:
	for callback: Callable in panel.get_meta(&"point_cleanup", []):
		callback.call()
	panel.set_meta(&"point_cleanup", [])


func _refresh_native_point_panel_metadata(panel: Control, display_index: int, storage_index: int) -> void:
	var drag_handle: EasingCurveDragHandle = panel.get_meta(&"point_drag_handle")
	drag_handle.index = display_index
	for header: PanelContainer in panel.get_meta(&"point_headers", []):
		var property_name: StringName = header.get_meta(&"point_property_name")
		var path := _point_property_path(storage_index, property_name)
		header.tooltip_text = path
		var label: Label = header.get_meta(&"point_label")
		label.tooltip_text = path
		if (
			header.get_meta(&"point_resource_id") == _point_list_controller.selected_point_resource_id
			and property_name == _point_list_controller.selected_point_property_name
		):
			_attach_selected_point_property_header(header)


func _create_transition_generate_action(object: Resource) -> EditorProperty:
	var backend := BackendFactory.create(object)
	if backend == null:
		return null
	var transition := int(
		object.get(&"transition")
		if backend.get_backend_id() == &"native"
		else object.get(&"trans_type")
	)
	var generated_transitions := (
		PackedInt32Array([102, 103])
		if backend.get_backend_id() == &"native"
		else PackedInt32Array([
			EasingCurve.TRANS.JITTER,
			EasingCurve.TRANS.IRREGULAR,
		])
	)
	if transition not in generated_transitions:
		return null
	var generate_editor := GenerateFunctionEditorProperty.new()
	generate_editor.name = &"GenerateControls"
	generate_editor.setup(easing_curve_editor, editor_undo_redo)
	# Generate is an action, not a second editable Randomness property.
	generate_editor.set_object_and_property(object, &"")
	return generate_editor


func _get_native_point_identity_signature(points: Array[Resource]) -> PackedInt64Array:
	var signature := PackedInt64Array()
	for point in points:
		if is_instance_valid(point):
			signature.append(point.get_instance_id())
	return signature


func _create_native_point_panel(
	point: Resource,
	index: int,
	point_count: int,
) -> Control:
	var panel := PanelContainer.new()
	panel.set_meta(&"point_resource", point)
	panel.set_meta(&"point_shape", _native_panel_shape(index, point_count))
	panel.set_meta(&"point_headers", [])
	panel.set_meta(&"point_cleanup", [])
	panel.tree_exiting.connect(_disconnect_native_panel_callbacks.bind(panel))
	panel.add_theme_stylebox_override(&"panel", _zero_margin_panel_stylebox)
	var selection_callback := func(selected_point: Resource) -> void:
		_update_native_point_panel_selection(selected_point, panel, point)
	native_selection_changed.connect(selection_callback)
	panel.get_meta(&"point_cleanup").append(_disconnect_native_selection_callback.bind(selection_callback))
	panel.tree_exiting.connect(
		_disconnect_native_selection_callback.bind(selection_callback)
	)
	_update_native_point_panel_selection(
		easing_curve_editor.get_selected_point_resource() if is_instance_valid(easing_curve_editor)
			else _point_at(_native_curve, _point_list_controller.selected_point_index),
		panel,
		point,
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", _compact_separation())
	panel.add_child(row)

	var move_buttons := VBoxContainer.new()
	move_buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var move_up := Button.new()
	move_up.flat = true
	move_up.icon = EDITOR_THEME_CACHE.get_icon(EDITOR_THEME_CACHE.ICON_MOVE_UP)
	move_up.tooltip_text = "Swap Previous Point"
	move_up.pressed.connect(
		_move_point_relative.bind(point, -1)
	)
	move_buttons.add_child(move_up)
	var drag_handle := EasingCurveDragHandle.new()
	drag_handle.texture = EDITOR_THEME_CACHE.get_icon(EDITOR_THEME_CACHE.ICON_TRIPLE_BAR)
	drag_handle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drag_handle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	drag_handle.focus_mode = Control.FOCUS_ALL
	drag_handle.index = index
	drag_handle.point_panel = panel
	drag_handle.point_list = _native_points_content
	panel.set_meta(&"point_drag_handle", drag_handle)
	move_buttons.add_child(drag_handle)
	var move_down := Button.new()
	move_down.flat = true
	move_down.icon = EDITOR_THEME_CACHE.get_icon(EDITOR_THEME_CACHE.ICON_MOVE_DOWN)
	move_down.tooltip_text = "Swap Next Point"
	move_down.pressed.connect(
		_move_point_relative.bind(point, 1)
	)
	move_buttons.add_child(move_down)
	row.add_child(move_buttons)

	var properties := GridContainer.new()
	properties.set_meta(&"point_panel", panel)
	properties.columns = 2
	properties.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	properties.add_theme_constant_override(&"h_separation", _compact_separation())
	properties.add_theme_constant_override(&"v_separation", _compact_separation())
	row.add_child(properties)
	_add_native_vector_property(properties, point, &"position", "Position")
	_add_native_handle_mode_property(properties, point, index)
	if index > 0:
		_add_native_vector_property(properties, point, &"left_control_point", "Left Control")
	if index < point_count - 1:
		_add_native_vector_property(properties, point, &"right_control_point", "Right Control")

	var remove_button := Button.new()
	remove_button.flat = true
	remove_button.icon = EDITOR_THEME_CACHE.get_icon(EDITOR_THEME_CACHE.ICON_REMOVE)
	remove_button.tooltip_text = "Remove Point"
	remove_button.pressed.connect(_remove_native_point.bind(point))
	row.add_child(remove_button)
	return panel


func _add_native_vector_property(
	grid: GridContainer,
	point: Resource,
	property_name: StringName,
	label_text: String,
) -> void:
	# Bind the displayed handle to its stored side; all edit/selection paths use that property.
	var backend := BackendFactory.create(_native_curve)
	if property_name in [&"left_control_point", &"right_control_point"]:
		var side: int = backend.CONTROL_SIDE_LEFT if property_name == &"left_control_point" else backend.CONTROL_SIDE_RIGHT
		property_name = (
			&"left_control_point"
			if backend.display_control_side_to_curve(side) == backend.CONTROL_SIDE_LEFT
			else &"right_control_point"
		)
	var property_header := _create_native_point_property_header(
		point,
		property_name,
		label_text,
	)
	var panel: Control = grid.get_meta(&"point_panel")
	panel.get_meta(&"point_headers").append(property_header)
	grid.add_child(property_header)
	var values := HBoxContainer.new()
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	values.size_flags_stretch_ratio = POINT_PROPERTY_VALUE_RATIO
	grid.add_child(values)
	var inputs: Array[EditorSpinSlider] = []
	for axis in range(2):
		var input := EditorSpinSlider.new()
		input.label = "X" if axis == 0 else "Y"
		input.min_value = 0.0 if property_name == &"position" else -1024.0
		input.max_value = 1.0 if property_name == &"position" else 1024.0
		input.step = SLIDER_INPUT_STEP
		input.hide_slider = true
		input.flat = true
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value: Vector2 = point.get(property_name)
		input.value = value[axis]
		input.grabbed.connect(
			_on_native_input_grabbed.bind(
				input,
				point,
				property_name,
				property_header,
			)
		)
		input.ungrabbed.connect(
			_on_native_input_ungrabbed.bind(input, point, property_name)
		)
		input.value_focus_entered.connect(
			_on_native_input_value_focus_entered.bind(input, point, property_name)
		)
		input.value_focus_exited.connect(
			_on_native_input_value_focus_exited.bind(input, point, property_name)
		)
		input.focus_entered.connect(
			_select_native_point_property.bind(
				property_header,
				point,
				property_name,
			)
		)
		input.value_changed.connect(
			_on_native_vector_value_changed.bind(
				point,
				property_name,
				axis,
				input,
			)
		)
		_connect_point_list_coordinate_signals(input, point, property_name)
		inputs.append(input)
		values.add_child(input)
	var changed_callback := func():
		_refresh_native_vector_inputs(point, property_name, inputs)
	point.changed.connect(changed_callback)
	native_point_display_changed.connect(changed_callback)
	panel.get_meta(&"point_cleanup").append(_disconnect_native_point_callback.bind(point, changed_callback))
	values.tree_exiting.connect(_disconnect_native_point_callback.bind(point, changed_callback))
	_refresh_native_vector_inputs(point, property_name, inputs)


func _on_native_input_grabbed(
	input: EditorSpinSlider,
	point: Resource,
	property_name: StringName,
	property_header: PanelContainer,
) -> void:
	if disposed:
		return
	if _prepare_native_point_edit(point, property_name):
		return
	_cancel_pending_native_point_edit_finish()
	input.set_meta(DRAGGING_META, true)
	_select_native_point_property(property_header, point, property_name)


func _on_native_input_ungrabbed(
	input: EditorSpinSlider,
	point: Resource,
	property_name: StringName,
) -> void:
	if input.has_meta(DRAGGING_META):
		input.remove_meta(DRAGGING_META)
	_queue_native_point_edit_finish(point, property_name)


func _on_native_input_value_focus_entered(
	input: EditorSpinSlider,
	point: Resource,
	property_name: StringName,
) -> void:
	if disposed:
		return
	if _prepare_native_point_edit(point, property_name):
		return
	_cancel_pending_native_point_edit_finish()
	if input.has_meta(DRAGGING_META):
		input.remove_meta(DRAGGING_META)
	input.set_meta(VALUE_EDITING_META, true)


func _on_native_input_value_focus_exited(
	input: EditorSpinSlider,
	point: Resource,
	property_name: StringName,
) -> void:
	if not input.has_meta(VALUE_EDITING_META):
		return
	input.remove_meta(VALUE_EDITING_META)
	_queue_native_point_edit_finish(point, property_name)


func _queue_native_point_edit_finish(
	point: Resource,
	property_name: StringName,
) -> void:
	if disposed or not is_instance_valid(_native_curve):
		return
	_native_point_edit_finish_request_id += 1
	_finish_native_point_edit_deferred.call_deferred(
		_native_point_edit_finish_request_id,
		_native_editor_generation,
		_native_curve.get_instance_id(),
		easing_curve_editor.get_instance_id() if is_instance_valid(easing_curve_editor) else 0,
		point.get_instance_id() if is_instance_valid(point) else 0,
		_get_native_point_input_edit_property(point, property_name),
	)


func _cancel_pending_native_point_edit_finish() -> void:
	_native_point_edit_finish_request_id += 1


func _finish_native_point_edit_deferred(
	request_id: int,
	editor_generation: int,
	curve_id: int,
	editor_id: int,
	point_id: int,
	property_name: StringName,
) -> void:
	if (
		disposed
		or request_id != _native_point_edit_finish_request_id
		or editor_generation != _native_editor_generation
		or not is_instance_valid(_native_curve)
		or _native_curve.get_instance_id() != curve_id
		or (editor_id != 0 and (not is_instance_valid(easing_curve_editor) or easing_curve_editor.get_instance_id() != editor_id))
	):
		return
	var backend := BackendFactory.create(_native_curve)
	if backend == null:
		return
	var point: Resource
	for index in range(backend.get_point_count()):
		var candidate: Resource = backend.get_point(index)
		if candidate.get_instance_id() == point_id:
			point = candidate
			break
	if not is_instance_valid(easing_curve_editor):
		_native_list_editor().finish()
	elif point != null:
		easing_curve_editor.finish_point_list_edit(point, property_name)
	else:
		easing_curve_editor.finish_active_point_edit()


func _on_native_vector_value_changed(
	value: float,
	point: Resource,
	property_name: StringName,
	axis: int,
	input: EditorSpinSlider,
) -> void:
	if (
		disposed
		or not is_instance_valid(point)
		or not is_instance_valid(input)
	):
		return
	var native_curve := _native_curve
	if native_curve == null:
		return
	var backend := BackendFactory.create(native_curve)
	var current_index: int = backend.find_point(point) if backend != null else -1
	if current_index < 0:
		return
	if not _is_native_point_input_editable(point, property_name):
		input.set_value_no_signal(_get_native_point_display_value(point, property_name)[axis])
		return
	var edit_property := _get_native_point_input_edit_property(point, property_name)
	var vector := _get_native_point_display_value(point, property_name)
	vector[axis] = value
	_edit_native_point_property(
		current_index,
		edit_property,
		backend.display_to_curve_position(vector),
		input.has_meta(DRAGGING_META) or input.has_meta(VALUE_EDITING_META),
	)


func _get_native_point_input_edit_property(point: Resource, property_name: StringName) -> StringName:
	if (
		point != null
		and int(point.get(&"handle_mode")) == EasingCurvePoint.HandleMode.LINEAR
		and property_name in [&"left_control_point", &"right_control_point"]
	):
		return &"position"
	return property_name


func _is_native_point_input_editable(point: Resource, property_name: StringName) -> bool:
	if _get_native_point_input_edit_property(point, property_name) == property_name:
		return true
	var locks: Dictionary = point.get(&"locked")
	return not bool(locks.get(property_name, false)) and not bool(locks.get(&"position", false))


func _refresh_native_vector_inputs(
	point: Resource,
	property_name: StringName,
	inputs: Array[EditorSpinSlider],
) -> void:
	if not is_instance_valid(point):
		return
	var edit_property := _get_native_point_input_edit_property(point, property_name)
	var value := _get_native_point_display_value(point, property_name)
	for axis in range(mini(2, inputs.size())):
		if is_instance_valid(inputs[axis]):
			var signals_blocked := inputs[axis].is_blocking_signals()
			inputs[axis].set_block_signals(true)
			inputs[axis].read_only = not _is_native_point_input_editable(point, property_name)
			inputs[axis].min_value = 0.0 if edit_property == &"position" else -1024.0
			inputs[axis].max_value = 1.0 if edit_property == &"position" else 1024.0
			inputs[axis].set_value_no_signal(value[axis])
			inputs[axis].set_block_signals(signals_blocked)


func _get_native_point_display_value(point: Resource, property_name: StringName) -> Vector2:
	var backend := BackendFactory.create(_native_curve)
	var edit_property := _get_native_point_input_edit_property(point, property_name)
	return backend.curve_to_display_position(point.get(edit_property) as Vector2)


func _add_native_handle_mode_property(
	grid: GridContainer,
	point: Resource,
	_index: int,
) -> void:
	var property_header := _create_native_point_property_header(
		point,
		&"handle_mode",
		"Handle Mode",
	)
	var panel: Control = grid.get_meta(&"point_panel")
	panel.get_meta(&"point_headers").append(property_header)
	grid.add_child(property_header)
	var option := OptionButton.new()
	_configure_compact_option(option)
	option.size_flags_stretch_ratio = POINT_PROPERTY_VALUE_RATIO
	for mode_name in ["Free", "Linear", "Balanced", "Mirrored", "Linked"]:
		option.add_item(mode_name)
	option.select(int(point.get(&"handle_mode")))
	option.focus_entered.connect(
		_select_native_point_property.bind(
			property_header,
			point,
			&"handle_mode",
		)
	)
	option.item_selected.connect(
		func(mode: int):
			if disposed or not is_instance_valid(point):
				return
			var native_curve := _native_curve
			if native_curve == null:
				return
			var backend := BackendFactory.create(native_curve)
			var current_index: int = backend.find_point(point) if backend != null else -1
			if current_index >= 0:
				_select_native_point_property(
					property_header,
					point,
					&"handle_mode",
				)
				_edit_native_point_property(current_index, &"handle_mode", mode)
	)
	var changed_callback := func() -> void:
		if is_instance_valid(option):
			option.select(int(point.get(&"handle_mode")))
	point.changed.connect(changed_callback)
	panel.get_meta(&"point_cleanup").append(_disconnect_native_point_callback.bind(point, changed_callback))
	option.tree_exiting.connect(_disconnect_native_point_callback.bind(point, changed_callback))
	grid.add_child(option)


func _disconnect_native_point_callback(point: Resource, callback: Callable) -> void:
	if is_instance_valid(point) and point.changed.is_connected(callback):
		point.changed.disconnect(callback)
	if native_point_display_changed.is_connected(callback):
		native_point_display_changed.disconnect(callback)


func _update_native_point_panel_selection(
	selected_point: Resource,
	panel: PanelContainer,
	point: Resource,
) -> void:
	if is_instance_valid(panel) and is_instance_valid(point):
		panel.self_modulate = Color(0.72, 0.86, 1.0) if selected_point == point else Color.WHITE


func _disconnect_native_selection_callback(callback: Callable) -> void:
	if native_selection_changed.is_connected(callback):
		native_selection_changed.disconnect(callback)


func _add_conversion_control(
	object: Object,
	attach_after_name: bool = false,
) -> void:
	if _conversion_added:
		return
	var resource := object as Resource
	var backend := BackendFactory.create(resource)
	if backend == null or not bool(backend.get_capabilities().get(backend.CAP_CONVERSION, false)):
		return
	_conversion_added = true
	var conversion_control := CurveConversionControl.new()
	conversion_control.setup(resource)
	if attach_after_name:
		add_property_editor(&"resource_name", conversion_control, true, "")
	else:
		add_custom_control(_create_inspector_section("Conversion", conversion_control, resource))


func _parse_end(object: Object) -> void:
	_add_conversion_control(object)


func _parse_property(object, type, name, hint_type, hint_string, usage_flags, wide):
	if name == "resource_name":
		_add_conversion_control(object, true)

	# Handle properties
	var native_backend := BackendFactory.create(object as Resource)
	if native_backend != null and native_backend.get_backend_id() == &"native":
		if name == "_editor_state_snapshot":
			var native_property := PointsEditorProperty.new()
			native_property.set_content(handle_easing_curve_editor(object))
			curve_editor_property = native_property
			easing_curve_editor.committed_change_publisher = Callable(
				native_property,
				"publish_current_value",
			)
			add_property_editor(name, native_property, false, "")
			return true
		if name in ["transition", "ease_type", "preset_override_active"]:
			return true
		if name == "points":
			if native_backend.is_point_graph():
				add_custom_control(_handle_native_points(object))
			return true
	if object is EasingCurve and name == "easing_curve_editor":
		curve = object
		var content := handle_easing_curve_editor(object)
		var property_editor := PointsEditorProperty.new()
		property_editor.set_content(content)
		curve_editor_property = property_editor
		add_property_editor(
			EasingCurve.FUNCTION_SNAPSHOT_PROPERTY,
			property_editor,
			false,
			String(name).capitalize(),
		)
		return true
	if object is EasingCurve and name == "points":
		curve = object
		if object.curve_mode != object.CurveMode.BEZIER:
			return true
		var point_list := handle_points(object)
		add_custom_control(_create_points_section(point_list, object))
		return true
	if object is EasingCurve and name == EasingCurve.POINT_SNAPSHOT_PROPERTY:
		return true
	if object is EasingCurve and name == EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY:
		return true
	if object is EasingCurve and name == EasingCurve.FUNCTION_SNAPSHOT_PROPERTY:
		return true
	if object is EasingCurve and name == "generate_tool_button":
		return true
	var uses_deferred_parameter_editor: bool = (
		(object is EasingCurve and EasingCurve.is_deferred_parameter(StringName(name)))
		or (
			native_backend != null
			and native_backend.get_backend_id() == &"native"
			and StringName(name) in NATIVE_DEFERRED_PARAMETERS
		)
	)
	if uses_deferred_parameter_editor:
		_instantiating_default_property = true
		var native_editor := EditorInspector.instantiate_property_editor(
			object,
			type,
			name,
			hint_type,
			hint_string,
			usage_flags,
			wide,
		)
		_instantiating_default_property = false
		if native_editor == null:
			return false
		var property_editor := DeferredParameterEditorProperty.new()
		if not property_editor.setup(
			native_editor,
			StringName(name),
			easing_curve_editor,
			editor_undo_redo,
		):
			native_editor.free()
			property_editor.free()
			return false
		add_property_editor(name, property_editor)
		if name == "randomness":
			var generate_editor := _create_transition_generate_action(
				object as Resource,
			)
			if generate_editor != null:
				add_custom_control(generate_editor)
		return true
	return false


func _update_point_reset_btn(
	reset_btn: Button,
	i: int,
	property_name: StringName,
) -> void:
	if (
		i < 0
		or i >= curve.points.size()
		or not EasingCurve.is_point_property_resettable(property_name)
	):
		return

	var value: Vector2 = curve.points[i].get(property_name)
	var default_value: Vector2 = curve.get_default_for_property(
		i,
		property_name
	)

	_set_point_reset_button_available(
		reset_btn,
		not value.is_equal_approx(default_value)
	)


func _on_reset_btn_pressed(
		point: EasingCurvePoint,
		x_input: EditorSpinSlider,
		y_input: EditorSpinSlider,
		property_name: String,
		reset_btn: Button,
) -> void:
	if not EasingCurve.is_point_property_resettable(property_name):
		return
	var i := _get_current_point_index(point)
	if i == -1:
		return
	_point_list_controller.request_selection_refresh_preservation()
	var edit_property_name := _get_point_input_edit_property(point, property_name)
	var new_default := curve.get_default_for_property(i, edit_property_name)

	x_input.set_value_no_signal(new_default.x)
	y_input.set_value_no_signal(new_default.y)
	_apply_point_property_change(
		i,
		edit_property_name,
		new_default,
		false,
		point if edit_property_name == &"position" else null,
	)

	_set_point_reset_button_available(reset_btn, false)


func _on_remove_btn_pressed(p: EasingCurvePoint) -> void:
	_remove_point(p)


func _on_x_input_value_changed(value: float, point: EasingCurvePoint, x_input: EditorSpinSlider, reset_btn: Button, property_name: String) -> void:
	var i := _get_current_point_index(point)
	if i == -1:
		return
	if not _is_point_input_editable(point, property_name):
		return
	var edit_property_name := _get_point_input_edit_property(point, property_name)
	var v: Vector2 = point.get(edit_property_name)
	v.x = value
	_apply_point_property_change(
		i,
		edit_property_name,
		v,
		x_input.has_meta(DRAGGING_META)
			or x_input.has_meta(VALUE_EDITING_META)
			or x_input.has_meta(POSITION_X_EDITING_META),
		point if edit_property_name == &"position" else null,
	)
	i = _get_current_point_index(point)
	_update_point_reset_btn(reset_btn, i, edit_property_name) # show reset if different
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.queue_redraw()


func _on_y_input_value_changed(value: float, point: EasingCurvePoint, y_input: EditorSpinSlider, reset_btn: Button, property_name: String) -> void:
	var i := _get_current_point_index(point)
	if i == -1:
		return
	if not _is_point_input_editable(point, property_name):
		return
	var edit_property_name := _get_point_input_edit_property(point, property_name)
	var v: Vector2 = point.get(edit_property_name)
	v.y = value
	_apply_point_property_change(
		i,
		edit_property_name,
		v,
		y_input.has_meta(DRAGGING_META) or y_input.has_meta(VALUE_EDITING_META),
		point if edit_property_name == &"position" else null,
	)
	_update_point_reset_btn(reset_btn, i, edit_property_name) # show reset if different
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.queue_redraw()


func _get_point_input_edit_property(
	point: EasingCurvePoint,
	property_name: String,
) -> StringName:
	if (
		point.handle_mode == EasingCurvePoint.HandleMode.LINEAR
		and property_name in ["left_control_point", "right_control_point"]
	):
		var side := (
			EasingCurvePoint.ControlSide.LEFT
			if property_name == "left_control_point"
			else EasingCurvePoint.ControlSide.RIGHT
		)
		if point.is_control_position_editable(side):
			return &"position"
	return StringName(property_name)


func _is_point_input_editable(
	point: EasingCurvePoint,
	property_name: String,
) -> bool:
	return point.is_position_input_editable(property_name)


func _move_point(from_index: int, to_index: int) -> void:
	if DEBUG_POINT_LIST_DRAG:
		print(
			"[EC LIST DRAG] frame=%d usec=%d event=MOVE_POINT from=%d to=%d"
			% [
				Engine.get_process_frames(),
				Time.get_ticks_usec(),
				from_index,
				to_index,
			]
		)

	if (
		from_index == to_index
		or from_index < 0
		or to_index < 0
		or from_index >= curve.points.size()
		or to_index >= curve.points.size()
	):
		return

	_point_edit_transaction_controller.swap_points(curve, from_index, to_index, _select_reordered_point)

func _select_reordered_point(point: EasingCurvePoint) -> void:
	var point_index := _get_current_point_index(point)
	if point_index == -1:
		return
	_point_list_controller.request_selection_refresh_preservation()
	_point_list_controller.assign_logical_selection(
		curve,
		point_index,
		_point_list_controller.selected_point_property_name,
	)
	_sync_graph_selected_point_index(point_index)


static func _set_point_reset_button_available(
	reset_btn: Button,
	available: bool,
) -> void:
	var tint := reset_btn.self_modulate
	tint.a = 1.0
	reset_btn.self_modulate = tint
	reset_btn.visible = available

	reset_btn.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if available
		else Control.MOUSE_FILTER_IGNORE
	)

	reset_btn.focus_mode = (
		Control.FOCUS_ALL
		if available
		else Control.FOCUS_NONE
	)
	_update_point_reset_button_label_margin(reset_btn)


static func _update_point_reset_button_label_margin(
	reset_btn: Button,
) -> void:
	if (
		not reset_btn.has_meta(&"point_property_label")
		or not reset_btn.has_meta(&"point_reset_width")
		or not reset_btn.has_meta(&"point_reset_gap")
	):
		return

	var property_label := (
		reset_btn.get_meta(&"point_property_label") as Label
	)
	if not is_instance_valid(property_label):
		return

	var reset_width := float(
		reset_btn.get_meta(&"point_reset_width")
	)
	var reset_gap := float(
		reset_btn.get_meta(&"point_reset_gap")
	)

	property_label.offset_right = (
		-(reset_width + reset_gap)
		if reset_btn.visible
		else 0.0
	)


static func _create_point_reset_button() -> Button:
	var reset_btn := Button.new()

	reset_btn.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_RELOAD
	)

	reset_btn.tooltip_text = "Reset to default"
	reset_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	reset_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reset_btn.custom_minimum_size = Vector2.ZERO
	reset_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS

	reset_btn.add_theme_stylebox_override(
		&"normal",
		StyleBoxEmpty.new(),
	)

	var hover_style := reset_btn.get_theme_stylebox(&"hover").duplicate()
	var pressed_style := reset_btn.get_theme_stylebox(&"pressed").duplicate()

	var horizontal_margin := 0.0

	hover_style.content_margin_left = horizontal_margin
	hover_style.content_margin_right = horizontal_margin

	pressed_style.content_margin_left = horizontal_margin
	pressed_style.content_margin_right = horizontal_margin

	reset_btn.add_theme_stylebox_override(&"hover", hover_style)
	reset_btn.add_theme_stylebox_override(&"pressed", pressed_style)


	reset_btn.add_theme_stylebox_override(
		&"focus",
		StyleBoxEmpty.new(),
	)

	return reset_btn


func _select_point_property(
	property_header: PanelContainer,
	point_index: int,
	property_name: StringName,
) -> void:
	if is_instance_valid(_selected_point_property_header):
		_set_point_property_selected(
			_selected_point_property_header,
			false
		)

	_point_list_controller.assign_logical_selection(curve,point_index, property_name)
	_attach_selected_point_property_header(property_header)


func _select_point_property_for_point(
	property_header: PanelContainer,
	point: EasingCurvePoint,
	property_name: StringName,
) -> void:
	var point_index := _get_current_point_index(point)
	if point_index != -1:
		_select_point_property(property_header, point_index, property_name)


func _get_current_point_index(point: EasingCurvePoint) -> int:
	return curve.points.find(point) if not disposed and curve != null else -1


func _reorder_position_edited_point(
	point: EasingCurvePoint,
	defer_list_reorder: bool = false,
) -> void:
	var point_order := EasingCurve.build_ordered_points_with_endpoint_takeover(
		curve.points,
		point,
	)
	if not defer_list_reorder:
		_position_x_order_preview_point = null
		if is_instance_valid(easing_curve_editor):
			easing_curve_editor.clear_position_x_order_preview()
	var point_index := point_order.find(point)
	if point_index == -1:
		return

	if defer_list_reorder:
		_position_x_order_preview_point = point
		if is_instance_valid(easing_curve_editor):
			easing_curve_editor.set_position_x_order_preview(point)
		return

	_point_list_controller.assign_logical_selection(
		curve,
		point_index,
		_point_list_controller.selected_point_property_name,
	)
	_sync_graph_selected_point_index(point_index)

	if curve.points != point_order:
		curve.points = point_order
	else:
		curve.sort_points(false)


func _commit_position_x_order_preview() -> void:
	if _position_x_order_preview_point == null:
		return

	var point := _position_x_order_preview_point
	_position_x_order_preview_point = null
	_reorder_position_edited_point(point)


func _set_point_property_selected(
	property_header: PanelContainer,
	selected: bool,
) -> void:
	if not selected:
		property_header.add_theme_stylebox_override(
			&"panel",
			StyleBoxEmpty.new()
		)
		return

	var style := StyleBoxFlat.new()

	var accent := Color(0.3, 0.6, 1.0)
	if DisplayServer.get_name() != "headless":
		var editor_theme := EDITOR_THEME_CACHE.get_theme()
		if editor_theme != null:
			accent = editor_theme.get_color(&"accent_color", &"Editor")

	accent.a = 0.10
	style.bg_color = accent

	property_header.add_theme_stylebox_override(
		&"panel",
		style
	)


func _create_normal_point_property_row(
		point_index: int,
		definition: Dictionary,
		reset_btn: Button,
		editor_control: Control,
		property_grid: GridContainer,
) -> Dictionary:
	var property_header := _create_selectable_point_property_header(
		point_index,
		definition["name"],
		definition["inspector_label"],
		reset_btn,
	)
	property_header.size_flags_stretch_ratio = POINT_PROPERTY_HEADER_RATIO
	property_grid.add_child(property_header)

	var value_panel := PanelContainer.new()
	value_panel.add_theme_stylebox_override(
		"panel",
		_zero_margin_panel_stylebox,
	)
	value_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_panel.size_flags_stretch_ratio = POINT_PROPERTY_VALUE_RATIO
	value_panel.custom_minimum_size.x = 0.0
	value_panel.z_index = 1
	property_grid.add_child(value_panel)
	value_panel.add_child(editor_control)

	return {
		"property_header": property_header,
		"value_panel": value_panel,
	}


func _create_bool_property(
		point: EasingCurvePoint,
		i: int,
		definition: Dictionary,
		property_grid: GridContainer,
) -> void:
	var property_name: StringName = definition["name"]
	if not EasingCurve.is_point_property_inspector_visible(property_name):
		return

	var default_value := bool(
		EasingCurve.get_point_property_default(property_name)
	)
	var current_value := bool(point.get(property_name))

	var reset_btn := _create_point_reset_button()
	_set_point_reset_button_available(
		reset_btn,
		current_value != default_value,
	)

	var check_box := CheckBox.new()
	check_box.text = "On"
	check_box.button_pressed = current_value
	check_box.alignment = HORIZONTAL_ALIGNMENT_LEFT
	check_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var row := _create_normal_point_property_row(
		i,
		definition,
		reset_btn,
		check_box,
		property_grid,
	)
	var property_header: PanelContainer = row["property_header"]

	check_box.toggled.connect(
		func(toggled_on: bool):
			var point_index := _get_current_point_index(point)
			if point_index == -1:
				return

			_select_point_property(
				property_header,
				point_index,
				property_name,
			)
			_apply_point_property_change(
				point_index,
				property_name,
				toggled_on,
			)
			_set_point_reset_button_available(
				reset_btn,
				toggled_on != default_value,
			)
	)

	check_box.focus_entered.connect(
		_select_point_property_for_point.bind(
			property_header,
			point,
			property_name,
		)
	)

	reset_btn.pressed.connect(
		func():
			var point_index := _get_current_point_index(point)
			if point_index == -1:
				return

			check_box.set_pressed_no_signal(default_value)
			_apply_point_property_change(
				point_index,
				property_name,
				default_value,
			)
			_set_point_reset_button_available(reset_btn, false)
	)

	reset_btn.pressed.connect(
		_select_point_property_for_point.bind(
			property_header,
			point,
			property_name,
		)
	)


func _create_vector2_property(
		point: EasingCurvePoint,
		i: int,
		definition: Dictionary,
		property_grid: GridContainer,
) -> void:
	var property_name: StringName = definition["name"]
	if not EasingCurve.is_point_property_inspector_visible(property_name):
		return
	var default_vec: Vector2 = curve.get_default_for_property(i, property_name)
	var current_vec: Vector2 = point.get(property_name)

	# Selectable property header and reset slot.
	var reset_btn := _create_point_reset_button()
	_set_point_reset_button_available(
		reset_btn,
		not current_vec.is_equal_approx(default_vec)
	)

	# HBox for x/y inputs; lock_btn
	var value_hbox := HBoxContainer.new()
	value_hbox.add_theme_constant_override("separation", _compact_separation())
	value_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := _create_normal_point_property_row(
		i,
		definition,
		reset_btn,
		value_hbox,
		property_grid,
	)
	var property_header: PanelContainer = row["property_header"]

	var force_linear_slot := Control.new()
	force_linear_slot.custom_minimum_size.x = (
		24.0 * EditorInterface.get_editor_scale()
	)
	force_linear_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Left side (the X/Y stack)
	var value_vbox := VBoxContainer.new()
	var x_input := EditorSpinSlider.new()
	var y_input := EditorSpinSlider.new()
	value_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_vbox.add_theme_constant_override("separation", 0)
	value_hbox.add_child(value_vbox)
	value_hbox.add_child(force_linear_slot)


	var force_linear_btn := _create_force_linear_button(
		point,
		i,
		property_name,
	)
	force_linear_slot.add_child(force_linear_btn)

	if point.is_lockable_property(property_name):
		var lock_btn := _create_point_lock_button(
			point,
			i,
			property_name,
			property_header,
		)
		value_hbox.add_child(lock_btn)

	var vec: Vector2 = point.get(property_name)

	var x_color := EDITOR_THEME_CACHE.get_color(
		&"property_color_x",
		&"Editor",
		Color(1.0, 0.35, 0.35),
	)
	var y_color := EDITOR_THEME_CACHE.get_color(
		&"property_color_y",
		&"Editor",
		Color(0.5, 1.0, 0.5),
	)

	var x_range := Vector2(0.0, 1.0) if property_name == "position" else Vector2(-1024, 1024)
	var x_row := _create_vector2_axis_row(
		point,
		x_input,
		"x",
		vec.x,
		x_range,
		x_color,
		property_name,
		property_header,
		reset_btn,
	)
	value_vbox.add_child(x_row)

	var y_row := _create_vector2_axis_row(
		point,
		y_input,
		"y",
		vec.y,
		x_range,
		y_color,
		property_name,
		property_header,
		reset_btn,
	)

	reset_btn.pressed.connect(_on_reset_btn_pressed.bind(point, x_input, y_input, property_name, reset_btn))
	reset_btn.pressed.connect(_select_point_property_for_point.bind(property_header, point, StringName(property_name)))

	value_vbox.add_child(y_row)


func _create_force_linear_button(
		point: EasingCurvePoint,
		i: int,
		property_name: String,
) -> Button:
	var force_linear_btn := Button.new()
	force_linear_btn.flat = true
	force_linear_btn.toggle_mode = true
	force_linear_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if property_name not in ["left_control_point", "right_control_point"]:
		force_linear_btn.modulate.a = 0.0
		force_linear_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		force_linear_btn.focus_mode = Control.FOCUS_NONE
		return force_linear_btn

	var pressed_color := Color.WHITE
	force_linear_btn.add_theme_color_override(
		"icon_pressed_color",
		pressed_color,
	)
	force_linear_btn.add_theme_color_override(
		"icon_hover_pressed_color",
		pressed_color,
	)

	var force_property := (
		&"left_force_linear"
		if property_name == "left_control_point"
		else &"right_force_linear"
	)
	var force_linear := point.is_control_forced_linear(
		EasingCurvePoint.ControlSide.LEFT
		if property_name == "left_control_point"
		else EasingCurvePoint.ControlSide.RIGHT
	)
	force_linear_btn.button_pressed = force_linear
	force_linear_btn.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_INSTANCE
		if force_linear
		else EDITOR_THEME_CACHE.ICON_UNLINKED
	)
	force_linear_btn.modulate.a = 1.0
	force_linear_btn.tooltip_text = (
		(
			"Unforce Linear — Handle returns to Free default"
			if force_linear
			else "Force Linear — Collapse this handle to the point"
		)
		if point.supports_control_state()
		else "Force Linear — Available in Free or Linked handle mode"
	)

	var force_linear_available := point.supports_control_state()
	force_linear_btn.disabled = not force_linear_available
	force_linear_btn.modulate.a = 0.25 if not force_linear_available else 1.0
	force_linear_btn.toggled.connect(
		func(toggled_on: bool):
			force_linear_btn.icon = EDITOR_THEME_CACHE.get_icon(
				EDITOR_THEME_CACHE.ICON_INSTANCE
				if toggled_on
				else EDITOR_THEME_CACHE.ICON_UNLINKED
			)
			force_linear_btn.modulate.a = 1.0
			_apply_point_property_change(_get_current_point_index(point), force_property, toggled_on)
			if is_instance_valid(easing_curve_editor):
				easing_curve_editor.queue_redraw()
	)
	return force_linear_btn


func _create_point_lock_button(
		point: EasingCurvePoint,
		i: int,
		property_name: String,
		property_header: PanelContainer,
) -> Button:
	var lock_btn := Button.new()
	lock_btn.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_LOCK
	)
	lock_btn.flat = true
	lock_btn.toggle_mode = true
	lock_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lock_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var pressed_color := Color.WHITE
	lock_btn.add_theme_color_override("icon_pressed_color", pressed_color)
	lock_btn.add_theme_color_override("icon_hover_pressed_color", pressed_color)

	var locked := point.locked.get(property_name, false)
	lock_btn.button_pressed = locked
	var toggled_on := lock_btn.button_pressed
	var lock_available := property_name == "position" or point.supports_control_state()
	lock_btn.disabled = not lock_available
	lock_btn.tooltip_text = (
		(
			"Unlock — Allow this property to be edited"
			if locked
			else "Lock — Prevent this property from being edited"
		)
		if lock_available
		else "Lock — Available in Free or Linked handle mode"
	)
	lock_btn.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_LOCK
		if toggled_on
		else EDITOR_THEME_CACHE.ICON_UNLOCK
	)
	lock_btn.modulate.a = 0.25 if not lock_available else 1.0 if toggled_on else 0.5
	lock_btn.toggled.connect(
		func(next_toggled_on: bool):
			_point_list_controller.request_selection_refresh_preservation()
			_select_point_property_for_point(property_header, point, StringName(property_name))
			lock_btn.icon = EDITOR_THEME_CACHE.get_icon(
				EDITOR_THEME_CACHE.ICON_LOCK
				if next_toggled_on
				else EDITOR_THEME_CACHE.ICON_UNLOCK
			)
			lock_btn.modulate.a = 1.0 if next_toggled_on else 0.5

			var lock_change_property := StringName()
			match property_name:
				"position":
					lock_change_property = &"position_lock"
				"left_control_point":
					lock_change_property = &"left_control_lock"
				"right_control_point":
					lock_change_property = &"right_control_lock"
			_apply_point_property_change(_get_current_point_index(point), lock_change_property, next_toggled_on)
	)
	return lock_btn


func _create_vector2_axis_row(
		point: EasingCurvePoint,
		input: EditorSpinSlider,
		axis: String,
		value: float,
		input_range: Vector2,
		axis_color: Color,
		property_name: String,
		property_header: PanelContainer,
		reset_btn: Button,
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -8)

	var label := Label.new()
	label.text = axis
	label.add_theme_color_override("font_color", axis_color)

	input.min_value = input_range.x
	input.max_value = input_range.y
	input.step = SLIDER_INPUT_STEP
	input.flat = true
	input.hide_slider = true
	input.label = ""
	input.value = value
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.x = 0.0

	if axis == "x":
		input.value_changed.connect(
			_on_x_input_value_changed.bind(point, input, reset_btn, property_name)
		)
	else:
		input.value_changed.connect(
			_on_y_input_value_changed.bind(point, input, reset_btn, property_name)
		)
	_connect_point_input_drag_signals(input)
	_connect_point_list_coordinate_signals(input, point, StringName(property_name))

	if axis == "x" and property_name == "position":
		input.value_focus_entered.connect(
			_on_position_x_input_focus_entered.bind(input)
		)
		input.value_focus_exited.connect(
			_on_position_x_input_focus_exited.bind(input)
		)
	elif axis == "x" and property_name in ["left_control_point", "right_control_point"]:
		input.value_focus_entered.connect(
			_on_linear_control_x_input_focus_entered.bind(input, point)
		)
		input.value_focus_exited.connect(
			_on_linear_control_x_input_focus_exited.bind(input, point)
		)

	input.grabbed.connect(
		_select_point_property_for_point.bind(
			property_header,
			point,
			StringName(property_name),
		)
	)
	input.focus_entered.connect(
		_select_point_property_for_point.bind(
			property_header,
			point,
			StringName(property_name),
		)
	)
	_point_list_controller.register_input_binding(point, StringName(property_name), axis, input)

	row.add_child(label)
	row.add_child(input)
	return row


func _on_add_point_btn_pressed() -> void:
	if disposed:
		return
	if curve == null and is_instance_valid(easing_curve_editor):
		easing_curve_editor.add_point_from_list()
		return
	var backend := BackendFactory.create(_point_list_curve_resource())
	if backend == null:
		return
	var new_point: Resource = backend.create_point_for_list(CurveEditorSettings.get_default_new_point_handle_mode())
	if curve == null:
		_native_list_editor().mutate("Add Easing Curve Point", func() -> void:
			if backend.add_point(new_point) >= 0:
				_select_native_point(new_point)
		)
		return
	var point := new_point as EasingCurvePoint
	if point == null:
		return
	_point_list_controller.request_selection_refresh_preservation()
	_add_point(point, _capture_point_selection_state(), true)


func _create_foldable_section(
	title: String,
	content: Control,
	curve_resource: Resource,
) -> Control:
	var section := PointsFoldableSection.new()
	section.setup(title, content, curve_resource)
	return section


func _create_inspector_section(
	title: String,
	content: Control,
	curve_resource: Resource,
) -> Control:
	var section := PointsFoldableSection.new()

	section.copy_value_callback = func():
		var point_index := _selected_point_index_for_resource(curve_resource)
		if point_index >= 0:
			_copy_point_property_value(
				point_index,
				_point_list_controller.selected_point_property_name
			)

	section.paste_value_callback = func():
		var point_index := _selected_point_index_for_resource(curve_resource)
		if point_index >= 0:
			_paste_point_property_value(
				point_index,
				_point_list_controller.selected_point_property_name
			)

	section.copy_path_callback = func():
		var point_index := _selected_point_index_for_resource(curve_resource)
		if point_index >= 0:
			_copy_point_property_path(
				point_index,
				_point_list_controller.selected_point_property_name
			)

	section.can_paste_callback = func():
		return (
			_selected_point_index_for_resource(curve_resource) >= 0
			and _clipboard_has_compatible_point_property_value(
				_point_list_controller.selected_point_property_name,
			)
		)

	section.setup(title, content, curve_resource)
	return section


func _selected_point_index_for_resource(curve_resource: Resource) -> int:
	if curve_resource == null:
		return -1
	var backend := BackendFactory.create(curve_resource)
	if backend == null:
		return -1
	var resource_id := _point_list_controller.selected_point_resource_id
	for point_index in range(backend.get_point_count()):
		if backend.get_point(point_index).get_instance_id() == resource_id:
			_point_list_controller.selected_point_index = point_index
			return point_index
	return -1


func _on_curve_editor_point_changed(_i: int, _new_point: EasingCurvePoint) -> void:
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.queue_redraw()


func _cancel_point_edit() -> void:
	if disposed:
		return
	_point_edit_finish_request_id += 1
	_point_edit_transaction_controller.cancel_point_edit(curve)


func _commit_point_edit(point_order: Array[EasingCurvePoint] = []) -> void:
	if disposed:
		return
	_point_edit_finish_request_id += 1
	_commit_position_x_order_preview()
	_point_edit_transaction_controller.finish_point_edit(curve, point_order)


func _connect_point_list_coordinate_signals(input: EditorSpinSlider, point: Resource, property_name: StringName) -> void:
	input.grabbed.connect(_begin_point_list_coordinates.bind(input, point, property_name))
	input.ungrabbed.connect(_end_point_list_coordinates.bind(input))
	input.value_focus_entered.connect(_end_point_list_coordinates.bind(input))
	input.tree_exiting.connect(_end_point_list_coordinates.bind(input))
	input.visibility_changed.connect(_on_coordinate_input_visibility_changed.bind(input))


func _on_coordinate_input_visibility_changed(input: EditorSpinSlider) -> void:
	if not input.is_visible_in_tree():
		_end_point_list_coordinates(input)


func _begin_point_list_coordinates(input: EditorSpinSlider, point: Resource, property_name: StringName) -> void:
	if disposed or not is_instance_valid(easing_curve_editor) or not input.has_meta(DRAGGING_META):
		return
	var edit_property := property_name
	if point is EasingCurvePoint:
		if not _is_point_input_editable(point, property_name):
			return
		edit_property = _get_point_input_edit_property(point, property_name)
	else:
		if not _is_native_point_input_editable(point, property_name):
			return
		edit_property = _get_native_point_input_edit_property(point, property_name)
	easing_curve_editor.begin_point_list_coordinate_drag(input, point, edit_property)


func _end_point_list_coordinates(input: EditorSpinSlider) -> void:
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.end_point_list_coordinate_drag(input)


func _connect_point_input_drag_signals(input: EditorSpinSlider) -> void:
	input.grabbed.connect(_on_point_input_grabbed.bind(input))
	input.ungrabbed.connect(_on_point_input_ungrabbed.bind(input))
	input.value_focus_entered.connect(_on_point_input_focus_entered.bind(input))
	input.value_focus_exited.connect(_on_point_input_focus_exited.bind(input))


func _on_point_input_grabbed(input: EditorSpinSlider) -> void:
	_point_edit_finish_request_id += 1
	input.set_meta(DRAGGING_META, true)


func _on_point_input_ungrabbed(input: EditorSpinSlider) -> void:
	if input.has_meta(DRAGGING_META):
		input.remove_meta(DRAGGING_META)
	_queue_point_edit_finish()


func _on_point_input_focus_entered(input: EditorSpinSlider) -> void:
	_point_edit_finish_request_id += 1
	if input.has_meta(DRAGGING_META):
		input.remove_meta(DRAGGING_META)
		_commit_point_edit()
	input.set_meta(VALUE_EDITING_META, true)


func _on_point_input_focus_exited(input: EditorSpinSlider) -> void:
	if not input.has_meta(VALUE_EDITING_META):
		return
	input.remove_meta(VALUE_EDITING_META)
	_queue_point_edit_finish()


func _queue_point_edit_finish() -> void:
	_point_edit_finish_request_id += 1
	_finish_point_edit_deferred.call_deferred(_point_edit_finish_request_id)


func _finish_point_edit_deferred(request_id: int) -> void:
	if not disposed and request_id == _point_edit_finish_request_id:
		_commit_point_edit()


func _on_position_x_input_focus_entered(input: EditorSpinSlider) -> void:
	_point_edit_finish_request_id += 1
	input.set_meta(POSITION_X_EDITING_META, true)


func _on_position_x_input_focus_exited(input: EditorSpinSlider) -> void:
	if input.has_meta(POSITION_X_EDITING_META):
		input.remove_meta(POSITION_X_EDITING_META)
		_queue_point_edit_finish()


func _on_linear_control_x_input_focus_entered(
	input: EditorSpinSlider,
	point: EasingCurvePoint,
) -> void:
	if point.handle_mode == EasingCurvePoint.HandleMode.LINEAR:
		_on_position_x_input_focus_entered(input)


func _on_linear_control_x_input_focus_exited(
	input: EditorSpinSlider,
	_point: EasingCurvePoint,
) -> void:
	if input.has_meta(POSITION_X_EDITING_META):
		_on_position_x_input_focus_exited(input)


func _on_curve_editor_point_add_requested(point: EasingCurvePoint) -> void:
	# Graph-created Legacy points are reconstructed by set_point_snapshot(), so
	# select the committed point resource here rather than the transient request.
	_add_point(point, _capture_point_selection_state(), true)


func _create_handle_mode_property(
		point: EasingCurvePoint,
		i: int,
		definition: Dictionary,
		property_grid: GridContainer,
) -> void:
	var property_name: StringName = definition["name"]
	if not EasingCurve.is_point_property_inspector_visible(property_name):
		return

	var reset_btn := _create_point_reset_button()
	_set_point_reset_button_available(
		reset_btn,
		point.handle_mode != EasingCurve.get_point_property_default(
			property_name,
		),
	)

	var option := OptionButton.new()
	_configure_compact_option(option)
	option.custom_minimum_size.x = 0.0
	var row := _create_normal_point_property_row(
		i,
		definition,
		reset_btn,
		option,
		property_grid,
	)
	var property_header: PanelContainer = row["property_header"]

	option.add_item("Free", EasingCurvePoint.HandleMode.FREE)
	option.add_item("Linear", EasingCurvePoint.HandleMode.LINEAR)
	option.add_item("Balanced", EasingCurvePoint.HandleMode.BALANCED)
	option.add_item("Mirrored", EasingCurvePoint.HandleMode.MIRRORED)
	option.add_item("Linked", EasingCurvePoint.HandleMode.LINKED)

	for index in range(option.item_count):
		if option.get_item_id(index) == point.handle_mode:
			option.select(index)
			break

	option.item_selected.connect(
		func(index: int):
			var point_index := _get_current_point_index(point)
			if point_index == -1:
				return
			_select_point_property(property_header, point_index, &"handle_mode")
			_apply_point_property_change(
				point_index,
				&"handle_mode",
				option.get_item_id(index),
			)
	)
	option.focus_entered.connect(
		_select_point_property_for_point.bind(
			property_header,
			point,
			&"handle_mode",
		)
	)
	reset_btn.pressed.connect(
		_on_handle_mode_reset_pressed.bind(point, option, reset_btn)
	)
	reset_btn.pressed.connect(
		_select_point_property_for_point.bind(
			property_header,
			point,
			&"handle_mode",
		)
	)

func _on_handle_mode_reset_pressed(
	point: EasingCurvePoint,
	option: OptionButton,
	reset_btn: Button,
) -> void:
	var i := _get_current_point_index(point)
	if i == -1:
		return
	var default_mode: int = EasingCurve.get_point_property_default(
	&"handle_mode",
)
	if point.handle_mode == default_mode:
		_set_point_reset_button_available(reset_btn, false)
		return
	option.select(option.get_item_index(default_mode))
	_apply_point_property_change(
		i,
		&"handle_mode",
		default_mode,
	)
	_set_point_reset_button_available(reset_btn, false)


func _apply_point_property_change(
	i: int,
	property_name: StringName,
	value: Variant,
	changing: bool = false,
	position_reorder_point: EasingCurvePoint = null,
) -> void:
	if disposed or curve == null or i < 0 or i >= curve.points.size():
		return
	_point_list_controller.request_selection_refresh_preservation()
	_point_edit_transaction_controller.apply_point_property_change(
		curve,
		i,
		property_name,
		value,
		changing,
		position_reorder_point,
	)


func _add_point(
	point: EasingCurvePoint,
	selection_before: Dictionary = {},
	select_added_immediately := false,
) -> EasingCurvePoint:
	var before := _point_edit_transaction_controller.capture_state(curve)
	var updated_points: Array[EasingCurvePoint] = curve.points.duplicate()
	updated_points.append(point)
	updated_points = EasingCurve.build_ordered_points_with_endpoint_takeover(
		updated_points,
		point,
	)
	var added_point_index := updated_points.find(point)
	curve.set_point_snapshot(curve.make_point_snapshot(updated_points))
	var added_point := curve.points[added_point_index]
	if select_added_immediately:
		_select_reordered_point(added_point)

	var selection_after := (
		_capture_point_selection_state()
		if select_added_immediately
		else {
			"has_selection": true,
			"point_index": added_point_index,
			"point_resource_id": added_point.get_instance_id(),
			"property_name": StringName(),
		}
	)
	_point_edit_transaction_controller.commit_applied_action(
		curve,
		"Add Easing Curve Point",
		_point_edit_transaction_controller.create_action_context(before).with_selection(
			_selection_restorer() if not selection_before.is_empty() else Callable(),
			selection_before,
			selection_after,
		),
	)
	return added_point

func _remove_point(point: EasingCurvePoint) -> void:
	var selection_before := _capture_point_selection_state()
	var before := _point_edit_transaction_controller.capture_state(curve)
	var updated_points: Array[EasingCurvePoint] = curve.points.duplicate()
	var point_index := updated_points.find(point)
	if point_index == -1:
		return
	updated_points.remove_at(point_index)
	curve.set_point_snapshot(curve.make_point_snapshot(updated_points))
	var selection_after := _capture_point_selection_state()
	_point_edit_transaction_controller.commit_applied_action(
		curve,
		"Remove Easing Curve Point",
		_point_edit_transaction_controller.create_action_context(before).with_selection(
			_selection_restorer(),
			selection_before,
			selection_after,
		),
	)

func _clear_transition_selection() -> void:
	_finish_applied_point_edit()
	_clear_point_property_selection()
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.selected_control_index = EasingCurveEditor.ControlIndex.NONE
	_sync_graph_selected_point_index(-1)
	_persist_legacy_selection()


func _emit_curve_property(property_name: StringName, value: Variant, object: EasingCurve) -> void:
	if object == null:
		return
	if (
		property_name == &"ease_type"
		and object.curve_mode == EasingCurve.CurveMode.BEZIER
		and object.is_selected_preset_modified()
	):
		return
	if property_name == &"trans_type" and object.trans_type != value:
		_clear_transition_selection()
	if is_instance_valid(easing_curve_editor) and easing_curve_editor.get_curve() == object:
		_queue_autofit_curve_editor()
	var action_name := "Change Easing Curve Ease" if property_name == &"ease_type" else "Change Easing Curve Transition"
	_point_edit_transaction_controller.apply_action(
		object,
		action_name,
		func(): object.set(property_name, value),
	)


func _consume_initial_autofit(object: EasingCurve) -> bool:
	if object == null:
		return false
	var resource_id := object.get_instance_id()
	if _initial_autofit_resource_ids.has(resource_id):
		return false
	_initial_autofit_resource_ids[resource_id] = true
	return true


func _queue_autofit_curve_editor() -> void:
	var request_id := _request_autofit()
	call_deferred(&"_autofit_curve_editor", request_id)


func _request_autofit() -> int:
	if not is_instance_valid(easing_curve_editor):
		return -1
	for pending_id: int in _autofit_requests.keys():
		if _autofit_requests[pending_id].editor.get_ref() == easing_curve_editor:
			_cancel_autofit(pending_id)
	_autofit_request_id += 1
	var request := AutofitRequest.new()
	request.editor = weakref(easing_curve_editor)
	if is_instance_valid(_curve_editor_section):
		request.section = weakref(_curve_editor_section)
	_autofit_requests[_autofit_request_id] = request
	easing_curve_editor.tree_exiting.connect(
		_on_autofit_editor_exiting.bind(_autofit_request_id), CONNECT_ONE_SHOT,
	)
	return _autofit_request_id


func _on_autofit_editor_exiting(request_id: int) -> void:
	if not _is_current_autofit_request(request_id):
		return
	var editor := _autofit_requests[request_id].editor.get_ref() as EasingCurveEditor
	if is_instance_valid(editor):
		var resource := editor.get_curve()
		if resource is EasingCurve:
			_autofit_rebuild_resources[resource.get_instance_id()] = weakref(resource)
	_cancel_autofit(request_id)


func _consume_rebuild_autofit(resource: Resource) -> bool:
	var resource_id := resource.get_instance_id()
	var pending := _autofit_rebuild_resources.has(resource_id)
	_autofit_rebuild_resources.erase(resource_id)
	for pending_id: int in _autofit_rebuild_resources.keys():
		if _autofit_rebuild_resources[pending_id].get_ref() == null:
			_autofit_rebuild_resources.erase(pending_id)
	return pending


func _cancel_autofit(request_id: int = -1) -> void:
	if request_id < 0:
		for pending_id: int in _autofit_requests.keys():
			_cancel_autofit(pending_id)
		return
	if not _is_current_autofit_request(request_id):
		return
	var editor := _autofit_requests[request_id].editor.get_ref() as EasingCurveEditor
	_autofit_requests.erase(request_id)
	if is_instance_valid(editor):
		var exit_callback := _on_autofit_editor_exiting.bind(request_id)
		if editor.tree_exiting.is_connected(exit_callback):
			editor.tree_exiting.disconnect(exit_callback)
		editor.set_graph_render_suppressed(false)


func _complete_autofit(request_id: int) -> void:
	if not _is_current_autofit_request(request_id):
		return
	var editor := _autofit_requests[request_id].editor.get_ref() as EasingCurveEditor
	if is_instance_valid(editor) and editor.is_autofit_ready() and editor.is_autofit_needed():
		editor.autofit()
	_cancel_autofit(request_id)


func _is_current_autofit_request(request_id: int) -> bool:
	return _autofit_requests.has(request_id)


func _is_autofit_pending() -> bool:
	return not _autofit_requests.is_empty()


func _on_curve_editor_section_folding_changed(is_folded: bool, editor_ref: WeakRef) -> void:
	if is_folded:
		return
	for request_id: int in _autofit_requests:
		if _autofit_requests[request_id].editor.get_ref() == editor_ref.get_ref():
			call_deferred(&"_autofit_curve_editor", request_id)


func _autofit_curve_editor(request_id: int = -1) -> void:
	if request_id < 0:
		request_id = _request_autofit()
	elif not _is_current_autofit_request(request_id):
		return
	_defer_autofit_frames(request_id, 2)


func _defer_autofit_frames(request_id: int, frames_remaining: int) -> void:
	if not _is_current_autofit_request(request_id):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or not is_instance_valid(_autofit_requests[request_id].editor.get_ref()):
		_cancel_autofit(request_id)
		return

	var editor := _autofit_requests[request_id].editor.get_ref() as EasingCurveEditor
	# Evaluate after the preset mutation, and again as layout settles. A request
	# alone must not hide a curve whose zoom and pan already match the fitted view.
	editor.set_graph_render_suppressed(editor.is_autofit_ready() and editor.is_autofit_needed())

	# Preset/resource changes may rebuild the Inspector and hide/show the
	# point toolbar. Let those minimum-size/layout changes settle before
	# fitting; only curves needing a different view wait to draw until then.
	if frames_remaining > 0:
		tree.process_frame.connect(
			func() -> void: _defer_autofit_frames(request_id, frames_remaining - 1),
			CONNECT_ONE_SHOT,
		)
		return

	var section_ref := _autofit_requests[request_id].section
	var section := section_ref.get_ref() as PointsFoldableSection if section_ref != null else null
	if is_instance_valid(section) and section.folded:
		return
	var request := _autofit_requests[request_id]
	var graph_rect := editor._get_graph_view_rect()
	if request.last_graph_rect != graph_rect:
		request.last_graph_rect = graph_rect
		_defer_autofit_frames(request_id, 1)
		return
	_complete_autofit(request_id)


func _on_reset_selected_preset(object: EasingCurve) -> void:
	if object == null:
		return
	_point_edit_transaction_controller.apply_action(
		object,
		"Reset Easing Curve Preset",
		func(): object.reset_selected_preset(),
	)


func _on_reset_ease(object: EasingCurve) -> void:
	if object == null or object.ease_type == EasingCurve.EASE.IN:
		return
	_emit_curve_property(&"ease_type", EasingCurve.EASE.IN, object)


static func _update_preset_state_ui(
		object: EasingCurve,
		ease_control: OptionButton,
		trans_control: OptionButton,
		ease_reset_control: Button,
		reset_control: Button,
) -> void:
	if (
		object == null
		or not is_instance_valid(ease_control)
		or not is_instance_valid(trans_control)
		or not is_instance_valid(ease_reset_control)
		or not is_instance_valid(reset_control)
	):
		return

	var ease_index := ease_control.get_item_index(object.ease_type)
	if ease_index >= 0:
		ease_control.select(ease_index)
	var trans_index := trans_control.get_item_index(object.trans_type)
	if trans_index >= 0:
		trans_control.select(trans_index)
	var modified := object.is_selected_preset_modified()
	var ease_available := (
		_transition_supports_ease(object.trans_type)
		and (
			object.curve_mode == EasingCurve.CurveMode.FUNCTION
			or not modified
		)
	)
	ease_control.disabled = not ease_available
	_set_preset_reset_button_available(
		ease_reset_control,
		ease_available and object.ease_type != EasingCurve.EASE.IN,
	)

	_set_transition_display(trans_control, object.trans_type, modified)
	_set_preset_reset_button_available(reset_control, modified)


static func _transition_supports_ease(transition: EasingCurve.TRANS) -> bool:
	return EasingCurve.transition_supports_ease(transition)


static func _native_transition_supports_ease(transition: int) -> bool:
	return transition not in [0, 100, 101, 104, 107, 108]


static func _set_transition_display(
	trans_control: OptionButton,
	selected_transition: EasingCurve.TRANS,
	modified: bool,
) -> void:
	var popup := trans_control.get_popup()

	for i in range(popup.item_count):
		if popup.is_item_separator(i):
			continue

		var transition := popup.get_item_id(i)
		var display := _enum_display_name(EasingCurve.TRANS.keys()[transition])

		if (
			SHOW_MODIFIED_ASTERISK
			and transition == selected_transition
			and modified
		):
			display += " *"

		trans_control.set_item_text(i, display)


static func _set_native_transition_display(
	trans_control: OptionButton,
	selected_transition: int,
	modified: bool,
) -> void:
	for group: Dictionary in NATIVE_TRANSITION_PRESENTATION:
		for item: Dictionary in group["items"]:
			var transition := int(item["transition"])
			var item_index := trans_control.get_item_index(transition)
			if item_index < 0:
				continue
			var display := String(item["label"])
			if SHOW_MODIFIED_ASTERISK and transition == selected_transition and modified:
				display += " *"
			trans_control.set_item_text(item_index, display)


static func _set_preset_reset_button_available(reset_control: Button, available: bool) -> void:
	var tint := reset_control.self_modulate
	tint.a = 1.0 if available else 0.0
	reset_control.self_modulate = tint
	reset_control.mouse_filter = Control.MOUSE_FILTER_STOP if available else Control.MOUSE_FILTER_IGNORE
	reset_control.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE


func _disconnect_preset_state_ui(object: EasingCurve, callback: Callable) -> void:
	if object != null and object.changed.is_connected(callback):
		object.changed.disconnect(callback)


func _undo_source_property() -> EditorProperty:
	if is_instance_valid(curve_editor_property):
		return curve_editor_property
	return null


static func _create_transition_option(
	selected_value: int,
) -> OptionButton:
	var option := OptionButton.new()
	_configure_compact_option(option)

	var popup := option.get_popup()

	for group: Dictionary in TRANSITION_PRESENTATION:
		popup.add_separator(group["name"])

		for item: Dictionary in group["items"]:
			var transition: EasingCurve.TRANS = item["transition"]
			var display := _enum_display_name(EasingCurve.TRANS.keys()[transition])

			option.add_icon_item(MODE_ICONS.get_transition_icon(EasingCurve.TRANS.keys()[transition], EDITOR_THEME_CACHE.get_theme()), display, transition)
			if transition == EasingCurve.TRANS.SMOOTHSTEP:
				option.set_item_tooltip(option.item_count - 1, "IN_OUT is canonical Smoothstep: 3t^2 - 2t^3")

	option.select(option.get_item_index(selected_value))
	return option


static func _create_native_transition_option(
	selected_value: int,
	allowed_transition_ids: PackedInt32Array,
) -> OptionButton:
	var option := OptionButton.new()
	_configure_compact_option(option)
	var popup := option.get_popup()
	for group: Dictionary in NATIVE_TRANSITION_PRESENTATION:
		var group_items: Array[Dictionary] = []
		for item: Dictionary in group["items"]:
			if allowed_transition_ids.has(int(item["transition"])):
				group_items.append(item)
		if group_items.is_empty():
			continue
		popup.add_separator(String(group["name"]))
		for item: Dictionary in group_items:
			option.add_icon_item(MODE_ICONS.get_native_transition_icon(int(item["transition"]), EDITOR_THEME_CACHE.get_theme()), String(item["label"]), int(item["transition"]))
			if int(item["transition"]) == 109:
				option.set_item_tooltip(option.item_count - 1, "IN_OUT is canonical Smoothstep: 3t^2 - 2t^3")
	option.select(option.get_item_index(selected_value))
	return option


static func _enum_display_name(key: String) -> String:
	match key:
		"CSS_CUBIC_BEZIER":
			return "cubic-bezier()"
		"CSS_LINEAR":
			return "linear()"
	return key.to_lower().capitalize().replace("_", " ")


static func _create_option(enum_dict: Dictionary, selected_value: int) -> OptionButton:
	var option := OptionButton.new()
	_configure_compact_option(option)
	var keys = enum_dict.keys()
	if keys.has("CSS_LINEAR") and keys.has("CSS_CUBIC_BEZIER"):
		keys.erase("CSS_CUBIC_BEZIER")
		keys.insert(keys.find("CSS_LINEAR") + 1, "CSS_CUBIC_BEZIER")
	for key in keys:
		var display := _enum_display_name(key)
		if enum_dict == EasingCurve.EASE:
			option.add_icon_item(MODE_ICONS.get_ease_icon(key, EDITOR_THEME_CACHE.get_theme()), display, enum_dict[key])
		else:
			option.add_item(display, enum_dict[key]) # store enum value as ID
	option.select(option.get_item_index(selected_value))
	return option


static func _align_preset_label_column(toolbar: GridContainer, editor: EasingCurveEditor) -> void:
	var navigation := editor._point_reorder_buttons
	var update_width := func() -> void:
		var column_width := 2.0 * navigation.get_theme_constant(&"separation")
		for control: Control in navigation.get_children():
			column_width += control.get_combined_minimum_size().x
		column_width += editor._point_mode_row.get_theme_constant(&"separation") - toolbar.get_theme_constant(&"h_separation")
		for index: int in [0, 3]:
			var label := toolbar.get_child(index) as Label
			label.custom_minimum_size.x = column_width
	for control: Control in navigation.get_children():
		control.minimum_size_changed.connect(update_width)
	editor._layout.sort_children.connect(update_width)
	update_width.call()


static func _create_option_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = label_text
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return label


static func _create_reserved_reset_button(button_tooltip: String) -> Button:
	var reset_button := EDITOR_THEME_CACHE.create_reserved_reset_button(button_tooltip)
	_set_preset_reset_button_available(reset_button, false)
	return reset_button


static func _configure_compact_label(label: Label) -> void:
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func _configure_compact_option(option: OptionButton) -> void:
	option.fit_to_longest_item = false
	option.clip_text = true
	option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# Separation of dropdown elements in graph (Ease, Trans)
static func _compact_separation() -> int:
	if Engine.is_editor_hint():
		return EDITOR_THEME_CACHE.compact_separation(EditorInterface.get_editor_scale())
	return 2

# Separation of points in points list
static func _point_separation() -> int:
	if Engine.is_editor_hint():
		return maxi(2, roundi(4.0 * EditorInterface.get_editor_scale()))
	return 4


func _on_legacy_preset_state_changed(object: EasingCurve, ease: OptionButton, trans: OptionButton, ease_reset: Button, preset_reset: Button) -> void:
	_update_preset_state_ui(object, ease, trans, ease_reset, preset_reset)


func _move_point_relative(point: Resource, offset: int) -> void:
	if disposed:
		return
	var backend := BackendFactory.create(_point_list_curve_resource())
	var index: int = backend.find_point(point)
	if index < 0:
		return
	var target := wrapi(index + offset, 0, backend.get_point_count())
	if curve != null:
		_move_point(index, target)
	else:
		var display_points: Array[Resource] = backend.get_display_points()
		var display_index := display_points.find(point)
		target = backend.find_point(display_points[wrapi(display_index + offset, 0, display_points.size())])
		_move_native_point(index, target)


func _on_point_list_swap(from_index: int, to_index: int, list: Control) -> void:
	if disposed or not is_instance_valid(list):
		return
	var panels: Array[Node] = []
	for child in list.get_children():
		if child is PanelContainer:
			panels.append(child)
	if from_index < 0 or to_index < 0 or from_index >= panels.size() or to_index >= panels.size():
		return
	var backend := BackendFactory.create(_point_list_curve_resource())
	var source: int = backend.find_point(panels[from_index].get_meta(&"point_resource", null))
	var target: int = backend.find_point(panels[to_index].get_meta(&"point_resource", null))
	if source < 0 or target < 0:
		return
	if curve != null:
		_move_point(source, target)
	else:
		_move_native_point(source, target)

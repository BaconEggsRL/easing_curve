@tool
extends EditorInspectorPlugin
## EasingCurve EditorInspectorPlugin
##
## Parses any exported EasingCurve resource using _can_handle and _parse_property.
## The points array is built using handle_points and the curve editor using handle_easing_curve_editor.
## This is designed to mimic the built-in property lists in ItemList node or Curve resource.

const EDITOR_THEME_CACHE = preload(
	"res://addons/easing_curve/scripts/editor/inspector/editor_theme_cache.gd"
)
const ZOOM_SLIDER_CONTAINER = preload(
	"res://addons/easing_curve/scripts/editor/widgets/zoom_slider_container.tscn"
)
const PointEditTransactionController = preload(
	"res://addons/easing_curve/scripts/editor/inspector/point_edit_transaction_controller.gd"
)
const POINT_SNAPSHOT_MUTATOR = preload(
	"res://addons/easing_curve/scripts/runtime/easing_curve_point_snapshot_mutator.gd"
)
const DeferredParameterEditorProperty = preload(
	"res://addons/easing_curve/scripts/editor/inspector/deferred_parameter_editor_property.gd"
)
const GenerateFunctionEditorProperty = preload(
	"res://addons/easing_curve/scripts/editor/inspector/generate_function_editor_property.gd"
)
const PointsEditorProperty = preload(
	"res://addons/easing_curve/scripts/editor/inspector/points_editor_property.gd"
)
const PointsFoldableSection = preload(
	"res://addons/easing_curve/scripts/editor/inspector/points_foldable_section.gd"
)
const PointPropertyClipboardController = preload(
	"res://addons/easing_curve/scripts/editor/inspector/point_property_clipboard_controller.gd"
)
const PointListController = preload(
	"res://addons/easing_curve/scripts/editor/inspector/point_list_controller.gd"
)
# Compatibility/test seam; construction ownership lives in PointListController.
const PointsListContainer = PointListController.PointsListContainer
## Vector2 slider step
const SLIDER_INPUT_STEP = 0.001
const DRAGGING_META := &"_easing_curve_dragging"
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



func _parse_begin(object: Object) -> void:
	_point_list_controller.clear_input_bindings()

	if not object is EasingCurve:
		return

	if _point_list_controller.consume_selection_refresh_preservation():
		return

	_clear_point_property_selection()


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
	_point_property_clipboard.copy_value(curve, point_index, property_name)


func _paste_point_property_value(
	point_index: int,
	property_name: StringName,
) -> void:
	_point_property_clipboard.paste_value(
		curve,
		point_index,
		property_name,
		Callable(self, "_apply_point_property_change"),
	)


func _apply_pasted_point_property_value(
	point_index: int,
	property_name: StringName,
	value: Variant,
) -> void:
	_point_property_clipboard.apply_value(
		curve,
		point_index,
		property_name,
		value,
		Callable(self, "_apply_point_property_change"),
	)


func _copy_point_property_path(
	point_index: int,
	property_name: StringName,
) -> void:
	PointPropertyClipboardController.copy_path(point_index, property_name)


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
	return _point_property_clipboard.create_context_menu(
		curve,
		point_index,
		property_name,
		Callable(self, "_apply_point_property_change"),
	)


func _create_selectable_point_property_header(
	i: int,
	property_name: StringName,
	label_text: String,
	reset_btn: Button,
) -> PanelContainer:
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
				_select_point_property(
					property_header,
					i,
					property_name,
				)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_select_point_property(
					property_header,
					i,
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
var _point_edit_before_state: Dictionary
var _point_edit_selection_before: Dictionary
var _point_edit_point_resource_ids_before := PackedInt64Array()
var _point_edit_action_name := "Edit Easing Curve Point"
var _selected_point_property_header: PanelContainer
var _point_list_controller := PointListController.new()
var _position_x_order_preview_point: EasingCurvePoint
var _initial_autofit_resource_ids: Dictionary[int, bool] = {}
var _autofit_pending := false
var _autofit_request_id := 0


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
		curve,
		graph_selected_index,
	)


func _restore_point_selection_state(selection: Dictionary) -> void:
	var point_index := _point_list_controller.restore_selection(curve, selection)
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
	return _point_list_controller.build_point_list(
		curve,
		_compact_separation(),
		_point_separation(),
		Callable(self, "_create_bool_property"),
		Callable(self, "_create_vector2_property"),
		Callable(self, "_create_handle_mode_property"),
		Callable(self, "_move_point"),
		Callable(self, "_on_remove_btn_pressed"),
		Callable(self, "_on_add_point_btn_pressed"),
	)


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


func handle_easing_curve_editor(object) -> Control:
	if object == null:
		return
	if object is EasingCurve:
		var curve_section := VBoxContainer.new()
		curve_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		curve_section.add_theme_constant_override("separation", 0)

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
		easing_curve_editor.editor_undo_redo = editor_undo_redo
		easing_curve_editor.set_curve(object)
		_apply_autofit_render_state()

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

		# Store reference to curve resource
		curve = object
		_point_edit_before_state = {}
		_point_edit_selection_before = {}
		_point_edit_point_resource_ids_before = PackedInt64Array()
		_point_edit_action_name = "Edit Easing Curve Point"
		# Connect ease/trans preset selected signals
		ease_option.item_selected.connect(
			func(idx):
				_emit_curve_property(&"ease_type", ease_option.get_item_id(idx))
		)

		trans_option.item_selected.connect(
			func(idx):
				_emit_curve_property(&"trans_type", trans_option.get_item_id(idx))
		)

		ease_reset_button.pressed.connect(_on_reset_ease.bind(object))
		preset_reset_button.pressed.connect(_on_reset_selected_preset.bind(object))
		var preset_state_callback := _update_preset_state_ui.bind(
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

		########################################
		# Add zoom slider
		var zoom_row := HBoxContainer.new()
		zoom_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		curve_editor_content.add_child(zoom_row)

		var zoom_spacer := Control.new()
		zoom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zoom_spacer.size_flags_stretch_ratio = 0.6
		zoom_row.add_child(zoom_spacer)

		var zoom_slider_container := ZOOM_SLIDER_CONTAINER.instantiate()
		zoom_slider_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zoom_slider_container.size_flags_stretch_ratio = 0.4
		zoom_row.add_child(zoom_slider_container)

		easing_curve_editor.set_slider_container(zoom_slider_container)
		easing_curve_editor.set_slider_value(
			view_state[EasingCurve.CURVE_EDITOR_VIEW_SLIDER_VALUE]
		)
		if _consume_initial_autofit_for_loaded_resource(object):
			_queue_autofit_curve_editor()


		_curve_editor_section = _create_foldable_section(
			"Curve Editor",
			curve_editor_content,
			object,
		) as PointsFoldableSection
		_curve_editor_section.folding_changed.connect(
			_on_curve_editor_section_folding_changed
		)
		curve_section.add_child(_curve_editor_section)
		########################################
		return curve_section
	return null


func _can_handle(object):
	if object is EasingCurve and not _instantiating_default_property:
		return true
	else:
		return false


func _parse_property(object, type, name, hint_type, hint_string, usage_flags, wide):
	# Handle properties
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
		var content = handle_points(object)
		var section = _create_inspector_section("Points", content, object)
		add_custom_control(section)
		return true
	if object is EasingCurve and name == EasingCurve.POINT_SNAPSHOT_PROPERTY:
		return true
	if object is EasingCurve and name == EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY:
		return true
	if object is EasingCurve and name == EasingCurve.FUNCTION_SNAPSHOT_PROPERTY:
		return true
	if object is EasingCurve and name == "generate_tool_button":
		if EasingCurve.uses_generated_function_data(object.trans_type):
			var property_editor := GenerateFunctionEditorProperty.new()
			property_editor.setup(easing_curve_editor, editor_undo_redo)
			add_custom_control(property_editor)
		return true
	if (
		object is EasingCurve
		and EasingCurve.is_deferred_parameter(
			StringName(name)
		)
	):
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
			or x_input.has_meta(POSITION_X_EDITING_META),
		point if edit_property_name == &"position" else null,
	)
	i = _get_current_point_index(point)
	_update_point_reset_btn(reset_btn, i, edit_property_name) # show reset if different
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
		y_input.has_meta(DRAGGING_META),
		point if edit_property_name == &"position" else null,
	)
	_update_point_reset_btn(reset_btn, i, edit_property_name) # show reset if different
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

	var selection_before := _capture_point_selection_state()
	var before := _point_edit_transaction_controller.capture_state(curve)
	var point_resource_ids_before := curve._get_editor_point_resource_ids()
	var moved_point := curve.points[from_index]
	curve.swap_points(from_index, to_index)
	_select_reordered_point(moved_point)
	var selection_after := _capture_point_selection_state()
	var point_resource_ids_after := curve._get_editor_point_resource_ids()
	_commit_curve_action(
		"Reorder Easing Curve Points",
		_point_edit_transaction_controller.create_action_context(before)
			.with_selection(
				Callable(self, "_restore_point_selection_state"),
				selection_before,
				selection_after,
			)
			.with_point_resource_ids(
				point_resource_ids_before,
				point_resource_ids_after,
			),
	)

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
	return curve.points.find(point)


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
		easing_curve_editor.clear_position_x_order_preview()
	var point_index := point_order.find(point)
	if point_index == -1:
		return

	if defer_list_reorder:
		_position_x_order_preview_point = point
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
			_apply_point_property_change(i, force_property, toggled_on)
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
			_select_point_property(property_header, i, StringName(property_name))
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
			_apply_point_property_change(i, lock_change_property, next_toggled_on)
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
	var has_left_endpoint := false
	var has_right_endpoint := false
	for point in curve.points:
		if point == null:
			continue
		has_left_endpoint = has_left_endpoint or EasingCurve.is_left_endpoint_x(
			point.position.x
		)
		has_right_endpoint = has_right_endpoint or EasingCurve.is_right_endpoint_x(
			point.position.x
		)

	if not has_left_endpoint:
		_add_points_list_point(EasingCurvePoint.new(Vector2(0.0, 0.0)))
		return

	if not has_right_endpoint:
		_add_points_list_point(EasingCurvePoint.new(Vector2(1.0, 1.0)))
		return

	var largest_gap := -1.0
	var new_x := 0.0
	for i in range(curve.points.size() - 1):
		var left_point := curve.points[i]
		var right_point := curve.points[i + 1]
		if left_point == null or right_point == null:
			continue
		var gap := right_point.position.x - left_point.position.x
		if gap > largest_gap:
			largest_gap = gap
			new_x = (left_point.position.x + right_point.position.x) * 0.5

	var new_point := EasingCurvePoint.new(Vector2(new_x, curve.sample(new_x)))
	new_point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	_add_points_list_point(new_point)


func _add_points_list_point(point: EasingCurvePoint) -> void:
	_point_list_controller.request_selection_refresh_preservation()
	_add_point(
		point,
		_capture_point_selection_state(),
		true,
	)

func _create_foldable_section(
	title: String,
	content: Control,
	curve: EasingCurve,
) -> Control:
	var section := PointsFoldableSection.new()
	section.setup(title, content, curve)
	return section


func _create_inspector_section(
	title: String,
	content: Control,
	curve: EasingCurve
) -> Control:
	var section := PointsFoldableSection.new()

	section.copy_value_callback = func():
		if _point_list_controller.selected_point_index >= 0:
			_copy_point_property_value(
				_point_list_controller.selected_point_index,
				_point_list_controller.selected_point_property_name
			)

	section.paste_value_callback = func():
		if _point_list_controller.selected_point_index >= 0:
			_paste_point_property_value(
				_point_list_controller.selected_point_index,
				_point_list_controller.selected_point_property_name
			)

	section.copy_path_callback = func():
		if _point_list_controller.selected_point_index >= 0:
			_copy_point_property_path(
				_point_list_controller.selected_point_index,
				_point_list_controller.selected_point_property_name
			)

	section.can_paste_callback = func():
		return (
			_point_list_controller.selected_point_index >= 0
			and _clipboard_has_compatible_point_property_value(
				_point_list_controller.selected_point_property_name,
			)
		)

	section.setup(title, content, curve)
	return section


func _on_curve_editor_point_changed(_i: int, _new_point: EasingCurvePoint) -> void:
	easing_curve_editor.queue_redraw()


func _commit_point_edit(point_order: Array[EasingCurvePoint] = []) -> void:
	_commit_position_x_order_preview()
	if _point_edit_before_state.is_empty():
		return
	var before := _point_edit_before_state
	var selection_before := _point_edit_selection_before
	var point_resource_ids_before := _point_edit_point_resource_ids_before
	var action_name := _point_edit_action_name
	_point_edit_before_state = {}
	_point_edit_selection_before = {}
	_point_edit_point_resource_ids_before = PackedInt64Array()
	_point_edit_action_name = "Edit Easing Curve Point"
	if not point_order.is_empty() and curve.points != point_order:
		curve.points = point_order
	var after := _point_edit_transaction_controller.capture_state(curve)
	var selection_after := _capture_point_selection_state()
	var point_resource_ids_after := curve._get_editor_point_resource_ids()
	# Flush the draft point notifications once at the drag boundary.
	curve.set_point_snapshot(curve.get_point_snapshot())
	_commit_curve_action(
		action_name,
		_point_edit_transaction_controller.create_action_context(before, after)
			.with_selection(
				Callable(self, "_restore_point_selection_state"),
				selection_before,
				selection_after,
			)
			.with_point_resource_ids(
				point_resource_ids_before,
				point_resource_ids_after,
			),
	)


func _commit_curve_action(
		action_name: String,
		context,
) -> bool:
	return _point_edit_transaction_controller.commit_applied_action(
		curve,
		action_name,
		context,
	)


func _connect_point_input_drag_signals(input: EditorSpinSlider) -> void:
	input.grabbed.connect(_on_point_input_grabbed.bind(input))
	input.ungrabbed.connect(_on_point_input_ungrabbed.bind(input))
	input.value_focus_entered.connect(_on_point_input_focus_entered.bind(input))


func _on_point_input_grabbed(input: EditorSpinSlider) -> void:
	input.set_meta(DRAGGING_META, true)


func _on_point_input_ungrabbed(input: EditorSpinSlider) -> void:
	if input.has_meta(DRAGGING_META):
		input.remove_meta(DRAGGING_META)
	_commit_point_edit.call_deferred()


func _on_point_input_focus_entered(input: EditorSpinSlider) -> void:
	if input.has_meta(DRAGGING_META):
		input.remove_meta(DRAGGING_META)
		_commit_point_edit()


func _on_position_x_input_focus_entered(input: EditorSpinSlider) -> void:
	input.set_meta(POSITION_X_EDITING_META, true)


func _on_position_x_input_focus_exited(input: EditorSpinSlider) -> void:
	if input.has_meta(POSITION_X_EDITING_META):
		input.remove_meta(POSITION_X_EDITING_META)
		_commit_point_edit.call_deferred()


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
	_add_point(point, _capture_point_selection_state())


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
	if i < 0 or i >= curve.points.size():
		return
	_point_list_controller.request_selection_refresh_preservation()
	var before := _point_edit_transaction_controller.capture_state(curve)
	if changing and _point_edit_before_state.is_empty():
		_point_edit_before_state = before
		_point_edit_selection_before = _capture_point_selection_state()
		_point_edit_point_resource_ids_before = curve._get_editor_point_resource_ids()
		_point_edit_action_name = _point_action_name(property_name)
	var snapshot := curve.get_point_snapshot()
	match property_name:
		&"position":
			var point := curve.points[i]
			var positions: PackedVector2Array = snapshot["positions"]
			var old_position := positions[i]
			var new_position: Vector2 = value
			positions[i] = new_position
			snapshot["positions"] = positions

			var delta := new_position - old_position
			if not point.is_lock_active(&"left_control_point"):
				var left_control_points: PackedVector2Array = snapshot[
					"left_control_points"
				]
				left_control_points[i] += delta
				snapshot["left_control_points"] = left_control_points

			if not point.is_lock_active(&"right_control_point"):
				var right_control_points: PackedVector2Array = snapshot[
					"right_control_points"
				]
				right_control_points[i] += delta
				snapshot["right_control_points"] = right_control_points

		&"left_control_point", &"right_control_point":
			var point := curve.points[i]

			var side := (
				EasingCurvePoint.ControlSide.LEFT
				if property_name == &"left_control_point"
				else EasingCurvePoint.ControlSide.RIGHT
			)

			var pair := point.get_control_point_pair(side, value)

			var left_control_points: PackedVector2Array = snapshot[
				"left_control_points"
			]
			var right_control_points: PackedVector2Array = snapshot[
				"right_control_points"
			]

			left_control_points[i] = pair["left"]
			right_control_points[i] = pair["right"]

			snapshot["left_control_points"] = left_control_points
			snapshot["right_control_points"] = right_control_points

		&"handle_mode":
			if not POINT_SNAPSHOT_MUTATOR.apply(
				snapshot, curve.points[i], i, property_name, value
			):
				return


		&"left_control_state", &"right_control_state":
			if not POINT_SNAPSHOT_MUTATOR.apply(
				snapshot, curve.points[i], i, property_name, value
			):
				return


		&"toolbar_options_reset":
			if not POINT_SNAPSHOT_MUTATOR.apply(
				snapshot, curve.points[i], i, property_name, value
			):
				return


		&"left_force_linear", &"right_force_linear":
			if not POINT_SNAPSHOT_MUTATOR.apply(
				snapshot, curve.points[i], i, property_name, value
			):
				return


		&"locked":
			if not POINT_SNAPSHOT_MUTATOR.apply(
				snapshot, curve.points[i], i, property_name, value
			):
				return

		&"position_lock", &"left_control_lock", &"right_control_lock":
			if not POINT_SNAPSHOT_MUTATOR.apply(
				snapshot, curve.points[i], i, property_name, value
			):
				return

		_:
			if (
				not EasingCurve.is_point_property_snapshot_lifecycle_ordinary(property_name)
				or not EasingCurve.set_point_snapshot_property_value(snapshot, property_name, i, value)
			):
				return

	var defer_notification := position_reorder_point != null
	snapshot["changing"] = changing or defer_notification
	curve.set_point_snapshot(snapshot)
	if position_reorder_point != null:
		_reorder_position_edited_point(position_reorder_point, changing)
		if not changing:
			curve.set_point_snapshot(curve.get_point_snapshot())

	if not changing:
		if not _point_edit_before_state.is_empty():
			_commit_point_edit()
			return
		_commit_curve_action(
			_point_action_name(property_name),
			_point_edit_transaction_controller.create_action_context(before),
		)


func _point_action_name(property_name: StringName) -> String:
	return PointEditTransactionController.point_action_name(property_name)


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
	_commit_curve_action(
		"Add Easing Curve Point",
		_point_edit_transaction_controller.create_action_context(before).with_selection(
			Callable(self, "_restore_point_selection_state") if not selection_before.is_empty() else Callable(),
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
	_commit_curve_action(
		"Remove Easing Curve Point",
		_point_edit_transaction_controller.create_action_context(before).with_selection(
			Callable(self, "_restore_point_selection_state"),
			selection_before,
			selection_after,
		),
	)

func _emit_curve_property(property_name: StringName, value: Variant) -> void:
	if (
		property_name == &"ease_type"
		and curve.curve_mode == EasingCurve.CurveMode.BEZIER
		and curve.is_selected_preset_modified()
	):
		return
	_queue_autofit_curve_editor()
	var action_name := "Change Easing Curve Ease" if property_name == &"ease_type" else "Change Easing Curve Transition"
	_point_edit_transaction_controller.apply_action(
		curve,
		action_name,
		func(): curve.set(property_name, value),
	)


func _consume_initial_autofit_for_loaded_resource(object: EasingCurve) -> bool:
	if object == null:
		return false
	var resource_path := object.resource_path
	if resource_path.is_empty() or resource_path.contains("::"):
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
	_autofit_pending = true
	_autofit_request_id += 1
	_apply_autofit_render_state()
	return _autofit_request_id


func _cancel_autofit(request_id: int = -1) -> void:
	if request_id >= 0 and not _is_current_autofit_request(request_id):
		return
	_autofit_pending = false
	_autofit_request_id += 1
	_apply_autofit_render_state()


func _complete_autofit(request_id: int) -> void:
	if not _is_current_autofit_request(request_id):
		return
	if not _is_autofit_ready():
		_cancel_autofit(request_id)
		return

	easing_curve_editor.autofit()
	_autofit_pending = false
	_apply_autofit_render_state()


func _is_current_autofit_request(request_id: int) -> bool:
	return _autofit_pending and request_id == _autofit_request_id


func _is_autofit_pending() -> bool:
	return _autofit_pending


func _is_autofit_ready() -> bool:
	return (
		is_instance_valid(easing_curve_editor)
		and easing_curve_editor.is_autofit_ready()
	)


func _apply_autofit_render_state() -> void:
	if is_instance_valid(easing_curve_editor):
		easing_curve_editor.set_graph_render_suppressed(_autofit_pending)


func _on_curve_editor_section_folding_changed(is_folded: bool) -> void:
	if is_folded or not _autofit_pending:
		return
	call_deferred(&"_autofit_curve_editor", _autofit_request_id)


func _autofit_curve_editor(request_id: int = -1) -> void:
	if request_id < 0:
		request_id = _request_autofit()
	elif not _is_current_autofit_request(request_id):
		return

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_cancel_autofit(request_id)
		return

	# Preset/resource changes may rebuild the Inspector and hide/show the
	# point toolbar. Let those minimum-size/layout changes settle before
	# measuring the graph rect used by Autofit. The graph stays suppressed
	# until the fitted view is ready, so no intermediate default-view frame
	# is presented.
	await tree.process_frame
	await tree.process_frame

	if not _is_current_autofit_request(request_id):
		return
	if (
		is_instance_valid(_curve_editor_section)
		and _curve_editor_section.folded
	):
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
	_emit_curve_property(&"ease_type", EasingCurve.EASE.IN)


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
		var display := (
			String(EasingCurve.TRANS.keys()[transition])
			.to_lower()
			.capitalize()
			.replace("_", " ")
		)

		if (
			SHOW_MODIFIED_ASTERISK
			and transition == selected_transition
			and modified
		):
			display += " *"

		trans_control.set_item_text(i, display)


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
			var display := (
				String(EasingCurve.TRANS.keys()[transition])
				.to_lower()
				.capitalize()
				.replace("_", " ")
			)

			option.add_item(display, transition)

	option.select(option.get_item_index(selected_value))
	return option


static func _create_option(enum_dict: Dictionary, selected_value: int) -> OptionButton:
	var option := OptionButton.new()
	_configure_compact_option(option)
	var keys = enum_dict.keys()
	if keys.has("CSS_LINEAR") and keys.has("CSS_CUBIC_BEZIER"):
		keys.erase("CSS_CUBIC_BEZIER")
		keys.insert(keys.find("CSS_LINEAR") + 1, "CSS_CUBIC_BEZIER")
	for key in keys:
		var display = key.to_lower().capitalize().replace("_", " ")
		option.add_item(display, enum_dict[key]) # store enum value as ID
	option.select(option.get_item_index(selected_value))
	return option


static func _create_option_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = label_text
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return label


static func _create_reserved_reset_button(button_tooltip: String) -> Button:
	var reset_button := Button.new()
	reset_button.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_RELOAD
	)
	reset_button.flat = true
	reset_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset_button.tooltip_text = button_tooltip
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
		return maxi(1, roundi(2.0 * EditorInterface.get_editor_scale()))
	return 2

# Separation of points in points list
static func _point_separation() -> int:
	if Engine.is_editor_hint():
		return maxi(2, roundi(4.0 * EditorInterface.get_editor_scale()))
	return 4

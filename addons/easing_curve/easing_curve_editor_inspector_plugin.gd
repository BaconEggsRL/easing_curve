@tool
extends EditorInspectorPlugin
## EasingCurve EditorInspectorPlugin
##
## Parses any exported EasingCurve resource using _can_handle and _parse_property.
## The points array is built using handle_points and the curve editor using handle_easing_curve_editor.
## This is designed to mimic the built-in property lists in ItemList node or Curve resource.

## Styleboxes
const X_STYLEBOX = preload("uid://dsapcj11t0kpu")
const BTN_NORMAL = preload("uid://c6hb75fm8lwht")
## GUI Icons
const GUI_TREE_ARROW_RIGHT = preload("res://addons/easing_curve/assets/icons/GuiTreeArrowRight.svg")
const GUI_TREE_ARROW_DOWN = preload("res://addons/easing_curve/assets/icons/GuiTreeArrowDown.svg")
const ZOOM_SLIDER_CONTAINER = preload("uid://r1ymwr6nae")

const FORCE_LINEAR_ICON_ON = preload("res://addons/easing_curve/assets/icons/Instance.svg")
const FORCE_LINEAR_ICON_OFF = preload("res://addons/easing_curve/assets/icons/Unlinked.svg")

const RELOAD = preload("res://addons/easing_curve/assets/icons/Reload.svg")
const REMOVE = preload("res://addons/easing_curve/assets/icons/Remove.svg")
const ADD = preload("res://addons/easing_curve/assets/icons/Add.svg")
const MOVE_DOWN = preload("res://addons/easing_curve/assets/icons/MoveDown.svg")
const MOVE_UP = preload("res://addons/easing_curve/assets/icons/MoveUp.svg")
const TRIPLE_BAR = preload("res://addons/easing_curve/assets/icons/TripleBar.svg")
const LOCK = preload("res://addons/easing_curve/assets/icons/Lock.svg")
const UNLOCK = preload("res://addons/easing_curve/assets/icons/Unlock.svg")
const EASING_CURVE_EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")
## Vector2 slider step
const SLIDER_INPUT_STEP = 0.001
const DRAGGING_META := &"_easing_curve_dragging"
const POSITION_X_EDITING_META := &"_easing_curve_position_x_editing"
# copy functions
const POINT_MENU_COPY_VALUE := 0
const POINT_MENU_PASTE_VALUE := 1
const POINT_MENU_COPY_PATH := 2
# modified preset indicator
const SHOW_MODIFIED_ASTERISK := true
# alignment
const POINT_PROPERTY_HEADER_RATIO := 0.35
const POINT_PROPERTY_VALUE_RATIO := 0.65


const TRANSITION_GROUPS := [
	{
		"name": "Basic",
		"items": [
			EasingCurve.TRANS.LINEAR,
			EasingCurve.TRANS.CONSTANT,
		],
	},
	{
		"name": "Polynomial",
		"items": [
			EasingCurve.TRANS.QUAD,
			EasingCurve.TRANS.CUBIC,
			EasingCurve.TRANS.QUART,
			EasingCurve.TRANS.QUINT,
			EasingCurve.TRANS.POWER,
		],
	},
	{
		"name": "Smooth",
		"items": [
			EasingCurve.TRANS.SINE,
			EasingCurve.TRANS.CIRC,
			EasingCurve.TRANS.EXPO,
		],
	},
	{
		"name": "Springy",
		"items": [
			EasingCurve.TRANS.BACK,
			EasingCurve.TRANS.ELASTIC,
			EasingCurve.TRANS.BOUNCE,
			EasingCurve.TRANS.SPRING,
			EasingCurve.TRANS.PHYSICS_SPRING,
		],
	},
	{
		"name": "Discrete",
		"items": [
			EasingCurve.TRANS.STEP,
			EasingCurve.TRANS.JITTER,
			EasingCurve.TRANS.IRREGULAR,
		],
	},
	{
		"name": "CSS",
		"items": [
			EasingCurve.TRANS.CSS_CUBIC_BEZIER,
			EasingCurve.TRANS.CSS_LINEAR,
		],
	},
	{
		"name": "Custom",
		"items": [
			EasingCurve.TRANS.CUSTOM,
		],
	},
]



func _parse_begin(object: Object) -> void:
	if not object is EasingCurve:
		return

	if _preserve_point_selection_on_refresh:
		_preserve_point_selection_on_refresh = false
		return

	_clear_point_property_selection()


static func _point_property_path(
	point_index: int,
	property_name: StringName,
) -> String:
	return "points/%d/%s" % [
		point_index,
		String(property_name),
	]


func _copy_point_property_value(
	point_index: int,
	property_name: StringName,
) -> void:
	if point_index < 0 or point_index >= curve.points.size():
		return

	var value: Variant = curve.points[point_index].get(property_name)

	DisplayServer.clipboard_set(
		var_to_str(value)
	)


func _paste_point_property_value(
	point_index: int,
	property_name: StringName,
) -> void:
	if point_index < 0 or point_index >= curve.points.size():
		return

	var clipboard := DisplayServer.clipboard_get()
	var value: Variant = str_to_var(clipboard)

	_apply_pasted_point_property_value(point_index, property_name, value)


func _apply_pasted_point_property_value(
	point_index: int,
	property_name: StringName,
	value: Variant,
) -> void:
	if not _is_point_property_value_compatible(property_name, value):
		return

	_apply_point_property_change(
		point_index,
		property_name,
		value
	)


func _copy_point_property_path(
	point_index: int,
	property_name: StringName,
) -> void:
	DisplayServer.clipboard_set(
		_point_property_path(
			point_index,
			property_name
		)
	)


static func _is_point_property_value_compatible(
	property_name: StringName,
	value: Variant,
) -> bool:
	if property_name == &"handle_mode":
		return (
			value is int
			and int(value) in EasingCurvePoint.HandleMode.values()
		)
	return value is Vector2


static func _clipboard_has_compatible_point_property_value(
	property_name: StringName,
) -> bool:
	var clipboard := DisplayServer.clipboard_get()

	if clipboard.is_empty():
		return false

	return _is_point_property_value_compatible(
		property_name,
		str_to_var(clipboard),
	)


func _create_point_property_context_menu(
	point_index: int,
	property_name: StringName,
) -> PopupMenu:
	var menu := PopupMenu.new()

	menu.add_item(
		"Copy Value",
		POINT_MENU_COPY_VALUE,
		KEY_MASK_CTRL | KEY_C
	)

	menu.add_item(
		"Paste Value",
		POINT_MENU_PASTE_VALUE,
		KEY_MASK_CTRL | KEY_V
	)

	menu.add_separator()

	menu.add_item(
		"Copy Property Path",
		POINT_MENU_COPY_PATH,
		KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_C
	)

	menu.id_pressed.connect(
		func(id: int):
			match id:
				POINT_MENU_COPY_VALUE:
					_copy_point_property_value(
						point_index,
						property_name
					)

				POINT_MENU_PASTE_VALUE:
					_paste_point_property_value(
						point_index,
						property_name
					)

				POINT_MENU_COPY_PATH:
					_copy_point_property_path(
						point_index,
						property_name
					)
	)

	return menu


func _create_selectable_point_property_header(
	i: int,
	property_name: StringName,
	label_text: String,
	reset_btn: Button,
) -> PanelContainer:
	var property_header := PanelContainer.new()
	property_header.focus_mode = Control.FOCUS_NONE
	#property_header.clip_contents = true

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

				var paste_index := property_context_menu.get_item_index(
					POINT_MENU_PASTE_VALUE,
				)

				property_context_menu.set_item_disabled(
					paste_index,
					not _clipboard_has_compatible_point_property_value(
						property_name,
					),
				)

				property_context_menu.position = (
					DisplayServer.mouse_get_position()
				)
				property_context_menu.popup()
				property_header.accept_event()
	)

	if (
		_selected_point_index == i
		and _selected_point_property_name == property_name
	):
		_selected_point_property_header = property_header
		_set_point_property_selected(property_header, true)

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


class DeferredParameterEditorProperty:
	extends EditorProperty

	var input: EditorSpinSlider
	var property_name: StringName
	var curve_editor: EasingCurveEditor
	var drag_original_snapshot: Dictionary
	var undo_redo: Object
	var reset_button: Button

	func setup(
			native_editor: EditorProperty,
			name: StringName,
			editor: EasingCurveEditor,
			undo_manager: Object,
	) -> bool:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var sliders := native_editor.find_children("*", "EditorSpinSlider", true, false)
		if sliders.size() != 1:
			return false

		input = sliders[0] as EditorSpinSlider
		if input == null:
			return false

		property_name = name
		curve_editor = editor
		undo_redo = undo_manager

		native_editor.remove_child(input)
		native_editor.free()

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(row)

		# The extracted native editor no longer has its original container managing
		# its width, so explicitly make it consume the available value-column space.
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.custom_minimum_size.x = 0.0
		row.add_child(input)
		add_focusable(input)

		# Added in Godot 4.7 -- defers property update to end of slider drag.
		if input.has_method("set_deferred_drag_mode_enabled"):
			input.set_deferred_drag_mode_enabled(false)

		input.grabbed.connect(_on_grabbed)
		input.ungrabbed.connect(_on_ungrabbed)
		input.value_focus_entered.connect(_on_value_focus_entered)
		input.value_changed.connect(_on_value_changed)
		input.tree_exiting.connect(_on_tree_exiting)

		return true

	func _update_property() -> void:
		var object := get_edited_object() as EasingCurve
		if object != null and input != null:
			input.set_value_no_signal(float(object.get(property_name)))
			_update_reset_button(object.get(property_name))

	func _on_grabbed() -> void:
		if input.has_meta(DRAGGING_META):
			return
		var object := get_edited_object() as EasingCurve
		if object == null:
			return
		input.set_meta(DRAGGING_META, true)
		drag_original_snapshot = EASING_CURVE_EDITOR_UNDO.capture_state(object)
		object._begin_editor_parameter_edit()

	func _on_ungrabbed() -> void:
		_commit_drag.call_deferred()

	func _on_value_focus_entered() -> void:
		if not input.has_meta(DRAGGING_META):
			return
		_commit_drag()

	func _on_value_changed(value: float) -> void:
		var object := get_edited_object() as EasingCurve
		if object == null:
			return
		var property_value: Variant = int(value) if object.get(property_name) is int else value
		if input.has_meta(DRAGGING_META):
			object.set(property_name, property_value)
		else:
			_commit_value(object, property_value)
		_update_reset_button(property_value)
		_queue_curve_redraw()


	func _on_reset_pressed() -> void:
		var object := get_edited_object() as EasingCurve
		if (
			object == null
			or not EasingCurve.has_parameter_default(property_name)
		):
			return

		var default_value := EasingCurve.get_parameter_default(
			property_name
		)

		_commit_value(
			object,
			default_value,
			"Reset Easing Curve %s" % String(property_name).capitalize(),
		)

		input.set_value_no_signal(float(default_value))
		_update_reset_button(default_value)
		_queue_curve_redraw()


	func _update_reset_button(value: Variant) -> void:
		if (
			reset_button == null
			or not EasingCurve.has_parameter_default(property_name)
		):
			return
		var default_value: Variant = (
			EasingCurve.get_parameter_default(property_name)
		)
		reset_button.visible = value != default_value

	func _on_tree_exiting() -> void:
		_commit_drag()

	func _commit_drag() -> void:
		if not input.has_meta(DRAGGING_META):
			return
		input.remove_meta(DRAGGING_META)
		var object := get_edited_object() as EasingCurve
		if object == null:
			return

		var final_snapshot := EASING_CURVE_EDITOR_UNDO.capture_state(object)
		if final_snapshot == drag_original_snapshot:
			object._cancel_editor_parameter_edit()
		else:
			object._finish_editor_parameter_edit()
			EASING_CURVE_EDITOR_UNDO.commit_applied_action(
				undo_redo,
				object,
				"Change Easing Curve %s" % String(property_name).capitalize(),
				drag_original_snapshot,
				final_snapshot,
				self,
			)
		_queue_curve_redraw()


	func _commit_value(
		object: EasingCurve,
		value: Variant,
		action_name := "",
	) -> void:
		var original_snapshot := EASING_CURVE_EDITOR_UNDO.capture_state(object)

		object._begin_editor_parameter_edit()
		object.set(property_name, value)

		var final_snapshot := EASING_CURVE_EDITOR_UNDO.capture_state(object)

		if final_snapshot == original_snapshot:
			object._cancel_editor_parameter_edit()
			return

		object._finish_editor_parameter_edit()

		if action_name.is_empty():
			action_name = (
				"Change Easing Curve %s"
				% String(property_name).capitalize()
			)

		EASING_CURVE_EDITOR_UNDO.commit_applied_action(
			undo_redo,
			object,
			action_name,
			original_snapshot,
			final_snapshot,
			self,
		)


	func _queue_curve_redraw() -> void:
		if is_instance_valid(curve_editor):
			curve_editor.queue_redraw()


class GenerateFunctionEditorProperty:
	extends EditorProperty

	var button_container: HBoxContainer
	var button: Button
	var curve_editor: EasingCurveEditor
	var undo_redo: Object

	func setup(editor: EasingCurveEditor, undo_manager: Object) -> void:
		curve_editor = editor
		undo_redo = undo_manager
		button_container = HBoxContainer.new()
		button_container.alignment = BoxContainer.ALIGNMENT_CENTER
		button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button = Button.new()
		button.text = "Generate"
		button.tooltip_text = "Generate a new random curve"
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var editor_theme := EditorInterface.get_editor_theme()
		if editor_theme.has_icon(&"Callable", &"EditorIcons"):
			button.icon = editor_theme.get_icon(&"Callable", &"EditorIcons")
		button_container.add_child(button)
		add_child(button_container)
		add_focusable(button)
		button.pressed.connect(_on_pressed)

	func _ready() -> void:
		_hide_property_chrome()

	func _update_property() -> void:
		_hide_property_chrome()

	func _hide_property_chrome() -> void:
		label = ""
		draw_label = false
		draw_background = false
		selectable = false
		name_split_ratio = 0.0
		tooltip_text = ""
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _on_pressed() -> void:
		var object := get_edited_object() as EasingCurve
		if object == null:
			return
		var original_snapshot := EASING_CURVE_EDITOR_UNDO.capture_state(object)
		object._begin_editor_parameter_edit()
		object.generate_irregular()
		var generated_snapshot := EASING_CURVE_EDITOR_UNDO.capture_state(object)
		if generated_snapshot == original_snapshot:
			object._cancel_editor_parameter_edit()
		else:
			object._finish_editor_parameter_edit()
			EASING_CURVE_EDITOR_UNDO.commit_applied_action(
				undo_redo,
				object,
				"Generate Easing Curve",
				original_snapshot,
				generated_snapshot,
				self,
			)
		if is_instance_valid(curve_editor):
			curve_editor.queue_redraw()


class PointsEditorProperty:
	extends EditorProperty

	func set_content(content: Control) -> void:
		add_child(content)
		_hide_property_chrome()

	func _ready() -> void:
		_hide_property_chrome()

	func _update_property() -> void:
		_hide_property_chrome()

	func _hide_property_chrome() -> void:
		label = ""
		draw_label = false
		draw_background = false
		selectable = false
		name_split_ratio = 0.0
		tooltip_text = ""


class PointsListContainer:
	extends VBoxContainer

	signal point_swap_requested(from_index: int, to_index: int)

	var drop_index := -1
	var drop_after := false

	func enable_drop_forwarding(control: Control) -> void:
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
		if not data.has("index") or not data.has("point"):
			return false

		var point_panels: Array[Control] = []

		for child in get_children():
			if child is PanelContainer:
				point_panels.append(child)

		if point_panels.is_empty():
			return false

		var from_index: int = data["index"]
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
		var point_panels: Array[Control] = []

		for child in get_children():
			if child is PanelContainer:
				point_panels.append(child)

		var from_index: int = data["index"]
		var to_index := _get_drop_target_index(position.y, point_panels)

		clear_drop_index()

		if to_index >= 0 and from_index != to_index:
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

		var editor_theme := EditorInterface.get_editor_theme()
		var color := editor_theme.get_color(&"accent_color", &"Editor")

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

class PointsFoldableSection:
	extends VBoxContainer

	var copy_value_callback: Callable
	var paste_value_callback: Callable
	var copy_path_callback: Callable
	var can_paste_callback: Callable

	static var folded_by_section: Dictionary[String, bool] = {}
	var resource_id: int
	var fold_state_key := ""
	var title: String
	var _native_section: Control
	var _fallback_header: Button
	const FOLD_SCROLL_DEBUG := true

	var _fallback_content: Control
	var _content: Control
	var _fallback_folded := false
	var _fold_scroll_debug_collapse_count := 0
	var _pending_fold_scroll_debug_collapse := 0
	var _fold_scroll_debug_hierarchy_logged := false
	var base := EditorInterface.get_base_control()
	var normal_color := base.get_theme_color(
		&"font_color",
		&"Editor"
	)
	var hover_color := base.get_theme_color(
		&"font_hover_color",
		&"Editor"
	)
	#var normal_color := Color(1.0, 1.0, 1.0, 0.75)
	#var hover_color := Color(1.0, 1.0, 1.0, 0.85)

	var normal_icon_color := Color(1.0, 1.0, 1.0, 0.90)
	var hover_icon_color := Color.WHITE

	var normal_font_base := Color(
		1.0,
		1.0,
		1.0,
		normal_color.a / normal_icon_color.a
	)

	var hover_font_base := Color(
		1.0,
		1.0,
		1.0,
		hover_color.a / hover_icon_color.a
	)

	var folded: bool:
		get:
			if is_instance_valid(_native_section):
				return bool(_native_section.get(&"folded"))
			return _fallback_folded


	func _ready() -> void:
		set_process_input(true)


	func _input(event: InputEvent) -> void:
		if (
			FOLD_SCROLL_DEBUG
			and event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
			and not folded
			and _is_native_title_click(event.position)
		):
			_fold_scroll_debug_collapse_count += 1
			_pending_fold_scroll_debug_collapse = _fold_scroll_debug_collapse_count
			_capture_fold_scroll_debug("before_title_click", _fold_scroll_debug_collapse_count)

		if not event is InputEventKey:
			return

		if not event.pressed or event.echo:
			return

		var focus_owner := get_viewport().gui_get_focus_owner()
		# Let external text editors handle their own copy/paste.
		if (
			focus_owner != null
			and not is_ancestor_of(focus_owner)
			and (
				focus_owner is TextEdit
				or focus_owner is LineEdit
			)
		):
			return

		if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_C:
			if copy_path_callback.is_valid():
				copy_path_callback.call()
				get_viewport().set_input_as_handled()
			return

		if event.ctrl_pressed and not event.shift_pressed and event.keycode == KEY_C:
			if copy_value_callback.is_valid():
				copy_value_callback.call()
				get_viewport().set_input_as_handled()
			return

		if event.ctrl_pressed and not event.shift_pressed and event.keycode == KEY_V:
			if (
				paste_value_callback.is_valid()
				and can_paste_callback.is_valid()
				and can_paste_callback.call()
			):
				paste_value_callback.call()
				get_viewport().set_input_as_handled()


	func setup(section_title: String, content: Control, object: EasingCurve) -> void:
		resource_id = object.get_instance_id()
		title = section_title
		_content = content
		fold_state_key = "%d:%s" % [
			resource_id,
			section_title,
		]
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var initially_folded: bool = folded_by_section.get(
			fold_state_key,
			false,
		)
		if ClassDB.class_exists(&"FoldableContainer"):
			_native_section = ClassDB.instantiate(&"FoldableContainer") as Control
			_native_section.focus_mode = Control.FOCUS_NONE
			_native_section.set(&"title", section_title)
			_native_section.set(&"title_text_overrun_behavior", TextServer.OVERRUN_TRIM_ELLIPSIS)
			_native_section.set(&"folded", initially_folded)
			for style_name in [
				#&"panel",
				&"title_panel",
				&"title_collapsed_panel",
				&"title_hover_panel",
				&"title_collapsed_hover_panel",
			]:
				_native_section.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())

				var style := _native_section.get_theme_stylebox(style_name).duplicate()
				if style is StyleBoxFlat:
					style.bg_color.a = 0.0
				style.content_margin_top = 4.0
				style.content_margin_left = 2.0
				style.content_margin_bottom = 4.0
				_native_section.add_theme_stylebox_override(style_name, style)

			_native_section.add_theme_stylebox_override(
				&"panel",
				StyleBoxEmpty.new()
			)

			_native_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_native_section.add_child(content)
			_native_section.connect(&"folding_changed", _on_folding_changed)
			add_child(_native_section)
			#call_deferred("_debug_points_layout")
			#call_deferred("_debug_fold_alignment")
			#call_deferred("_debug_theme")


			_native_section.add_theme_color_override(
				&"font_color",
				normal_font_base
			)

			_native_section.add_theme_color_override(
				&"collapsed_font_color",
				normal_font_base
			)

			_native_section.add_theme_color_override(
				&"hover_font_color",
				hover_font_base
			)

			_native_section.self_modulate = normal_icon_color

			_native_section.mouse_entered.connect(func():
				_native_section.self_modulate = hover_icon_color
			)

			_native_section.mouse_exited.connect(func():
				_native_section.self_modulate = normal_icon_color
			)

			return

		_fallback_header = Button.new()
		_fallback_header.text = section_title
		_fallback_header.flat = true
		_fallback_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_fallback_header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_fallback_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_fallback_header.pressed.connect(_toggle_fallback)
		add_child(_fallback_header)
		_fallback_content = content
		add_child(content)
		_set_fallback_folded(initially_folded)

	func fold() -> void:
		if is_instance_valid(_native_section):
			_native_section.call(&"fold")
			return
		_set_fallback_folded(true)

	func expand() -> void:
		if is_instance_valid(_native_section):
			_native_section.call(&"expand")
			return
		_set_fallback_folded(false)

	func _on_folding_changed(is_folded: bool) -> void:
		folded_by_section[fold_state_key] = is_folded
		if (
			not FOLD_SCROLL_DEBUG
			or not is_folded
			or _pending_fold_scroll_debug_collapse == 0
		):
			return

		var collapse_id := _pending_fold_scroll_debug_collapse
		_pending_fold_scroll_debug_collapse = 0
		_capture_fold_scroll_debug("folding_changed", collapse_id)
		call_deferred("_capture_fold_scroll_debug", "deferred", collapse_id)
		_capture_fold_scroll_debug_after_frames(collapse_id)

	func _is_native_title_click(click_position: Vector2) -> bool:
		if (
			folded
			or not is_instance_valid(_native_section)
			or not is_instance_valid(_content)
		):
			return false

		var section_rect := _native_section.get_global_rect()
		var content_top := _content.get_global_position().y
		return (
			section_rect.has_point(click_position)
			and click_position.y < content_top
		)

	func _find_inspector_scroll_container() -> ScrollContainer:
		var ancestor := get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer:
				return ancestor as ScrollContainer
			ancestor = ancestor.get_parent()
		return null

	func _capture_fold_scroll_debug_hierarchy() -> void:
		if _fold_scroll_debug_hierarchy_logged:
			return
		_fold_scroll_debug_hierarchy_logged = true

		var inspectors: Array[Dictionary] = []
		var ancestor := get_parent()
		while ancestor != null:
			if ancestor is EditorInspector:
				var inspector := ancestor as EditorInspector
				var scroll_bar := inspector.get_v_scroll_bar()
				inspectors.append({
					"path": String(inspector.get_path()),
					"instance_id": inspector.get_instance_id(),
					"size_y": inspector.size.y,
					"scroll_vertical": inspector.get_v_scroll(),
					"scrollbar_value": scroll_bar.value,
					"scrollbar_max_value": scroll_bar.max_value,
					"scrollbar_page": scroll_bar.page,
				})
			ancestor = ancestor.get_parent()

		print("EC_FOLD_SCROLL_HIERARCHY ", JSON.stringify(inspectors))

	func _capture_fold_scroll_debug(stage: String, collapse_id: int) -> void:
		if not FOLD_SCROLL_DEBUG or not is_inside_tree():
			return

		_capture_fold_scroll_debug_hierarchy()
		var nested_inspector := _find_inspector_scroll_container()
		if nested_inspector == null:
			print("EC_FOLD_SCROLL collapse=%d stage=%s nested_inspector=missing" % [collapse_id, stage])
			return

		var nested_scroll_bar := nested_inspector.get_v_scroll_bar()
		var main_inspector := EditorInterface.get_inspector()
		var main_scroll_bar := main_inspector.get_v_scroll_bar()
		var focus_owner := get_viewport().gui_get_focus_owner()
		var focus_in_content := (
			is_instance_valid(focus_owner)
			and is_instance_valid(_content)
			and (focus_owner == _content or _content.is_ancestor_of(focus_owner))
		)
		var focus_name := "none"
		if is_instance_valid(focus_owner):
			focus_name = "%s:%s" % [focus_owner.get_class(), focus_owner.get_path()]

		print("EC_FOLD_SCROLL ", JSON.stringify({
			"collapse": collapse_id,
			"stage": stage,
			"folded": folded,
			"nested_path": String(nested_inspector.get_path()),
			"nested_instance_id": nested_inspector.get_instance_id(),
			"nested_size_y": nested_inspector.size.y,
			"nested_scroll_vertical": nested_inspector.get_v_scroll(),
			"nested_scrollbar_value": nested_scroll_bar.value,
			"nested_scrollbar_max_value": nested_scroll_bar.max_value,
			"nested_scrollbar_page": nested_scroll_bar.page,
			"main_path": String(main_inspector.get_path()),
			"main_instance_id": main_inspector.get_instance_id(),
			"main_size_y": main_inspector.size.y,
			"main_global_y": main_inspector.global_position.y,
			"main_scroll_vertical": main_inspector.get_v_scroll(),
			"main_scrollbar_value": main_scroll_bar.value,
			"main_scrollbar_max_value": main_scroll_bar.max_value,
			"main_scrollbar_page": main_scroll_bar.page,
			"section_global_y": _native_section.global_position.y,
			"section_viewport_y": _native_section.global_position.y - main_inspector.global_position.y,
			"section_size_y": _native_section.size.y,
			"section_minimum_y": _native_section.get_combined_minimum_size().y,
			"content_size_y": _content.size.y,
			"content_minimum_y": _content.get_combined_minimum_size().y,
			"focus_owner": focus_name,
			"focus_in_content": focus_in_content,
		}))
	func _capture_fold_scroll_debug_after_frames(collapse_id: int) -> void:
		if not is_inside_tree():
			return
		await get_tree().process_frame
		_capture_fold_scroll_debug("one_process_frame", collapse_id)
		await get_tree().process_frame
		_capture_fold_scroll_debug("two_process_frames", collapse_id)

	func _toggle_fallback() -> void:
		_set_fallback_folded(not _fallback_folded)

	func _set_fallback_folded(is_folded: bool) -> void:
		_fallback_folded = is_folded
		_fallback_content.visible = not is_folded
		_fallback_header.icon = GUI_TREE_ARROW_RIGHT if is_folded else GUI_TREE_ARROW_DOWN
		_on_folding_changed(is_folded)


## Curve
var editor_undo_redo: EditorUndoRedoManager # assigned from EditorPlugin
var easing_curve_editor: EasingCurveEditor
var curve_editor_property: EditorProperty
var points_editor_property: EditorProperty
var ease_option: OptionButton
var trans_option: OptionButton
var preset_reset_button: Button
var curve: EasingCurve
var _instantiating_default_property := false
var _point_edit_before_state: Dictionary
var _point_edit_action_name := "Edit Easing Curve Point"
var _selected_point_property_header: PanelContainer
var _selected_point_index := -1
var _selected_point_property_name := StringName()
var _selected_point_resource_id := 0
var _preserve_point_selection_on_refresh := false
var _position_x_order_preview_point: EasingCurvePoint


func _clear_point_property_selection() -> void:
	if is_instance_valid(_selected_point_property_header):
		_set_point_property_selected(
			_selected_point_property_header,
			false
		)

	_selected_point_property_header = null
	_selected_point_index = -1
	_selected_point_property_name = StringName()
	_selected_point_resource_id = 0


func handle_points(curve: EasingCurve) -> VBoxContainer:
	# Contains the list of points
	var point_list = PointsListContainer.new()
	point_list.point_swap_requested.connect(_move_point)

	# Add a gap between "Points" header label and the list of points.
	point_list.add_spacer(true)
	point_list.add_theme_constant_override("separation", _point_separation())

	# Show list of points
	for i in range(curve.points.size()):
		var point := curve.points[i]
		var position := point.position

		# Panel container for each point
		var point_panel := PanelContainer.new() # contains the point
		point_panel.add_theme_stylebox_override("panel", X_STYLEBOX)

		# Keep point controls on one stable row and let the editable fields shrink.
		var point_main_hbox := HBoxContainer.new()
		point_main_hbox.add_theme_constant_override("separation", _compact_separation())
		point_panel.add_child(point_main_hbox)

		# Left side VBox with Move Up / TripleBar / Move Down
		var side_vbox := _create_point_side_vbox(i, point_list, point_panel, point)
		point_main_hbox.add_child(side_vbox)

		var point_properties_grid := GridContainer.new()
		point_properties_grid.columns = 2
		point_properties_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		point_properties_grid.add_theme_constant_override(
			"h_separation",
			_compact_separation(),
		)
		point_properties_grid.add_theme_constant_override(
			"v_separation",
			_compact_separation(),
		)
		point_main_hbox.add_child(point_properties_grid)

		# Remove button (centered vertically)
		var remove_btn := Button.new()
		remove_btn.icon = REMOVE
		remove_btn.flat = true
		remove_btn.tooltip_text = "Remove Point"
		remove_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		remove_btn.pressed.connect(_on_remove_btn_pressed.bind(point_list, i, point_panel, point))

		point_main_hbox.add_child(remove_btn)

		# Position
		_create_vector2_property(
			point,
			i,
			"position",
			"Position",
			point_properties_grid,
		)

		# Handle Mode
		_create_handle_mode_property(
			point,
			i,
			point_properties_grid,
		)

		# Control Points
		var point_count = curve.points.size()

		if point_count > 1:
			if i != 0: # not the first point -> add left control
				_create_vector2_property(
					point,
					i,
					"left_control_point",
					"Left Control",
					point_properties_grid,
				)
			if i != point_count - 1: # not the last point -> add right control
				_create_vector2_property(
					point,
					i,
					"right_control_point",
					"Right Control",
					point_properties_grid,
				)

		# IMPORTANT: add panel to list
		point_list.add_child(point_panel)
		point_list.enable_drop_forwarding(point_panel)

	# Add Point button
	if curve.curve_mode == curve.CurveMode.BEZIER:
		var add_point_btn := Button.new()
		add_point_btn.icon = ADD
		add_point_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_point_btn.text = "Add Point"
		add_point_btn.pressed.connect(_on_add_point_btn_pressed)
		point_list.add_child(add_point_btn)

	# Add a gap below the Points contents.
	# point_list.add_spacer(true)

	return point_list


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

		# Restore last UI state
		if object._last_zoom:
			easing_curve_editor.set_zoom(object._last_zoom)
		if object._last_pan:
			easing_curve_editor.set_pan(object._last_pan)

		# Connect curve editor signals
		easing_curve_editor.slider_changed.connect(object._on_curve_editor_slider_value_changed)
		easing_curve_editor.zoom_changed.connect(object._on_curve_editor_zoom_changed)
		easing_curve_editor.pan_changed.connect(object._on_curve_editor_pan_changed)
		easing_curve_editor.point_changed.connect(_on_curve_editor_point_changed)
		easing_curve_editor.point_property_change_requested.connect(_on_curve_editor_point_property_change_requested)
		easing_curve_editor.point_add_requested.connect(_on_curve_editor_point_add_requested)
		easing_curve_editor.point_remove_requested.connect(_on_curve_editor_point_remove_requested)
		easing_curve_editor.point_edit_finished.connect(_on_curve_editor_point_edit_finished)

		# Store reference to curve resource
		curve = object
		_point_edit_before_state = {}
		_point_edit_action_name = "Edit Easing Curve Point"
		# print("curve.ease_type = ", curve.EASE.keys()[curve.ease_type])
		# print("curve.trans_type = ", curve.TRANS.keys()[curve.trans_type])

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

		easing_curve_editor._slider = zoom_slider_container
		easing_curve_editor.set_slider_value(object._last_slider_value)


		var curve_editor_section := _create_foldable_section(
			"Curve Editor",
			curve_editor_content,
			object,
		)
		curve_section.add_child(curve_editor_section)
		########################################
		return curve_section
	return null


func print_properties(object, type, name, hint_type, hint_string, usage_flags, wide):
	print("=============================")
	print("object: ", object)
	print("type: ", type)
	print("name: ", name)
	print("hint_type: ", hint_type)
	print("hint_string: ", hint_string)
	print("usage_flags: ", usage_flags)
	print("wide: ", wide)


func _can_handle(object):
	if object is EasingCurve and not _instantiating_default_property:
		return true
	else:
		return false


func _parse_property(object, type, name, hint_type, hint_string, usage_flags, wide):
	# print_properties(object, type, name, hint_type, hint_string, usage_flags, wide)
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
	if object is EasingCurve and name == "generate_tool_button":
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


#func _update_reset_btn(reset_btn: Button, value: float, default: float) -> void:
	#reset_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	#reset_btn.visible = !is_equal_approx(value, default)
func _update_point_reset_btn(
	reset_btn: Button,
	i: int,
	property_name: StringName,
) -> void:
	if i < 0 or i >= curve.points.size():
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
		i: int,
		point: EasingCurvePoint,
		_default: Vector2,
		x_input: EditorSpinSlider,
		y_input: EditorSpinSlider,
		property_name: String,
		reset_btn: Button,
) -> void:
	i = _get_current_point_index(point)
	if i == -1:
		return
	_preserve_point_selection_on_refresh = true
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


func _on_remove_btn_pressed(_point_list: VBoxContainer, _i: int, _point_panel: PanelContainer, p: EasingCurvePoint) -> void:
	_remove_point(p)


func _on_x_input_value_changed(value: float, i: int, point: EasingCurvePoint, x_input: EditorSpinSlider, reset_btn: Button, default: float, property_name: String) -> void:
	# print("p%d x: %.3f" % [i, value])
	i = _get_current_point_index(point)
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


func _on_y_input_value_changed(value: float, i: int, point: EasingCurvePoint, y_input: EditorSpinSlider, reset_btn: Button, default: float, property_name: String) -> void:
	# print("p%d y: %.3f" % [i, value])
	i = _get_current_point_index(point)
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
	if property_name not in ["left_control_point", "right_control_point"]:
		return true
	var side := (
		EasingCurvePoint.ControlSide.LEFT
		if property_name == "left_control_point"
		else EasingCurvePoint.ControlSide.RIGHT
	)
	return point.is_control_position_editable(side)


func _move_point_up(i: int) -> void:
	var point_count := curve.points.size()
	if point_count < 2:
		return

	_move_point(
		i,
		wrapi(i - 1, 0, point_count),
	)


func _move_point_down(i: int) -> void:
	var point_count := curve.points.size()
	if point_count < 2:
		return

	_move_point(
		i,
		wrapi(i + 1, 0, point_count),
	)


func _move_point(from_index: int, to_index: int) -> void:
	if (
		from_index == to_index
		or from_index < 0
		or to_index < 0
		or from_index >= curve.points.size()
		or to_index >= curve.points.size()
	):
		return
	var moved_point := curve.points[from_index]
	EASING_CURVE_EDITOR_UNDO.apply_action(
		editor_undo_redo,
		curve,
		"Reorder Easing Curve Points",
		func():
			curve.swap_points(from_index, to_index)
			_select_reordered_point(moved_point),
		_undo_source_property(),
	)


func _select_reordered_point(point: EasingCurvePoint) -> void:
	var point_index := _get_current_point_index(point)
	if point_index == -1:
		return
	_preserve_point_selection_on_refresh = true
	_selected_point_index = point_index
	_selected_point_resource_id = point.get_instance_id()
	if easing_curve_editor != null:
		easing_curve_editor.select_point(point)


# remember bind() arguments are at the end
func _create_point_side_vbox(i: int, point_list: VBoxContainer, point_panel: PanelContainer, point: EasingCurvePoint) -> VBoxContainer:
	var side_vbox = VBoxContainer.new()
	side_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# side_vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Move Up Button
	var move_up_btn = Button.new()
	move_up_btn.icon = MOVE_UP
	move_up_btn.flat = true
	move_up_btn.tooltip_text = "Move Point Up"
	move_up_btn.pressed.connect(_move_point_up.bind(i))
	side_vbox.add_child(move_up_btn)

	# TripleBar TextureRect (drag handle)
	var triple_bar = EasingCurveDragHandle.new()
	triple_bar.texture = TRIPLE_BAR
	triple_bar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	triple_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	triple_bar.set_focus_mode(Control.FOCUS_ALL)

	triple_bar.index = i
	triple_bar.point_panel = point_panel
	triple_bar.point_list = point_list
	triple_bar.curve = curve
	triple_bar.easing_curve_editor = easing_curve_editor

	side_vbox.add_child(triple_bar)

	# Move Down Button
	var move_down_btn = Button.new()
	move_down_btn.icon = MOVE_DOWN
	move_down_btn.flat = true
	move_down_btn.tooltip_text = "Move Point Down"
	move_down_btn.pressed.connect(_move_point_down.bind(i))
	side_vbox.add_child(move_down_btn)

	return side_vbox


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

	var editor_theme := EditorInterface.get_editor_theme()
	reset_btn.icon = editor_theme.get_icon(
		&"Reload",
		&"EditorIcons",
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

	_selected_point_property_header = property_header
	_selected_point_index = point_index
	_selected_point_property_name = property_name
	_selected_point_resource_id = (
		curve.points[point_index].get_instance_id()
		if point_index >= 0 and point_index < curve.points.size()
		else 0
	)

	_set_point_property_selected(property_header, true)


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
		easing_curve_editor._clear_position_x_order_preview()
	var point_index := point_order.find(point)
	if point_index == -1:
		return

	if defer_list_reorder:
		_position_x_order_preview_point = point
		easing_curve_editor._set_position_x_order_preview(point)
		return

	_selected_point_index = point_index
	_selected_point_resource_id = point.get_instance_id()
	easing_curve_editor.selected_index = point_index

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
		var base_control := EditorInterface.get_base_control()
		if is_instance_valid(base_control):
			accent = base_control.get_theme_color(&"accent_color", &"Editor")

	accent.a = 0.10
	style.bg_color = accent

	property_header.add_theme_stylebox_override(
		&"panel",
		style
	)


func _create_vector2_property(
	point: EasingCurvePoint,
	i: int,
	property_name: String,
	label_text: String,
	property_grid: GridContainer,
) -> void:
	var position := point.position
	var default_vec: Vector2 = curve.get_default_for_property(i, property_name)
	var current_vec: Vector2 = point.get(property_name)

	# Selectable property header and reset slot.
	var reset_btn := _create_point_reset_button()
	_set_point_reset_button_available(
		reset_btn,
		not current_vec.is_equal_approx(default_vec)
	)

	var property_header := _create_selectable_point_property_header(
		i,
		StringName(property_name),
		label_text,
		reset_btn,
	)
	property_header.size_flags_stretch_ratio = POINT_PROPERTY_HEADER_RATIO
	property_grid.add_child(property_header)

	# Value container panel (x/y inputs; lock_btn)
	var value_panel := PanelContainer.new()
	value_panel.add_theme_stylebox_override("panel", X_STYLEBOX)
	value_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_panel.size_flags_stretch_ratio = POINT_PROPERTY_VALUE_RATIO
	value_panel.custom_minimum_size.x = 0.0
	value_panel.z_index = 1
	property_grid.add_child(value_panel)

	# HBox for x/y inputs; lock_btn
	var value_hbox := HBoxContainer.new()
	value_hbox.add_theme_constant_override("separation", _compact_separation())
	value_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_panel.add_child(value_hbox)

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


	##############################################
	# Force Linear button (control handles only)
	var force_linear_btn := Button.new()
	force_linear_btn.flat = true
	force_linear_btn.toggle_mode = true
	force_linear_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if property_name in ["left_control_point", "right_control_point"]:

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

		var editor_theme := EditorInterface.get_editor_theme()
		var anchor_icon := editor_theme.get_icon(
			&"Anchor",
			&"EditorIcons",
		)

		force_linear_btn.icon = (
			FORCE_LINEAR_ICON_ON
			if force_linear
			else FORCE_LINEAR_ICON_OFF
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

		if not force_linear_available:
			force_linear_btn.modulate.a = 0.25
		else:
			force_linear_btn.modulate.a = 1.0

		force_linear_btn.toggled.connect(
			func(toggled_on: bool):

				force_linear_btn.icon = (
					FORCE_LINEAR_ICON_ON
					if toggled_on
					else FORCE_LINEAR_ICON_OFF
				)

				force_linear_btn.modulate.a = 1.0

				_apply_point_property_change(
					i,
					force_property,
					toggled_on,
				)

				easing_curve_editor.queue_redraw()
		)

	else:
		force_linear_btn.modulate.a = 0.0
		force_linear_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		force_linear_btn.focus_mode = Control.FOCUS_NONE

	#value_hbox.add_child(force_linear_btn)
	force_linear_slot.add_child(force_linear_btn)

	##############################################


	# Right side (lock button)
	var lock_btn := Button.new()
	lock_btn.icon = LOCK
	lock_btn.flat = true
	lock_btn.toggle_mode = true
	lock_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lock_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var pressed_color := Color.WHITE
	lock_btn.add_theme_color_override("icon_pressed_color", pressed_color)
	lock_btn.add_theme_color_override("icon_hover_pressed_color", pressed_color)

	var locked := point.locked[property_name]
	lock_btn.button_pressed = locked
	var toggled_on := lock_btn.button_pressed

	var lock_available := (
		property_name == "position"
		or point.supports_control_state()
	)

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

	lock_btn.icon = LOCK if toggled_on else UNLOCK

	if not lock_available:
		lock_btn.modulate.a = 0.25
	else:
		lock_btn.modulate.a = 1.0 if toggled_on else 0.5

	lock_btn.toggled.connect(
		func(toggled_on: bool):
			_preserve_point_selection_on_refresh = true
			_select_point_property(
				property_header,
				i,
				StringName(property_name)
			)

			lock_btn.icon = LOCK if toggled_on else UNLOCK
			lock_btn.modulate.a = 1.0 if toggled_on else 0.5

			var locks: Dictionary = curve.points[i].locked.duplicate()

			if (
				point.handle_mode == EasingCurvePoint.HandleMode.LINKED
				and property_name in [
					"left_control_point",
					"right_control_point",
				]
			):
				locks["left_control_point"] = toggled_on
				locks["right_control_point"] = toggled_on
			else:
				locks[property_name] = toggled_on

			_apply_point_property_change(i, &"locked", locks)
	)

	value_hbox.add_child(lock_btn)

	var vec: Vector2 = point.get(property_name)

	var x_color := EditorInterface.get_editor_theme().get_color("property_color_x", "Editor")
	var y_color := EditorInterface.get_editor_theme().get_color("property_color_y", "Editor")

	# X
	var x_row := HBoxContainer.new()
	x_row.add_theme_constant_override("separation", -8)

	var x_label := Label.new()
	x_label.text = "x"
	x_label.add_theme_color_override("font_color", x_color)

	if property_name == "position":
		x_input.min_value = 0.0
		x_input.max_value = 1.0
	else:
		x_input.min_value = -1024
		x_input.max_value = 1024
	x_input.step = SLIDER_INPUT_STEP
	x_input.flat = true
	x_input.hide_slider = true
	x_input.label = ""
	x_input.value = vec.x
	x_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	x_input.custom_minimum_size.x = 0.0

	x_input.value_changed.connect(_on_x_input_value_changed.bind(i, point, x_input, reset_btn, default_vec.x, property_name))
	_connect_point_input_drag_signals(x_input)
	if property_name == "position":
		x_input.value_focus_entered.connect(
			_on_position_x_input_focus_entered.bind(x_input)
		)
		x_input.value_focus_exited.connect(
			_on_position_x_input_focus_exited.bind(x_input)
		)
	elif property_name in ["left_control_point", "right_control_point"]:
		x_input.value_focus_entered.connect(
			_on_linear_control_x_input_focus_entered.bind(x_input, point)
		)
		x_input.value_focus_exited.connect(
			_on_linear_control_x_input_focus_exited.bind(x_input, point)
		)
	x_input.grabbed.connect(_select_point_property_for_point.bind(property_header, point, StringName(property_name)))
	x_input.focus_entered.connect(_select_point_property_for_point.bind(property_header, point, StringName(property_name)))
	point.set_input_control(property_name, "x", x_input)

	x_row.add_child(x_label)
	x_row.add_child(x_input)
	value_vbox.add_child(x_row)

	# Y
	var y_row := HBoxContainer.new()
	y_row.add_theme_constant_override("separation", -8)

	var y_label := Label.new()
	y_label.text = "y"
	y_label.add_theme_color_override("font_color", y_color)

	if property_name == "position":
		y_input.min_value = 0.0
		y_input.max_value = 1.0
	else:
		y_input.min_value = -1024
		y_input.max_value = 1024
	y_input.step = SLIDER_INPUT_STEP
	y_input.flat = true
	y_input.hide_slider = true
	y_input.label = ""
	y_input.value = vec.y
	y_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	y_input.custom_minimum_size.x = 0.0

	y_input.value_changed.connect(_on_y_input_value_changed.bind(i, point, y_input, reset_btn, default_vec.y, property_name))
	_connect_point_input_drag_signals(y_input)
	y_input.grabbed.connect(_select_point_property_for_point.bind(property_header, point, StringName(property_name)))
	y_input.focus_entered.connect(_select_point_property_for_point.bind(property_header, point, StringName(property_name)))
	point.set_input_control(property_name, "y", y_input)

	reset_btn.pressed.connect(_on_reset_btn_pressed.bind(i, point, position, x_input, y_input, property_name, reset_btn))
	reset_btn.pressed.connect(_select_point_property_for_point.bind(property_header, point, StringName(property_name)))

	y_row.add_child(y_label)
	y_row.add_child(y_input)
	value_vbox.add_child(y_row)

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
	_preserve_point_selection_on_refresh = true
	var added_point := _add_point(point)
	_select_reordered_point(added_point)


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
		if _selected_point_index >= 0:
			_copy_point_property_value(
				_selected_point_index,
				_selected_point_property_name
			)

	section.paste_value_callback = func():
		if _selected_point_index >= 0:
			_paste_point_property_value(
				_selected_point_index,
				_selected_point_property_name
			)

	section.copy_path_callback = func():
		if _selected_point_index >= 0:
			_copy_point_property_path(
				_selected_point_index,
				_selected_point_property_name
			)

	section.can_paste_callback = func():
		return (
			_selected_point_index >= 0
			and _clipboard_has_compatible_point_property_value(
				_selected_point_property_name,
			)
		)

	section.setup(title, content, curve)
	return section


func _on_curve_editor_point_changed(_i: int, _new_point: EasingCurvePoint) -> void:
	easing_curve_editor.queue_redraw()


func _on_curve_editor_point_property_change_requested(i: int, property_name: StringName, value: Variant, changing: bool) -> void:
	_apply_point_property_change(i, property_name, value, changing)


func _on_curve_editor_point_edit_finished(point_order: Array[EasingCurvePoint]) -> void:
	_commit_point_edit(point_order)


func _commit_point_edit(point_order: Array[EasingCurvePoint] = []) -> void:
	_commit_position_x_order_preview()
	if _point_edit_before_state.is_empty():
		return
	var before := _point_edit_before_state
	var action_name := _point_edit_action_name
	_point_edit_before_state = {}
	_point_edit_action_name = "Edit Easing Curve Point"
	if not point_order.is_empty() and curve.points != point_order:
		curve.points = point_order
	var after := EASING_CURVE_EDITOR_UNDO.capture_state(curve)
	# Flush the draft point notifications once at the drag boundary.
	curve.set_point_snapshot(curve.get_point_snapshot())
	EASING_CURVE_EDITOR_UNDO.commit_applied_action(
		editor_undo_redo,
		curve,
		action_name,
		before,
		after,
		_undo_source_property(),
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
	_add_point(point)


func _on_curve_editor_point_remove_requested(point: EasingCurvePoint) -> void:
	_remove_point(point)


func _create_handle_mode_property(
	point: EasingCurvePoint,
	i: int,
	property_grid: GridContainer,
) -> void:

	var reset_btn := _create_point_reset_button()
	_set_point_reset_button_available(
		reset_btn,
		point.handle_mode != EasingCurvePoint.HandleMode.FREE,
	)
	var property_header := _create_selectable_point_property_header(
		i,
		&"handle_mode",
		"Handle Mode",
		reset_btn,
	)
	property_header.size_flags_stretch_ratio = POINT_PROPERTY_HEADER_RATIO
	property_grid.add_child(property_header)

	var value_panel := PanelContainer.new()
	value_panel.add_theme_stylebox_override(&"panel", X_STYLEBOX)
	value_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_panel.size_flags_stretch_ratio = POINT_PROPERTY_VALUE_RATIO
	value_panel.custom_minimum_size.x = 0.0
	value_panel.z_index = 1
	property_grid.add_child(value_panel)

	var option := OptionButton.new()
	_configure_compact_option(option)
	option.custom_minimum_size.x = 0.0
	value_panel.add_child(option)

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
	if point.handle_mode == EasingCurvePoint.HandleMode.FREE:
		_set_point_reset_button_available(reset_btn, false)
		return
	option.select(option.get_item_index(EasingCurvePoint.HandleMode.FREE))
	_apply_point_property_change(
		i,
		&"handle_mode",
		EasingCurvePoint.HandleMode.FREE,
	)
	_set_point_reset_button_available(reset_btn, false)


func _set_snapshot_handle_mode(
	snapshot: Dictionary,
	i: int,
	new_mode: int,
) -> void:
	var point := curve.points[i]
	var handles := point.get_handles_for_mode_change(new_mode)

	if new_mode == EasingCurvePoint.HandleMode.LINKED:
		var locks: Array = snapshot["locks"]
		var point_locks: Dictionary = locks[i].duplicate(true)
		var left_force_linear: PackedByteArray = snapshot[
			"left_force_linear"
		]
		var right_force_linear: PackedByteArray = snapshot[
			"right_force_linear"
		]

		var shared_locked := (
			bool(point_locks.get("left_control_point", false))
			or bool(point_locks.get("right_control_point", false))
		)
		var shared_force_linear := (
			bool(left_force_linear[i])
			or bool(right_force_linear[i])
		)

		point_locks["left_control_point"] = shared_locked
		point_locks["right_control_point"] = shared_locked
		left_force_linear[i] = int(shared_force_linear)
		right_force_linear[i] = int(shared_force_linear)

		locks[i] = point_locks
		snapshot["locks"] = locks
		snapshot["left_force_linear"] = left_force_linear
		snapshot["right_force_linear"] = right_force_linear
		if shared_force_linear:
			handles["left"] = point.position
			handles["right"] = point.position

	if new_mode == EasingCurvePoint.HandleMode.FREE:
		var left_force_linear: PackedByteArray = snapshot[
			"left_force_linear"
		]
		var right_force_linear: PackedByteArray = snapshot[
			"right_force_linear"
		]

		if bool(left_force_linear[i]):
			handles["left"] = point.position

		if bool(right_force_linear[i]):
			handles["right"] = point.position

	var handle_modes: PackedInt32Array = snapshot["handle_modes"]
	var left_control_points: PackedVector2Array = snapshot[
		"left_control_points"
	]
	var right_control_points: PackedVector2Array = snapshot[
		"right_control_points"
	]

	handle_modes[i] = new_mode
	left_control_points[i] = handles["left"]
	right_control_points[i] = handles["right"]

	snapshot["handle_modes"] = handle_modes
	snapshot["left_control_points"] = left_control_points
	snapshot["right_control_points"] = right_control_points


func _set_snapshot_control_state(
	snapshot: Dictionary,
	i: int,
	side: EasingCurvePoint.ControlSide,
	control_state: int,
) -> void:
	var point := curve.points[i]
	var handle_modes: PackedInt32Array = snapshot["handle_modes"]
	var linked := handle_modes[i] == EasingCurvePoint.HandleMode.LINKED
	var sides: Array[EasingCurvePoint.ControlSide] = [side]
	if linked:
		sides = [
			EasingCurvePoint.ControlSide.LEFT,
			EasingCurvePoint.ControlSide.RIGHT,
		]

	var locks: Array = snapshot["locks"]
	var point_locks: Dictionary = locks[i].duplicate(true)
	var left_force_linear: PackedByteArray = snapshot[
		"left_force_linear"
	]
	var right_force_linear: PackedByteArray = snapshot[
		"right_force_linear"
	]
	var left_control_points: PackedVector2Array = snapshot[
		"left_control_points"
	]
	var right_control_points: PackedVector2Array = snapshot[
		"right_control_points"
	]
	var had_force_linear := (
		bool(left_force_linear[i])
		if linked
		else (
			bool(left_force_linear[i])
			if side == EasingCurvePoint.ControlSide.LEFT
			else bool(right_force_linear[i])
		)
	)

	for control_side in sides:
		var force_property := (
			&"left_force_linear"
			if control_side == EasingCurvePoint.ControlSide.LEFT
			else &"right_force_linear"
		)
		var lock_property := (
			&"left_control_point"
			if control_side == EasingCurvePoint.ControlSide.LEFT
			else &"right_control_point"
		)
		var offset := (
			Vector2.LEFT
			if control_side == EasingCurvePoint.ControlSide.LEFT
			else Vector2.RIGHT
		)

		if force_property == &"left_force_linear":
			left_force_linear[i] = int(
				control_state == EasingCurvePoint.ControlState.LINEAR
			)
		else:
			right_force_linear[i] = int(
				control_state == EasingCurvePoint.ControlState.LINEAR
			)

		point_locks[lock_property] = (
			control_state == EasingCurvePoint.ControlState.LOCKED
		)

		if control_state == EasingCurvePoint.ControlState.LINEAR:
			if control_side == EasingCurvePoint.ControlSide.LEFT:
				left_control_points[i] = point.position
			else:
				right_control_points[i] = point.position
		elif had_force_linear:
			if control_side == EasingCurvePoint.ControlSide.LEFT:
				left_control_points[i] = (
					point.position
					+ offset * EasingCurvePoint.DEFAULT_HANDLE_LENGTH
				)
			else:
				right_control_points[i] = (
					point.position
					+ offset * EasingCurvePoint.DEFAULT_HANDLE_LENGTH
				)

	if linked and control_state != EasingCurvePoint.ControlState.LINEAR and had_force_linear:
		var linked_default := (
			point.position
			+ Vector2.RIGHT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH
		)
		left_control_points[i] = linked_default
		right_control_points[i] = linked_default

	locks[i] = point_locks
	snapshot["locks"] = locks
	snapshot["left_force_linear"] = left_force_linear
	snapshot["right_force_linear"] = right_force_linear
	snapshot["left_control_points"] = left_control_points
	snapshot["right_control_points"] = right_control_points


func _apply_point_property_change(
	i: int,
	property_name: StringName,
	value: Variant,
	changing: bool = false,
	position_reorder_point: EasingCurvePoint = null,
) -> void:
	if i < 0 or i >= curve.points.size():
		return
	_preserve_point_selection_on_refresh = true
	var before := EASING_CURVE_EDITOR_UNDO.capture_state(curve)
	if changing and _point_edit_before_state.is_empty():
		_point_edit_before_state = before
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
			_set_snapshot_handle_mode(snapshot, i, int(value))


		&"left_control_state", &"right_control_state":
			var point := curve.points[i]
			if not point.supports_control_state():
				return

			var side := (
				EasingCurvePoint.ControlSide.LEFT
				if property_name == &"left_control_state"
				else EasingCurvePoint.ControlSide.RIGHT
			)
			var control_state := int(value)
			if control_state not in [
				EasingCurvePoint.ControlState.FREE,
				EasingCurvePoint.ControlState.LINEAR,
				EasingCurvePoint.ControlState.LOCKED,
			]:
				return

			_set_snapshot_control_state(snapshot, i, side, control_state)


		&"toolbar_options_reset":
			_set_snapshot_handle_mode(
				snapshot,
				i,
				EasingCurvePoint.HandleMode.FREE,
			)
			_set_snapshot_control_state(
				snapshot,
				i,
				EasingCurvePoint.ControlSide.LEFT,
				EasingCurvePoint.ControlState.FREE,
			)
			_set_snapshot_control_state(
				snapshot,
				i,
				EasingCurvePoint.ControlSide.RIGHT,
				EasingCurvePoint.ControlState.FREE,
			)


		&"left_force_linear", &"right_force_linear":
			var point := curve.points[i]
			var linked := point.handle_mode == EasingCurvePoint.HandleMode.LINKED
			var force_values: PackedByteArray = snapshot[property_name]
			force_values[i] = int(value)
			snapshot[property_name] = force_values

			var control_property := (
				&"left_control_points"
				if property_name == &"left_force_linear"
				else &"right_control_points"
			)

			var lock_property := (
				&"left_control_point"
				if property_name == &"left_force_linear"
				else &"right_control_point"
			)

			var offset := (
				Vector2.LEFT
				if property_name == &"left_force_linear"
				else Vector2.RIGHT
			)

			var control_points: PackedVector2Array = snapshot[
				control_property
			]

			if linked:
				var left_force_linear: PackedByteArray = snapshot[
					"left_force_linear"
				]
				var right_force_linear: PackedByteArray = snapshot[
					"right_force_linear"
				]
				var left_control_points: PackedVector2Array = snapshot[
					"left_control_points"
				]
				var right_control_points: PackedVector2Array = snapshot[
					"right_control_points"
				]

				left_force_linear[i] = int(value)
				right_force_linear[i] = int(value)
				if value:
					var locks: Array = snapshot["locks"]
					var point_locks: Dictionary = locks[i].duplicate(true)
					point_locks["left_control_point"] = false
					point_locks["right_control_point"] = false
					locks[i] = point_locks
					snapshot["locks"] = locks
					left_control_points[i] = point.position
					right_control_points[i] = point.position
				else:
					var linked_default := (
						point.position
						+ Vector2.RIGHT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH
					)
					left_control_points[i] = linked_default
					right_control_points[i] = linked_default

				snapshot["left_force_linear"] = left_force_linear
				snapshot["right_force_linear"] = right_force_linear
				snapshot["left_control_points"] = left_control_points
				snapshot["right_control_points"] = right_control_points

			elif value:
				# Force Linear wins over Lock.
				var locks: Array = snapshot["locks"]
				var point_locks: Dictionary = locks[i].duplicate(true)
				point_locks[lock_property] = false
				locks[i] = point_locks
				snapshot["locks"] = locks

				control_points[i] = curve.points[i].position

			else:
				control_points[i] = (
					curve.points[i].position
					+ offset * EasingCurvePoint.DEFAULT_HANDLE_LENGTH
				)

			if not linked:
				snapshot[control_property] = control_points


		&"locked":
			var point := curve.points[i]
			var locks: Array = snapshot["locks"]
			var previous_locks: Dictionary = locks[i]
			var new_locks: Dictionary = value.duplicate(true)
			var linked_force_linear_cleared := false

			for control_property in [
				&"left_control_point",
				&"right_control_point",
			]:
				var was_locked := bool(
					previous_locks.get(control_property, false)
				)
				var is_locked := bool(
					new_locks.get(control_property, false)
				)

				# Only react when this handle is being locked.
				if was_locked or not is_locked:
					continue

				var force_property := (
					&"left_force_linear"
					if control_property == &"left_control_point"
					else &"right_force_linear"
				)

				var force_values: PackedByteArray = snapshot[
					force_property
				]

				if not bool(force_values[i]):
					continue

				# Lock wins over Force Linear.
				force_values[i] = 0
				snapshot[force_property] = force_values
				linked_force_linear_cleared = (
					point.handle_mode == EasingCurvePoint.HandleMode.LINKED
				)

				# Create default 0.1 handle
				var control_array_name := (
					&"left_control_points"
					if control_property == &"left_control_point"
					else &"right_control_points"
				)

				var offset := (
					Vector2.LEFT
					if control_property == &"left_control_point"
					else Vector2.RIGHT
				)

				var control_points: PackedVector2Array = snapshot[
					control_array_name
				]

				# Leaving Force Linear restores the default handle
				# before locking it.
				control_points[i] = (
					curve.points[i].position
					+ offset * EasingCurvePoint.DEFAULT_HANDLE_LENGTH
				)

				snapshot[control_array_name] = control_points

			locks[i] = new_locks
			snapshot["locks"] = locks

			if linked_force_linear_cleared:
				var linked_default := (
					point.position
					+ Vector2.RIGHT * EasingCurvePoint.DEFAULT_HANDLE_LENGTH
				)
				var left_control_points: PackedVector2Array = snapshot[
					"left_control_points"
				]
				var right_control_points: PackedVector2Array = snapshot[
					"right_control_points"
				]
				left_control_points[i] = linked_default
				right_control_points[i] = linked_default
				snapshot["left_control_points"] = left_control_points
				snapshot["right_control_points"] = right_control_points

		_:
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
		EASING_CURVE_EDITOR_UNDO.commit_applied_action(
			editor_undo_redo,
			curve,
			_point_action_name(property_name),
			before,
			{},
			_undo_source_property(),
		)


func _point_action_name(property_name: StringName) -> String:
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
		&"locked":
			return "Change Easing Curve Point Lock"
		&"left_force_linear", &"right_force_linear":
			return "Change Easing Curve Handle Force Linear State"
	return "Edit Easing Curve Point"


func _add_point(point: EasingCurvePoint) -> EasingCurvePoint:
	var before := EASING_CURVE_EDITOR_UNDO.capture_state(curve)
	var updated_points: Array[EasingCurvePoint] = curve.points.duplicate()
	updated_points.append(point)
	updated_points = EasingCurve.build_ordered_points_with_endpoint_takeover(
		updated_points,
		point,
	)
	var added_point_index := updated_points.find(point)
	curve.set_point_snapshot(curve.make_point_snapshot(updated_points))
	EASING_CURVE_EDITOR_UNDO.commit_applied_action(
		editor_undo_redo,
		curve,
		"Add Easing Curve Point",
		before,
		{},
		_undo_source_property(),
	)
	return curve.points[added_point_index]


func _remove_point(point: EasingCurvePoint) -> void:
	var before := EASING_CURVE_EDITOR_UNDO.capture_state(curve)
	var updated_points: Array[EasingCurvePoint] = curve.points.duplicate()
	var point_index := updated_points.find(point)
	if point_index == -1:
		return
	updated_points.remove_at(point_index)
	curve.set_point_snapshot(curve.make_point_snapshot(updated_points))
	EASING_CURVE_EDITOR_UNDO.commit_applied_action(
		editor_undo_redo,
		curve,
		"Remove Easing Curve Point",
		before,
		{},
		_undo_source_property(),
	)


func _emit_curve_property(property_name: StringName, value: Variant) -> void:
	if (
		property_name == &"ease_type"
		and curve.curve_mode == EasingCurve.CurveMode.BEZIER
		and curve.is_selected_preset_modified()
	):
		return
	var before := EASING_CURVE_EDITOR_UNDO.capture_state(curve)
	curve.set(property_name, value)
	var action_name := "Change Easing Curve Ease" if property_name == &"ease_type" else "Change Easing Curve Transition"
	EASING_CURVE_EDITOR_UNDO.commit_applied_action(
		editor_undo_redo,
		curve,
		action_name,
		before,
		{},
		_undo_source_property(),
	)

func _on_reset_selected_preset(object: EasingCurve) -> void:
	if object == null:
		return
	var before := EASING_CURVE_EDITOR_UNDO.capture_state(object)
	if not object.reset_selected_preset():
		return
	EASING_CURVE_EDITOR_UNDO.commit_applied_action(
		editor_undo_redo,
		object,
		"Reset Easing Curve Preset",
		before,
		{},
		_undo_source_property(),
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
	return transition not in [
		EasingCurve.TRANS.CUSTOM,
		EasingCurve.TRANS.CONSTANT,
		EasingCurve.TRANS.LINEAR,
		EasingCurve.TRANS.STEP,
		EasingCurve.TRANS.CSS_LINEAR,
		EasingCurve.TRANS.CSS_CUBIC_BEZIER,
	]


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
	if is_instance_valid(points_editor_property):
		return points_editor_property
	if is_instance_valid(curve_editor_property):
		return curve_editor_property
	return null


static func _create_transition_option(
	selected_value: int,
) -> OptionButton:
	var option := OptionButton.new()
	_configure_compact_option(option)

	var popup := option.get_popup()

	for group in TRANSITION_GROUPS:
		popup.add_separator(group["name"])

		for transition in group["items"]:
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
	reset_button.icon = RELOAD
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

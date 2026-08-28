@tool
extends VBoxContainer

const EDITOR_THEME_CACHE = preload(
	"res://addons/easing_curve/inspector/editor_theme_cache.gd"
)

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
var _fallback_content: Control
var _fallback_folded := false
var normal_color := EDITOR_THEME_CACHE.get_color(
	&"font_color",
	&"Editor",
	Color(1.0, 1.0, 1.0, 0.7),
)
var hover_color := EDITOR_THEME_CACHE.get_color(
	&"font_hover_color",
	&"Editor",
	Color.WHITE,
)
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
		# Native focus makes the outer Inspector ScrollContainer follow focus,
		# which jumps the scroll position when this section is collapsed.
		_native_section.focus_mode = Control.FOCUS_NONE
		_native_section.set(&"title", section_title)
		_native_section.set(&"title_text_overrun_behavior", TextServer.OVERRUN_TRIM_ELLIPSIS)
		_native_section.set(&"folded", initially_folded)
		for style_name in [
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

func _toggle_fallback() -> void:
	_set_fallback_folded(not _fallback_folded)

func _set_fallback_folded(is_folded: bool) -> void:
	_fallback_folded = is_folded
	_fallback_content.visible = not is_folded
	_fallback_header.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_GUI_TREE_ARROW_RIGHT
		if is_folded
		else EDITOR_THEME_CACHE.ICON_GUI_TREE_ARROW_DOWN
	)
	_on_folding_changed(is_folded)

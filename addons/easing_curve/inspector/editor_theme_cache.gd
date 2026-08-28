@tool
extends RefCounted

const EDITOR_ICONS := &"EditorIcons"

const ICON_ADD := &"Add"
const ICON_ANIMATION_AUTO_FIT_BEZIER := &"AnimationAutoFitBezier"
const ICON_CALLABLE := &"Callable"
const ICON_GUI_TREE_ARROW_DOWN := &"GuiTreeArrowDown"
const ICON_GUI_TREE_ARROW_RIGHT := &"GuiTreeArrowRight"
const ICON_INSTANCE := &"Instance"
const ICON_LOCK := &"Lock"
const ICON_MOVE_DOWN := &"MoveDown"
const ICON_MOVE_UP := &"MoveUp"
const ICON_RELOAD := &"Reload"
const ICON_REMOVE := &"Remove"
const ICON_TRIPLE_BAR := &"TripleBar"
const ICON_UNLINKED := &"Unlinked"
const ICON_UNLOCK := &"Unlock"
const ICON_ZOOM := &"Zoom"

static var _editor_theme: Theme
static var _icons: Dictionary[StringName, Texture2D] = {}


static func get_theme() -> Theme:
	if _editor_theme == null:
		_editor_theme = EditorInterface.get_editor_theme()
	return _editor_theme


static func get_icon(icon_name: StringName) -> Texture2D:
	if _icons.has(icon_name):
		return _icons[icon_name]

	var editor_theme := get_theme()
	var icon: Texture2D = null
	if editor_theme != null and editor_theme.has_icon(icon_name, EDITOR_ICONS):
		icon = editor_theme.get_icon(icon_name, EDITOR_ICONS)

	_icons[icon_name] = icon
	return icon


static func make_zero_margin_panel_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	style.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_detail = 5
	return style

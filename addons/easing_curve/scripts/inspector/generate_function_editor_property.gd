@tool
extends EditorProperty


const EASING_CURVE_EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")
const EDITOR_THEME_CACHE = preload(
	"res://addons/easing_curve/scripts/inspector/editor_theme_cache.gd"
)


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
	button.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_CALLABLE
	)
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
	EASING_CURVE_EDITOR_UNDO.apply_parameter_action(
		undo_redo,
		object,
		"Generate Easing Curve",
		func(): object.generate_irregular(),
		self,
	)
	if is_instance_valid(curve_editor):
		curve_editor.queue_redraw()

@tool
extends EditorProperty


const EASING_CURVE_EDITOR_UNDO = preload("res://addons/easing_curve/scripts/editor/easing_curve_editor_undo.gd")
const EDITOR_THEME_CACHE = preload(
	"res://addons/easing_curve/scripts/editor/inspector/editor_theme_cache.gd"
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
	var object := get_edited_object() as Resource
	if object == null:
		return
	if object.get_class() == &"NativeEasingCurve":
		_generate_native_curve(object)
		return
	EASING_CURVE_EDITOR_UNDO.apply_parameter_action(
		undo_redo,
		object as EasingCurve,
		"Generate Easing Curve",
		func(): object.generate_irregular(),
		self,
	)
	if is_instance_valid(curve_editor):
		curve_editor.queue_redraw()


func _generate_native_curve(object: Resource) -> void:
	if (
		not object.has_method(&"generate_irregular")
		or not object.has_method(&"get_editor_state_snapshot")
	):
		return
	var before := (object.call(&"get_editor_state_snapshot") as Dictionary).duplicate(true)
	object.call(&"begin_parameter_edit")
	object.call(&"generate_irregular")
	var after := (object.call(&"get_editor_state_snapshot") as Dictionary).duplicate(true)
	if before == after:
		object.call(&"cancel_parameter_edit")
		return
	_commit_native_generate_action(object, before, after)
	object.call(&"finish_parameter_edit")
	if is_instance_valid(curve_editor):
		curve_editor.queue_redraw()
		if curve_editor.committed_change_publisher.is_valid():
			curve_editor.committed_change_publisher.call()


func _commit_native_generate_action(
	object: Resource,
	before: Dictionary,
	after: Dictionary,
) -> void:
	if undo_redo == null:
		return
	if undo_redo is EditorUndoRedoManager:
		undo_redo.create_action(
			"Generate Easing Curve",
			UndoRedo.MERGE_DISABLE,
			object,
		)
	else:
		undo_redo.create_action("Generate Easing Curve")
	undo_redo.add_do_property(object, &"_editor_state_snapshot", after)
	undo_redo.add_undo_property(object, &"_editor_state_snapshot", before)
	if undo_redo is EditorUndoRedoManager:
		undo_redo.add_do_method(object, &"_apply_live_editor_snapshot", after)
		undo_redo.add_undo_method(object, &"_apply_live_editor_snapshot", before)
	# Generate already applied the after state while parameter publication was muted.
	undo_redo.commit_action(false)

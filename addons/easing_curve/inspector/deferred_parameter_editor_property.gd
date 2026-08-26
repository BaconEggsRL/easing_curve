@tool
extends EditorProperty


const EASING_CURVE_EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")
const DRAGGING_META := &"_easing_curve_dragging"


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
	if object == null or not EasingCurve.has_parameter_default(property_name):
		return

	var default_value := EasingCurve.get_parameter_default(property_name)
	_commit_value(
		object,
		default_value,
		"Reset Easing Curve %s" % String(property_name).capitalize(),
	)

	input.set_value_no_signal(float(default_value))
	_update_reset_button(default_value)
	_queue_curve_redraw()


func _update_reset_button(value: Variant) -> void:
	if reset_button == null or not EasingCurve.has_parameter_default(property_name):
		return
	var default_value: Variant = EasingCurve.get_parameter_default(property_name)
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


func _commit_value(object: EasingCurve, value: Variant, action_name := "") -> void:
	if action_name.is_empty():
		action_name = "Change Easing Curve %s" % String(property_name).capitalize()

	EASING_CURVE_EDITOR_UNDO.apply_parameter_action(
		undo_redo,
		object,
		action_name,
		func(): object.set(property_name, value),
		self,
	)


func _queue_curve_redraw() -> void:
	if is_instance_valid(curve_editor):
		curve_editor.queue_redraw()

@tool
extends EditorProperty


const EASING_CURVE_EDITOR_UNDO = preload("res://addons/easing_curve/scripts/editor/easing_curve_editor_undo.gd")
const DRAGGING_META := &"_easing_curve_dragging"


var input: EditorSpinSlider
var property_name: StringName
var curve_editor: EasingCurveEditor
var drag_original_snapshot: Dictionary
var drag_original_value: Variant
var undo_redo: Object


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
	var object := get_edited_object() as Resource
	if object != null and input != null:
		input.set_value_no_signal(float(object.get(property_name)))


func _on_grabbed() -> void:
	if input.has_meta(DRAGGING_META):
		return
	var object := get_edited_object() as Resource
	if object == null:
		return
	input.set_meta(DRAGGING_META, true)
	if _is_native_curve(object):
		drag_original_value = object.get(property_name)
		object.call(&"begin_parameter_edit")
	else:
		drag_original_snapshot = EASING_CURVE_EDITOR_UNDO.capture_state(object as EasingCurve)
		(object as EasingCurve)._begin_editor_parameter_edit()


func _on_ungrabbed() -> void:
	_commit_drag.call_deferred()


func _on_value_focus_entered() -> void:
	if not input.has_meta(DRAGGING_META):
		return
	_commit_drag()


func _on_value_changed(value: float) -> void:
	var object := get_edited_object() as Resource
	if object == null:
		return
	var property_value: Variant = int(value) if object.get(property_name) is int else value
	if input.has_meta(DRAGGING_META):
		object.set(property_name, property_value)
	elif _is_native_curve(object):
		emit_changed(property_name, property_value)
	else:
		_commit_value(object as EasingCurve, property_value)
	_queue_curve_redraw()


func _on_tree_exiting() -> void:
	_commit_drag()


func _commit_drag() -> void:
	if not input.has_meta(DRAGGING_META):
		return
	input.remove_meta(DRAGGING_META)
	var object := get_edited_object() as Resource
	if object == null:
		return
	if _is_native_curve(object):
		_commit_native_drag(object)
		_queue_curve_redraw()
		return

	var legacy_curve := object as EasingCurve
	var final_snapshot := EASING_CURVE_EDITOR_UNDO.capture_state(legacy_curve)
	if final_snapshot == drag_original_snapshot:
		legacy_curve._cancel_editor_parameter_edit()
	else:
		legacy_curve._finish_editor_parameter_edit()
		EASING_CURVE_EDITOR_UNDO.commit_applied_action(
			undo_redo,
			legacy_curve,
			"Change Easing Curve %s" % String(property_name).capitalize(),
			EasingCurveEditorUndo.ActionContext.new(
				drag_original_snapshot,
				final_snapshot,
			),
			self,
		)
	_queue_curve_redraw()


func _commit_native_drag(object: Resource) -> void:
	var final_value := object.get(property_name)
	# Restore before emitting the final EditorProperty change so Godot captures
	# the actual pre-drag value for Undo and live-debug publication.
	object.set(property_name, drag_original_value)
	object.call(&"cancel_parameter_edit")
	if final_value != drag_original_value:
		emit_changed(property_name, final_value)


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


func _is_native_curve(object: Resource) -> bool:
	return object != null and object.get_class() == &"NativeEasingCurve"

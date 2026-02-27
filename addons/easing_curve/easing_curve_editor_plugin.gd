@tool
extends EditorPlugin
## EasingCurve EditorPlugin
##
## Main script for the EasingCurve plugin.
## Instantiates the EasingCurve EditorInspectorPlugin.
## Detects when an EasingCurve resource has been saved, and changes the trans_type to CUSTOM.
## This prevents _update_preset() from running when the resource is initialized; keeping the user's custom settings intact.

const EasingCurveEditorInspectorPlugin = preload("uid://bqic40cwwnu7l")

var easing_curve_editor_inspector_plugin
var editor_undo_redo: EditorUndoRedoManager = get_undo_redo()


func _enter_tree() -> void:
	resource_saved.connect(_on_resource_saved)
	# Initialization of the plugin goes here.
	easing_curve_editor_inspector_plugin = EasingCurveEditorInspectorPlugin.new()
	if easing_curve_editor_inspector_plugin:
		easing_curve_editor_inspector_plugin.editor_undo_redo = editor_undo_redo
		add_inspector_plugin(easing_curve_editor_inspector_plugin)
	pass


func _exit_tree() -> void:
	resource_saved.disconnect(_on_resource_saved)
	# Clean-up of the plugin goes here.
	if easing_curve_editor_inspector_plugin:
		remove_inspector_plugin(easing_curve_editor_inspector_plugin)
	pass


func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _on_resource_saved(resource: Resource) -> void:
	if resource is not EasingCurve:
		return
	if resource.trans_type != EasingCurve.TRANS.CUSTOM:
		resource.trans_type = EasingCurve.TRANS.CUSTOM
	print("EasingCurve saved: %s" % [resource])

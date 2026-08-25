@tool
class_name EasingCurveEditorHostTestHarness
extends RefCounted

const INSPECTOR_PLUGIN = preload("res://addons/easing_curve/easing_curve_editor_inspector_plugin.gd")


static func require_editor_host(test_name: String) -> bool:
	if Engine.is_editor_hint():
		return true
	push_error(
		"%s requires an Editor host. Run: godot --editor --headless --path . --script res://test/%s"
		% [test_name, test_name]
	)
	return false


static func require_inspector_host(test_name: String) -> bool:
	if not require_editor_host(test_name):
		return false
	var inspector := INSPECTOR_PLUGIN.new()
	if inspector is EditorInspectorPlugin:
		return true
	push_error("%s could not instantiate EasingCurveEditorInspectorPlugin" % test_name)
	return false


static func supports_native_layout_fixtures() -> bool:
	return DisplayServer.get_name() != "headless"


static func create_inspector_context(
	curve: EasingCurve,
	editor_size := Vector2(600.0, 300.0),
) -> Dictionary:
	var editor := EasingCurveEditor.new()
	editor.size = editor_size
	editor.set_curve(curve)
	var inspector := INSPECTOR_PLUGIN.new()
	if not inspector is EditorInspectorPlugin:
		push_error("Could not create EasingCurveEditorInspectorPlugin test context")
		editor.free()
		return {}
	inspector.set("curve", curve)
	inspector.set("easing_curve_editor", editor)
	return {"editor": editor, "inspector": inspector}

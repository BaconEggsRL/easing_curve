@tool
extends EditorInspectorPlugin
## Constructs one context per parse; rendered controls retain their own owner.

const Context := preload("res://addons/easing_curve/scripts/editor/inspector/inspector_curve_context.gd")
const BackendFactory := preload("res://addons/easing_curve/scripts/editor/backend/curve_editor_backend_factory.gd")

var editor_undo_redo: EditorUndoRedoManager
var _construction_context: InspectorCurveContext
var _instantiating_default_property := false
var _initial_autofit_resource_ids: Dictionary[int, bool] = {}
var _autofit_rebuild_resources: Dictionary[int, WeakRef] = {}
# Selection must outlive one Inspector parse/context because point edits can rebuild
# the Legacy Inspector. Context-local selection alone is lost during that rebuild.
var _legacy_selection_by_resource: Dictionary[int, Dictionary] = {}


func _can_handle(object: Object) -> bool:
	return not _instantiating_default_property and BackendFactory.create(object as Resource) != null


func _parse_begin(object: Object) -> void:
	_construction_context = Context.new()
	_construction_context.editor_undo_redo = editor_undo_redo
	_construction_context._initial_autofit_resource_ids = _initial_autofit_resource_ids
	_construction_context._autofit_rebuild_resources = _autofit_rebuild_resources
	_construction_context._legacy_selection_by_resource = _legacy_selection_by_resource
	_construction_context._parse_begin(object)


func _parse_property(object, type, name, hint_type, hint_string, usage_flags, wide):
	if _construction_context == null:
		return false
	_instantiating_default_property = true
	var handled: bool = _construction_context._parse_property(object, type, name, hint_type, hint_string, usage_flags, wide)
	_instantiating_default_property = false
	_flush_controls()
	return handled


func _parse_end(object: Object) -> void:
	if _construction_context != null:
		_construction_context._parse_end(object)
		_flush_controls()
	_construction_context = null


func _flush_controls() -> void:
	for registration: Dictionary in _construction_context.registrations:
		if registration.has("name"):
			add_property_editor(registration.name, registration.control, registration.end, registration.label)
		else:
			add_custom_control(registration.control)
	_construction_context.registrations.clear()

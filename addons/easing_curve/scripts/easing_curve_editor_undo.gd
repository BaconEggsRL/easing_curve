@tool
class_name EasingCurveEditorUndo
extends RefCounted
## Central editor-only Undo / Redo integration for EasingCurve mutations.


static func capture_state(curve: EasingCurve) -> Dictionary:
	return curve.get_editor_state_snapshot()


static func commit_applied_action(
		undo_redo: Object,
		curve: EasingCurve,
		action_name: String,
		before: Dictionary,
		after: Dictionary = {},
		source_property: EditorProperty = null,
		selection_restorer: Callable = Callable(),
		before_selection: Dictionary = {},
		after_selection: Dictionary = {},
) -> bool:
	if curve == null:
		return false
	if after.is_empty():
		after = capture_state(curve)
	if before == after:
		return false
	if undo_redo == null:
		return false

	undo_redo.create_action(action_name)
	undo_redo.add_do_property(
		curve,
		EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY,
		after.duplicate(true),
	)
	undo_redo.add_undo_property(
		curve,
		EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY,
		before.duplicate(true),
	)
	var inspector := _find_parent_inspector(source_property)
	if inspector != null and undo_redo is EditorUndoRedoManager:
		# Match native Inspector actions so live debugging receives the same complete
		# resource-free snapshot on the initial edit, Undo, and Redo.
		undo_redo.add_do_method(inspector, "_edit_request_change", curve, "")
		undo_redo.add_undo_method(inspector, "_edit_request_change", curve, "")
		undo_redo.add_do_method(
			inspector,
			"emit_signal",
			&"property_edited",
			String(EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY),
		)
		undo_redo.add_undo_method(
			inspector,
			"emit_signal",
			&"property_edited",
			String(EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY),
		)
	if selection_restorer.is_valid():
		if undo_redo is EditorUndoRedoManager:
			undo_redo.add_do_method(
				selection_restorer.get_object(),
				selection_restorer.get_method(),
				after_selection.duplicate(true),
			)
			undo_redo.add_undo_method(
				selection_restorer.get_object(),
				selection_restorer.get_method(),
				before_selection.duplicate(true),
			)
		else:
			undo_redo.add_do_method(
				selection_restorer.bind(after_selection.duplicate(true)),
			)
			undo_redo.add_undo_method(
				selection_restorer.bind(before_selection.duplicate(true)),
			)
	# The editor control already applied the resulting state for immediate feedback.
	undo_redo.commit_action(false)
	if inspector != null:
		inspector.call("_edit_request_change", curve, "")
		inspector.emit_signal(
			&"property_edited",
			String(EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY),
		)
	return true


static func apply_action(
		undo_redo: Object,
		curve: EasingCurve,
		action_name: String,
		mutation: Callable,
		source_property: EditorProperty = null,
) -> bool:
	if curve == null or not mutation.is_valid():
		return false
	var before := capture_state(curve)
	mutation.call()
	return commit_applied_action(undo_redo, curve, action_name, before, {}, source_property)


static func _find_parent_inspector(source_property: EditorProperty) -> EditorInspector:
	var current: Node = source_property
	while current != null:
		if current is EditorInspector:
			return current as EditorInspector
		current = current.get_parent()
	return null

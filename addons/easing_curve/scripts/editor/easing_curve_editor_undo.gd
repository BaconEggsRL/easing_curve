@tool
class_name EasingCurveEditorUndo
extends RefCounted
## Central editor-only Undo / Redo integration for EasingCurve mutations.


class ActionContext extends RefCounted:
	var before: Dictionary
	var after: Dictionary
	var selection_restorer := Callable()
	var before_selection: Dictionary = {}
	var after_selection: Dictionary = {}
	var before_point_resource_ids := PackedInt64Array()
	var after_point_resource_ids := PackedInt64Array()

	func _init(before_state: Dictionary, after_state: Dictionary = {}) -> void:
		before = before_state
		after = after_state

	func with_selection(
		restorer: Callable,
		before_state: Dictionary,
		after_state: Dictionary,
	) -> ActionContext:
		selection_restorer = restorer
		before_selection = before_state
		after_selection = after_state
		return self

	func with_point_resource_ids(
		before_ids: PackedInt64Array,
		after_ids: PackedInt64Array,
	) -> ActionContext:
		before_point_resource_ids = before_ids
		after_point_resource_ids = after_ids
		return self


static func capture_state(curve: EasingCurve) -> Dictionary:
	return curve.get_editor_state_snapshot()


static func commit_applied_action(
		undo_redo: Object,
		curve: EasingCurve,
		action_name: String,
		context: ActionContext,
		source_property: EditorProperty = null,
) -> bool:
	if curve == null or context == null:
		return false
	if context.after.is_empty():
		context.after = capture_state(curve)
	if context.before == context.after:
		return false
	if undo_redo == null:
		return false

	undo_redo.create_action(action_name)
	var restores_point_resource_order := (
		context.before_point_resource_ids.size() == curve.points.size()
		and context.after_point_resource_ids.size() == curve.points.size()
	)
	if restores_point_resource_order:
		if undo_redo is EditorUndoRedoManager:
			undo_redo.add_do_method(
				curve,
				"_set_editor_state_snapshot_with_point_resource_order",
				context.after.duplicate(true),
				context.after_point_resource_ids.duplicate(),
			)
			undo_redo.add_undo_method(
				curve,
				"_set_editor_state_snapshot_with_point_resource_order",
				context.before.duplicate(true),
				context.before_point_resource_ids.duplicate(),
			)
		else:
			undo_redo.add_do_method(
				Callable(
					curve,
					"_set_editor_state_snapshot_with_point_resource_order",
				).bind(
					context.after.duplicate(true),
					context.after_point_resource_ids.duplicate(),
				),
			)
			undo_redo.add_undo_method(
				Callable(
					curve,
					"_set_editor_state_snapshot_with_point_resource_order",
				).bind(
					context.before.duplicate(true),
					context.before_point_resource_ids.duplicate(),
				),
			)
	else:
		undo_redo.add_do_property(
			curve,
			EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY,
			context.after.duplicate(true),
		)
		undo_redo.add_undo_property(
			curve,
			EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY,
			context.before.duplicate(true),
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
	if context.selection_restorer.is_valid():
		if undo_redo is EditorUndoRedoManager:
			undo_redo.add_do_method(
				context.selection_restorer.get_object(),
				context.selection_restorer.get_method(),
				context.after_selection.duplicate(true),
			)
			undo_redo.add_undo_method(
				context.selection_restorer.get_object(),
				context.selection_restorer.get_method(),
				context.before_selection.duplicate(true),
			)
		else:
			undo_redo.add_do_method(
				context.selection_restorer.bind(context.after_selection.duplicate(true)),
			)
			undo_redo.add_undo_method(
				context.selection_restorer.bind(context.before_selection.duplicate(true)),
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
	return commit_applied_action(undo_redo, curve, action_name, ActionContext.new(before), source_property)


static func apply_parameter_action(
		undo_redo: Object,
		curve: EasingCurve,
		action_name: String,
		mutation: Callable,
		source_property: EditorProperty = null,
) -> bool:
	if curve == null or not mutation.is_valid():
		return false
	var before := capture_state(curve)
	curve._begin_editor_parameter_edit()
	mutation.call()
	var after := capture_state(curve)
	if before == after:
		curve._cancel_editor_parameter_edit()
		return false
	curve._finish_editor_parameter_edit()
	return commit_applied_action(
		undo_redo,
		curve,
		action_name,
		ActionContext.new(before, after),
		source_property,
	)


static func _find_parent_inspector(source_property: EditorProperty) -> EditorInspector:
	var current: Node = source_property
	while current != null:
		if current is EditorInspector:
			return current as EditorInspector
		current = current.get_parent()
	return null

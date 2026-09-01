@tool
extends RefCounted
## Owns Inspector-side Undo adapter coordination for EasingCurve edit transactions.
##
## Point mutation dispatch and gesture lifecycle callbacks remain on the Inspector
## facade until the later EDITOR-03 routing steps.

const EASING_CURVE_EDITOR_UNDO = preload(
	"res://addons/easing_curve/scripts/editor/easing_curve_editor_undo.gd"
)

var _undo_redo: Object
var _source_property_provider := Callable()


func setup(
	undo_redo: Object,
	source_property_provider: Callable,
) -> void:
	_undo_redo = undo_redo
	_source_property_provider = source_property_provider


func capture_state(curve: EasingCurve) -> Dictionary:
	return EASING_CURVE_EDITOR_UNDO.capture_state(curve)


func create_action_context(
	before: Dictionary,
	after: Dictionary = {},
) -> EasingCurveEditorUndo.ActionContext:
	return EASING_CURVE_EDITOR_UNDO.ActionContext.new(before, after)


func commit_applied_action(
	curve: EasingCurve,
	action_name: String,
	context: EasingCurveEditorUndo.ActionContext,
) -> bool:
	return EASING_CURVE_EDITOR_UNDO.commit_applied_action(
		_undo_redo,
		curve,
		action_name,
		context,
		_source_property(),
	)


func apply_action(
	curve: EasingCurve,
	action_name: String,
	mutation: Callable,
) -> bool:
	return EASING_CURVE_EDITOR_UNDO.apply_action(
		_undo_redo,
		curve,
		action_name,
		mutation,
		_source_property(),
	)


static func point_action_name(property_name: StringName) -> String:
	match property_name:
		&"position":
			return "Move Easing Curve Point"
		&"left_control_point", &"right_control_point":
			return "Move Easing Curve Handle"
		&"left_control_state", &"right_control_state":
			return "Change Easing Curve Handle State"
		&"toolbar_options_reset":
			return "Reset Easing Curve Point Options"
		&"handle_mode":
			return "Change Easing Curve Handle Mode"
		&"locked", &"position_lock", &"left_control_lock", &"right_control_lock":
			return "Change Easing Curve Point Lock"
		&"left_force_linear", &"right_force_linear":
			return "Change Easing Curve Handle Force Linear State"
	return "Edit Easing Curve Point"


func _source_property() -> EditorProperty:
	if not _source_property_provider.is_valid():
		return null
	return _source_property_provider.call() as EditorProperty

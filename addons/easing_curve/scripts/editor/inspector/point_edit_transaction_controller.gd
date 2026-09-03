@tool
extends RefCounted
## Owns Inspector-side EasingCurve point edit transaction coordination.
##
## The controller captures/commits draft gesture state and applies point snapshot
## mutations while delegating semantic point-state rules to the existing mutator
## and Godot Undo/Redo integration to EasingCurveEditorUndo.

const EASING_CURVE_EDITOR_UNDO = preload(
	"res://addons/easing_curve/scripts/editor/easing_curve_editor_undo.gd"
)
const BackendFactory = preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_editor_backend_factory.gd"
)

var _undo_redo: Object
var _source_property_provider := Callable()
var _selection_capture := Callable()
var _selection_restorer := Callable()
var _position_reorder_handler := Callable()

var _point_edit_before_state: Dictionary = {}
var _point_edit_selection_before: Dictionary = {}
var _point_edit_point_resource_ids_before := PackedInt64Array()
var _point_edit_action_name := "Edit Easing Curve Point"
var _point_edit_backend: RefCounted


func setup(
	undo_redo: Object,
	source_property_provider: Callable,
) -> void:
	_undo_redo = undo_redo
	_source_property_provider = source_property_provider


func setup_point_edit_callbacks(
	selection_capture: Callable,
	selection_restorer: Callable,
	position_reorder_handler: Callable,
) -> void:
	_selection_capture = selection_capture
	_selection_restorer = selection_restorer
	_position_reorder_handler = position_reorder_handler


func reset_point_edit() -> void:
	if _point_edit_backend != null:
		_point_edit_backend.finish_point_edit()
	_point_edit_before_state = {}
	_point_edit_selection_before = {}
	_point_edit_point_resource_ids_before = PackedInt64Array()
	_point_edit_action_name = "Edit Easing Curve Point"
	_point_edit_backend = null


func is_point_edit_active() -> bool:
	return not _point_edit_before_state.is_empty()


func get_point_edit_transaction_state() -> Dictionary:
	return {
		"active": is_point_edit_active(),
		"before": _point_edit_before_state.duplicate(true),
		"selection_before": _point_edit_selection_before.duplicate(true),
		"point_resource_ids_before": _point_edit_point_resource_ids_before.duplicate(),
		"action_name": _point_edit_action_name,
	}


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


func apply_point_property_change(
	curve: EasingCurve,
	point_index: int,
	property_name: StringName,
	value: Variant,
	changing: bool = false,
	position_reorder_point: EasingCurvePoint = null,
) -> void:
	if curve == null or point_index < 0 or point_index >= curve.points.size():
		return

	var before := capture_state(curve)
	var backend := _point_edit_backend
	if backend == null:
		backend = BackendFactory.create(curve)
	if backend == null:
		return
	if changing and not is_point_edit_active():
		_begin_point_edit(curve, property_name, before, backend)

	if not backend.apply_point_property(
		point_index,
		property_name,
		value,
		changing or position_reorder_point != null,
	):
		return

	if position_reorder_point != null and _position_reorder_handler.is_valid():
		_position_reorder_handler.call(position_reorder_point, changing)
		if not changing:
			curve.set_point_snapshot(curve.get_point_snapshot())

	if changing:
		return
	if is_point_edit_active():
		finish_point_edit(curve)
		return

	commit_applied_action(
		curve,
		point_action_name(property_name),
		create_action_context(before),
	)


func finish_point_edit(
	curve: EasingCurve,
	point_order: Array[EasingCurvePoint] = [],
) -> bool:
	if curve == null or not is_point_edit_active():
		return false

	var before := _point_edit_before_state
	var selection_before := _point_edit_selection_before
	var point_resource_ids_before := _point_edit_point_resource_ids_before
	var action_name := _point_edit_action_name
	var backend := _point_edit_backend
	_point_edit_backend = null
	reset_point_edit()

	if not point_order.is_empty() and curve.points != point_order:
		curve.points = point_order

	if backend != null:
		backend.finish_point_edit()
	var after := capture_state(curve)
	var selection_after := _capture_selection_state()
	var point_resource_ids_after := curve._get_editor_point_resource_ids()

	return commit_applied_action(
		curve,
		action_name,
		create_action_context(before, after)
			.with_selection(
				_selection_restorer,
				selection_before,
				selection_after,
			)
			.with_point_resource_ids(
				point_resource_ids_before,
				point_resource_ids_after,
			),
	)


func _begin_point_edit(
	curve: EasingCurve,
	property_name: StringName,
	before: Dictionary,
	backend: RefCounted,
) -> void:
	if is_point_edit_active():
		return
	_point_edit_before_state = before
	_point_edit_selection_before = _capture_selection_state()
	_point_edit_point_resource_ids_before = curve._get_editor_point_resource_ids()
	_point_edit_action_name = point_action_name(property_name)
	_point_edit_backend = backend
	_point_edit_backend.begin_point_edit()


func _capture_selection_state() -> Dictionary:
	if not _selection_capture.is_valid():
		return {}
	var selection: Variant = _selection_capture.call()
	return selection if selection is Dictionary else {}


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

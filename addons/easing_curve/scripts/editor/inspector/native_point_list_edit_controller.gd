@tool
extends RefCounted
## Keeps Native Points editable after its graph surface has detached.
## History owns the resource backend and only a weak selection callback.

const Backend = preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_editor_backend.gd"
)
const Transaction = preload(
	"res://addons/easing_curve/scripts/editor/inspector/point_edit_transaction_controller.gd"
)

var backend: Backend
var undo_redo: Object
var capture_selection := Callable()
var restore_selection := Callable()
var _before: Dictionary = {}
var _selection_before: Dictionary = {}
var _point: Resource
var _property: StringName


func prepare(point: Resource, property_name: StringName) -> bool:
	if _before.is_empty() or (_point == point and _property == property_name):
		return false
	finish()
	return true


func edit(
	point: Resource,
	property_name: StringName,
	value: Variant,
	changing: bool,
) -> void:
	var index: int = backend.find_point(point)
	if index < 0:
		return
	prepare(point, property_name)
	if _before.is_empty():
		_before = backend.capture_snapshot().duplicate(true)
		_selection_before = capture_selection.call()
		_point = point
		_property = property_name
		backend.begin_point_edit()
	backend.apply_point_property(index, property_name, value, changing)
	if not changing:
		finish()


func finish() -> void:
	if _before.is_empty():
		return
	var before := _before
	var selection_before := _selection_before
	var property_name := _property
	var point := _point
	_before = {}
	_selection_before = {}
	_point = null
	_property = &""
	if property_name == &"position" and backend.find_point(point) >= 0:
		backend.apply_point_order(backend.get_ordered_points(point))
	backend.finish_point_edit()
	_commit(before, selection_before, Transaction.point_action_name(property_name))


func mutate(action_name: String, mutation: Callable) -> void:
	finish()
	var before: Dictionary = backend.capture_snapshot().duplicate(true)
	var selection_before: Dictionary = capture_selection.call()
	mutation.call()
	_commit(before, selection_before, action_name)


func _commit(before: Dictionary, selection_before: Dictionary, action_name: String) -> void:
	var after: Dictionary = backend.capture_snapshot().duplicate(true)
	if undo_redo == null or before == after:
		return
	var selection_after: Dictionary = capture_selection.call()
	var restore := Callable(get_script(), &"_apply_snapshot")
	if undo_redo is EditorUndoRedoManager:
		undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, backend.curve)
		undo_redo.add_do_method(
			get_script(), &"_apply_snapshot", backend, after, restore_selection, selection_after,
		)
		undo_redo.add_undo_method(
			get_script(), &"_apply_snapshot", backend, before, restore_selection, selection_before,
		)
		undo_redo.add_do_method(backend.curve, &"_apply_live_editor_snapshot", after[&"live_state"])
		undo_redo.add_undo_method(backend.curve, &"_apply_live_editor_snapshot", before[&"live_state"])
	else:
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(restore.bind(backend, after, restore_selection, selection_after))
		undo_redo.add_undo_method(restore.bind(backend, before, restore_selection, selection_before))
	undo_redo.commit_action(undo_redo is EditorUndoRedoManager)


static func _apply_snapshot(
	target: Backend,
	snapshot: Dictionary,
	restore: Callable,
	selection: Dictionary,
) -> void:
	if target.apply_snapshot(snapshot) and restore.is_valid():
		restore.call(selection)


func dispose() -> void:
	finish()
	capture_selection = Callable()
	restore_selection = Callable()
	undo_redo = null

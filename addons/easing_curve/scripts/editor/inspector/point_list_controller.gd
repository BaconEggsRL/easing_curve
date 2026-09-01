@tool
extends RefCounted
## Owns Inspector point-list logical selection and point-input binding state.
##
## UI construction, graph synchronization, mutations, transactions, and Undo/Redo
## remain on the Inspector side of this focused controller boundary.

var selected_point_index := -1
var selected_point_property_name := StringName()
var selected_point_resource_id := 0

var _preserve_selection_on_refresh := false
var _input_bindings: Dictionary[int, Dictionary] = {}


func request_selection_refresh_preservation() -> void:
	_preserve_selection_on_refresh = true


func consume_selection_refresh_preservation() -> bool:
	if not _preserve_selection_on_refresh:
		return false
	_preserve_selection_on_refresh = false
	return true


func assign_logical_selection(
	curve: EasingCurve,
	point_index: int,
	property_name: StringName,
) -> void:
	selected_point_index = point_index
	selected_point_resource_id = (
		curve.points[point_index].get_instance_id()
		if curve != null and point_index >= 0 and point_index < curve.points.size()
		else 0
	)
	selected_point_property_name = property_name


func clear_logical_selection() -> void:
	selected_point_index = -1
	selected_point_resource_id = 0
	selected_point_property_name = StringName()


func capture_selection(
	curve: EasingCurve,
	graph_selected_index: int,
) -> Dictionary:
	if curve == null:
		return {"has_selection": false}

	var point_index := -1
	var property_name := StringName()
	if selected_point_index >= 0 and selected_point_index < curve.points.size():
		var selected_point := curve.points[selected_point_index]
		if (
			selected_point_resource_id == 0
			or selected_point.get_instance_id() == selected_point_resource_id
		):
			point_index = selected_point_index
			property_name = selected_point_property_name

	if (
		point_index == -1
		and graph_selected_index >= 0
		and graph_selected_index < curve.points.size()
	):
		point_index = graph_selected_index

	if point_index == -1:
		return {"has_selection": false}

	return {
		"has_selection": true,
		"point_index": point_index,
		"point_resource_id": curve.points[point_index].get_instance_id(),
		"property_name": property_name,
	}


func restore_selection(curve: EasingCurve, selection: Dictionary) -> int:
	if curve == null or not bool(selection.get("has_selection", false)):
		clear_logical_selection()
		return -1

	var point_index := int(selection.get("point_index", -1))
	var point_resource_id := int(selection.get("point_resource_id", 0))
	if point_resource_id != 0:
		for i in range(curve.points.size()):
			if curve.points[i].get_instance_id() == point_resource_id:
				point_index = i
				break

	if point_index < 0 or point_index >= curve.points.size():
		clear_logical_selection()
		return -1

	assign_logical_selection(
		curve,
		point_index,
		StringName(selection.get("property_name", StringName())),
	)
	return point_index


func clear_input_bindings() -> void:
	for binding in _input_bindings.values():
		var point: EasingCurvePoint = binding.get("point")
		var changed_callback: Callable = binding.get("changed_callback", Callable())
		if (
			point != null
			and changed_callback.is_valid()
			and point.changed.is_connected(changed_callback)
		):
			point.changed.disconnect(changed_callback)
	_input_bindings.clear()


func register_input_binding(
	point: EasingCurvePoint,
	property_name: StringName,
	axis: String,
	input: EditorSpinSlider,
) -> void:
	if point == null or input == null:
		return

	var point_id := point.get_instance_id()
	if not _input_bindings.has(point_id):
		var changed_callback := _on_bound_point_changed.bind(point_id)
		_input_bindings[point_id] = {
			"point": point,
			"changed_callback": changed_callback,
			"inputs": {},
		}
		point.changed.connect(changed_callback)

	var binding: Dictionary = _input_bindings[point_id]
	var inputs: Dictionary = binding["inputs"]
	inputs[property_name + axis] = {
		"property_name": property_name,
		"axis": axis,
		"input": weakref(input),
	}
	binding["inputs"] = inputs
	_input_bindings[point_id] = binding
	_refresh_input_bindings(point_id)


## Returns a detached inspection snapshot so callers cannot mutate controller-owned state.
func get_input_bindings() -> Dictionary:
	return _input_bindings.duplicate(true)


func _on_bound_point_changed(point_id: int) -> void:
	_refresh_input_bindings(point_id)


func _refresh_input_bindings(point_id: int) -> void:
	if not _input_bindings.has(point_id):
		return

	var binding: Dictionary = _input_bindings[point_id]
	var point: EasingCurvePoint = binding.get("point")
	if point == null:
		_input_bindings.erase(point_id)
		return

	var inputs: Dictionary = binding["inputs"]
	for input_key in inputs.keys():
		var input_binding: Dictionary = inputs[input_key]
		var input_ref: WeakRef = input_binding["input"]
		var input := input_ref.get_ref() if input_ref != null else null
		if input == null:
			inputs.erase(input_key)
			continue

		var property_name: StringName = input_binding["property_name"]
		var value: Vector2 = point.get(property_name)
		input.set_value_no_signal(
			value.x if input_binding["axis"] == "x" else value.y
		)
		input.read_only = not point.is_position_input_editable(String(property_name))

	if inputs.is_empty():
		var changed_callback: Callable = binding["changed_callback"]
		if point.changed.is_connected(changed_callback):
			point.changed.disconnect(changed_callback)
		_input_bindings.erase(point_id)
		return

	binding["inputs"] = inputs
	_input_bindings[point_id] = binding

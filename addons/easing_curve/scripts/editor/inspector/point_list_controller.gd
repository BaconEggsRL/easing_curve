@tool
extends RefCounted
## Owns Inspector point-list construction/routing, logical selection, and point-input bindings.
##
## Leaf property controls, graph synchronization, mutations, transactions, and Undo/Redo
## remain on the Inspector side of this focused controller boundary.

const EDITOR_THEME_CACHE = preload(
	"res://addons/easing_curve/scripts/editor/inspector/editor_theme_cache.gd"
)
const PointsListContainer = preload(
	"res://addons/easing_curve/scripts/editor/inspector/points_list_container.gd"
)
const POINT_INSPECTOR_PROPERTY_ORDER: Array[StringName] = [
	&"position",
	&"handle_mode",
	&"left_control_point",
	&"right_control_point",
]

var _zero_margin_panel_stylebox: StyleBox = (
	EDITOR_THEME_CACHE.make_zero_margin_panel_stylebox()
)

var selected_point_index := -1
var selected_point_property_name := StringName()
var selected_point_resource_id := 0

var _preserve_selection_on_refresh := false
var _input_bindings: Dictionary[int, Dictionary] = {}


func build_point_list(
	curve: EasingCurve,
	compact_separation: int,
	point_separation: int,
	create_bool_property: Callable,
	create_vector2_property: Callable,
	create_handle_mode_property: Callable,
	move_point: Callable,
	remove_point: Callable,
	create_add_controls: Callable,
) -> VBoxContainer:
	var point_list := PointsListContainer.new()
	point_list.point_swap_requested.connect(move_point)
	point_list.add_spacer(true)
	point_list.add_theme_constant_override(&"separation", point_separation)

	for point_index in range(curve.points.size()):
		var point := curve.points[point_index]
		var point_panel := PanelContainer.new()
		point_panel.add_theme_stylebox_override(
			&"panel",
			_zero_margin_panel_stylebox,
		)

		var point_main_hbox := HBoxContainer.new()
		point_main_hbox.add_theme_constant_override(
			&"separation",
			compact_separation,
		)
		point_panel.add_child(point_main_hbox)

		point_main_hbox.add_child(
			_create_point_side_vbox(
				curve,
				point_index,
				point_list,
				point_panel,
				move_point,
			)
		)

		var point_properties_grid := GridContainer.new()
		point_properties_grid.columns = 2
		point_properties_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		point_properties_grid.add_theme_constant_override(
			&"h_separation",
			compact_separation,
		)
		point_properties_grid.add_theme_constant_override(
			&"v_separation",
			compact_separation,
		)
		point_main_hbox.add_child(point_properties_grid)

		var remove_btn := Button.new()
		remove_btn.icon = EDITOR_THEME_CACHE.get_icon(
			EDITOR_THEME_CACHE.ICON_REMOVE
		)
		remove_btn.flat = true
		remove_btn.tooltip_text = "Remove Point"
		remove_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		remove_btn.pressed.connect(remove_point.bind(point))
		point_main_hbox.add_child(remove_btn)

		create_normal_point_property_rows(
			point,
			point_index,
			curve.points.size(),
			point_properties_grid,
			create_bool_property,
			create_vector2_property,
			create_handle_mode_property,
		)

		point_list.add_child(point_panel)
		point_list.enable_drop_forwarding(point_panel)

	if curve.curve_mode == EasingCurve.CurveMode.BEZIER:
		point_list.add_child(create_add_controls.call())

	return point_list


static func get_normal_point_property_definitions(
	point_index: int,
	point_count: int,
) -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for property_name in POINT_INSPECTOR_PROPERTY_ORDER:
		if not EasingCurve.is_point_property_inspector_visible(property_name):
			continue
		if property_name == &"left_control_point" and point_index == 0:
			continue
		if property_name == &"right_control_point" and point_index == point_count - 1:
			continue
		definitions.append(EasingCurve.get_point_property_definition(property_name))
	return definitions


static func create_normal_point_property_rows(
	point: EasingCurvePoint,
	point_index: int,
	point_count: int,
	property_grid: GridContainer,
	create_bool_property: Callable,
	create_vector2_property: Callable,
	create_handle_mode_property: Callable,
) -> void:
	for definition in get_normal_point_property_definitions(point_index, point_count):
		match StringName(definition["editor_kind"]):
			EasingCurve.POINT_EDITOR_KIND_BOOL:
				create_bool_property.call(
					point,
					point_index,
					definition,
					property_grid,
				)
			EasingCurve.POINT_EDITOR_KIND_VECTOR2:
				create_vector2_property.call(
					point,
					point_index,
					definition,
					property_grid,
				)
			EasingCurve.POINT_EDITOR_KIND_HANDLE_MODE:
				create_handle_mode_property.call(
					point,
					point_index,
					definition,
					property_grid,
				)


func request_move_up(
	point_index: int,
	curve: EasingCurve,
	move_point: Callable,
) -> void:
	var point_count := curve.points.size()
	if point_count < 2:
		return
	move_point.call(point_index, wrapi(point_index - 1, 0, point_count))


func request_move_down(
	point_index: int,
	curve: EasingCurve,
	move_point: Callable,
) -> void:
	var point_count := curve.points.size()
	if point_count < 2:
		return
	move_point.call(point_index, wrapi(point_index + 1, 0, point_count))


func _create_point_side_vbox(
	curve: EasingCurve,
	point_index: int,
	point_list: VBoxContainer,
	point_panel: PanelContainer,
	move_point: Callable,
) -> VBoxContainer:
	var side_vbox := VBoxContainer.new()
	side_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var move_up_btn := Button.new()
	move_up_btn.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_MOVE_UP
	)
	move_up_btn.flat = true
	move_up_btn.tooltip_text = "Move Point Up"
	move_up_btn.pressed.connect(
		request_move_up.bind(point_index, curve, move_point)
	)
	side_vbox.add_child(move_up_btn)

	var triple_bar := EasingCurveDragHandle.new()
	triple_bar.texture = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_TRIPLE_BAR
	)
	triple_bar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	triple_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	triple_bar.set_focus_mode(Control.FOCUS_ALL)
	triple_bar.index = point_index
	triple_bar.point_panel = point_panel
	triple_bar.point_list = point_list
	side_vbox.add_child(triple_bar)

	var move_down_btn := Button.new()
	move_down_btn.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_MOVE_DOWN
	)
	move_down_btn.flat = true
	move_down_btn.tooltip_text = "Move Point Down"
	move_down_btn.pressed.connect(
		request_move_down.bind(point_index, curve, move_point)
	)
	side_vbox.add_child(move_down_btn)

	return side_vbox


func request_selection_refresh_preservation() -> void:
	_preserve_selection_on_refresh = true


func consume_selection_refresh_preservation() -> bool:
	if not _preserve_selection_on_refresh:
		return false
	_preserve_selection_on_refresh = false
	return true


func assign_logical_selection(
	curve_resource: Resource,
	point_index: int,
	property_name: StringName,
) -> void:
	var points := _get_resource_points(curve_resource)
	selected_point_index = point_index
	selected_point_resource_id = (
		points[point_index].get_instance_id()
		if point_index >= 0 and point_index < points.size()
		else 0
	)
	selected_point_property_name = property_name


func clear_logical_selection() -> void:
	selected_point_index = -1
	selected_point_resource_id = 0
	selected_point_property_name = StringName()


func capture_selection(
	curve_resource: Resource,
	graph_selected_index: int,
) -> Dictionary:
	var points := _get_resource_points(curve_resource)
	if points.is_empty():
		return {"has_selection": false}

	var point_index := -1
	var property_name := StringName()
	if selected_point_index >= 0 and selected_point_index < points.size():
		var selected_point := points[selected_point_index]
		if (
			selected_point_resource_id == 0
			or selected_point.get_instance_id() == selected_point_resource_id
		):
			point_index = selected_point_index
			property_name = selected_point_property_name

	if (
		point_index == -1
		and graph_selected_index >= 0
		and graph_selected_index < points.size()
	):
		point_index = graph_selected_index

	if point_index == -1:
		return {"has_selection": false}

	return {
		"has_selection": true,
		"point_index": point_index,
		"point_resource_id": points[point_index].get_instance_id(),
		"property_name": property_name,
	}


func restore_selection(curve_resource: Resource, selection: Dictionary) -> int:
	var points := _get_resource_points(curve_resource)
	if points.is_empty() or not bool(selection.get("has_selection", false)):
		clear_logical_selection()
		return -1

	var point_index := int(selection.get("point_index", -1))
	var point_resource_id := int(selection.get("point_resource_id", 0))
	if point_resource_id != 0:
		for i in range(points.size()):
			if points[i].get_instance_id() == point_resource_id:
				point_index = i
				break

	if point_index < 0 or point_index >= points.size():
		clear_logical_selection()
		return -1

	assign_logical_selection(
		curve_resource,
		point_index,
		StringName(selection.get("property_name", StringName())),
	)
	return point_index


static func _get_resource_points(curve_resource: Resource) -> Array[Resource]:
	if curve_resource == null:
		return []
	var points: Array[Resource] = []
	var resource_points: Variant = curve_resource.get(&"points")
	if not resource_points is Array:
		return points
	for point in resource_points:
		if point is Resource:
			points.append(point)
	return points


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

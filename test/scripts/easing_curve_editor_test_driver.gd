extends RefCounted


static func connect_curve_editor(editor: EasingCurveEditor, inspector: Object) -> void:
	editor.point_property_change_requested.connect(
		func(index: int, property_name: StringName, value: Variant, changing: bool) -> void:
			inspector.call(
				"_on_curve_editor_point_property_change_requested",
				index,
				property_name,
				value,
				changing,
			)
	)
	editor.point_edit_finished.connect(
		func(point_order: Array[EasingCurvePoint]) -> void:
			inspector.call("_on_curve_editor_point_edit_finished", point_order)
	)
	editor.point_add_requested.connect(
		func(point: EasingCurvePoint) -> void:
			inspector.call("_on_curve_editor_point_add_requested", point)
	)
	editor.point_remove_requested.connect(
		func(point: EasingCurvePoint) -> void:
			inspector.call("_remove_point", point)
	)


static func create_curve_editor(inspector: Object, curve: EasingCurve) -> Control:
	return inspector.call("handle_easing_curve_editor", curve)


static func curve_editor(inspector: Object) -> EasingCurveEditor:
	return inspector.get("easing_curve_editor") as EasingCurveEditor


static func select_point_property(
	inspector: Object,
	property_header: PanelContainer,
	point_index: int,
	property_name: StringName,
) -> void:
	inspector.call("_select_point_property", property_header, point_index, property_name)


static func select_point(inspector: Object, point: EasingCurvePoint) -> void:
	inspector.call("_select_reordered_point", point)


static func clear_point_selection(inspector: Object) -> void:
	inspector.call("_clear_point_property_selection")


static func capture_point_selection(inspector: Object) -> Dictionary:
	return inspector.call("_capture_point_selection_state")


static func selected_point_index(inspector: Object) -> int:
	return int(inspector.get("_selected_point_index"))


static func selected_point_resource_id(inspector: Object) -> int:
	return int(inspector.get("_selected_point_resource_id"))


static func selected_point_property_name(inspector: Object) -> StringName:
	return StringName(inspector.get("_selected_point_property_name"))


static func selected_point_property_header(inspector: Object) -> PanelContainer:
	return inspector.get("_selected_point_property_header") as PanelContainer


static func change_point_property(
	inspector: Object,
	point_index: int,
	property_name: StringName,
	value: Variant,
	changing := false,
	position_reorder_point: EasingCurvePoint = null,
) -> void:
	inspector.call(
		"_apply_point_property_change",
		point_index,
		property_name,
		value,
		changing,
		position_reorder_point,
	)


static func commit_point_edit(
	inspector: Object,
	point_order: Array[EasingCurvePoint] = [],
) -> void:
	inspector.call("_commit_point_edit", point_order)


static func add_point_from_toolbar(inspector: Object) -> void:
	inspector.call("_on_add_point_btn_pressed")


static func add_point_from_graph(inspector: Object, point: EasingCurvePoint) -> void:
	inspector.call("_on_curve_editor_point_add_requested", point)


static func rebuild_for_curve(inspector: Object, curve: EasingCurve) -> void:
	inspector.call("_parse_begin", curve)


static func move_point(inspector: Object, from_index: int, to_index: int) -> void:
	inspector.call("_move_point", from_index, to_index)


static func move_point_up(inspector: Object, point_index: int) -> void:
	inspector.call("_move_point_up", point_index)


static func move_point_down(inspector: Object, point_index: int) -> void:
	inspector.call("_move_point_down", point_index)


static func is_point_property_value_compatible(
	inspector: Object,
	property_name: StringName,
	value: Variant,
) -> bool:
	return bool(inspector.call("_is_point_property_value_compatible", property_name, value))


static func paste_point_property_value(
	inspector: Object,
	point_index: int,
	property_name: StringName,
	value: Variant,
) -> void:
	inspector.call("_apply_pasted_point_property_value", point_index, property_name, value)

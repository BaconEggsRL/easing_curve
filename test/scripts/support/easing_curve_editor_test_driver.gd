extends RefCounted


static func connect_curve_editor(editor: EasingCurveEditor, inspector: Object) -> void:
	editor.point_property_change_requested.connect(
		Callable(inspector, "_apply_point_property_change")
	)
	editor.point_edit_finished.connect(
		Callable(inspector, "_commit_point_edit")
	)
	editor.point_add_requested.connect(
		Callable(inspector, "_on_curve_editor_point_add_requested")
	)
	editor.point_remove_requested.connect(
		Callable(inspector, "_remove_point")
	)


static func create_curve_editor(inspector: Object, curve: EasingCurve) -> Control:
	return inspector.call("handle_easing_curve_editor", curve)


static func create_points_list(inspector: Object, curve: EasingCurve) -> VBoxContainer:
	return inspector.call("handle_points", curve) as VBoxContainer


static func point_list_controller(inspector: Object) -> RefCounted:
	return inspector.get("_point_list_controller") as RefCounted


static func point_edit_transaction_controller(inspector: Object) -> RefCounted:
	return inspector.get("_point_edit_transaction_controller") as RefCounted


static func curve_editor(inspector: Object) -> EasingCurveEditor:
	return inspector.get("easing_curve_editor") as EasingCurveEditor


static func request_autofit(inspector: Object) -> void:
	inspector.call("_autofit_curve_editor")


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


static func restore_point_selection(
	inspector: Object,
	selection: Dictionary,
) -> void:
	inspector.call("_restore_point_selection_state", selection)


static func selected_point_index(inspector: Object) -> int:
	return int(point_list_controller(inspector).get("selected_point_index"))


static func selected_point_resource_id(inspector: Object) -> int:
	return int(point_list_controller(inspector).get("selected_point_resource_id"))


static func register_point_input_binding(
	inspector: Object,
	point: EasingCurvePoint,
	property_name: StringName,
	axis: String,
	input: EditorSpinSlider,
) -> void:
	point_list_controller(inspector).call(
		"register_input_binding",
		point,
		property_name,
		axis,
		input,
	)


static func clear_point_input_bindings(inspector: Object) -> void:
	point_list_controller(inspector).call("clear_input_bindings")


static func point_input_binding_count(inspector: Object) -> int:
	var bindings: Dictionary = point_list_controller(inspector).call("get_input_bindings")
	return bindings.size()


static func point_input_binding_input_count(
	inspector: Object,
	point: EasingCurvePoint,
) -> int:
	var bindings: Dictionary = point_list_controller(inspector).call("get_input_bindings")
	var binding: Dictionary = bindings.get(point.get_instance_id(), {})
	var inputs: Dictionary = binding.get("inputs", {})
	return inputs.size()


static func point_input_binding_callback(
	inspector: Object,
	point: EasingCurvePoint,
) -> Callable:
	var bindings: Dictionary = point_list_controller(inspector).call("get_input_bindings")
	var binding: Dictionary = bindings.get(point.get_instance_id(), {})
	return binding.get("changed_callback", Callable())


static func point_input_binding_is_connected(
	inspector: Object,
	point: EasingCurvePoint,
) -> bool:
	var changed_callback := point_input_binding_callback(inspector, point)
	return changed_callback.is_valid() and point.changed.is_connected(changed_callback)


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


static func point_edit_transaction_state(inspector: Object) -> Dictionary:
	return point_edit_transaction_controller(inspector).call(
		"get_point_edit_transaction_state"
	)


static func add_point_from_toolbar(inspector: Object) -> void:
	inspector.call("_on_add_point_btn_pressed")


static func add_point_from_graph(inspector: Object, point: EasingCurvePoint) -> void:
	inspector.call("_on_curve_editor_point_add_requested", point)


static func rebuild_for_curve(inspector: Object, curve: EasingCurve) -> void:
	inspector.call("_parse_begin", curve)


static func move_point(inspector: Object, from_index: int, to_index: int) -> void:
	inspector.call("_move_point", from_index, to_index)


static func move_point_up(inspector: Object, point_index: int) -> void:
	point_list_controller(inspector).call(
		"request_move_up",
		point_index,
		inspector.get("curve"),
		Callable(inspector, "_move_point"),
	)


static func move_point_down(inspector: Object, point_index: int) -> void:
	point_list_controller(inspector).call(
		"request_move_down",
		point_index,
		inspector.get("curve"),
		Callable(inspector, "_move_point"),
	)


static func paste_point_property_value(
	inspector: Object,
	point_index: int,
	property_name: StringName,
	value: Variant,
) -> void:
	inspector.call("_apply_pasted_point_property_value", point_index, property_name, value)


static func point_property_path(
	inspector: Object,
	point_index: int,
	property_name: StringName,
) -> String:
	return String(
		inspector.call("_point_property_path", point_index, property_name)
	)


static func copy_point_property_value(
	inspector: Object,
	point_index: int,
	property_name: StringName,
) -> void:
	inspector.call("_copy_point_property_value", point_index, property_name)


static func paste_clipboard_point_property_value(
	inspector: Object,
	point_index: int,
	property_name: StringName,
) -> void:
	inspector.call("_paste_point_property_value", point_index, property_name)


static func copy_point_property_path(
	inspector: Object,
	point_index: int,
	property_name: StringName,
) -> void:
	inspector.call("_copy_point_property_path", point_index, property_name)


static func is_point_property_value_compatible(
	inspector: Object,
	property_name: StringName,
	value: Variant,
) -> bool:
	return bool(
		inspector.call(
			"_is_point_property_value_compatible",
			property_name,
			value,
		)
	)


static func clipboard_has_compatible_point_property_value(
	inspector: Object,
	property_name: StringName,
) -> bool:
	return bool(
		inspector.call(
			"_clipboard_has_compatible_point_property_value",
			property_name,
		)
	)


static func open_point_property_context_menu(
	property_header: PanelContainer,
) -> void:
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	property_header.emit_signal(&"gui_input", right_click)


static func selected_point_property_header(
	inspector: Object,
) -> PanelContainer:
	return inspector.get("_selected_point_property_header") as PanelContainer


static func selected_point_property_name(
	inspector: Object,
) -> StringName:
	return StringName(
		point_list_controller(inspector).get("selected_point_property_name")
	)

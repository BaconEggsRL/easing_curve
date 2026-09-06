extends "res://test/scripts/support/test_case.gd"

const CURVE_EDITOR := preload(
	"res://addons/easing_curve/scripts/editor/easing_curve_editor.gd"
)
const INSPECTOR_PLUGIN := preload(
	"res://addons/easing_curve/scripts/editor/inspector/easing_curve_editor_inspector_plugin.gd"
)
const CURVE_EDITOR_SETTINGS := preload(
	"res://addons/easing_curve/scripts/editor/curve_editor_settings.gd"
)
const DEFERRED_PARAMETER_EDITOR_PROPERTY := preload(
	"res://addons/easing_curve/scripts/editor/inspector/deferred_parameter_editor_property.gd"
)
const POINTS_EDITOR_PROPERTY := preload(
	"res://addons/easing_curve/scripts/editor/inspector/points_editor_property.gd"
)
const CURVE_CONVERSION_CONTROL := preload(
	"res://addons/easing_curve/scripts/editor/inspector/curve_conversion_control.gd"
)
const ZOOM_SLIDER := preload(
	"res://addons/easing_curve/scripts/editor/widgets/zoom_slider_container.tscn"
)
func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_default_new_point_handle_modes()
	await _test_shared_wheel_zoom_routing()
	_test_legacy_selection_path()
	_test_native_selection_and_point_options()
	_test_native_bezier_transform_preview()
	_test_native_geometry_gestures()
	_test_native_add_delete_and_endpoint_topology()
	_test_native_existing_point_endpoint_takeover()
	_test_native_crossing_and_toolbar_reorder()
	_test_native_point_list_swap_parity()
	await _test_native_inspector_path()
	await _test_native_deferred_parameter_editor()
	await _test_native_property_clipboard_and_lifecycle()
	_finish("shared curve editor vertical slice")


func _test_default_new_point_handle_modes() -> void:
	CURVE_EDITOR_SETTINGS.setup()
	var settings := EditorInterface.get_editor_settings()
	var setting_name: String = (
		CURVE_EDITOR_SETTINGS.DEFAULT_NEW_POINT_HANDLE_MODE_SETTING
	)
	_expect(settings.has_setting(setting_name), "Default new-point handle setting was not registered")
	var original_value := int(settings.get_setting(setting_name))

	var legacy_curve := _make_handle_mode_curve(&"legacy")
	var native_curve := _make_handle_mode_curve(&"native")
	var legacy_editor := CURVE_EDITOR.new() as EasingCurveEditor
	var native_editor := CURVE_EDITOR.new() as EasingCurveEditor
	legacy_editor.set_curve(legacy_curve)
	native_editor.set_curve(native_curve)
	legacy_editor.size = Vector2(520.0, 260.0)
	native_editor.size = Vector2(520.0, 260.0)
	root.add_child(legacy_editor)
	root.add_child(native_editor)
	await process_frame

	var legacy_inspector := INSPECTOR_PLUGIN.new()
	var native_inspector := INSPECTOR_PLUGIN.new()
	legacy_inspector.set("easing_curve_editor", legacy_editor)
	native_inspector.set("easing_curve_editor", native_editor)
	var legacy_controls := legacy_inspector.call("_create_point_add_controls") as Control
	var native_controls := native_inspector.call("_create_point_add_controls") as Control
	root.add_child(legacy_controls)
	root.add_child(native_controls)
	var legacy_option := legacy_controls.get_node("NewPointHandleMode") as OptionButton
	var native_option := native_controls.get_node("NewPointHandleMode") as OptionButton
	_expect(legacy_option != null and native_option != null, "Shared Add Point controls omitted the handle-mode dropdown")
	_expect(
		legacy_controls.size_flags_horizontal == Control.SIZE_SHRINK_CENTER,
		"Shared Add Point controls did not remain content-sized",
	)
	_expect(
		legacy_option.fit_to_longest_item,
		"New-point handle dropdown did not reserve its longest item width",
	)
	_expect(
		legacy_option.size_flags_horizontal == Control.SIZE_SHRINK_CENTER,
		"New-point handle dropdown expanded beyond its content width",
	)
	_expect(
		legacy_controls.get_child_count() == 2,
		"Shared Add Point controls included an unexpected standalone label",
	)
	_expect(_find_button(legacy_controls, "Add Point") != null, "Legacy controls omitted Add Point beside the dropdown")
	_expect(_find_button(native_controls, "Add Point") != null, "Native controls omitted Add Point beside the dropdown")

	var legacy_changes := [0]
	var native_changes := [0]
	legacy_curve.changed.connect(func() -> void: legacy_changes[0] += 1)
	native_curve.changed.connect(func() -> void: native_changes[0] += 1)
	var mirrored_index := _option_index_for_id(
		legacy_option,
		EasingCurvePoint.HandleMode.MIRRORED,
	)
	legacy_option.item_selected.emit(mirrored_index)
	await process_frame
	_expect(
		_selected_option_id(native_option) == EasingCurvePoint.HandleMode.MIRRORED,
		"Open Native Inspector did not synchronize an external preference change",
	)
	_expect(
		legacy_changes[0] == 0 and native_changes[0] == 0,
		"Changing the editor preference dirtied a curve resource",
	)
	_expect(
		int(settings.get_setting(setting_name)) == EasingCurvePoint.HandleMode.MIRRORED,
		"EditorSettings did not retain the selected handle mode",
	)

	settings.set_setting(setting_name, 999)
	_expect(
		CURVE_EDITOR_SETTINGS.get_default_new_point_handle_mode()
		== EasingCurvePoint.HandleMode.FREE,
		"Invalid stored handle mode did not fall back to Free",
	)
	legacy_editor.call("_sync_default_new_point_handle_mode")
	native_editor.call("_sync_default_new_point_handle_mode")
	_expect(
		legacy_editor.get_default_new_point_handle_mode()
		== EasingCurvePoint.HandleMode.FREE,
		"Legacy editor did not adopt the invalid-value fallback",
	)
	_expect(
		native_editor.get_default_new_point_handle_mode()
		== EasingCurvePoint.HandleMode.FREE,
		"Native editor did not adopt the invalid-value fallback",
	)

	legacy_controls.queue_free()
	native_controls.queue_free()
	legacy_editor.queue_free()
	native_editor.queue_free()
	await process_frame

	for backend_id: StringName in [&"legacy", &"native"]:
		for handle_mode: int in range(
			EasingCurvePoint.HandleMode.FREE,
			EasingCurvePoint.HandleMode.LINKED + 1,
		):
			await _test_handle_mode_creation_case(backend_id, handle_mode)

	for resource: Resource in [legacy_curve, native_curve]:
		var property_names: Array[StringName] = []
		for property: Dictionary in resource.get_property_list():
			property_names.append(property[&"name"])
		_expect(
			not property_names.has(StringName(setting_name)),
			"Editor-only handle preference leaked into a saved curve contract",
		)

	settings.set_setting(setting_name, original_value)


func _test_shared_wheel_zoom_routing() -> void:
	for backend_id: StringName in [&"legacy", &"native"]:
		if backend_id == &"native" and not ClassDB.class_exists(&"NativeEasingCurve"):
			continue
		var curve := _make_handle_mode_curve(backend_id)
		var editor := CURVE_EDITOR.new() as EasingCurveEditor
		editor._slider = ZOOM_SLIDER.instantiate()
		editor.set_curve(curve)
		editor.size = Vector2(520.0, 260.0)
		root.add_child(editor)
		await process_frame
		editor.update_view_transform()
		_expect(
			editor.mouse_force_pass_scroll_events,
			"%s graph does not pass unhandled wheel input to the Inspector" % backend_id,
		)

		var anchor := Vector2(173.0, 121.0)
		var step_before := editor._zoom_step
		var pan_before := editor.pan_offset
		editor.selected_index = 0
		editor.dragging_point = 0
		editor.dragging_control = EasingCurveEditor.ControlIndex.RIGHT
		var plain_wheel := _mouse_button(
			anchor,
			true,
			MOUSE_BUTTON_WHEEL_UP,
		)
		_expect(
			not bool(editor.call(&"_handle_wheel", plain_wheel)),
			"%s graph consumed plain wheel input" % backend_id,
		)
		_expect(
			editor._zoom_step == step_before and editor.pan_offset == pan_before,
			"%s graph changed zoom or pan for plain wheel input" % backend_id,
		)
		_expect(
			editor.selected_index == 0
			and editor.dragging_point == 0
			and editor.dragging_control == EasingCurveEditor.ControlIndex.RIGHT,
			"%s graph changed selection or active drag state for plain wheel input"
			% backend_id,
		)

		var world_before := editor.get_world_pos(anchor)
		var modified_wheel := _mouse_button(
			anchor,
			true,
			MOUSE_BUTTON_WHEEL_UP,
			true,
		)
		_expect(
			bool(editor.call(&"_handle_wheel", modified_wheel)),
			"%s graph did not consume Ctrl/Cmd+wheel" % backend_id,
		)
		_expect(
			editor._zoom_step == mini(step_before + 1, EasingCurve.ZOOM_STEPS),
			"%s graph Ctrl/Cmd+wheel did not advance exactly one zoom step"
			% backend_id,
		)
		_expect(
			editor.get_world_pos(anchor).is_equal_approx(world_before),
			"%s graph Ctrl/Cmd+wheel did not preserve the point below the cursor"
			% backend_id,
		)
		_expect(
			editor.selected_index == 0
			and editor.dragging_point == 0
			and editor.dragging_control == EasingCurveEditor.ControlIndex.RIGHT,
			"%s graph Ctrl/Cmd+wheel changed selection or active drag state"
			% backend_id,
		)

		editor._zoom_step = EasingCurve.ZOOM_STEPS
		editor.call(&"_apply_zoom_from_step")
		_expect(
			bool(editor.call(&"_handle_wheel", modified_wheel))
			and editor._zoom_step == EasingCurve.ZOOM_STEPS,
			"%s graph did not consume modified wheel input at maximum zoom"
			% backend_id,
		)
		editor._zoom_step = 0
		editor.call(&"_apply_zoom_from_step")
		var modified_wheel_down := _mouse_button(
			anchor,
			true,
			MOUSE_BUTTON_WHEEL_DOWN,
			true,
		)
		_expect(
			bool(editor.call(&"_handle_wheel", modified_wheel_down))
			and editor._zoom_step == 0,
			"%s graph did not consume modified wheel input at minimum zoom"
			% backend_id,
		)
		editor._slider.free()
		editor.queue_free()
		await process_frame


func _test_handle_mode_creation_case(
	backend_id: StringName,
	handle_mode: int,
) -> void:
	var curve := _make_handle_mode_curve(backend_id)
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	editor.size = Vector2(520.0, 260.0)
	editor.set_curve(curve)
	root.add_child(editor)
	await process_frame
	editor.set_default_new_point_handle_mode(handle_mode)

	var publications := [0]
	curve.changed.connect(func() -> void: publications[0] += 1)
	var list_point := editor.add_point_from_list()
	_expect(list_point != null, "%s Add Point did not create a point" % backend_id)
	_expect(
		int(list_point.get(&"handle_mode")) == handle_mode,
		"%s Add Point ignored handle mode %d" % [backend_id, handle_mode],
	)
	_expect(
		editor.call(&"_selected_point_resource") == list_point,
		"%s Add Point did not select the created resource" % backend_id,
	)

	var before_pending_count := _curve_point_count(curve)
	var pending_position := Vector2(0.25, 0.8)
	var pending_view := editor.get_view_pos(pending_position)
	editor._gui_input(_mouse_button(pending_view, true))
	var pending := editor.get("pending_add_point") as Resource
	_expect(pending != null, "%s graph click did not create a pending point" % backend_id)
	if pending != null:
		_expect(
			int(pending.get(&"handle_mode")) == handle_mode,
			"%s pending graph point ignored handle mode %d" % [backend_id, handle_mode],
		)
	_expect(
		_curve_point_count(curve) == before_pending_count,
		"%s pending graph point attached before release" % backend_id,
	)
	editor._gui_input(_mouse_motion(editor.get_view_pos(Vector2(0.3, 0.75))))
	var publications_before_commit: int = publications[0]
	editor._gui_input(_mouse_button(editor.get_view_pos(Vector2(0.3, 0.75)), false))
	_expect(
		_curve_point_count(curve) == before_pending_count + 1,
		"%s graph release did not commit one point" % backend_id,
	)
	_expect(
		publications[0] == publications_before_commit + 1,
		"%s graph addition did not publish exactly once" % backend_id,
	)
	var graph_point := editor.call(&"_selected_point_resource") as Resource
	_expect(graph_point == pending, "%s graph addition lost point identity" % backend_id)
	_expect(history.has_undo(), "%s graph addition did not create Undo history" % backend_id)
	history.undo()
	_expect(_curve_point_index(curve, graph_point) == -1, "%s graph-add Undo retained the point" % backend_id)
	history.redo()
	_expect(
		_curve_point_index(curve, graph_point) >= 0
		and editor.call(&"_selected_point_resource") == graph_point,
		"%s graph-add Redo lost point identity or selection" % backend_id,
	)

	editor._gui_input(_mouse_button(editor.get_view_pos(Vector2(0.7, 0.2)), true))
	_expect(editor.get("pending_add_point") != null, "%s cancellation fixture did not start" % backend_id)
	editor._gui_input(_mouse_button(editor.get_view_pos(Vector2(0.7, 0.2)), true, MOUSE_BUTTON_RIGHT))
	_expect(editor.get("pending_add_point") == null, "%s RMB did not cancel pending addition" % backend_id)

	history.clear_history(false)
	history.free()
	editor.queue_free()
	await process_frame


func _make_handle_mode_curve(backend_id: StringName) -> Resource:
	if backend_id == &"native":
		var native_curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
		native_curve.set(&"transition", 100)
		return native_curve
	var legacy_curve := EasingCurve.new()
	legacy_curve.trans_type = EasingCurve.TRANS.CUSTOM
	legacy_curve.points = [
		EasingCurvePoint.new(Vector2.ZERO),
		EasingCurvePoint.new(Vector2.ONE),
	]
	return legacy_curve


func _curve_point_count(curve: Resource) -> int:
	return curve.points.size() if curve is EasingCurve else int(curve.call(&"get_point_count"))


func _curve_point_index(curve: Resource, point: Resource) -> int:
	if curve is EasingCurve:
		return curve.points.find(point)
	return (curve.call(&"get_points") as Array).find(point)


func _option_index_for_id(option: OptionButton, item_id: int) -> int:
	for index in range(option.item_count):
		if option.get_item_id(index) == item_id:
			return index
	return -1


func _selected_option_id(option: OptionButton) -> int:
	return option.get_item_id(option.selected)


func _test_legacy_selection_path() -> void:
	var curve := EasingCurve.new()
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	editor.set_curve(curve)
	root.add_child(editor)
	_expect(
		editor.focus_mode == Control.FOCUS_NONE,
		"Curve graph still takes focus and can scroll the Inspector on handle clicks",
	)
	_expect(editor.get_backend_id() == &"legacy", "Curve Editor did not select the legacy backend")
	_expect(editor.select_point(curve.points[0]), "Curve Editor could not select a legacy point")
	_expect(editor.selected_index == 0, "legacy point selection index changed")
	editor.queue_free()


func _test_native_selection_and_point_options() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		_expect(false, "NativeEasingCurve is unavailable")
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var point := curve.call(&"get_point", 0) as Resource
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	editor.set_curve(curve)
	root.add_child(editor)
	_expect(editor.get_backend_id() == &"native", "Curve Editor did not select the Native backend")
	_expect(editor.select_point(point), "Curve Editor could not select a Native point")
	_expect(editor.selected_index == 0, "Native point selection index changed")

	var change_count := [0]
	curve.changed.connect(func(): change_count[0] += 1)
	editor.call(
		&"_on_point_toolbar_control_state_selected",
		EasingCurvePoint.ControlState.LINEAR,
		EasingCurvePoint.ControlSide.RIGHT,
	)
	_expect(point.get(&"right_force_linear"), "Native Force Linear was not applied from the shared toolbar")
	_expect(change_count[0] == 1, "Native Force Linear amplified curve change signals")

	editor.call(
		&"_on_point_toolbar_control_state_selected",
		EasingCurvePoint.ControlState.LOCKED,
		EasingCurvePoint.ControlSide.RIGHT,
	)
	var locks := point.get(&"locked") as Dictionary
	_expect(locks[&"right_control_point"], "Native lock was not applied from the shared toolbar")
	_expect(not point.get(&"right_force_linear"), "Native lock did not clear Force Linear")
	_expect(change_count[0] == 2, "Native locking amplified curve change signals")

	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	editor.call(
		&"_on_point_toolbar_handle_mode_selected",
		EasingCurvePoint.HandleMode.MIRRORED,
	)
	_expect(
		editor.call(&"_selected_point_resource") == point,
		"Native Handle Mode change cleared the selected point",
	)
	var handle_mode_option := editor.get("_point_handle_mode") as OptionButton
	_expect(
		handle_mode_option != null and handle_mode_option.self_modulate.a > 0.0,
		"Native Handle Mode change hid the selected-point toolbar",
	)
	history.undo()
	_expect(
		editor.call(&"_selected_point_resource") == point,
		"Native Handle Mode Undo cleared the selected point",
	)
	history.redo()
	_expect(
		editor.call(&"_selected_point_resource") == point,
		"Native Handle Mode Redo cleared the selected point",
	)

	curve.set(&"transition", 0)
	_expect(not editor.call(&"_is_point_toolbar_hidden"), "Native editable preset hid point options")
	editor.queue_free()


func _test_native_bezier_transform_preview() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var first := curve.call(&"get_point", 0) as Resource
	var last := curve.call(&"get_point", 1) as Resource
	first.set(&"right_control_point", Vector2(0.2, 0.4))
	last.set(&"position", Vector2(1.0, 0.8))
	last.set(&"left_control_point", Vector2(0.7, 0.6))

	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	editor.set_curve(curve)
	editor.size = Vector2(520.0, 260.0)
	root.add_child(editor)
	editor.update_view_transform()

	curve.set(&"reverse", true)
	curve.set(&"invert", true)
	var display_points := editor.call(&"_get_display_points") as Array
	_expect(
		display_points == [last, first],
		"Native Reverse preview did not reverse displayed point order",
	)
	editor.select_point(last)
	editor.call(&"_request_point_move_down")
	_expect(
		editor.call(&"_selected_point_resource") == first,
		"Native Reverse preview navigation did not follow displayed point order",
	)
	var backend := editor.get("_backend") as RefCounted
	_expect(
		(backend.call(&"curve_to_display_position", last.get(&"position")) as Vector2).is_equal_approx(Vector2(0.0, 0.2)),
		"Native Reverse/Invert preview did not transform point geometry",
	)
	_expect(
		(backend.call(&"get_display_control_point", last, EasingCurvePoint.ControlSide.RIGHT) as Vector2).is_equal_approx(Vector2(0.3, 0.4)),
		"Native Reverse/Invert preview did not swap and transform handles",
	)
	var displayed_last_control := Vector2(0.3, 0.4)
	var control_hit := editor.get_control_at(
		editor.get_view_pos(displayed_last_control)
	)
	_expect(
		control_hit == [1, EasingCurveEditor.ControlIndex.LEFT],
		"Native transformed handle hit-testing did not map back to the stored side",
	)
	var transformed_first := backend.call(
		&"curve_to_display_position",
		first.get(&"position"),
	) as Vector2
	_expect(
		editor.get_point_at(editor.get_view_pos(transformed_first)) == 0,
		"Native transformed preview hit-testing lost point identity",
	)
	var drag_target := Vector2(0.8, 0.75)
	editor._gui_input(_mouse_button(editor.get_view_pos(transformed_first), true))
	editor._gui_input(_mouse_motion(editor.get_view_pos(drag_target)))
	editor._gui_input(_mouse_button(editor.get_view_pos(drag_target), false))
	_expect(
		(first.get(&"position") as Vector2).is_equal_approx(Vector2(0.2, 0.25)),
		"Native transformed point drag did not map back to stored coordinates",
	)
	_expect(
		editor.call(&"_selected_point_resource") == first,
		"Native transformed point drag lost selection identity",
	)
	editor.queue_free()


func _test_native_inspector_path() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	var snapshot_property := POINTS_EDITOR_PROPERTY.new() as EditorProperty
	snapshot_property.set_object_and_property(curve, &"_editor_state_snapshot")
	var revert_update := {&"received": false, &"can_revert": true}
	snapshot_property.property_can_revert_changed.connect(
		func(property_name: StringName, can_revert: bool) -> void:
			if property_name == &"_editor_state_snapshot":
				revert_update[&"received"] = true
				revert_update[&"can_revert"] = can_revert
	)
	snapshot_property.call(&"set_content", Control.new())
	_expect(
		revert_update[&"received"] and not revert_update[&"can_revert"],
		"Native snapshot bridge did not suppress its floating revert control",
	)
	snapshot_property.free()

	var conversion_control := CURVE_CONVERSION_CONTROL.new() as Control
	conversion_control.call(&"setup", curve)
	var conversion_dialog := conversion_control.get("_dialog") as ConfirmationDialog
	var conversion_opens_deferred := false
	for connection: Dictionary in conversion_dialog.get_signal_connection_list(&"confirmed"):
		if int(connection.get(&"flags", 0)) & CONNECT_DEFERRED:
			conversion_opens_deferred = true
	_expect(
		conversion_opens_deferred,
		"Conversion resource opening was not deferred past the confirmation signal",
	)
	conversion_control.free()

	var inspector := INSPECTOR_PLUGIN.new()
	_expect(inspector._can_handle(curve), "Inspector plugin rejected NativeEasingCurve")
	var content := inspector.handle_easing_curve_editor(curve)
	_expect(content != null, "Inspector plugin did not build the Native Curve Editor")
	if content != null:
		root.add_child(content)
		var points_section := inspector.call("_handle_native_points", curve) as Control
		root.add_child(points_section)
		var preset_toolbar := content.find_child("CurvePresetToolbar", true, false)
		var ease_control := content.find_child("CurveEase", true, false) as OptionButton
		var trans_control := content.find_child("CurveTransition", true, false) as OptionButton
		_expect(
			preset_toolbar != null and ease_control != null and trans_control != null,
			"Native Inspector did not mirror the legacy Ease/Trans header",
		)
		_expect(
			_find_label_starting_with(content, "Preset geometry") == null,
			"Native Inspector retained the standalone preset-geometry label",
		)
		if trans_control != null:
			var custom_index := trans_control.get_item_index(100)
			var linear_index := trans_control.get_item_index(0)
			_expect(
				custom_index >= 0
				and linear_index >= 0
				and trans_control.get_item_text(custom_index) == "Custom"
				and trans_control.get_item_text(linear_index) == "Linear",
				"Native Trans dropdown used legacy transition IDs",
			)
		var editor := _find_curve_editor(content)
		_expect(editor != null, "Native Inspector content omitted the shared Curve Editor")
		if editor != null:
			_expect(editor.get_backend_id() == &"native", "Native Inspector used the wrong backend")
			var add_button := _find_button(content, "Add Point")
			_expect(add_button != null, "Native Curve Editor omitted its Add Point control")
			var add_controls := content.find_child("PointAddControls", true, false)
			_expect(
				add_controls != null
					and add_controls.get_index() == add_controls.get_parent().get_child_count() - 1,
				"Native Add Point controls were not last in the Curve Editor section",
			)
			_expect(
				_find_button(points_section, "Add Point") == null,
				"Native Points section retained its Add Point control",
			)
			_expect(_find_drag_handle(points_section) != null, "Native point list omitted the legacy drag handle")
			var first_point := curve.call(&"get_point", 0) as Resource
			var first_panel: Node = inspector.get("_native_points_content").get_child(0)
			var position_inputs := first_panel.find_children("*", "EditorSpinSlider", true, false)
			if not position_inputs.is_empty():
				var typed_input := position_inputs[0] as EditorSpinSlider
				var live_publications := [0]
				editor.committed_change_publisher = func() -> void:
					live_publications[0] += 1
				typed_input.value_focus_entered.emit()
				typed_input.value = 0.05
				_expect(
					live_publications[0] == 0,
					"Native typed point value published before entry was accepted",
				)
				typed_input.value_focus_exited.emit()
				await process_frame
				_expect(
					live_publications[0] == 1,
					"Native typed point value did not publish one accepted edit",
				)
			var original_position: Vector2 = first_point.get(&"position")
			var preview_position := original_position + Vector2(0.0, 0.2)
			editor.edit_point_property(0, &"position", preview_position, true)
			_expect(
				editor.get("position_x_order_preview_point") == first_point,
				"Native point-list drag did not enable graph-order preview",
			)
			_expect(
				(editor.call(&"_get_display_points") as Array).has(first_point),
				"Native point-list drag omitted the edited point from graph preview",
			)
			editor.finish_point_list_edit(first_point, &"position")
			_expect(
				editor.get("position_x_order_preview_point") == null,
				"Native point-list drag retained stale graph-order preview state",
			)
			_expect(
				not inspector.get("_native_points_refresh_queued")
				and inspector.get("_native_points_content").get_child(0) == first_panel,
				"Native geometry commit rebuilt the entire point list",
			)
			if add_button != null:
				var before_count: int = curve.call(&"get_point_count")
				add_button.pressed.emit()
				_expect(curve.call(&"get_point_count") == before_count + 1, "Native point-list Add did not use the shared backend")
		await process_frame
		points_section.free()
	content.free()

	curve.set(&"transition", 102)
	var generated_content := inspector.handle_easing_curve_editor(curve)
	root.add_child(generated_content)
	var generate_controls := generated_content.find_child("GenerateControls", true, false)
	_expect(
		generate_controls != null
			and generate_controls.get_index() == generate_controls.get_parent().get_child_count() - 1
			and _find_button(generate_controls, "Generate") != null,
		"Native Generate control was not last in the Curve Editor section",
	)
	generated_content.free()


func _test_native_deferred_parameter_editor() -> void:
	await _test_native_deferred_parameter_case(
		NativeEasingCurve.TRANS_BOUNCE,
		&"bounce_damping",
		60.0,
		45.0,
		37.5,
		false,
	)
	await _test_native_deferred_parameter_case(
		NativeEasingCurve.TRANS_CONSTANT,
		&"constant_value",
		0.25,
		0.75,
		0.4,
		true,
	)
	await _test_native_deferred_parameter_case(
		NativeEasingCurve.TRANS_BACK,
		&"overshoot",
		2.1,
		3.2,
		1.4,
		true,
	)


func _test_native_deferred_parameter_case(
		transition: int,
		property_name: StringName,
		preview_value: float,
		final_value: float,
		typed_value: float,
		expects_point_publication: bool,
) -> void:
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", transition)
	var native_editor := EditorProperty.new()
	var input := EditorSpinSlider.new()
	input.min_value = 0.0
	input.max_value = 100.0
	input.step = 0.01
	native_editor.add_child(input)
	var property_editor := DEFERRED_PARAMETER_EDITOR_PROPERTY.new() as EditorProperty
	_expect(
		property_editor.call(&"setup", native_editor, property_name, null, null),
		"Native %s did not create a deferred slider editor" % property_name,
	)
	property_editor.set_object_and_property(curve, property_name)
	root.add_child(property_editor)
	var applied_edits := [0]
	var curve_publications := [0]
	var point_publications := [0]
	property_editor.property_changed.connect(
		func(property: StringName, value: Variant, _field: StringName, _changing: bool) -> void:
			applied_edits[0] += 1
			curve.set(property, value)
	)
	curve.changed.connect(func() -> void: curve_publications[0] += 1)
	curve.connect(&"points_changed", func(_points: Array) -> void: point_publications[0] += 1)

	input.grabbed.emit()
	input.value = preview_value
	input.value = final_value
	_expect(is_equal_approx(curve.get(property_name), final_value), "Native parameter drag did not update its local preview value")
	_expect(applied_edits[0] == 0, "Native parameter drag published through the Inspector before release")
	_expect(curve_publications[0] == 0, "Native parameter drag published a Resource change before release")
	_expect(point_publications[0] == 0, "Native Bézier parameter drag published point geometry before release")
	input.ungrabbed.emit()
	await process_frame
	_expect(applied_edits[0] == 1, "Native parameter drag did not publish exactly once on release")
	_expect(curve_publications[0] == 1, "Native parameter drag did not publish one Resource change on release")
	_expect(
		point_publications[0] == int(expects_point_publication),
		"Native parameter drag published the wrong number of point changes on release",
	)
	_expect(is_equal_approx(curve.get(property_name), final_value), "Native parameter drag release lost its final value")

	input.value = typed_value
	_expect(applied_edits[0] == 2, "Native typed parameter value did not publish immediately")
	_expect(curve_publications[0] == 2, "Native typed parameter value did not publish one Resource change")
	_expect(
		point_publications[0] == int(expects_point_publication) * 2,
		"Native typed parameter value published the wrong number of point changes",
	)
	_expect(is_equal_approx(curve.get(property_name), typed_value), "Native typed parameter value was not applied")
	property_editor.free()


func _test_native_property_clipboard_and_lifecycle() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var point := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	point.set(&"position", Vector2(0.5, 0.5))
	point.set(&"left_control_point", Vector2(0.35, 0.45))
	point.set(&"right_control_point", Vector2(0.65, 0.55))
	_expect(bool(curve.call(&"insert_point", 1, point)), "Native clipboard fixture rejected its middle point")

	var inspector := INSPECTOR_PLUGIN.new()
	var content := inspector.handle_easing_curve_editor(curve)
	root.add_child(content)
	var points_section := inspector.call("_handle_native_points", curve) as Control
	root.add_child(points_section)
	var editor := _find_curve_editor(content)
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	var publications := [0]
	editor.committed_change_publisher = func() -> void:
		publications[0] += 1

	for property_name: StringName in [
		&"position",
		&"handle_mode",
		&"left_control_point",
		&"right_control_point",
	]:
		var header := _find_native_property_header(points_section, point, property_name)
		_expect(header != null, "Native point list omitted selectable %s" % property_name)
		if header == null:
			continue
		header.gui_input.emit(_mouse_button(Vector2.ZERO, true))
		_expect(
			int(inspector.get("_point_list_controller").get("selected_point_resource_id"))
			== point.get_instance_id(),
			"Native %s selection did not retain point identity" % property_name,
		)
		_expect(
			StringName(inspector.get("_point_list_controller").get("selected_point_property_name"))
			== property_name,
			"Native %s selection did not retain the property name" % property_name,
		)
		_expect(
			inspector.get("_selected_point_property_header") == header,
			"Native %s selection did not attach its property highlight" % property_name,
		)
		_expect(
			editor.get_selected_point_resource() == point,
			"Native %s selection did not synchronize the graph" % property_name,
		)
		var menu := _find_popup_menu(header)
		_expect(
			menu != null
			and _popup_has_item(menu, "Copy Value")
			and _popup_has_item(menu, "Paste Value")
			and _popup_has_item(menu, "Copy Property Path"),
			"Native %s property menu is incomplete" % property_name,
		)

	var shortcut_focus := points_section.find_children("*", "Button", true, false)[0] as Button
	shortcut_focus.grab_focus()
	var shortcut_counts := {&"copy": 0, &"paste": 0, &"path": 0}
	points_section.set(&"copy_value_callback", func() -> void: shortcut_counts[&"copy"] += 1)
	points_section.set(&"paste_value_callback", func() -> void: shortcut_counts[&"paste"] += 1)
	points_section.set(&"copy_path_callback", func() -> void: shortcut_counts[&"path"] += 1)
	points_section.set(&"can_paste_callback", func() -> bool: return true)
	for shortcut in [
		{&"key": KEY_C, &"shift": false, &"counter": &"copy"},
		{&"key": KEY_V, &"shift": false, &"counter": &"paste"},
		{&"key": KEY_C, &"shift": true, &"counter": &"path"},
	]:
		var event := InputEventKey.new()
		event.pressed = true
		event.ctrl_pressed = true
		event.shift_pressed = shortcut[&"shift"]
		event.keycode = shortcut[&"key"]
		points_section.call(&"_input", event)
		_expect(shortcut_counts[shortcut[&"counter"]] == 1, "Native Points shortcut did not route %s" % shortcut[&"counter"])
	var command_copy := InputEventKey.new()
	command_copy.pressed = true
	command_copy.meta_pressed = true
	command_copy.keycode = KEY_C
	points_section.call(&"_input", command_copy)
	_expect(shortcut_counts[&"copy"] == 2, "Native Points shortcut did not accept Cmd+C")

	var handle_header := _find_native_property_header(points_section, point, &"handle_mode")
	handle_header.gui_input.emit(_mouse_button(Vector2.ZERO, true))
	var original_point := point
	var original_mode := int(point.get(&"handle_mode"))
	inspector.call(
		"_apply_pasted_point_property_value",
		1,
		&"handle_mode",
		EasingCurvePoint.HandleMode.BALANCED,
	)
	_expect(int(point.get(&"handle_mode")) == EasingCurvePoint.HandleMode.BALANCED, "Native Handle Mode paste was not applied")
	_expect(history.get_history_count() == 1, "Native paste did not create exactly one Undo action")
	_expect(publications[0] == 1, "Native paste did not publish exactly once")
	_expect(curve.call(&"get_point", 1) == original_point, "Native paste replaced point identity")
	history.undo()
	_expect(int(point.get(&"handle_mode")) == original_mode, "Native paste Undo did not restore the value")
	history.redo()
	_expect(int(point.get(&"handle_mode")) == EasingCurvePoint.HandleMode.BALANCED, "Native paste Redo did not restore the value")

	var history_before_invalid := history.get_history_count()
	var publications_before_invalid: int = publications[0]
	inspector.call("_apply_pasted_point_property_value", 1, &"handle_mode", 99)
	inspector.call("_apply_pasted_point_property_value", 1, &"position", 0.25)
	_expect(history.get_history_count() == history_before_invalid, "Invalid Native paste created Undo history")
	_expect(publications[0] == publications_before_invalid, "Invalid Native paste published a change")

	var clipboard_supported := DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	var original_clipboard := DisplayServer.clipboard_get() if clipboard_supported else ""
	if clipboard_supported:
		inspector.call("_copy_point_property_value", 1, &"handle_mode")
		_expect(DisplayServer.clipboard_get() == var_to_str(EasingCurvePoint.HandleMode.BALANCED), "Native Copy Value changed the shared serialized format")

		var legacy_curve := _make_handle_mode_curve(&"legacy") as EasingCurve
		var legacy_inspector := INSPECTOR_PLUGIN.new()
		var legacy_content := legacy_inspector.handle_easing_curve_editor(legacy_curve)
		legacy_inspector.call("_paste_point_property_value", 1, &"handle_mode")
		_expect(legacy_curve.points[1].handle_mode == EasingCurvePoint.HandleMode.BALANCED, "Native-to-Legacy clipboard paste failed")

		legacy_curve.points[1].handle_mode = EasingCurvePoint.HandleMode.LINEAR
		legacy_inspector.call("_copy_point_property_value", 1, &"handle_mode")
		inspector.call("_paste_point_property_value", 1, &"handle_mode")
		_expect(int(point.get(&"handle_mode")) == EasingCurvePoint.HandleMode.LINEAR, "Legacy-to-Native clipboard paste failed")

		editor.move_point_from_list(1, 2)
		var current_index := (curve.call(&"get_points") as Array).find(point)
		inspector.call("_copy_point_property_path", current_index, &"handle_mode")
		_expect(DisplayServer.clipboard_get() == "points/%d/handle_mode" % current_index, "Native Copy Property Path retained a stale pre-reorder index")
		DisplayServer.clipboard_set(original_clipboard)
		legacy_content.free()

	history.clear_history()
	publications[0] = 0
	var point_panel := inspector.get("_native_points_content").get_child(1) as Control
	var inputs := point_panel.find_children("*", "EditorSpinSlider", true, false)
	_expect(not inputs.is_empty(), "Native lifecycle fixture omitted its vector input")
	if not inputs.is_empty():
		var input := inputs[0] as EditorSpinSlider
		input.grabbed.emit()
		input.value = input.value + 0.05
		input.ungrabbed.emit()
		input.value_focus_entered.emit()
		_expect(bool(editor.get("_backend_point_edit_active")), "Native focus handoff closed the edit before text entry")
		_expect(publications[0] == 0, "Native focus handoff published before commit")
		input.value_focus_exited.emit()
		inspector.call("_refresh_native_point_list", curve)
		await process_frame
		_expect(not bool(editor.get("_backend_point_edit_active")), "Native deferred edit survived a point-list rebuild")
		_expect(publications[0] == 1, "Native rebuilt-row edit did not publish exactly once")

		point_panel = inspector.get("_native_points_content").get_child(1) as Control
		inputs = point_panel.find_children("*", "EditorSpinSlider", true, false)
		input = inputs[0] as EditorSpinSlider
		input.value_focus_entered.emit()
		input.value = input.value + 0.05
		input.value_focus_exited.emit()
		var add_button := _find_button(content, "Add Point")
		var count_before_add: int = curve.call(&"get_point_count")
		add_button.pressed.emit()
		var publications_after_add: int = publications[0]
		await process_frame
		_expect(curve.call(&"get_point_count") == count_before_add + 1, "Queued Native edit blocked point addition")
		_expect(publications_after_add == publications[0], "Stale Native deferred finish published after point addition")
		_expect(not bool(editor.get("_backend_point_edit_active")), "Native topology action retained an active value transaction")

	var disposal_panel := inspector.get("_native_points_content").get_child(1) as Control
	var disposal_inputs := disposal_panel.find_children("*", "EditorSpinSlider", true, false)
	_expect(not disposal_inputs.is_empty(), "Native disposal fixture omitted its vector input")
	if not disposal_inputs.is_empty():
		var disposal_input := disposal_inputs[0] as EditorSpinSlider
		disposal_input.value_focus_entered.emit()
		disposal_input.value = disposal_input.value + 0.05
		disposal_input.value_focus_exited.emit()
		var publications_before_disposal: int = publications[0]
		var replacement_curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
		inspector.call("_parse_begin", replacement_curve)
		content.free()
		await process_frame
		_expect(
			publications[0] == publications_before_disposal + 1,
			"Native editor disposal did not finish its active edit exactly once",
		)
	else:
		content.free()
	points_section.free()

	history.clear_history(false)
	history.free()


func _find_native_property_header(
	parent: Control,
	point: Resource,
	property_name: StringName,
) -> PanelContainer:
	for node in parent.find_children("*", "PanelContainer", true, false):
		var panel := node as PanelContainer
		if (
			panel.has_meta(&"point_resource_id")
			and int(panel.get_meta(&"point_resource_id")) == point.get_instance_id()
			and StringName(panel.get_meta(&"point_property_name")) == property_name
		):
			return panel
	return null


func _find_popup_menu(parent: Node) -> PopupMenu:
	for child in parent.get_children():
		if child is PopupMenu:
			return child
	return null


func _popup_has_item(menu: PopupMenu, text: String) -> bool:
	for index in range(menu.item_count):
		if menu.get_item_text(index) == text:
			return true
	return false


func _find_label_starting_with(root_control: Control, prefix: String) -> Label:
	for node in root_control.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.text.begins_with(prefix):
			return label
	return null


func _test_native_geometry_gestures() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var point := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	point.set(&"position", Vector2(0.5, 0.5))
	point.set(&"left_control_point", Vector2(0.4, 0.45))
	point.set(&"right_control_point", Vector2(0.6, 0.55))
	_expect(bool(curve.call(&"insert_point", 1, point)), "Native interior point fixture was rejected")
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	var live_publications := [0]
	editor.committed_change_publisher = func(): live_publications[0] += 1
	editor.set_curve(curve)
	editor.size = Vector2(520.0, 260.0)
	root.add_child(editor)
	editor.update_view_transform()

	var original_position := point.get(&"position") as Vector2
	var original_left := point.get(&"left_control_point") as Vector2
	var original_right := point.get(&"right_control_point") as Vector2
	point.set(&"right_control_point", Vector2(0.6, 3.5))
	var native_bounds := editor.call(&"_get_autofit_world_bounds") as Rect2
	_expect(native_bounds.end.y >= 3.5, "Native Autofit bounds ignored a visible control handle")
	point.set(&"right_control_point", original_right)
	var target_position := Vector2(0.55, 0.6)
	var position_delta := target_position - original_position
	var start_view := editor.get_view_pos(original_position)
	var intermediate_view := editor.get_view_pos(Vector2(0.525, 0.55))
	var target_view := editor.get_view_pos(target_position)
	var change_count := [0]
	curve.changed.connect(func(): change_count[0] += 1)
	editor._gui_input(_mouse_button(start_view, true))
	editor._gui_input(_mouse_motion(intermediate_view))
	_expect(bool(editor.get("_backend_point_edit_active")), "Native point drag did not open one backend transaction")
	editor._gui_input(_mouse_motion(target_view))
	editor._gui_input(_mouse_button(target_view, false))
	_expect(point.get(&"position").is_equal_approx(target_position), "Native point drag did not update geometry")
	_expect(
		point.get(&"left_control_point").is_equal_approx(original_left + position_delta),
		"Native point drag did not translate its left handle once",
	)
	_expect(
		point.get(&"right_control_point").is_equal_approx(original_right + position_delta),
		"Native point drag did not translate its right handle once",
	)
	_expect(not bool(editor.get("_backend_point_edit_active")), "Native point drag did not close its backend transaction")
	_expect(change_count[0] == 1, "Native point drag did not defer publication to release")
	_expect(live_publications[0] == 1, "Native point drag did not publish one live-edit snapshot")
	_expect(history.has_undo(), "Native point drag did not create an Undo action")
	history.undo()
	_expect(point.get(&"position").is_equal_approx(original_position), "Native point drag Undo did not restore geometry")
	_expect(live_publications[0] == 2, "Native point drag Undo did not publish one live-edit snapshot")
	_expect(not history.has_undo() and history.has_redo(), "Native point drag created more than one Undo action")
	history.redo()
	_expect(point.get(&"position").is_equal_approx(target_position), "Native point drag Redo did not restore geometry")
	_expect(live_publications[0] == 3, "Native point drag Redo did not publish one live-edit snapshot")

	history.clear_history()
	var original_control := point.get(&"right_control_point") as Vector2
	var target_control := target_position + Vector2(0.25, 0.2)
	start_view = editor.get_view_pos(original_control)
	target_view = editor.get_view_pos(target_control)
	editor._gui_input(_mouse_button(start_view, true))
	editor._gui_input(_mouse_motion(target_view))
	editor._gui_input(_mouse_button(target_view, false))
	_expect(point.get(&"right_control_point").is_equal_approx(target_control), "Native handle drag did not update geometry")
	_expect(history.has_undo(), "Native handle drag did not create an Undo action")
	history.undo()
	_expect(point.get(&"right_control_point").is_equal_approx(original_control), "Native handle drag Undo did not restore geometry")
	_expect(not history.has_undo() and history.has_redo(), "Native handle drag created more than one Undo action")
	history.redo()
	_expect(point.get(&"right_control_point").is_equal_approx(target_control), "Native handle drag Redo did not restore geometry")

	point.call(&"set_locked", &"position", true)
	history.clear_history()
	start_view = editor.get_view_pos(target_position)
	target_view = editor.get_view_pos(Vector2(0.4, 0.4))
	editor._gui_input(_mouse_button(start_view, true))
	editor._gui_input(_mouse_motion(target_view))
	editor._gui_input(_mouse_button(target_view, false))
	_expect(point.get(&"position").is_equal_approx(target_position), "Native position lock did not block graph dragging")
	_expect(not history.has_undo(), "Blocked Native point drag created an Undo action")
	editor.queue_free()


func _test_native_existing_point_endpoint_takeover() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var middle := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	middle.set(&"position", Vector2(0.5, 0.5))
	middle.set(&"left_control_point", Vector2(0.4, 0.5))
	middle.set(&"right_control_point", Vector2(0.6, 0.5))
	curve.call(&"insert_point", 1, middle)
	var old_right := curve.call(&"get_point", 2) as Resource
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	editor.set_curve(curve)
	editor.size = Vector2(520.0, 260.0)
	root.add_child(editor)
	editor.update_view_transform()
	var start_view := editor.get_view_pos(middle.get(&"position"))
	var endpoint_view := editor.get_view_pos(Vector2(1.0, 0.75))
	editor._gui_input(_mouse_button(start_view, true))
	editor._gui_input(_mouse_motion(endpoint_view))
	editor._gui_input(_mouse_button(endpoint_view, false))
	_expect(curve.call(&"get_point_count") == 2, "Native point drag to x=1 retained the old endpoint")
	_expect(curve.call(&"get_point", 1) == middle, "Native point drag endpoint takeover lost point identity")
	_expect((curve.call(&"get_points") as Array).find(old_right) == -1, "Native point drag did not detach the displaced endpoint")
	_expect(editor.selected_index == 1, "Native point drag endpoint takeover lost selection")
	_expect(history.has_undo(), "Native point drag endpoint takeover omitted Undo history")
	history.undo()
	_expect(curve.call(&"get_point_count") == 3, "Native endpoint takeover Undo did not restore the displaced endpoint")
	_expect(curve.call(&"get_point", 1) == middle and curve.call(&"get_point", 2) == old_right, "Native endpoint takeover Undo lost resource identity")
	history.redo()
	_expect(curve.call(&"get_point_count") == 2 and curve.call(&"get_point", 1) == middle, "Native endpoint takeover Redo failed")
	editor.queue_free()


func _test_native_add_delete_and_endpoint_topology() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	editor.set_curve(curve)
	editor.size = Vector2(520.0, 260.0)
	root.add_child(editor)
	editor.update_view_transform()

	var add_world := Vector2(0.35, 0.4)
	var add_view := editor.get_view_pos(add_world)
	editor._gui_input(_mouse_button(add_view, true))
	var cancelled_point := editor.get(&"pending_add_point") as Resource
	_expect(cancelled_point != null, "Native pending add did not create a backend point")
	_expect(curve.call(&"get_point_count") == 2, "Native pending add mutated topology before release")
	editor.notification(Control.NOTIFICATION_FOCUS_EXIT)
	_expect(editor.get(&"pending_add_point") == null, "Native focus exit retained a stale pending point")
	editor._gui_input(_mouse_button(add_view, true))
	cancelled_point = editor.get(&"pending_add_point") as Resource
	_expect(cancelled_point != null, "Native pending add could not restart after focus exit")
	editor._gui_input(_mouse_button(add_view, true, MOUSE_BUTTON_RIGHT))
	_expect(editor.get(&"pending_add_point") == null, "Native RMB did not cancel pending add")
	_expect(not history.has_undo(), "Native pending-add cancellation created Undo history")

	var changes := [0]
	curve.changed.connect(func() -> void: changes[0] += 1)
	editor._gui_input(_mouse_button(add_view, true))
	var added_point := editor.get(&"pending_add_point") as Resource
	editor._gui_input(_mouse_button(add_view, false))
	_expect(curve.call(&"get_point_count") == 3, "Native click add did not commit topology")
	_expect(editor.selected_index == 1 and curve.call(&"get_point", 1) == added_point, "Native click add lost point identity or selection")
	_expect(changes[0] == 1, "Native click add published more than once")
	_expect(history.has_undo(), "Native click add did not create Undo history")
	history.undo()
	_expect(curve.call(&"get_point_count") == 2, "Native click-add Undo did not remove the point")
	_expect(editor.selected_index == -1, "Native click-add Undo did not restore selection")
	_expect(not history.has_undo() and history.has_redo(), "Native click add created more than one Undo action")
	history.redo()
	_expect(curve.call(&"get_point", 1) == added_point, "Native click-add Redo recreated point identity")
	_expect(editor.selected_index == 1, "Native click-add Redo did not restore point selection")

	history.clear_history()
	add_view = editor.get_view_pos(added_point.get(&"position"))
	editor._gui_input(_mouse_button(add_view, true))
	editor._gui_input(_mouse_button(add_view, false))
	_expect(not history.has_undo(), "Native no-op point release created Undo history")

	var old_left := curve.call(&"get_point", 0) as Resource
	var endpoint_start_view := editor.get_view_pos(Vector2(0.2, 0.7))
	var endpoint_view := editor.get_view_pos(Vector2(0.0, 0.7))
	history.clear_history()
	editor._gui_input(_mouse_button(endpoint_start_view, true))
	var replacement := editor.get(&"pending_add_point") as Resource
	editor._gui_input(_mouse_motion(endpoint_view))
	changes[0] = 0
	editor._gui_input(_mouse_button(endpoint_view, false))
	_expect(curve.call(&"get_point_count") == 3, "Native endpoint takeover changed the point count")
	_expect(curve.call(&"get_point", 0) == replacement, "Native endpoint takeover lost the replacement resource")
	_expect(curve.call(&"get_points").find(old_left) == -1, "Native endpoint takeover retained the displaced endpoint")
	_expect(changes[0] == 1, "Native endpoint takeover published more than once")

	var selected_point := curve.call(&"get_point", 2) as Resource
	editor.select_point(selected_point)
	var delete_point := curve.call(&"get_point", 1) as Resource
	var delete_view := editor.get_view_pos(delete_point.get(&"position"))
	history.clear_history()
	changes[0] = 0
	editor.set_position_x_order_preview(delete_point)
	editor._gui_input(_mouse_button(delete_view, true, MOUSE_BUTTON_RIGHT))
	editor._gui_input(_mouse_button(delete_view, false, MOUSE_BUTTON_RIGHT))
	_expect(curve.call(&"get_point_count") == 2, "Native RMB delete did not remove the point")
	_expect(editor.get("position_x_order_preview_point") == null, "Native deletion retained a detached preview point")
	_expect(not (editor.call(&"_get_display_points") as Array).has(delete_point), "Native graph retained a deleted point")
	_expect(editor.selected_index == 1 and curve.call(&"get_point", 1) == selected_point, "Native RMB delete did not preserve shifted selection identity")
	_expect(changes[0] == 1, "Native RMB delete published more than once")
	_expect(not editor.is_right_delete_dragging, "Native RMB release retained stale drag state")
	history.undo()
	_expect(curve.call(&"get_point", 1) == delete_point, "Native RMB-delete Undo recreated point identity")
	_expect(editor.selected_index == 2 and curve.call(&"get_point", 2) == selected_point, "Native RMB-delete Undo lost selection identity")
	history.redo()
	_expect(editor.selected_index == 1 and curve.call(&"get_point", 1) == selected_point, "Native RMB-delete Redo lost selection identity")

	history.clear_history()
	delete_view = editor.get_view_pos(selected_point.get(&"position"))
	editor._gui_input(_mouse_button(delete_view, true, MOUSE_BUTTON_RIGHT))
	editor._gui_input(_mouse_button(delete_view, false, MOUSE_BUTTON_RIGHT))
	_expect(editor.selected_index == -1, "Deleting the selected Native point did not clear selection")
	history.undo()
	_expect(editor.selected_index == 1 and curve.call(&"get_point", 1) == selected_point, "Selected-point delete Undo lost selection identity")
	history.redo()
	_expect(editor.selected_index == -1, "Selected-point delete Redo did not clear selection")
	editor.queue_free()


func _test_native_point_list_swap_parity() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var first := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	first.set(&"position", Vector2(0.25, 0.3))
	first.set(&"left_control_point", Vector2(0.15, 0.2))
	first.set(&"right_control_point", Vector2(0.35, 0.4))
	first.call(&"set_locked", &"left_control_point", true)
	first.call(&"set_locked", &"right_control_point", true)
	var middle := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	middle.set(&"position", Vector2(0.5, 0.5))
	var last := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	last.set(&"position", Vector2(0.75, 0.7))
	last.set(&"left_control_point", Vector2(0.65, 0.6))
	last.set(&"right_control_point", Vector2(0.85, 0.8))
	curve.call(&"insert_point", 1, first)
	curve.call(&"insert_point", 2, middle)
	curve.call(&"insert_point", 3, last)
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	editor.set_curve(curve)
	root.add_child(editor)
	var first_state := first.call(&"capture_state") as Dictionary
	var last_state := last.call(&"capture_state") as Dictionary
	editor.move_point_from_list(1, 3)
	_expect(curve.call(&"get_point", 1) == last, "Native list swap did not move the target resource to the source slot")
	_expect(curve.call(&"get_point", 2) == middle, "Native list swap shifted an unrelated point")
	_expect(curve.call(&"get_point", 3) == first, "Native list swap lost the dragged resource")
	_expect(editor.get_selected_point_resource() == first, "Native list swap lost selection identity")
	_expect(_state_was_horizontally_translated(first, first_state, 0.75), "Native list swap did not translate the dragged point and handles")
	_expect(_state_was_horizontally_translated(last, last_state, 0.25), "Native list swap did not translate the target point and handles")
	history.undo()
	_expect(curve.call(&"get_point", 1) == first and curve.call(&"get_point", 3) == last, "Native list-swap Undo lost point identity")
	_expect(first.call(&"capture_state") == first_state and last.call(&"capture_state") == last_state, "Native list-swap Undo lost point state")
	history.redo()
	_expect(curve.call(&"get_point", 3) == first and editor.get_selected_point_resource() == first, "Native list-swap Redo lost point identity or selection")
	editor.queue_free()


func _state_was_horizontally_translated(
	point: Resource,
	original: Dictionary,
	target_x: float,
) -> bool:
	var current := point.call(&"capture_state") as Dictionary
	var delta_x := target_x - (original[&"position"] as Vector2).x
	for property_name: StringName in [&"position", &"left_control_point", &"right_control_point"]:
		var expected := original[property_name] as Vector2
		expected.x += delta_x
		if not (current[property_name] as Vector2).is_equal_approx(expected):
			return false
	return true


func _test_native_crossing_and_toolbar_reorder() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	curve.set(&"transition", 100)
	var first := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	first.set(&"position", Vector2(0.35, 0.35))
	first.set(&"left_control_point", Vector2(0.25, 0.35))
	first.set(&"right_control_point", Vector2(0.45, 0.35))
	var second := ClassDB.instantiate(&"NativeEasingCurvePoint") as Resource
	second.set(&"position", Vector2(0.65, 0.65))
	second.set(&"left_control_point", Vector2(0.55, 0.65))
	second.set(&"right_control_point", Vector2(0.75, 0.65))
	curve.call(&"insert_point", 1, first)
	curve.call(&"insert_point", 2, second)
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	var history := UndoRedo.new()
	editor.editor_undo_redo = history
	editor.set_curve(curve)
	editor.size = Vector2(520.0, 260.0)
	root.add_child(editor)
	editor.update_view_transform()

	var start_view := editor.get_view_pos(first.get(&"position"))
	var target_position := Vector2(0.8, 0.45)
	var target_view := editor.get_view_pos(target_position)
	var changes := [0]
	curve.changed.connect(func() -> void: changes[0] += 1)
	editor._gui_input(_mouse_button(start_view, true))
	_expect(editor.selected_index == 1, "Native crossing press did not select the dragged point")
	editor._gui_input(_mouse_motion(target_view))
	_expect(editor.get("_backend_point_edit_selected_before") == first, "Native crossing transaction did not capture selected resource identity")
	var changes_before_release: int = changes[0]
	editor._gui_input(_mouse_button(target_view, false))
	_expect(curve.call(&"get_point", 2) == first, "Native right crossing did not commit point order")
	_expect(editor.selected_index == 2, "Native right crossing lost selected point identity")
	_expect(changes[0] == changes_before_release + 1, "Native crossing release did not publish exactly once")
	_expect(history.has_undo(), "Native crossing did not create Undo history")
	history.undo()
	_expect(curve.call(&"get_point", 1) == first, "Native crossing Undo lost point identity")
	_expect(
		editor.selected_index == 1,
		"Native crossing Undo lost selection identity (index=%d, resolved=%d)"
		% [editor.selected_index, (curve.call(&"get_points") as Array).find(first)],
	)
	_expect(not history.has_undo() and history.has_redo(), "Native crossing created more than one Undo action")
	history.redo()
	_expect(curve.call(&"get_point", 2) == first and editor.selected_index == 2, "Native crossing Redo lost identity or selection")

	history.clear_history()
	start_view = editor.get_view_pos(first.get(&"position"))
	target_position = Vector2(0.2, 0.45)
	target_view = editor.get_view_pos(target_position)
	editor._gui_input(_mouse_button(start_view, true))
	editor._gui_input(_mouse_motion(target_view))
	editor._gui_input(_mouse_button(target_view, false))
	_expect(curve.call(&"get_point", 1) == first and editor.selected_index == 1, "Native left crossing lost identity or selection")
	history.undo()
	_expect(curve.call(&"get_point", 2) == first and editor.selected_index == 2, "Native left-crossing Undo lost identity or selection")
	history.redo()
	_expect(curve.call(&"get_point", 1) == first and editor.selected_index == 1, "Native left-crossing Redo lost identity or selection")
	history.undo()

	history.clear_history()
	editor.point_move_buttons_reorder_points = true
	editor.call(&"_request_point_move_up")
	_expect(curve.call(&"get_point", 1) == first and editor.selected_index == 1, "Native toolbar reorder lost identity or selection")
	_expect(history.has_undo(), "Native toolbar reorder did not create Undo history")
	history.undo()
	_expect(curve.call(&"get_point", 2) == first and editor.selected_index == 2, "Native toolbar reorder Undo lost identity or selection")
	history.redo()
	_expect(curve.call(&"get_point", 1) == first and editor.selected_index == 1, "Native toolbar reorder Redo lost identity or selection")
	editor.queue_free()


func _mouse_button(
	position: Vector2,
	pressed: bool,
	button_index: MouseButton = MOUSE_BUTTON_LEFT,
	command_or_control_pressed := false,
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.position = position
	event.pressed = pressed
	if command_or_control_pressed:
		if OS.get_name() == "macOS":
			event.meta_pressed = true
		else:
			event.ctrl_pressed = true
	return event


func _mouse_motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event


func _find_curve_editor(node: Node) -> EasingCurveEditor:
	if node is EasingCurveEditor:
		return node
	for child in node.get_children():
		var result := _find_curve_editor(child)
		if result != null:
			return result
	return null


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var result := _find_button(child, text)
		if result != null:
			return result
	return null


func _find_drag_handle(node: Node) -> EasingCurveDragHandle:
	if node is EasingCurveDragHandle:
		return node
	for child in node.get_children():
		var result := _find_drag_handle(child)
		if result != null:
			return result
	return null

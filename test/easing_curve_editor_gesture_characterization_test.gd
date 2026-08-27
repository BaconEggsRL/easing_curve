extends SceneTree

const EDITOR_HOST = preload("res://test/editor_host_test_harness.gd")
const ZOOM_SLIDER = preload("res://addons/easing_curve/scripts/zoom_slider_container.tscn")

var _failures := 0
var _checks := 0


func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("easing_curve_editor_gesture_characterization_test.gd"):
		quit(1)
		return
	call_deferred(&"_run")


func _run() -> void:
	_test_zoom_metadata_contract()
	_test_pending_add_cancel_and_no_op_release()
	_test_point_and_control_drag_boundaries()
	_test_zoom_and_pan_interactions()
	if _failures == 0:
		print("PASS: %d graph gesture characterization checks" % _checks)
		quit()
	else:
		push_error("FAIL: %d of %d graph gesture characterization checks failed" % [_failures, _checks])
		quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _fixture() -> Dictionary:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [
		EasingCurvePoint.new(Vector2(0.1, 0.1)),
		EasingCurvePoint.new(Vector2(0.5, 0.5)),
		EasingCurvePoint.new(Vector2(0.9, 0.9)),
	]
	curve.points[1].left_control_point = Vector2(0.4, 0.3)
	curve.points[1].right_control_point = Vector2(0.6, 0.7)
	var context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = context.editor
	var inspector: Object = context.inspector
	editor.point_property_change_requested.connect(
		func(index: int, property_name: StringName, value: Variant, changing: bool) -> void:
			inspector.call("_on_curve_editor_point_property_change_requested", index, property_name, value, changing),
	)
	editor.point_edit_finished.connect(
		func(point_order: Array[EasingCurvePoint]) -> void:
			inspector.call("_on_curve_editor_point_edit_finished", point_order),
	)
	editor.point_add_requested.connect(func(point: EasingCurvePoint) -> void: inspector.call("_on_curve_editor_point_add_requested", point))
	editor.point_remove_requested.connect(func(point: EasingCurvePoint) -> void: inspector.call("_remove_point", point))
	editor._slider = ZOOM_SLIDER.instantiate()
	editor.update_view_transform()
	return {"curve": curve, "editor": editor, "inspector": inspector}


func _button(button: MouseButton, position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.pressed = pressed
	return event


func _motion(position: Vector2, buttons := 0) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = buttons
	return event


func _point_view(editor: EasingCurveEditor, point: EasingCurvePoint) -> Vector2:
	return editor.get_view_pos(point.position)


func _test_zoom_metadata_contract() -> void:
	_expect(EasingCurve.ZOOM_MIN == 0.1, "EasingCurve ZOOM_MIN changed")
	_expect(EasingCurve.ZOOM_MAX == 10.0, "EasingCurve ZOOM_MAX changed")
	_expect(EasingCurve.ZOOM_FACTOR == 1.2, "EasingCurve ZOOM_FACTOR changed")
	_expect(EasingCurve.ZOOM_STEPS == 25, "EasingCurve ZOOM_STEPS changed")
	_expect(EasingCurve.DEFAULT_SLIDER_VALUE == 12.0, "EasingCurve DEFAULT_SLIDER_VALUE changed")

	for value_pair in [
		[EasingCurveEditor.ZOOM_MIN, EasingCurveZoomSliderContainer.ZOOM_MIN],
		[EasingCurveEditor.ZOOM_MAX, EasingCurveZoomSliderContainer.ZOOM_MAX],
		[EasingCurveEditor.ZOOM_FACTOR, EasingCurveZoomSliderContainer.ZOOM_FACTOR],
		[EasingCurveEditor.ZOOM_STEPS, EasingCurveZoomSliderContainer.ZOOM_STEPS],
		[EasingCurveEditor.DEFAULT_SLIDER_VALUE, EasingCurveZoomSliderContainer.DEFAULT_SLIDER_VALUE],
	]:
		_expect(value_pair[0] == value_pair[1], "Editor and zoom slider zoom metadata diverged")

	_expect(EasingCurveEditor.ZOOM_MIN == EasingCurve.ZOOM_MIN, "Editor ZOOM_MIN diverged from EasingCurve")
	_expect(EasingCurveEditor.ZOOM_MAX == EasingCurve.ZOOM_MAX, "Editor ZOOM_MAX diverged from EasingCurve")
	_expect(EasingCurveEditor.ZOOM_FACTOR == EasingCurve.ZOOM_FACTOR, "Editor ZOOM_FACTOR diverged from EasingCurve")
	_expect(EasingCurveEditor.ZOOM_STEPS == EasingCurve.ZOOM_STEPS, "Editor ZOOM_STEPS diverged from EasingCurve")
	_expect(EasingCurveEditor.DEFAULT_SLIDER_VALUE == EasingCurve.DEFAULT_SLIDER_VALUE, "Editor DEFAULT_SLIDER_VALUE diverged from EasingCurve")

	_expect(
		EasingCurve.ZOOM_STEPS == int(round(log(EasingCurve.ZOOM_MAX / EasingCurve.ZOOM_MIN) / log(EasingCurve.ZOOM_FACTOR))),
		"Zoom step count no longer matches the public zoom range/factor",
	)
	_expect(
		EasingCurve.DEFAULT_SLIDER_VALUE == floor(EasingCurve.ZOOM_STEPS / 2.0),
		"Default slider value is no longer the midpoint of the zoom-step range",
	)

	var editor := EasingCurveEditor.new()
	var default_step := int(EasingCurve.DEFAULT_SLIDER_VALUE)
	_expect(is_equal_approx(editor.step_to_zoom(0), EasingCurve.ZOOM_MIN), "Zoom step zero no longer maps to ZOOM_MIN")
	_expect(editor.zoom_to_step(editor.step_to_zoom(default_step)) == default_step, "Default zoom step no longer round-trips through the zoom conversion")
	editor.free()


func _test_pending_add_cancel_and_no_op_release() -> void:
	var fixture := _fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var empty := Vector2(580.0, 280.0)
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, empty, true))
	_expect(editor.pending_add_point != null, "Graph press did not begin a pending add")
	editor._gui_input(_button(MOUSE_BUTTON_RIGHT, empty, true))
	_expect(editor.pending_add_point == null and not editor.is_right_delete_dragging, "RMB pending-add cancel leaked graph delete/add state")
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, empty, false))
	_expect(curve.points.size() == 3, "Canceled pending add committed on the later LMB release")

	var point_position := _point_view(editor, curve.points[1])
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_position, true))
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_position, false))
	_expect(inspector.get("_point_edit_before_state").is_empty(), "No-op point click created an edit transaction")
	_expect(editor.dragging_point == -1 and editor.dragging_control == EasingCurveEditor.ControlIndex.NONE, "No-op point release leaked drag state")
	editor.free()


func _test_point_and_control_drag_boundaries() -> void:
	var fixture := _fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var inspector: Object = fixture.inspector
	var point := curve.points[1]
	var start := _point_view(editor, point)
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, start, true))
	editor._gui_input(_motion(start + Vector2(30.0, -20.0), MOUSE_BUTTON_MASK_LEFT))
	_expect(not inspector.get("_point_edit_before_state").is_empty(), "Point drag did not begin one edit transaction")
	editor._gui_input(_motion(start + Vector2(45.0, -25.0), MOUSE_BUTTON_MASK_LEFT))
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, start + Vector2(45.0, -25.0), false))
	_expect(inspector.get("_point_edit_before_state").is_empty(), "Point drag release did not complete its transaction")
	_expect(editor.dragging_point == -1 and editor.dragging_control == EasingCurveEditor.ControlIndex.NONE, "Point drag release leaked graph state")

	point = curve.points[editor.selected_index]
	var control_view := editor.get_view_pos(point.right_control_point)
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, control_view, true))
	editor._gui_input(_motion(control_view + Vector2(20.0, 15.0), MOUSE_BUTTON_MASK_LEFT))
	_expect(not inspector.get("_point_edit_before_state").is_empty(), "Control drag did not begin one edit transaction")
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, control_view + Vector2(20.0, 15.0), false))
	_expect(inspector.get("_point_edit_before_state").is_empty(), "Control drag release did not complete its transaction")
	editor.free()


func _test_zoom_and_pan_interactions() -> void:
	var fixture := _fixture()
	var editor: EasingCurveEditor = fixture.editor
	var point_view := _point_view(editor, fixture.curve.points[1])
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_view, true))
	var zoom_before := editor._zoom_step
	editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, point_view, true))
	_expect(editor.dragging_point != -1, "Zoom during a point drag canceled the active drag")
	_expect(editor._zoom_step != zoom_before, "Zoom during a point drag did not update the view")
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_view, false))

	get_root().add_child(editor)
	var pan_before := editor.pan_offset
	editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, Vector2(100.0, 100.0), true))
	editor._gui_input(_motion(Vector2(125.0, 115.0), MOUSE_BUTTON_MASK_MIDDLE))
	editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, Vector2(125.0, 115.0), false))
	_expect(editor.pan_offset != pan_before and not editor.is_panning, "Pan gesture did not move the view and clear panning state")
	editor.get_parent().remove_child(editor)
	editor._slider.free()
	editor.free()

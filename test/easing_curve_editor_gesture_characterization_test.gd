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
	_test_zoom_behavioral_invariants()
	_test_pending_add_cancel_and_no_op_release()
	_test_modifier_capable_drag_baseline()
	_test_point_axis_constraint_behavior()
	_test_handle_axis_constraint_behavior()
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


func _button(
	button: MouseButton,
	position: Vector2,
	pressed: bool,
	shift_pressed := false,
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	return event


func _motion(
	position: Vector2,
	buttons := 0,
	shift_pressed := false,
) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = buttons
	event.shift_pressed = shift_pressed
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


func _test_zoom_behavioral_invariants() -> void:
	var fixture := _fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var default_step := int(EasingCurve.DEFAULT_SLIDER_VALUE)
	var default_zoom := editor.step_to_zoom(default_step)

	_expect(
		curve._last_slider_value == EasingCurve.DEFAULT_SLIDER_VALUE,
		"New EasingCurve resource no longer starts at the canonical slider value",
	)

	editor.set_slider_value(default_step)
	_expect(editor._zoom_step == default_step, "Applying the default slider value did not select the canonical zoom step")
	_expect(
		is_equal_approx(editor._zoom_x, default_zoom) and is_equal_approx(editor._zoom_y, default_zoom),
		"Default slider value no longer maps to the canonical zoom",
	)
	_expect(editor._slider.slider.value == default_step, "Editor and slider value diverged at the canonical zoom step")

	var slider_step := mini(default_step + 2, EasingCurve.ZOOM_STEPS)
	editor.set_slider_value(slider_step)
	var slider_zoom := editor.step_to_zoom(slider_step)
	_expect(editor._zoom_step == slider_step, "Slider-driven zoom did not update the editor zoom step")
	_expect(
		is_equal_approx(editor._zoom_x, slider_zoom) and is_equal_approx(editor._zoom_y, slider_zoom),
		"Slider-driven zoom no longer uses step_to_zoom() consistently",
	)

	editor.update_view_transform()
	var wheel_anchor := Vector2(137.0, 113.0)
	var world_before := editor.get_world_pos(wheel_anchor)
	var wheel_step_before := editor._zoom_step
	editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, wheel_anchor, true))
	var expected_wheel_step := mini(wheel_step_before + 1, EasingCurve.ZOOM_STEPS)
	var wheel_zoom := editor.step_to_zoom(expected_wheel_step)
	_expect(editor._zoom_step == expected_wheel_step, "Wheel zoom did not advance exactly one zoom step")
	_expect(
		is_equal_approx(editor._zoom_x, wheel_zoom) and is_equal_approx(editor._zoom_y, wheel_zoom),
		"Wheel zoom no longer uses the same step-to-zoom conversion as slider zoom",
	)
	var world_after := editor.get_world_pos(wheel_anchor)
	_expect(
		world_after.is_equal_approx(world_before),
		"Zoom around an off-center pointer no longer preserves the world point under the cursor",
	)

	editor.pan_offset = Vector2(23.0, -17.0)
	editor.set_slider_value(mini(default_step + 3, EasingCurve.ZOOM_STEPS))
	editor._on_autofit_pressed()
	_expect(editor._zoom_step == default_step, "Autofit no longer restores the canonical default zoom step")
	_expect(editor._slider.slider.value == default_step, "Autofit left the slider out of sync with the canonical default step")
	_expect(editor.pan_offset == Vector2.ZERO, "Autofit no longer clears graph pan")
	_expect(
		is_equal_approx(editor._zoom_x, default_zoom) and is_equal_approx(editor._zoom_y, default_zoom),
		"Autofit no longer restores the canonical default zoom",
	)

	editor._slider.free()
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


func _test_modifier_capable_drag_baseline() -> void:
	var point_fixture := _fixture()
	var point_curve: EasingCurve = point_fixture.curve
	var point_editor: EasingCurveEditor = point_fixture.editor
	var point := point_curve.points[1]
	var point_start := _point_view(point_editor, point)
	var point_target_view := point_start + Vector2(26.0, -17.0)
	var expected_point_target := point_editor.get_world_pos(point_target_view).clamp(
		Vector2(0, point_curve.min_value),
		Vector2(1.0, point_curve.max_value),
	)
	point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_start, true, true))
	_expect(point_editor.dragging_point == 1, "Pre-held Shift prevented the ordinary point drag from starting")
	point_editor._gui_input(_motion(point_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(point.position.is_equal_approx(expected_point_target), "Pre-held Shift changed the ordinary unconstrained point target")
	point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_target_view, false, true))
	_expect(point_editor.dragging_point == -1, "Pre-held Shift point drag did not clear drag state on release")
	point_editor._slider.free()
	point_editor.free()

	var left_fixture := _fixture()
	var left_curve: EasingCurve = left_fixture.curve
	var left_editor: EasingCurveEditor = left_fixture.editor
	var left_point := left_curve.points[1]
	var left_start := left_editor.get_view_pos(left_point.left_control_point)
	var left_target_view := left_start + Vector2(-18.0, 12.0)
	var expected_left_target := left_editor.get_world_pos(left_target_view)
	left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, left_start, true))
	_expect(left_editor.dragging_control == EasingCurveEditor.ControlIndex.LEFT, "Ordinary left-handle drag did not start on the left control")
	left_editor._gui_input(_motion(left_target_view, MOUSE_BUTTON_MASK_LEFT))
	_expect(left_point.left_control_point.is_equal_approx(expected_left_target), "Ordinary left-handle drag no longer follows the unconstrained mouse target")
	left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, left_target_view, false))
	left_editor._slider.free()
	left_editor.free()

	var right_fixture := _fixture()
	var right_curve: EasingCurve = right_fixture.curve
	var right_editor: EasingCurveEditor = right_fixture.editor
	var right_point := right_curve.points[1]
	var right_start := right_editor.get_view_pos(right_point.right_control_point)
	var right_target_view := right_start + Vector2(18.0, -12.0)
	var expected_right_target := right_editor.get_world_pos(right_target_view)
	right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, right_start, true))
	_expect(right_editor.dragging_control == EasingCurveEditor.ControlIndex.RIGHT, "Ordinary right-handle drag did not start on the right control")
	right_editor._gui_input(_motion(right_target_view, MOUSE_BUTTON_MASK_LEFT))
	_expect(right_point.right_control_point.is_equal_approx(expected_right_target), "Ordinary right-handle drag no longer follows the unconstrained mouse target")
	right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, right_target_view, false))
	right_editor._slider.free()
	right_editor.free()


func _test_point_axis_constraint_behavior() -> void:
	var fixture := _fixture()
	var curve: EasingCurve = fixture.curve
	var editor: EasingCurveEditor = fixture.editor
	var point := curve.points[1]
	var origin := point.position
	var start := _point_view(editor, point)

	editor._gui_input(_button(MOUSE_BUTTON_LEFT, start, true))
	editor._gui_input(_motion(start + Vector2(8.0, -5.0), MOUSE_BUTTON_MASK_LEFT))

	var horizontal_view := start + Vector2(54.0, 14.0)
	var horizontal_world := editor.get_world_pos(horizontal_view)
	var expected_horizontal := Vector2(horizontal_world.x, origin.y).clamp(
		Vector2(0, curve.min_value),
		Vector2(1.0, curve.max_value),
	)
	editor._gui_input(_motion(horizontal_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		point.position.is_equal_approx(expected_horizontal),
		"Mid-drag Shift did not constrain the point to the horizontal axis from the original drag position",
	)

	var vertical_view := start + Vector2(14.0, -54.0)
	var vertical_world := editor.get_world_pos(vertical_view)
	var expected_vertical := Vector2(origin.x, vertical_world.y).clamp(
		Vector2(0, curve.min_value),
		Vector2(1.0, curve.max_value),
	)
	editor._gui_input(_motion(vertical_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		point.position.is_equal_approx(expected_vertical),
		"Held Shift did not switch to the vertical axis when total view displacement became Y-dominant",
	)

	var free_view := start + Vector2(42.0, -30.0)
	var expected_free := editor.get_world_pos(free_view).clamp(
		Vector2(0, curve.min_value),
		Vector2(1.0, curve.max_value),
	)
	editor._gui_input(_motion(free_view, MOUSE_BUTTON_MASK_LEFT, false))
	_expect(
		point.position.is_equal_approx(expected_free),
		"Releasing Shift did not immediately restore ordinary unconstrained point dragging",
	)
	editor._gui_input(_button(MOUSE_BUTTON_LEFT, free_view, false))
	_expect(editor.dragging_point == -1, "Constrained point drag did not clear drag state on release")
	editor._slider.free()
	editor.free()

	var preheld_fixture := _fixture()
	var preheld_curve: EasingCurve = preheld_fixture.curve
	var preheld_editor: EasingCurveEditor = preheld_fixture.editor
	var preheld_point := preheld_curve.points[1]
	var preheld_origin := preheld_point.position
	var preheld_start := _point_view(preheld_editor, preheld_point)
	preheld_editor._gui_input(_button(MOUSE_BUTTON_LEFT, preheld_start, true, true))

	var held_view := preheld_start + Vector2(40.0, -12.0)
	var expected_held := preheld_editor.get_world_pos(held_view).clamp(
		Vector2(0, preheld_curve.min_value),
		Vector2(1.0, preheld_curve.max_value),
	)
	preheld_editor._gui_input(_motion(held_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		preheld_point.position.is_equal_approx(expected_held),
		"Pre-held Shift unexpectedly activated point axis constraint",
	)

	var released_shift_view := preheld_start + Vector2(45.0, -20.0)
	var expected_released_shift := preheld_editor.get_world_pos(released_shift_view).clamp(
		Vector2(0, preheld_curve.min_value),
		Vector2(1.0, preheld_curve.max_value),
	)
	preheld_editor._gui_input(_motion(released_shift_view, MOUSE_BUTTON_MASK_LEFT, false))
	_expect(
		preheld_point.position.is_equal_approx(expected_released_shift),
		"Releasing a pre-held Shift did not preserve the ordinary point drag target",
	)

	var repress_view := preheld_start + Vector2(52.0, 10.0)
	var repress_world := preheld_editor.get_world_pos(repress_view)
	var expected_repress := Vector2(repress_world.x, preheld_origin.y).clamp(
		Vector2(0, preheld_curve.min_value),
		Vector2(1.0, preheld_curve.max_value),
	)
	preheld_editor._gui_input(_motion(repress_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		preheld_point.position.is_equal_approx(expected_repress),
		"Shift did not become eligible after a pre-held Shift was released and pressed again during the same drag",
	)
	preheld_editor._gui_input(_button(MOUSE_BUTTON_LEFT, repress_view, false, true))
	preheld_editor._slider.free()
	preheld_editor.free()


func _test_handle_axis_constraint_behavior() -> void:
	var left_fixture := _fixture()
	var left_curve: EasingCurve = left_fixture.curve
	var left_editor: EasingCurveEditor = left_fixture.editor
	var left_point := left_curve.points[1]
	var left_origin := left_point.left_control_point
	var left_start := left_editor.get_view_pos(left_origin)
	left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, left_start, true))

	var left_horizontal_view := left_start + Vector2(-52.0, 12.0)
	var left_horizontal_world := left_editor.get_world_pos(left_horizontal_view)
	var expected_left_horizontal := Vector2(left_horizontal_world.x, left_origin.y)
	left_editor._gui_input(_motion(left_horizontal_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		left_point.left_control_point.is_equal_approx(expected_left_horizontal),
		"Shift did not constrain the left handle to the horizontal axis from its original drag position",
	)

	var left_vertical_view := left_start + Vector2(-12.0, -52.0)
	var left_vertical_world := left_editor.get_world_pos(left_vertical_view)
	var expected_left_vertical := Vector2(left_origin.x, left_vertical_world.y)
	left_editor._gui_input(_motion(left_vertical_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		left_point.left_control_point.is_equal_approx(expected_left_vertical),
		"Held Shift did not constrain the left handle to the vertical axis when Y became dominant",
	)

	var left_free_view := left_start + Vector2(-30.0, -24.0)
	var expected_left_free := left_editor.get_world_pos(left_free_view)
	left_editor._gui_input(_motion(left_free_view, MOUSE_BUTTON_MASK_LEFT, false))
	_expect(
		left_point.left_control_point.is_equal_approx(expected_left_free),
		"Releasing Shift did not immediately restore ordinary unconstrained left-handle dragging",
	)
	left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, left_free_view, false))
	left_editor._slider.free()
	left_editor.free()

	var right_fixture := _fixture()
	var right_curve: EasingCurve = right_fixture.curve
	var right_editor: EasingCurveEditor = right_fixture.editor
	var right_point := right_curve.points[1]
	var right_origin := right_point.right_control_point
	var right_start := right_editor.get_view_pos(right_origin)
	right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, right_start, true))

	var right_horizontal_view := right_start + Vector2(52.0, -12.0)
	var right_horizontal_world := right_editor.get_world_pos(right_horizontal_view)
	var expected_right_horizontal := Vector2(right_horizontal_world.x, right_origin.y)
	right_editor._gui_input(_motion(right_horizontal_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		right_point.right_control_point.is_equal_approx(expected_right_horizontal),
		"Shift did not constrain the right handle to the horizontal axis from its original drag position",
	)

	var right_vertical_view := right_start + Vector2(12.0, 52.0)
	var right_vertical_world := right_editor.get_world_pos(right_vertical_view)
	var expected_right_vertical := Vector2(right_origin.x, right_vertical_world.y)
	right_editor._gui_input(_motion(right_vertical_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		right_point.right_control_point.is_equal_approx(expected_right_vertical),
		"Held Shift did not constrain the right handle to the vertical axis when Y became dominant",
	)
	right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, right_vertical_view, false, true))
	right_editor._slider.free()
	right_editor.free()


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

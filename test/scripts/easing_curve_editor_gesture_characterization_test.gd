extends SceneTree

const EDITOR_HOST = preload("res://test/scripts/editor_host_test_harness.gd")
const ZOOM_SLIDER = preload("res://addons/easing_curve/scripts/editor/widgets/zoom_slider_container.tscn")

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
	_test_bezier_draw_clipping_and_tessellation()
	_test_pending_add_cancel_and_no_op_release()
	_test_modifier_capable_drag_baseline()
	_test_point_axis_constraint_behavior()
	_test_handle_axis_constraint_behavior()
	_test_axis_constraint_downstream_control_semantics()
	_test_axis_constraint_view_and_order_geometry()
	_test_axis_constraint_request_and_input_boundaries()
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


func _handles_are_opposite_in_display_space(point: EasingCurvePoint) -> bool:
	var left_delta := (point.left_control_point - point.position) * point.handle_display_scale
	var right_delta := (point.right_control_point - point.position) * point.handle_display_scale
	if left_delta.is_zero_approx() or right_delta.is_zero_approx():
		return false
	return left_delta.normalized().is_equal_approx(-right_delta.normalized())


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


func _test_bezier_draw_clipping_and_tessellation() -> void:
	var editor := EasingCurveEditor.new()
	editor.size = Vector2(600.0, 300.0)
	editor.update_view_transform()
	var default_bounds := editor._get_visible_world_x_bounds()
	editor.set_zoom(Vector2(10.0, 10.0))
	editor.update_view_transform()
	var zoomed_bounds := editor._get_visible_world_x_bounds()
	_expect(
		zoomed_bounds.y - zoomed_bounds.x < default_bounds.y - default_bounds.x,
		"Visible world-X clipping bounds did not narrow under horizontal zoom",
	)

	var a := EasingCurvePoint.new(Vector2.ZERO)
	var b := EasingCurvePoint.new(Vector2.ONE)
	var curved_out_control := Vector2(0.1, 1.0)
	var curved_in_control := Vector2(0.9, 0.0)
	var start_view := editor.get_view_pos(a.position)
	var end_view := editor.get_view_pos(b.position)
	var curved_polyline := PackedVector2Array([start_view])
	editor._append_adaptive_bezier_points(
		start_view,
		editor.get_view_pos(curved_out_control),
		editor.get_view_pos(curved_in_control),
		end_view,
		0,
		curved_polyline,
	)
	_expect(
		curved_polyline.size() > 2 and curved_polyline.size() < int(editor.size.x),
		"Adaptive Bézier tessellation did not reduce the curved segment below per-pixel sampling",
	)

	var straight_out_control := Vector2.ONE / 3.0
	var straight_in_control := Vector2.ONE * 2.0 / 3.0
	var straight_polyline := PackedVector2Array([start_view])
	editor._append_adaptive_bezier_points(
		start_view,
		editor.get_view_pos(straight_out_control),
		editor.get_view_pos(straight_in_control),
		end_view,
		0,
		straight_polyline,
	)
	_expect(
		straight_polyline.size() == 2,
		"Adaptive Bézier tessellation produced %d points for a straight segment"
		% straight_polyline.size(),
	)
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


func _test_axis_constraint_downstream_control_semantics() -> void:
	var locked_point_fixture := _fixture()
	var locked_point_curve: EasingCurve = locked_point_fixture.curve
	var locked_point_editor: EasingCurveEditor = locked_point_fixture.editor
	var locked_point := locked_point_curve.points[1]
	var locked_point_origin := locked_point.position
	var locked_point_start := _point_view(locked_point_editor, locked_point)
	locked_point.set_locked("position", true)
	locked_point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_point_start, true))
	_expect(locked_point_editor.dragging_point == -1, "Locked point position unexpectedly started a graph drag")
	locked_point_editor._gui_input(_motion(locked_point_start + Vector2(50.0, 10.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(locked_point.position == locked_point_origin, "Shift motion moved a locked point position")
	locked_point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_point_start + Vector2(50.0, 10.0), false, true))
	locked_point_editor._slider.free()
	locked_point_editor.free()

	var locked_left_fixture := _fixture()
	var locked_left_curve: EasingCurve = locked_left_fixture.curve
	var locked_left_editor: EasingCurveEditor = locked_left_fixture.editor
	var locked_left_point := locked_left_curve.points[1]
	var locked_left_origin := locked_left_point.left_control_point
	var locked_left_start := locked_left_editor.get_view_pos(locked_left_origin)
	locked_left_point.set_locked("left_control_point", true)
	locked_left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_left_start, true))
	_expect(locked_left_editor.dragging_point == -1, "Locked left control unexpectedly started a graph drag")
	locked_left_editor._gui_input(_motion(locked_left_start + Vector2(-50.0, 10.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(locked_left_point.left_control_point == locked_left_origin, "Shift motion moved a locked left control")
	locked_left_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_left_start + Vector2(-50.0, 10.0), false, true))
	locked_left_editor._slider.free()
	locked_left_editor.free()

	var locked_right_fixture := _fixture()
	var locked_right_curve: EasingCurve = locked_right_fixture.curve
	var locked_right_editor: EasingCurveEditor = locked_right_fixture.editor
	var locked_right_point := locked_right_curve.points[1]
	var locked_right_origin := locked_right_point.right_control_point
	var locked_right_start := locked_right_editor.get_view_pos(locked_right_origin)
	locked_right_point.set_locked("right_control_point", true)
	locked_right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_right_start, true))
	_expect(locked_right_editor.dragging_point == -1, "Locked right control unexpectedly started a graph drag")
	locked_right_editor._gui_input(_motion(locked_right_start + Vector2(50.0, -10.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(locked_right_point.right_control_point == locked_right_origin, "Shift motion moved a locked right control")
	locked_right_editor._gui_input(_button(MOUSE_BUTTON_LEFT, locked_right_start + Vector2(50.0, -10.0), false, true))
	locked_right_editor._slider.free()
	locked_right_editor.free()

	var free_fixture := _fixture()
	var free_curve: EasingCurve = free_fixture.curve
	var free_editor: EasingCurveEditor = free_fixture.editor
	var free_point := free_curve.points[1]
	var free_left_origin := free_point.left_control_point
	var free_right_origin := free_point.right_control_point
	var free_start := free_editor.get_view_pos(free_left_origin)
	free_editor._gui_input(_button(MOUSE_BUTTON_LEFT, free_start, true))
	var free_target_view := free_start + Vector2(-48.0, 10.0)
	var free_target_world := free_editor.get_world_pos(free_target_view)
	var expected_free_left := Vector2(free_target_world.x, free_left_origin.y)
	free_editor._gui_input(_motion(free_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(free_point.left_control_point.is_equal_approx(expected_free_left), "Free Shift drag did not preserve the constrained requested handle target")
	_expect(free_point.right_control_point == free_right_origin, "Free Shift drag unexpectedly changed the opposite handle")
	free_editor._gui_input(_button(MOUSE_BUTTON_LEFT, free_target_view, false, true))
	free_editor._slider.free()
	free_editor.free()

	var force_fixture := _fixture()
	var force_curve: EasingCurve = force_fixture.curve
	var force_editor: EasingCurveEditor = force_fixture.editor
	var force_point := force_curve.points[1]
	force_point.left_force_linear = true
	var force_origin := force_point.position
	var force_start := _point_view(force_editor, force_point)
	force_editor._gui_input(_button(MOUSE_BUTTON_LEFT, force_start, true))
	var force_target_view := force_start + Vector2(50.0, 10.0)
	var force_target_world := force_editor.get_world_pos(force_target_view)
	var expected_force_position := Vector2(force_target_world.x, force_origin.y).clamp(
		Vector2(0, force_curve.min_value),
		Vector2(1.0, force_curve.max_value),
	)
	force_editor._gui_input(_motion(force_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(force_point.position.is_equal_approx(expected_force_position), "Force Linear point did not receive the constrained point target")
	_expect(force_point.left_control_point == force_point.position, "Constrained point drag bypassed downstream Force Linear geometry")
	force_editor._gui_input(_button(MOUSE_BUTTON_LEFT, force_target_view, false, true))
	force_editor._slider.free()
	force_editor.free()

	var balanced_fixture := _fixture()
	var balanced_curve: EasingCurve = balanced_fixture.curve
	var balanced_editor: EasingCurveEditor = balanced_fixture.editor
	var balanced_point := balanced_curve.points[1]
	balanced_point.set_handle_display_scale(balanced_editor.get_world_to_view_scale())
	balanced_point.handle_mode = EasingCurvePoint.HandleMode.BALANCED
	var balanced_left_origin := balanced_point.left_control_point
	var balanced_right_display_length := (
		(balanced_point.right_control_point - balanced_point.position)
		* balanced_point.handle_display_scale
	).length()
	var balanced_start := balanced_editor.get_view_pos(balanced_left_origin)
	balanced_editor._gui_input(_button(MOUSE_BUTTON_LEFT, balanced_start, true))
	var balanced_target_view := balanced_start + Vector2(-50.0, 10.0)
	var balanced_target_world := balanced_editor.get_world_pos(balanced_target_view)
	var expected_balanced_left := Vector2(balanced_target_world.x, balanced_left_origin.y)
	balanced_editor._gui_input(_motion(balanced_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(balanced_point.left_control_point.is_equal_approx(expected_balanced_left), "Balanced Shift drag did not preserve the constrained requested handle target")
	_expect(_handles_are_opposite_in_display_space(balanced_point), "Balanced Shift drag bypassed downstream opposite-direction geometry")
	_expect(
		is_equal_approx(
			((balanced_point.right_control_point - balanced_point.position) * balanced_point.handle_display_scale).length(),
			balanced_right_display_length,
		),
		"Balanced Shift drag did not preserve the downstream opposite display-space length",
	)
	balanced_editor._gui_input(_button(MOUSE_BUTTON_LEFT, balanced_target_view, false, true))
	balanced_editor._slider.free()
	balanced_editor.free()

	var mirrored_fixture := _fixture()
	var mirrored_curve: EasingCurve = mirrored_fixture.curve
	var mirrored_editor: EasingCurveEditor = mirrored_fixture.editor
	var mirrored_point := mirrored_curve.points[1]
	mirrored_point.set_handle_display_scale(mirrored_editor.get_world_to_view_scale())
	mirrored_point.handle_mode = EasingCurvePoint.HandleMode.MIRRORED
	var mirrored_right_origin := mirrored_point.right_control_point
	var mirrored_start := mirrored_editor.get_view_pos(mirrored_right_origin)
	mirrored_editor._gui_input(_button(MOUSE_BUTTON_LEFT, mirrored_start, true))
	var mirrored_target_view := mirrored_start + Vector2(10.0, 50.0)
	var mirrored_target_world := mirrored_editor.get_world_pos(mirrored_target_view)
	var expected_mirrored_right := Vector2(mirrored_right_origin.x, mirrored_target_world.y)
	mirrored_editor._gui_input(_motion(mirrored_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(mirrored_point.right_control_point.is_equal_approx(expected_mirrored_right), "Mirrored Shift drag did not preserve the constrained requested handle target")
	_expect(
		((mirrored_point.left_control_point - mirrored_point.position) * mirrored_point.handle_display_scale).is_equal_approx(
			-((mirrored_point.right_control_point - mirrored_point.position) * mirrored_point.handle_display_scale)
		),
		"Mirrored Shift drag bypassed downstream mirrored display-space geometry",
	)
	mirrored_editor._gui_input(_button(MOUSE_BUTTON_LEFT, mirrored_target_view, false, true))
	mirrored_editor._slider.free()
	mirrored_editor.free()

	var linked_fixture := _fixture()
	var linked_curve: EasingCurve = linked_fixture.curve
	var linked_editor: EasingCurveEditor = linked_fixture.editor
	var linked_point := linked_curve.points[1]
	linked_point.handle_mode = EasingCurvePoint.HandleMode.LINKED
	var linked_origin := linked_point.left_control_point
	var linked_start := linked_editor.get_view_pos(linked_origin)
	linked_editor._gui_input(_button(MOUSE_BUTTON_LEFT, linked_start, true))
	_expect(linked_editor.dragging_control == EasingCurveEditor.ControlIndex.LEFT, "Linked shared handle did not enter the existing left-control graph path")
	var linked_target_view := linked_start + Vector2(50.0, 10.0)
	var linked_target_world := linked_editor.get_world_pos(linked_target_view)
	var expected_linked := Vector2(linked_target_world.x, linked_origin.y)
	linked_editor._gui_input(_motion(linked_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		linked_point.left_control_point.is_equal_approx(expected_linked)
		and linked_point.right_control_point.is_equal_approx(expected_linked),
		"Linked Shift drag did not keep both controls synchronized to the constrained request",
	)
	linked_editor._gui_input(_button(MOUSE_BUTTON_LEFT, linked_target_view, false, true))
	linked_editor._slider.free()
	linked_editor.free()

	var linear_fixture := _fixture()
	var linear_curve: EasingCurve = linear_fixture.curve
	var linear_editor: EasingCurveEditor = linear_fixture.editor
	var linear_point := linear_curve.points[1]
	linear_point.handle_mode = EasingCurvePoint.HandleMode.LINEAR
	var linear_origin := linear_point.position
	var linear_start := linear_editor.get_view_pos(linear_point.left_control_point)
	linear_editor._gui_input(_button(MOUSE_BUTTON_LEFT, linear_start, true))
	_expect(
		linear_editor.dragging_point == 1 and linear_editor.dragging_control == EasingCurveEditor.ControlIndex.NONE,
		"Linear collapsed handle did not fall back to the existing point drag path",
	)
	var linear_target_view := linear_start + Vector2(50.0, 10.0)
	var linear_target_world := linear_editor.get_world_pos(linear_target_view)
	var expected_linear_position := Vector2(linear_target_world.x, linear_origin.y).clamp(
		Vector2(0, linear_curve.min_value),
		Vector2(1.0, linear_curve.max_value),
	)
	linear_editor._gui_input(_motion(linear_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(linear_point.position.is_equal_approx(expected_linear_position), "Linear fallback point drag did not receive the constrained point target")
	_expect(
		linear_point.left_control_point == linear_point.position
		and linear_point.right_control_point == linear_point.position,
		"Linear fallback point drag did not retain collapsed downstream controls",
	)
	linear_editor._gui_input(_button(MOUSE_BUTTON_LEFT, linear_target_view, false, true))
	linear_editor._slider.free()
	linear_editor.free()


func _test_axis_constraint_view_and_order_geometry() -> void:
	var view_fixture := _fixture()
	var view_curve: EasingCurve = view_fixture.curve
	var view_editor: EasingCurveEditor = view_fixture.editor
	var view_point := view_curve.points[1]
	var view_origin := view_point.position
	var view_start := _point_view(view_editor, view_point)
	var disagreement_view := view_start + Vector2(40.0, 30.0)
	var disagreement_world := view_editor.get_world_pos(disagreement_view)
	var disagreement_world_delta := disagreement_world - view_origin
	_expect(
		absf(disagreement_world_delta.y) > absf(disagreement_world_delta.x),
		"View-space dominance fixture no longer disagrees with world-space dominance",
	)
	view_editor._gui_input(_button(MOUSE_BUTTON_LEFT, view_start, true))
	view_editor._gui_input(_motion(disagreement_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		view_point.position.is_equal_approx(
			Vector2(disagreement_world.x, view_origin.y).clamp(
				Vector2(0, view_curve.min_value),
				Vector2(1.0, view_curve.max_value),
			)
		),
		"Shift axis choice followed world-space magnitude instead of view-space pixel displacement",
	)

	var equal_view := view_start + Vector2(32.0, 32.0)
	var equal_world := view_editor.get_world_pos(equal_view)
	view_editor._gui_input(_motion(equal_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		view_point.position.is_equal_approx(
			Vector2(view_origin.x, equal_world.y).clamp(
				Vector2(0, view_curve.min_value),
				Vector2(1.0, view_curve.max_value),
			)
		),
		"Equal view-space displacement no longer resolves to the Y axis",
	)

	var x_side_view := view_start + Vector2(33.0, 32.0)
	var x_side_world := view_editor.get_world_pos(x_side_view)
	view_editor._gui_input(_motion(x_side_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		view_point.position.is_equal_approx(
			Vector2(x_side_world.x, view_origin.y).clamp(
				Vector2(0, view_curve.min_value),
				Vector2(1.0, view_curve.max_value),
			)
		),
		"X side of the view-space diagonal did not constrain horizontally",
	)

	var y_side_view := view_start + Vector2(32.0, 33.0)
	var y_side_world := view_editor.get_world_pos(y_side_view)
	view_editor._gui_input(_motion(y_side_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		view_point.position.is_equal_approx(
			Vector2(view_origin.x, y_side_world.y).clamp(
				Vector2(0, view_curve.min_value),
				Vector2(1.0, view_curve.max_value),
			)
		),
		"Y side of the view-space diagonal did not constrain vertically",
	)
	view_editor._gui_input(_button(MOUSE_BUTTON_LEFT, y_side_view, false, true))
	view_editor._slider.free()
	view_editor.free()

	var zoom_fixture := _fixture()
	var zoom_curve: EasingCurve = zoom_fixture.curve
	var zoom_editor: EasingCurveEditor = zoom_fixture.editor
	zoom_editor.set_slider_value(
		mini(int(EasingCurve.DEFAULT_SLIDER_VALUE) + 3, EasingCurve.ZOOM_STEPS)
	)
	zoom_editor.update_view_transform()
	zoom_editor.pan_offset = Vector2(37.0, -21.0)
	var zoom_point := zoom_curve.points[1]
	var zoom_origin := zoom_point.position
	var zoom_start := _point_view(zoom_editor, zoom_point)
	zoom_editor._gui_input(_button(MOUSE_BUTTON_LEFT, zoom_start, true))
	var zoom_target_view := zoom_start + Vector2(44.0, 20.0)
	var zoom_target_world := zoom_editor.get_world_pos(zoom_target_view)
	zoom_editor._gui_input(_motion(zoom_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		zoom_point.position.is_equal_approx(
			Vector2(zoom_target_world.x, zoom_origin.y).clamp(
				Vector2(0, zoom_curve.min_value),
				Vector2(1.0, zoom_curve.max_value),
			)
		),
		"Shift constraint did not preserve view-space axis behavior under zoom and pan",
	)
	var zoom_step_before_wheel := zoom_editor._zoom_step
	zoom_editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, zoom_target_view, true, true))
	_expect(
		zoom_editor.dragging_point == 1
		and zoom_editor._zoom_step == mini(zoom_step_before_wheel + 1, EasingCurve.ZOOM_STEPS),
		"Wheel zoom during a constrained drag canceled the drag or failed to advance zoom",
	)
	var post_wheel_view := zoom_start + Vector2(56.0, 18.0)
	var post_wheel_world := zoom_editor.get_world_pos(post_wheel_view)
	zoom_editor._gui_input(_motion(post_wheel_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		zoom_point.position.is_equal_approx(
			Vector2(post_wheel_world.x, zoom_origin.y).clamp(
				Vector2(0, zoom_curve.min_value),
				Vector2(1.0, zoom_curve.max_value),
			)
		),
		"Constrained drag after wheel zoom stopped using the original view-space drag axis",
	)
	zoom_editor._gui_input(_button(MOUSE_BUTTON_LEFT, post_wheel_view, false, true))
	zoom_editor._slider.free()
	zoom_editor.free()

	var endpoint_fixture := _fixture()
	var endpoint_curve: EasingCurve = endpoint_fixture.curve
	var endpoint_editor: EasingCurveEditor = endpoint_fixture.editor
	endpoint_curve.points[2].position = Vector2(1.0, endpoint_curve.points[2].position.y)
	var endpoint_points: Array[EasingCurvePoint] = endpoint_curve.points.duplicate()
	var endpoint_moved := endpoint_points[1]
	var endpoint_origin := endpoint_moved.position
	var endpoint_start := _point_view(endpoint_editor, endpoint_moved)
	endpoint_editor._gui_input(_button(MOUSE_BUTTON_LEFT, endpoint_start, true))
	var endpoint_target_view := endpoint_start + Vector2(1000.0, 5.0)
	endpoint_editor._gui_input(_motion(endpoint_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		endpoint_moved.position.is_equal_approx(Vector2(1.0, endpoint_origin.y)),
		"Horizontal constrained point drag did not clamp to the right X endpoint",
	)
	_expect(
		endpoint_curve.points == endpoint_points
		and endpoint_editor._get_display_points() == [endpoint_points[0], endpoint_moved],
		"Horizontal constrained endpoint takeover changed source order or failed to update the live preview",
	)
	endpoint_editor._gui_input(_button(MOUSE_BUTTON_LEFT, endpoint_target_view, false, true))
	_expect(
		endpoint_curve.points == [endpoint_points[0], endpoint_moved]
		and endpoint_editor.selected_index == 1,
		"Horizontal constrained endpoint takeover did not commit through the existing ordering path",
	)
	endpoint_editor._slider.free()
	endpoint_editor.free()

	var vertical_fixture := _fixture()
	var vertical_curve: EasingCurve = vertical_fixture.curve
	var vertical_editor: EasingCurveEditor = vertical_fixture.editor
	var vertical_points: Array[EasingCurvePoint] = vertical_curve.points.duplicate()
	var vertical_moved := vertical_points[1]
	var vertical_origin := vertical_moved.position
	var vertical_start := _point_view(vertical_editor, vertical_moved)
	vertical_editor._gui_input(_button(MOUSE_BUTTON_LEFT, vertical_start, true))
	var vertical_target_view := vertical_start + Vector2(5.0, -1000.0)
	vertical_editor._gui_input(_motion(vertical_target_view, MOUSE_BUTTON_MASK_LEFT, true))
	_expect(
		vertical_moved.position.is_equal_approx(
			Vector2(vertical_origin.x, vertical_curve.max_value)
		),
		"Vertical constrained point drag did not clamp Y while preserving the original X",
	)
	_expect(
		vertical_curve.points == vertical_points
		and vertical_editor._get_display_points() == vertical_points,
		"Vertical constrained movement changed point ordering during the live preview",
	)
	vertical_editor._gui_input(_button(MOUSE_BUTTON_LEFT, vertical_target_view, false, true))
	_expect(
		vertical_curve.points == vertical_points
		and vertical_editor.selected_index == 1,
		"Vertical constrained movement changed committed point ordering",
	)
	vertical_editor._slider.free()
	vertical_editor.free()


func _test_axis_constraint_request_and_input_boundaries() -> void:
	var point_fixture := _fixture()
	var point_curve: EasingCurve = point_fixture.curve
	var point_editor: EasingCurveEditor = point_fixture.editor
	var point_inspector: Object = point_fixture.inspector
	var point_requests: Array = []
	var point_finish := {"count": 0}
	point_editor.point_property_change_requested.connect(
		func(_index: int, property_name: StringName, _value: Variant, changing: bool) -> void:
			point_requests.append({"name": property_name, "changing": changing})
	)
	point_editor.point_edit_finished.connect(
		func(_point_order: Array[EasingCurvePoint]) -> void:
			point_finish["count"] += 1
	)
	var point := point_curve.points[1]
	var point_start := _point_view(point_editor, point)
	point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_start, true))
	point_editor._gui_input(_motion(point_start + Vector2(48.0, 10.0), MOUSE_BUTTON_MASK_LEFT, true))
	var point_transaction: Dictionary = point_inspector.get("_point_edit_before_state").duplicate(true)
	_expect(not point_transaction.is_empty(), "Constrained point drag did not start an edit transaction")
	_expect(point_inspector.get("_point_edit_action_name") == "Move Easing Curve Point", "Constrained point drag changed its Undo action name")
	point_editor._gui_input(_motion(point_start + Vector2(56.0, 12.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(point_inspector.get("_point_edit_before_state") == point_transaction, "Repeated constrained point motion started a second edit transaction")
	var point_request_names := []
	var point_requests_all_changing := true
	for request: Dictionary in point_requests:
		point_request_names.append(request["name"])
		point_requests_all_changing = point_requests_all_changing and bool(request["changing"])
	_expect(
		point_request_names == [
			&"position", &"left_control_point", &"right_control_point",
			&"position", &"left_control_point", &"right_control_point",
		],
		"Constrained point drag changed the existing point/control request sequence",
	)
	_expect(point_requests_all_changing, "Constrained point drag emitted a non-changing motion request")
	var point_request_count_before_release := point_requests.size()
	point_editor._gui_input(_button(MOUSE_BUTTON_LEFT, point_start + Vector2(56.0, 12.0), false, true))
	_expect(point_requests.size() == point_request_count_before_release, "Constrained point release emitted an extra point-property request")
	_expect(int(point_finish["count"]) == 1, "Constrained point drag emitted the wrong number of edit-finished boundaries")
	_expect(point_inspector.get("_point_edit_before_state").is_empty(), "Constrained point drag left the Inspector transaction open after release")
	point_editor._slider.free()
	point_editor.free()

	var handle_fixture := _fixture()
	var handle_curve: EasingCurve = handle_fixture.curve
	var handle_editor: EasingCurveEditor = handle_fixture.editor
	var handle_inspector: Object = handle_fixture.inspector
	var handle_requests: Array = []
	var handle_finish := {"count": 0}
	handle_editor.point_property_change_requested.connect(
		func(_index: int, property_name: StringName, _value: Variant, changing: bool) -> void:
			handle_requests.append({"name": property_name, "changing": changing})
	)
	handle_editor.point_edit_finished.connect(
		func(_point_order: Array[EasingCurvePoint]) -> void:
			handle_finish["count"] += 1
	)
	var handle_point := handle_curve.points[1]
	var handle_start := handle_editor.get_view_pos(handle_point.right_control_point)
	handle_editor._gui_input(_button(MOUSE_BUTTON_LEFT, handle_start, true))
	handle_editor._gui_input(_motion(handle_start + Vector2(46.0, -8.0), MOUSE_BUTTON_MASK_LEFT, true))
	var handle_transaction: Dictionary = handle_inspector.get("_point_edit_before_state").duplicate(true)
	_expect(not handle_transaction.is_empty(), "Constrained handle drag did not start an edit transaction")
	_expect(handle_inspector.get("_point_edit_action_name") == "Move Easing Curve Handle", "Constrained handle drag changed its Undo action name")
	handle_editor._gui_input(_motion(handle_start + Vector2(54.0, -10.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(handle_inspector.get("_point_edit_before_state") == handle_transaction, "Repeated constrained handle motion started a second edit transaction")
	var handle_request_names := []
	var handle_requests_all_changing := true
	for request: Dictionary in handle_requests:
		handle_request_names.append(request["name"])
		handle_requests_all_changing = handle_requests_all_changing and bool(request["changing"])
	_expect(handle_request_names == [&"right_control_point", &"right_control_point"], "Constrained handle drag changed the existing handle request sequence")
	_expect(handle_requests_all_changing, "Constrained handle drag emitted a non-changing motion request")
	handle_editor._gui_input(_button(MOUSE_BUTTON_LEFT, handle_start + Vector2(54.0, -10.0), false, true))
	_expect(int(handle_finish["count"]) == 1, "Constrained handle drag emitted the wrong number of edit-finished boundaries")
	_expect(handle_inspector.get("_point_edit_before_state").is_empty(), "Constrained handle drag left the Inspector transaction open after release")
	handle_editor._slider.free()
	handle_editor.free()

	var noop_fixture := _fixture()
	var noop_curve: EasingCurve = noop_fixture.curve
	var noop_editor: EasingCurveEditor = noop_fixture.editor
	var noop_inspector: Object = noop_fixture.inspector
	var noop_point := noop_curve.points[1]
	var noop_position := noop_point.position
	var noop_left := noop_point.left_control_point
	var noop_right := noop_point.right_control_point
	var noop_start := _point_view(noop_editor, noop_point)
	noop_editor._gui_input(_button(MOUSE_BUTTON_LEFT, noop_start, true))
	noop_editor._gui_input(_motion(noop_start, MOUSE_BUTTON_MASK_LEFT, true))
	noop_editor._gui_input(_button(MOUSE_BUTTON_LEFT, noop_start, false, true))
	_expect(
		noop_point.position.is_equal_approx(noop_position)
		and noop_point.left_control_point.is_equal_approx(noop_left)
		and noop_point.right_control_point.is_equal_approx(noop_right),
		"Zero-displacement constrained drag changed point geometry",
	)
	_expect(noop_inspector.get("_point_edit_before_state").is_empty(), "Zero-displacement constrained drag left a transaction open")
	noop_editor._slider.free()
	noop_editor.free()

	var pending_fixture := _fixture()
	var pending_curve: EasingCurve = pending_fixture.curve
	var pending_editor: EasingCurveEditor = pending_fixture.editor
	var pending_count := pending_curve.points.size()
	var pending_start := Vector2(580.0, 280.0)
	var pending_target := Vector2(540.0, 250.0)
	pending_editor._gui_input(_button(MOUSE_BUTTON_LEFT, pending_start, true, true))
	_expect(pending_editor.pending_add_point != null, "Pre-held Shift prevented ordinary pending-add start")
	pending_editor._gui_input(_motion(pending_target, MOUSE_BUTTON_MASK_LEFT, true))
	var expected_pending := pending_editor.get_world_pos(pending_target).clamp(
		Vector2(0, pending_curve.min_value),
		Vector2(1.0, pending_curve.max_value),
	)
	_expect(pending_editor.pending_add_point.position.is_equal_approx(expected_pending), "Shift changed pending-add mouse tracking")
	pending_editor._gui_input(_button(MOUSE_BUTTON_RIGHT, pending_target, true, true))
	_expect(pending_editor.pending_add_point == null and pending_curve.points.size() == pending_count and not pending_editor.is_right_delete_dragging, "Shift changed RMB pending-add cancel semantics")
	pending_editor._gui_input(_button(MOUSE_BUTTON_RIGHT, pending_target, false, true))
	pending_editor._gui_input(_button(MOUSE_BUTTON_LEFT, pending_target, false, true))
	pending_editor._slider.free()
	pending_editor.free()

	var delete_fixture := _fixture()
	var delete_curve: EasingCurve = delete_fixture.curve
	var delete_editor: EasingCurveEditor = delete_fixture.editor
	var deleted_point := delete_curve.points[1]
	var delete_view := delete_editor.get_view_pos(deleted_point.position)
	delete_editor._gui_input(_button(MOUSE_BUTTON_RIGHT, delete_view, true, true))
	_expect(not delete_curve.points.has(deleted_point), "Shift changed RMB point deletion")
	delete_editor._gui_input(_button(MOUSE_BUTTON_RIGHT, delete_view, false, true))
	_expect(not delete_editor.is_right_delete_dragging, "Shift+RMB release left delete-drag active")
	delete_editor._slider.free()
	delete_editor.free()

	var navigation_fixture := _fixture()
	var navigation_editor: EasingCurveEditor = navigation_fixture.editor
	get_root().add_child(navigation_editor)
	var pan_before := navigation_editor.pan_offset
	navigation_editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, Vector2(100.0, 100.0), true, true))
	navigation_editor._gui_input(_motion(Vector2(125.0, 115.0), MOUSE_BUTTON_MASK_MIDDLE, true))
	navigation_editor._gui_input(_button(MOUSE_BUTTON_MIDDLE, Vector2(125.0, 115.0), false, true))
	_expect(navigation_editor.pan_offset == pan_before + Vector2(25.0, 15.0) and not navigation_editor.is_panning, "Shift changed MMB pan semantics")
	var zoom_before := navigation_editor._zoom_step
	navigation_editor._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, Vector2(200.0, 150.0), true, true))
	_expect(navigation_editor._zoom_step == mini(zoom_before + 1, EasingCurve.ZOOM_STEPS), "Shift changed wheel zoom semantics")
	var hover_view := navigation_editor.get_view_pos(navigation_fixture.curve.points[1].position)
	navigation_editor._gui_input(_motion(hover_view, 0, true))
	_expect(navigation_editor.hovered_index == 1, "Shift changed ordinary graph hover detection")
	navigation_editor.get_parent().remove_child(navigation_editor)
	navigation_editor._slider.free()
	navigation_editor.free()

	var function_fixture := _fixture()
	var function_curve: EasingCurve = function_fixture.curve
	var function_editor: EasingCurveEditor = function_fixture.editor
	function_curve.curve_mode = EasingCurve.CurveMode.FUNCTION
	function_editor.hovered_index = -1
	function_editor._gui_input(_button(MOUSE_BUTTON_LEFT, Vector2(500.0, 250.0), true, true))
	function_editor._gui_input(_motion(Vector2(300.0, 160.0), MOUSE_BUTTON_MASK_LEFT, true))
	_expect(function_editor.pending_add_point == null and function_editor.dragging_point == -1 and function_editor.hovered_index == -1, "Shift activated graph point input in Function mode")
	function_editor._slider.free()
	function_editor.free()


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

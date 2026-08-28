extends SceneTree

const EDITOR_UNDO = preload("res://addons/easing_curve/scripts/easing_curve_editor_undo.gd")
const INSPECTOR_PLUGIN = preload("res://addons/easing_curve/easing_curve_editor_inspector_plugin.gd")
const RELOAD_ICON = preload("res://addons/easing_curve/assets/icons/Reload.svg")
const EDITOR_HOST = preload("res://test/auto/editor_host_test_harness.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	if not EDITOR_HOST.require_inspector_host("editor_undo_redo_test.gd"):
		quit(1)
		return
	seed(948217)
	_test_editor_snapshot_contract()
	_test_no_op_action_rejected()
	_test_point_drag()
	_test_handle_drag()
	_test_add_point()
	_test_topology_selection_undo_redo()
	_test_remove_point()
	_test_point_lock()
	_test_point_reset()
	_test_point_reorder()
	_test_preset_changes()
	_test_preset_modified_detection()
	_test_back_overshoot_undo_redo()
	_test_back_overshoot_property_reset()
	_test_back_modified_reset_uses_current_overshoot()
	_test_back_point_property_defaults()
	_test_preset_reset_layout_stability()
	_test_transition_presentation_contract()
	_test_css_cubic_bezier_dropdown_order()
	if EDITOR_HOST.supports_native_layout_fixtures():
		_test_points_foldable_section()
		_test_responsive_graph_layout()
	else:
		print("SKIP: native layout fixtures require a visible Editor host; Godot 4.7 crashes FoldableContainer and cannot validate responsive layout under --editor --headless")
	_test_three_point_preset_modified_detection()
	_test_preset_modified_undo_redo()
	_test_clean_preset_ease_reset_undo_redo()
	_test_preset_ease_control_availability()
	_test_preset_reset_undo_redo()
	_test_function_parameter_changes()
	_test_parameter_reset()
	_test_generate_action()

	if _failures == 0:
		print("PASS: %d editor Undo / Redo checks" % _checks)
	else:
		push_error("FAIL: %d of %d editor Undo / Redo checks failed" % [_failures, _checks])
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error(message)


func _contains_resource(value: Variant) -> bool:
	if value is Resource:
		return true
	if value is Dictionary:
		for key in value:
			if _contains_resource(key) or _contains_resource(value[key]):
				return true
	elif value is Array:
		for item in value:
			if _contains_resource(item):
				return true
	return false


func _test_editor_snapshot_contract() -> void:
	var curve := _three_point_curve()
	var snapshot := curve.get_editor_state_snapshot()
	_expect(not _contains_resource(snapshot), "Complete editor state snapshot contains a Resource")
	var found_property := false
	for property in curve.get_property_list():
		if property.name == EasingCurve.EDITOR_STATE_SNAPSHOT_PROPERTY:
			found_property = true
			_expect(
				(property.usage & PROPERTY_USAGE_STORAGE) == 0,
				"Editor state snapshot changed curve serialization",
			)
	_expect(found_property, "Editor state snapshot property is not registered")


func _signal_counts(curve: EasingCurve) -> Dictionary:
	var counts := {"changed": 0, "points": 0}
	curve.changed.connect(func() -> void: counts.changed += 1)
	curve.points_changed.connect(
		func(_updated_points: Array[EasingCurvePoint]) -> void: counts.points += 1,
	)
	return counts


func _dispose_history(history: UndoRedo) -> void:
	history.clear_history(false)
	history.free()


func _three_point_curve() -> EasingCurve:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var points: Array[EasingCurvePoint] = [
		EasingCurvePoint.new(Vector2.ZERO),
		EasingCurvePoint.new(Vector2(0.5, 0.75)),
		EasingCurvePoint.new(Vector2.ONE),
	]
	points[0].right_control_point = Vector2(0.2, 0.1)
	points[1].left_control_point = Vector2(0.35, 0.7)
	points[1].right_control_point = Vector2(0.65, 0.8)
	points[2].left_control_point = Vector2(0.8, 0.95)
	curve.set_point_snapshot(curve.make_point_snapshot(points))
	return curve


func _commit_applied(
		history: UndoRedo,
		curve: EasingCurve,
		action_name: String,
		before: Dictionary,
) -> Dictionary:
	var after := EDITOR_UNDO.capture_state(curve)
	_expect(
		EDITOR_UNDO.commit_applied_action(history, curve, action_name, EasingCurveEditorUndo.ActionContext.new(before, after)),
		"%s was not added to Undo / Redo history" % action_name,
	)
	return after


func _verify_single_action(
		history: UndoRedo,
		curve: EasingCurve,
		before: Dictionary,
		after: Dictionary,
		label: String,
		cycles: int = 1,
) -> void:
	_expect(history.has_undo(), "%s did not create an Undo action" % label)
	for cycle in range(cycles):
		history.undo()
		_expect(curve.get_editor_state_snapshot() == before, "%s Undo lost state on cycle %d" % [label, cycle + 1])
		_expect(not history.has_undo(), "%s created more than one history action" % label)
		_expect(history.has_redo(), "%s Undo did not create a Redo action" % label)
		history.redo()
		_expect(curve.get_editor_state_snapshot() == after, "%s Redo lost state on cycle %d" % [label, cycle + 1])
		_expect(history.has_undo(), "%s Redo did not restore the Undo action" % label)


func _test_no_op_action_rejected() -> void:
	var curve := _three_point_curve()
	var history := UndoRedo.new()
	var state := EDITOR_UNDO.capture_state(curve)
	_expect(
		not EDITOR_UNDO.commit_applied_action(
			history,
			curve,
			"No-op Easing Curve Edit",
			EasingCurveEditorUndo.ActionContext.new(state, state.duplicate(true)),
		),
		"Identical before/after state created an Undo action",
	)
	_expect(not history.has_undo() and not history.has_redo(), "Rejected no-op action left Undo/Redo history entries")
	_dispose_history(history)


func _test_point_drag() -> void:
	var curve := _three_point_curve()
	var history := UndoRedo.new()
	var counts := _signal_counts(curve)
	var before := EDITOR_UNDO.capture_state(curve)
	for step in range(1, 8):
		var snapshot := curve.get_point_snapshot()
		var positions: PackedVector2Array = snapshot.positions
		var left_handles: PackedVector2Array = snapshot.left_control_points
		var right_handles: PackedVector2Array = snapshot.right_control_points
		var next_position := Vector2(0.5 + step * 0.02, 0.75 - step * 0.03)
		var delta := next_position - positions[1]
		positions[1] = next_position
		left_handles[1] += delta
		right_handles[1] += delta
		snapshot.positions = positions
		snapshot.left_control_points = left_handles
		snapshot.right_control_points = right_handles
		snapshot.changing = true
		curve.set_point_snapshot(snapshot)
	_expect(counts.changed == 0 and counts.points == 0, "Point drag emitted final signals during mouse motion")
	var after := EDITOR_UNDO.capture_state(curve)
	curve.set_point_snapshot(curve.get_point_snapshot())
	_expect(counts.changed == 1 and counts.points == 1, "Point drag did not finalize signals exactly once")
	_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Move Easing Curve Point", EasingCurveEditorUndo.ActionContext.new(before, after)), "Point drag was not committed")
	counts.changed = 0
	counts.points = 0
	_verify_single_action(history, curve, before, after, "Point drag", 3)
	_expect(counts.changed == 6 and counts.points == 6, "Repeated point Undo / Redo did not emit one signal pair per state")
	_dispose_history(history)


func _test_handle_drag() -> void:
	var curve := _three_point_curve()
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)
	for step in range(1, 10):
		var snapshot := curve.get_point_snapshot()
		var handles: PackedVector2Array = snapshot.right_control_points
		handles[0] = Vector2(0.2 + step * 0.015, 0.1 + step * 0.025)
		snapshot.right_control_points = handles
		snapshot.changing = true
		curve.set_point_snapshot(snapshot)
	var after := EDITOR_UNDO.capture_state(curve)
	curve.set_point_snapshot(curve.get_point_snapshot())
	_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Move Easing Curve Handle", EasingCurveEditorUndo.ActionContext.new(before, after)), "Handle drag was not committed")
	_verify_single_action(history, curve, before, after, "Handle drag", 3)
	_dispose_history(history)


func _test_add_point() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)
	var added := EasingCurvePoint.new(Vector2(0.4, 0.85))
	added.left_control_point = Vector2(0.3, 0.7)
	added.right_control_point = Vector2(0.55, 0.9)
	added.set_locked("right_control_point", true)
	var points: Array[EasingCurvePoint] = curve.points.duplicate()
	points.append(added)
	points.sort_custom(func(a: EasingCurvePoint, b: EasingCurvePoint) -> bool: return a.position.x < b.position.x)
	curve.set_point_snapshot(curve.make_point_snapshot(points))
	var after := _commit_applied(history, curve, "Add Easing Curve Point", before)
	_verify_single_action(history, curve, before, after, "Add point", 3)
	_expect(curve.points.size() == 3, "Add point Redo did not restore topology")
	_expect(curve.points[1].locked.right_control_point, "Add point Redo did not restore point locks")
	_expect(curve.points[1].changed.is_connected(Callable(curve, "_on_point_changed")), "Add point Redo left the restored point disconnected")
	_dispose_history(history)


func _test_topology_selection_undo_redo() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.CUSTOM
	curve.points = [
		EasingCurvePoint.new(Vector2.ZERO),
		EasingCurvePoint.new(Vector2.ONE),
	]
	var editor_context := EDITOR_HOST.create_inspector_context(curve)
	var editor: EasingCurveEditor = editor_context.editor
	var inspector: Object = editor_context.inspector
	var history := UndoRedo.new()
	inspector.call("_clear_point_property_selection")
	editor.selected_index = -1

	var add_a_before := EDITOR_UNDO.capture_state(curve)
	var add_a_before_selection: Dictionary = inspector.call(
		"_capture_point_selection_state"
	)
	var point_a := EasingCurvePoint.new(Vector2(0.33, 0.25))
	var add_a_points: Array[EasingCurvePoint] = curve.points.duplicate()
	add_a_points.append(point_a)
	var point_a_index := add_a_points.find(point_a)
	curve.set_point_snapshot(curve.make_point_snapshot(add_a_points))
	inspector.call("_select_reordered_point", curve.points[point_a_index])
	var add_a_after_selection: Dictionary = inspector.call(
		"_capture_point_selection_state"
	)
	_expect(
		EDITOR_UNDO.commit_applied_action(
			history,
			curve,
			"Add Easing Curve Point A",
			EasingCurveEditorUndo.ActionContext.new(add_a_before).with_selection(
				Callable(inspector, "_restore_point_selection_state"),
				add_a_before_selection,
				add_a_after_selection,
			),
		),
		"Add A did not record selection restoration",
	)
	_expect(editor.selected_index == point_a_index, "Add A did not select its point")
	history.undo()
	_expect(editor.selected_index == -1, "Undo Add A did not restore no graph selection")
	_expect(inspector.get("_selected_point_index") == -1, "Undo Add A did not restore no list selection")
	history.redo()
	point_a_index = int(add_a_after_selection.point_index)
	_expect(editor.selected_index == point_a_index, "Redo Add A did not restore graph selection")
	_expect(inspector.get("_selected_point_index") == point_a_index, "Redo Add A did not restore list selection")

	var add_b_before := EDITOR_UNDO.capture_state(curve)
	var add_b_before_selection: Dictionary = inspector.call(
		"_capture_point_selection_state"
	)
	var point_b := EasingCurvePoint.new(Vector2(0.66, 0.75))
	var add_b_points: Array[EasingCurvePoint] = curve.points.duplicate()
	add_b_points.append(point_b)
	var point_b_index := add_b_points.find(point_b)
	curve.set_point_snapshot(curve.make_point_snapshot(add_b_points))
	inspector.call("_select_reordered_point", curve.points[point_b_index])
	var add_b_after_selection: Dictionary = inspector.call(
		"_capture_point_selection_state"
	)
	_expect(
		EDITOR_UNDO.commit_applied_action(
			history,
			curve,
			"Add Easing Curve Point B",
			EasingCurveEditorUndo.ActionContext.new(add_b_before).with_selection(
				Callable(inspector, "_restore_point_selection_state"),
				add_b_before_selection,
				add_b_after_selection,
			),
		),
		"Add B did not record selection restoration",
	)
	history.undo()
	point_a_index = int(add_b_before_selection.point_index)
	_expect(editor.selected_index == point_a_index, "Undo Add B did not restore Add A selection")
	history.redo()
	point_b_index = int(add_b_after_selection.point_index)
	_expect(editor.selected_index == point_b_index, "Redo Add B did not restore Add B selection")
	history.undo()
	history.undo()
	_expect(editor.selected_index == -1, "Undoing both adds did not restore no graph selection")
	_expect(inspector.get("_selected_point_index") == -1, "Undoing both adds did not restore no list selection")
	history.redo()
	_expect(editor.selected_index == point_a_index, "Redo Add A after no selection did not restore A")
	history.redo()
	_expect(editor.selected_index == point_b_index, "Redo Add B after no selection did not restore B")
	history.clear_history(false)
	history.free()
	editor.free()

func _test_remove_point() -> void:
	var curve := _three_point_curve()
	curve.points[1].set_locked("position", true)
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)
	var points: Array[EasingCurvePoint] = curve.points.duplicate()
	points.remove_at(1)
	curve.set_point_snapshot(curve.make_point_snapshot(points))
	var after := _commit_applied(history, curve, "Remove Easing Curve Point", before)
	_verify_single_action(history, curve, before, after, "Remove point", 3)
	history.undo()
	_expect(curve.points.size() == 3, "Remove point Undo did not restore topology")
	_expect(curve.points[1].locked.position, "Remove point Undo did not restore point properties")
	_expect(curve.points[1].changed.is_connected(Callable(curve, "_on_point_changed")), "Remove point Undo left the restored point disconnected")
	_dispose_history(history)


func _test_point_lock() -> void:
	var curve := _three_point_curve()
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)
	curve.set_point_locked(1, &"left_control_point", true)
	var after := _commit_applied(history, curve, "Change Easing Curve Point Lock", before)
	_verify_single_action(history, curve, before, after, "Point lock", 3)
	_expect(curve.points[1].locked.left_control_point, "Point lock Redo did not restore the lock")
	_dispose_history(history)


func _test_point_reset() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.SINE
	curve.points[0].right_control_point = Vector2(0.45, 0.8)
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)
	var snapshot := curve.get_point_snapshot()
	var handles: PackedVector2Array = snapshot.right_control_points
	handles[0] = curve.get_default_for_property(0, "right_control_point")
	snapshot.right_control_points = handles
	curve.set_point_snapshot(snapshot)
	var after := _commit_applied(history, curve, "Reset Easing Curve Point", before)
	_verify_single_action(history, curve, before, after, "Point reset", 3)
	_dispose_history(history)


func _test_point_reorder() -> void:
	var curve := _three_point_curve()
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)
	curve.swap_points(1, 2)
	var after := _commit_applied(history, curve, "Reorder Easing Curve Points", before)
	_verify_single_action(history, curve, before, after, "Point reorder", 3)
	_dispose_history(history)


func _test_preset_changes() -> void:
	var curve := _three_point_curve()
	var custom_state := EDITOR_UNDO.capture_state(curve)
	var transition_history := UndoRedo.new()
	curve.trans_type = EasingCurve.TRANS.SINE
	var sine_in_state := _commit_applied(
		transition_history,
		curve,
		"Change Easing Curve Transition",
		custom_state,
	)
	_expect(curve.points.size() == 2, "Sine In preset did not produce the expected topology")
	_verify_single_action(transition_history, curve, custom_state, sine_in_state, "Transition preset", 3)
	_dispose_history(transition_history)

	var ease_history := UndoRedo.new()
	var before_ease := EDITOR_UNDO.capture_state(curve)
	curve.ease_type = EasingCurve.EASE.IN_OUT
	var combined_state := _commit_applied(ease_history, curve, "Change Easing Curve Ease", before_ease)
	_expect(curve.points.size() == 3, "Combined preset did not retain its three-point geometry")
	_expect(curve.points[1].position == Vector2(0.5, 0.5), "Combined preset midpoint changed")
	_verify_single_action(ease_history, curve, before_ease, combined_state, "Three-point ease preset", 5)
	_dispose_history(ease_history)


func _test_preset_modified_detection() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.SINE
	var canonical := curve.get_canonical_preset_point_snapshot()
	_expect(curve.has_builtin_bezier_preset(), "Sine was not recognized as a built-in Bezier preset")
	_expect(not curve.is_selected_preset_modified(), "Untouched Sine preset reported modified")

	curve.points[0].position += Vector2(0.02, 0.03)
	_expect(curve.is_selected_preset_modified(), "Point edit did not mark the preset modified")
	curve.set_point_snapshot(canonical.duplicate(true))
	_expect(not curve.is_selected_preset_modified(), "Exact point restoration did not clear modified state")

	curve.points[0].right_control_point += Vector2(0.03, -0.02)
	_expect(curve.is_selected_preset_modified(), "Handle edit did not mark the preset modified")
	curve.set_point_snapshot(canonical.duplicate(true))

	curve.points[0].set_locked("right_control_point", true)
	_expect(curve.is_selected_preset_modified(), "Point lock edit did not mark the preset modified")
	curve.set_point_snapshot(canonical.duplicate(true))

	var added_points: Array[EasingCurvePoint] = curve.points.duplicate()
	added_points.append(EasingCurvePoint.new(Vector2(0.4, 0.6)))
	added_points.sort_custom(func(a: EasingCurvePoint, b: EasingCurvePoint) -> bool: return a.position.x < b.position.x)
	curve.set_point_snapshot(curve.make_point_snapshot(added_points))
	_expect(curve.is_selected_preset_modified(), "Adding a point did not mark the preset modified")
	curve.set_point_snapshot(canonical.duplicate(true))

	var removed_points: Array[EasingCurvePoint] = curve.points.duplicate()
	removed_points.remove_at(0)
	curve.set_point_snapshot(curve.make_point_snapshot(removed_points))
	_expect(curve.is_selected_preset_modified(), "Removing a point did not mark the preset modified")
	curve.set_point_snapshot(canonical.duplicate(true))

	curve.swap_points(0, 1)
	_expect(curve.is_selected_preset_modified(), "Reordering preset points did not mark the preset modified")
	curve.set_point_snapshot(canonical.duplicate(true))
	_expect(not curve.is_selected_preset_modified(), "Canonical topology restoration did not clear modified state")
	curve.points[0].position.x += EasingCurve.PRESET_GEOMETRY_TOLERANCE * 0.5
	_expect(not curve.is_selected_preset_modified(), "Sub-tolerance geometry noise marked the preset modified")
	curve.set_point_snapshot(canonical.duplicate(true))

	var custom_curve := EasingCurve.new()
	custom_curve.trans_type = EasingCurve.TRANS.CUSTOM
	custom_curve.points[0].position += Vector2(0.1, 0.2)
	_expect(not custom_curve.has_builtin_bezier_preset(), "Custom curve was classified as a built-in preset")
	_expect(not custom_curve.is_selected_preset_modified(), "Custom curve reported as a modified built-in preset")
	var custom_snapshot := custom_curve.get_point_snapshot()
	_expect(not custom_curve.reset_selected_preset(), "Custom curve exposed the built-in preset reset")
	_expect(custom_curve.get_point_snapshot() == custom_snapshot, "Built-in preset reset changed a Custom curve")


func _test_three_point_preset_modified_detection() -> void:
	for ease in [EasingCurve.EASE.IN_OUT, EasingCurve.EASE.OUT_IN]:
		var curve := EasingCurve.new()
		curve.ease_type = ease
		curve.trans_type = EasingCurve.TRANS.QUAD
		var canonical := curve.get_canonical_preset_point_snapshot()
		var label: String = EasingCurve.EASE.keys()[ease]
		_expect(curve.points.size() == 3, "Quad %s did not generate three-point geometry" % label)
		_expect(not curve.is_selected_preset_modified(), "Untouched Quad %s reported modified" % label)
		curve.points[1].right_control_point += Vector2(0.01, 0.02)
		_expect(curve.is_selected_preset_modified(), "Quad %s midpoint edit was not detected" % label)
		curve.set_point_snapshot(canonical.duplicate(true))
		_expect(not curve.is_selected_preset_modified(), "Quad %s canonical geometry reported modified" % label)


func _test_preset_reset_layout_stability() -> void:
	var row := HBoxContainer.new()
	var transition_option := OptionButton.new()
	for transition_name in EasingCurve.TRANS.keys():
		var transition: int = EasingCurve.TRANS[transition_name]
		var display := String(transition_name).to_lower().capitalize().replace("_", " ")
		transition_option.add_item(display, transition)
	INSPECTOR_PLUGIN._configure_compact_option(transition_option)
	var constant_item := transition_option.get_item_index(EasingCurve.TRANS.CONSTANT)
	transition_option.select(constant_item)
	INSPECTOR_PLUGIN._set_transition_display(transition_option, EasingCurve.TRANS.CONSTANT, false)
	var reset_button := Button.new()
	reset_button.icon = RELOAD_ICON
	reset_button.flat = true
	row.add_child(transition_option)
	row.add_child(reset_button)
	INSPECTOR_PLUGIN._set_preset_reset_button_available(reset_button, false)
	var reserved_size := row.get_combined_minimum_size()

	_expect(not transition_option.fit_to_longest_item, "Transition dropdown still fits its longest item")
	_expect(transition_option.clip_text, "Transition dropdown does not clip narrow text")
	_expect(
		transition_option.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
		"Transition dropdown does not truncate with an ellipsis",
	)
	_expect(reset_button.visible, "Clean preset removed its reset button from layout")
	_expect(is_zero_approx(reset_button.self_modulate.a), "Clean preset reset button remained visible")
	_expect(reset_button.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Hidden reset button still receives mouse input")
	_expect(reset_button.focus_mode == Control.FOCUS_NONE, "Hidden reset button still receives focus input")
	_expect(row.get_combined_minimum_size() == reserved_size, "Clean preset changed reserved reset width")

	INSPECTOR_PLUGIN._set_transition_display(transition_option, EasingCurve.TRANS.CONSTANT, true)
	INSPECTOR_PLUGIN._set_preset_reset_button_available(reset_button, true)
	_expect(transition_option.get_item_text(constant_item) == "Constant *", "Modified marker was not shown inside the Transition dropdown")
	_expect(is_equal_approx(reset_button.self_modulate.a, 1.0), "Modified preset reset button remained hidden")
	_expect(reset_button.mouse_filter == Control.MOUSE_FILTER_STOP, "Visible reset button does not receive mouse input")
	_expect(reset_button.focus_mode == Control.FOCUS_ALL, "Visible reset button does not receive focus input")
	_expect(row.get_combined_minimum_size() == reserved_size, "Modified preset changed reserved reset width")

	for modified in [false, true]:
		for transition in EasingCurve.TRANS.values():
			transition_option.select(transition_option.get_item_index(transition))
			INSPECTOR_PLUGIN._set_transition_display(transition_option, transition, modified)
			_expect(row.get_combined_minimum_size() == reserved_size, "Transition text changed the dropdown minimum width")

	INSPECTOR_PLUGIN._set_transition_display(transition_option, EasingCurve.TRANS.CONSTANT, false)
	INSPECTOR_PLUGIN._set_preset_reset_button_available(reset_button, false)
	_expect(transition_option.get_item_text(constant_item) == "Constant", "Clean preset retained its modified marker")
	_expect(row.get_combined_minimum_size() == reserved_size, "Reset or mode switch changed reserved reset width")
	row.free()


func _test_css_cubic_bezier_dropdown_order() -> void:
	var transition_option := INSPECTOR_PLUGIN._create_transition_option(EasingCurve.TRANS.CSS_CUBIC_BEZIER)
	var linear_index := transition_option.get_item_index(EasingCurve.TRANS.CSS_LINEAR)
	var cubic_index := transition_option.get_item_index(EasingCurve.TRANS.CSS_CUBIC_BEZIER)
	_expect(linear_index >= 0, "CSS Linear is missing from the Transition dropdown")
	_expect(linear_index == cubic_index + 1, "CSS Linear is not directly below CSS Cubic Bezier")
	_expect(
		transition_option.get_selected_id() == EasingCurve.TRANS.CSS_CUBIC_BEZIER,
		"CSS Cubic Bezier could not be selected in the Transition dropdown",
	)
	_expect(
		not INSPECTOR_PLUGIN._transition_supports_ease(EasingCurve.TRANS.CSS_CUBIC_BEZIER),
		"CSS Cubic Bezier unexpectedly enables the Ease dropdown",
	)
	transition_option.free()


func _test_transition_presentation_contract() -> void:
	var expected_groups := [
		{"name": "Basic", "items": [EasingCurve.TRANS.LINEAR, EasingCurve.TRANS.CONSTANT]},
		{"name": "Polynomial", "items": [EasingCurve.TRANS.QUAD, EasingCurve.TRANS.CUBIC, EasingCurve.TRANS.QUART, EasingCurve.TRANS.QUINT, EasingCurve.TRANS.POWER]},
		{"name": "Smooth", "items": [EasingCurve.TRANS.SINE, EasingCurve.TRANS.CIRC, EasingCurve.TRANS.EXPO]},
		{"name": "Springy", "items": [EasingCurve.TRANS.BACK, EasingCurve.TRANS.ELASTIC, EasingCurve.TRANS.BOUNCE, EasingCurve.TRANS.SPRING, EasingCurve.TRANS.PHYSICS_SPRING]},
		{"name": "Discrete", "items": [EasingCurve.TRANS.STEP, EasingCurve.TRANS.JITTER, EasingCurve.TRANS.IRREGULAR]},
		{"name": "CSS", "items": [EasingCurve.TRANS.CSS_CUBIC_BEZIER, EasingCurve.TRANS.CSS_LINEAR]},
		{"name": "Custom", "items": [EasingCurve.TRANS.CUSTOM]},
	]
	var expected_without_ease := [
		EasingCurve.TRANS.CUSTOM,
		EasingCurve.TRANS.CONSTANT,
		EasingCurve.TRANS.LINEAR,
		EasingCurve.TRANS.STEP,
		EasingCurve.TRANS.CSS_LINEAR,
		EasingCurve.TRANS.CSS_CUBIC_BEZIER,
	]
	var option := INSPECTOR_PLUGIN._create_transition_option(EasingCurve.TRANS.CSS_LINEAR)
	var popup := option.get_popup()
	var expected_index := 0
	var seen := []

	for group: Dictionary in expected_groups:
		_expect(popup.is_item_separator(expected_index), "%s group separator is missing" % group["name"])
		_expect(popup.get_item_text(expected_index) == group["name"], "%s group label changed" % group["name"])
		expected_index += 1
		for transition: EasingCurve.TRANS in group["items"]:
			var expected_label := String(EasingCurve.TRANS.keys()[transition]).to_lower().capitalize().replace("_", " ")
			_expect(not popup.is_item_separator(expected_index), "%s became a separator" % expected_label)
			_expect(option.get_item_id(expected_index) == transition, "%s dropdown ID or order changed" % expected_label)
			_expect(option.get_item_text(expected_index) == expected_label, "%s dropdown label changed" % expected_label)
			seen.append(transition)
			expected_index += 1

	_expect(expected_index == popup.item_count, "Transition dropdown item count changed")
	_expect(seen.size() == EasingCurve.TRANS.size(), "Transition dropdown does not include every transition exactly once")
	for transition: EasingCurve.TRANS in EasingCurve.TRANS.values():
		_expect(seen.count(transition) == 1, "%s dropdown membership changed" % EasingCurve.TRANS.keys()[transition])
		_expect(INSPECTOR_PLUGIN._transition_supports_ease(transition) == (transition not in expected_without_ease), "%s Ease availability changed" % EasingCurve.TRANS.keys()[transition])
	_expect(option.get_selected_id() == EasingCurve.TRANS.CSS_LINEAR, "Transition dropdown selected ID changed")
	option.free()


func _test_responsive_graph_layout() -> void:
	var editor := EasingCurveEditor.new()
	var sizes_by_width := {}
	for width in [180.0, 390.0, 600.0, 390.0, 180.0]:
		editor.size = Vector2(width, 1.0)
		editor.update_minimum_size()
		var minimum := editor._get_minimum_size()
		_expect(is_equal_approx(minimum.x, 64.0), "Responsive graph changed its horizontal minimum")
		if sizes_by_width.has(width):
			_expect(minimum == sizes_by_width[width], "Repeated graph resize produced an unstable minimum size")
		else:
			sizes_by_width[width] = minimum

	var narrow: Vector2 = sizes_by_width[180.0]
	var proportional: Vector2 = sizes_by_width[390.0]
	var wide: Vector2 = sizes_by_width[600.0]
	_expect(is_equal_approx(narrow.y, EasingCurveEditor.MIN_GRAPH_HEIGHT), "Narrow graph became too short to use")
	_expect(proportional.y > narrow.y and wide.y > proportional.y, "Graph height did not grow with available width")
	_expect(is_equal_approx(proportional.y / 390.0, EasingCurveEditor.ASPECT_RATIO), "Graph lost its intended aspect ratio")
	_expect(is_equal_approx(wide.y / 600.0, EasingCurveEditor.ASPECT_RATIO), "Wide graph lost its intended aspect ratio")
	editor.free()


func _test_points_foldable_section() -> void:
	var curve := EasingCurve.new()
	var first_content := VBoxContainer.new()
	var first_control := Button.new()
	first_content.add_child(first_control)
	var first_section := INSPECTOR_PLUGIN.PointsFoldableSection.new()
	first_section.setup("Points", first_content, curve)
	_expect(first_section.title == "Points", "Points section title was not configured")
	_expect(not first_section.folded, "New Points section started collapsed")
	if is_instance_valid(first_section._native_section):
		for style_name in [
			&"panel",
			&"title_panel",
			&"title_collapsed_panel",
			&"title_hover_panel",
			&"title_collapsed_hover_panel",
		]:
			_expect(
				first_section._native_section.get_theme_stylebox(style_name) is StyleBoxEmpty,
				"Native Points disclosure retained its %s border" % style_name,
			)
	first_section.fold()
	_expect(first_section.folded, "Points section did not collapse")
	_expect(first_control.get_parent() == first_content, "Collapsing Points discarded its editing controls")

	var second_content := VBoxContainer.new()
	var second_section := INSPECTOR_PLUGIN.PointsFoldableSection.new()
	second_section.setup("Points", second_content, curve)
	_expect(second_section.folded, "Points section did not preserve its transient collapsed state")
	second_section.expand()
	_expect(not second_section.folded, "Points section did not expand again")

	var third_section := INSPECTOR_PLUGIN.PointsFoldableSection.new()
	third_section.setup("Points", VBoxContainer.new(), curve)
	_expect(not third_section.folded, "Expanded Points state was not preserved after rebuilding the Inspector")
	INSPECTOR_PLUGIN.PointsFoldableSection.folded_by_section.erase("%d:%s" % [curve.get_instance_id(), "Points"])
	first_section.free()
	second_section.free()
	third_section.free()


func _test_preset_modified_undo_redo() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.SINE
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)
	curve.points[0].position += Vector2(0.05, 0.02)
	var after := _commit_applied(history, curve, "Move Easing Curve Point", before)
	_expect(curve.is_selected_preset_modified(), "Preset edit did not report modified before Undo")
	history.undo()
	_expect(not curve.is_selected_preset_modified(), "Undo did not return the preset indicator to clean")
	history.redo()
	_expect(curve.is_selected_preset_modified(), "Redo did not restore the preset modified indicator")
	_expect(curve.get_editor_state_snapshot() == after, "Redo did not restore the modified preset geometry")
	_dispose_history(history)


func _test_clean_preset_ease_reset_undo_redo() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.QUAD
	curve.ease_type = EasingCurve.EASE.OUT
	var before := EDITOR_UNDO.capture_state(curve)
	var history := UndoRedo.new()
	curve.ease_type = EasingCurve.EASE.IN
	var after := _commit_applied(history, curve, "Change Easing Curve Ease", before)
	_expect(curve.ease_type == EasingCurve.EASE.IN, "Ease reset did not select the default In mode")
	_expect(
		curve.get_point_snapshot() == curve.get_canonical_preset_point_snapshot(),
		"Ease reset did not regenerate canonical In geometry",
	)
	_expect(not curve.is_selected_preset_modified(), "Ease reset made a clean preset modified")
	_verify_single_action(history, curve, before, after, "Clean preset Ease reset", 3)
	_dispose_history(history)


func _test_preset_ease_control_availability() -> void:
	var ease_control := INSPECTOR_PLUGIN._create_option(EasingCurve.EASE, EasingCurve.EASE.OUT)
	var trans_control := INSPECTOR_PLUGIN._create_option(EasingCurve.TRANS, EasingCurve.TRANS.QUAD)
	var ease_reset := INSPECTOR_PLUGIN._create_reserved_reset_button("Reset Ease to In")
	var preset_reset := INSPECTOR_PLUGIN._create_reserved_reset_button("Restore preset")
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.QUAD
	curve.ease_type = EasingCurve.EASE.OUT
	curve.add_point(EasingCurvePoint.new(Vector2(0.4, 0.2)))
	curve.sort_points()
	var modified_state := curve.get_editor_state_snapshot()

	INSPECTOR_PLUGIN._update_preset_state_ui(curve, ease_control, trans_control, ease_reset, preset_reset)
	_expect(ease_control.disabled, "Modified Quad did not disable its Ease dropdown")
	_expect(ease_control.get_selected_id() == EasingCurve.EASE.OUT, "Disabled modified Quad lost its selected Ease")
	_expect(is_zero_approx(ease_reset.self_modulate.a), "Modified Quad displayed its unavailable Ease reset arrow")
	_expect(ease_reset.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Modified Quad Ease reset receives mouse input")
	_expect(ease_reset.focus_mode == Control.FOCUS_NONE, "Modified Quad Ease reset receives focus input")
	_expect(is_equal_approx(preset_reset.self_modulate.a, 1.0), "Modified Quad did not show its preset reset arrow")

	_expect(curve.reset_selected_preset(), "Modified Quad could not be restored for the Ease availability test")
	var clean_state := curve.get_editor_state_snapshot()
	INSPECTOR_PLUGIN._update_preset_state_ui(curve, ease_control, trans_control, ease_reset, preset_reset)
	_expect(not ease_control.disabled, "Reset Quad did not re-enable its Ease dropdown")
	_expect(is_equal_approx(ease_reset.self_modulate.a, 1.0), "Clean Quad Out did not show its Ease reset arrow")
	_expect(is_zero_approx(preset_reset.self_modulate.a), "Clean Quad retained its preset reset arrow")

	curve.set_editor_state_snapshot(modified_state)
	INSPECTOR_PLUGIN._update_preset_state_ui(curve, ease_control, trans_control, ease_reset, preset_reset)
	_expect(ease_control.disabled, "Undo-equivalent modified state did not disable Ease")
	curve.set_editor_state_snapshot(clean_state)
	INSPECTOR_PLUGIN._update_preset_state_ui(curve, ease_control, trans_control, ease_reset, preset_reset)
	_expect(not ease_control.disabled, "Redo-equivalent clean state did not re-enable Ease")

	var custom_curve := EasingCurve.new()
	custom_curve.trans_type = EasingCurve.TRANS.CUSTOM
	INSPECTOR_PLUGIN._update_preset_state_ui(custom_curve, ease_control, trans_control, ease_reset, preset_reset)
	_expect(ease_control.disabled, "Custom curve unexpectedly enabled its Ease dropdown")
	_expect(is_zero_approx(ease_reset.self_modulate.a), "Custom curve displayed an unavailable Ease reset arrow")
	_expect(ease_reset.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Hidden Ease reset still receives mouse input")
	_expect(ease_reset.focus_mode == Control.FOCUS_NONE, "Hidden Ease reset still receives focus input")

	ease_control.free()
	trans_control.free()
	ease_reset.free()
	preset_reset.free()


func _test_preset_reset_undo_redo() -> void:
	var curve := EasingCurve.new()
	curve.ease_type = EasingCurve.EASE.IN_OUT
	curve.trans_type = EasingCurve.TRANS.QUAD
	var canonical := curve.get_canonical_preset_point_snapshot()
	var customized_points: Array[EasingCurvePoint] = curve.points.duplicate()
	customized_points.append(EasingCurvePoint.new(Vector2(0.75, 0.9)))
	customized_points.sort_custom(func(a: EasingCurvePoint, b: EasingCurvePoint) -> bool: return a.position.x < b.position.x)
	curve.set_point_snapshot(curve.make_point_snapshot(customized_points))
	var customized := EDITOR_UNDO.capture_state(curve)
	_expect(curve.is_selected_preset_modified(), "Reset test setup did not modify the preset")

	var history := UndoRedo.new()
	_expect(curve.reset_selected_preset(), "Modified preset refused to reset")
	var reset_state := _commit_applied(history, curve, "Reset Easing Curve Preset", customized)
	_expect(curve.get_point_snapshot() == canonical, "Reset did not restore exact canonical preset geometry")
	_expect(not curve.is_selected_preset_modified(), "Reset preset still reported modified")
	_expect(history.has_undo(), "Preset reset did not create an Undo action")
	history.undo()
	_expect(curve.get_editor_state_snapshot() == customized, "Undo reset did not restore customized geometry")
	_expect(curve.is_selected_preset_modified(), "Undo reset did not restore modified state")
	_expect(not history.has_undo() and history.has_redo(), "Preset reset created more than one Undo action")
	history.redo()
	_expect(curve.get_editor_state_snapshot() == reset_state, "Redo reset did not restore canonical state")
	_expect(curve.get_point_snapshot() == canonical, "Redo reset did not restore exact canonical geometry")
	_expect(not curve.is_selected_preset_modified(), "Redo reset did not clear modified state")
	_dispose_history(history)


func _test_back_overshoot_undo_redo() -> void:
	var curve := EasingCurve.new()
	curve.ease_type = EasingCurve.EASE.OUT_IN
	curve.trans_type = EasingCurve.TRANS.BACK
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)
	var before_geometry := curve.get_point_snapshot()

	curve._begin_editor_parameter_edit()
	curve.overshoot = 3.25
	var after := EDITOR_UNDO.capture_state(curve)
	var after_geometry := curve.get_point_snapshot()
	curve._finish_editor_parameter_edit()

	_expect(is_equal_approx(curve.overshoot, 3.25), "Back Overshoot edit lost its scalar value")
	_expect(after_geometry != before_geometry, "Back Overshoot edit did not regenerate Bezier geometry")
	_expect(not curve.is_selected_preset_modified(), "Changing Back Overshoot alone produced Back *")
	_expect(
		EDITOR_UNDO.commit_applied_action(
			history,
			curve,
			"Change Easing Curve Overshoot",
			EasingCurveEditorUndo.ActionContext.new(before, after),
		),
		"Back Overshoot action was not committed",
	)
	_expect(history.has_undo(), "Back Overshoot did not create an Undo action")

	history.undo()
	_expect(is_equal_approx(curve.overshoot, 1.70158), "Back Overshoot Undo did not restore the scalar")
	_expect(curve.get_point_snapshot() == before_geometry, "Back Overshoot Undo did not restore geometry")
	_expect(not curve.is_selected_preset_modified(), "Back Overshoot Undo produced Back *")
	_expect(not history.has_undo() and history.has_redo(), "Back Overshoot created more than one history action")

	history.redo()
	_expect(is_equal_approx(curve.overshoot, 3.25), "Back Overshoot Redo did not restore the scalar")
	_expect(curve.get_point_snapshot() == after_geometry, "Back Overshoot Redo did not restore geometry")
	_expect(curve.get_editor_state_snapshot() == after, "Back Overshoot Redo lost editor state")
	_expect(not curve.is_selected_preset_modified(), "Back Overshoot Redo produced Back *")
	_dispose_history(history)


func _test_back_overshoot_property_reset() -> void:
	var curve := EasingCurve.new()
	curve.ease_type = EasingCurve.EASE.OUT
	curve.trans_type = EasingCurve.TRANS.BACK
	curve.overshoot = 4.25
	var changed_geometry := curve.get_point_snapshot()
	var before := EDITOR_UNDO.capture_state(curve)
	var history := UndoRedo.new()

	curve._begin_editor_parameter_edit()
	curve.overshoot = 1.70158
	var after := EDITOR_UNDO.capture_state(curve)
	curve._finish_editor_parameter_edit()
	_expect(
		EDITOR_UNDO.commit_applied_action(
			history,
			curve,
			"Reset Easing Curve Overshoot",
			EasingCurveEditorUndo.ActionContext.new(before, after),
		),
		"Back Overshoot reset action was not committed",
	)

	var default_curve := EasingCurve.new()
	default_curve.ease_type = EasingCurve.EASE.OUT
	default_curve.trans_type = EasingCurve.TRANS.BACK
	_expect(is_equal_approx(curve.overshoot, 1.70158), "Back Overshoot reset did not restore 1.70158")
	_expect(curve.get_point_snapshot() != changed_geometry, "Back Overshoot reset did not regenerate geometry")
	_expect(
		curve.get_point_snapshot() == default_curve.get_point_snapshot(),
		"Back Overshoot reset did not restore default Back geometry",
	)
	_expect(not curve.is_selected_preset_modified(), "Back Overshoot reset produced Back *")
	_verify_single_action(history, curve, before, after, "Back Overshoot reset", 2)
	_dispose_history(history)


func _test_back_modified_reset_uses_current_overshoot() -> void:
	var curve := EasingCurve.new()
	curve.ease_type = EasingCurve.EASE.IN_OUT
	curve.trans_type = EasingCurve.TRANS.BACK
	curve.overshoot = 2.75
	var canonical := curve.get_canonical_preset_point_snapshot()
	var transition_option := INSPECTOR_PLUGIN._create_option(
		EasingCurve.TRANS,
		EasingCurve.TRANS.BACK,
	)
	var transition_index := transition_option.get_item_index(EasingCurve.TRANS.BACK)

	INSPECTOR_PLUGIN._set_transition_display(
		transition_option,
		curve.trans_type,
		curve.is_selected_preset_modified(),
	)
	_expect(transition_option.get_item_text(transition_index) == "Back", "Parameterized Back displayed as Back *")

	curve.points[1].left_control_point += Vector2(0.02, -0.03)
	var modified := EDITOR_UNDO.capture_state(curve)
	_expect(curve.is_selected_preset_modified(), "Manual Back handle edit did not produce Back *")
	INSPECTOR_PLUGIN._set_transition_display(
		transition_option,
		curve.trans_type,
		curve.is_selected_preset_modified(),
	)
	_expect(transition_option.get_item_text(transition_index) == "Back *", "Modified Back label omitted its asterisk")

	var history := UndoRedo.new()
	_expect(curve.reset_selected_preset(), "Modified Back refused to reset")
	var reset_state := _commit_applied(history, curve, "Reset Easing Curve Preset", modified)
	_expect(is_equal_approx(curve.overshoot, 2.75), "Back * reset changed Overshoot")
	_expect(curve.get_point_snapshot() == canonical, "Back * reset ignored the current Overshoot")
	_expect(not curve.is_selected_preset_modified(), "Reset Back still reported modified")
	INSPECTOR_PLUGIN._set_transition_display(
		transition_option,
		curve.trans_type,
		curve.is_selected_preset_modified(),
	)
	_expect(transition_option.get_item_text(transition_index) == "Back", "Reset Back retained its asterisk")

	history.undo()
	_expect(is_equal_approx(curve.overshoot, 2.75), "Undo Back * reset changed Overshoot")
	_expect(curve.is_selected_preset_modified(), "Undo Back * reset did not restore modified geometry")
	history.redo()
	_expect(curve.get_editor_state_snapshot() == reset_state, "Redo Back * reset lost canonical state")
	_expect(is_equal_approx(curve.overshoot, 2.75), "Redo Back * reset changed Overshoot")
	_expect(curve.get_point_snapshot() == canonical, "Redo Back * reset lost current-Overshoot geometry")
	_dispose_history(history)
	transition_option.free()


func _test_back_point_property_defaults() -> void:
	var curve := EasingCurve.new()
	curve.ease_type = EasingCurve.EASE.IN_OUT
	curve.trans_type = EasingCurve.TRANS.BACK
	curve.overshoot = 3.2
	var in_out_overshoot := curve.overshoot * 1.525
	var expected_left := Vector2(1.0 / 3.0, -in_out_overshoot / 6.0)
	var expected_right := Vector2(2.0 / 3.0, 1.0 + in_out_overshoot / 6.0)

	_expect(
		curve.get_default_for_property(1, "left_control_point").is_equal_approx(expected_left),
		"Back midpoint left-handle reset default ignored current Overshoot",
	)
	_expect(
		curve.get_default_for_property(1, "right_control_point").is_equal_approx(expected_right),
		"Back midpoint right-handle reset default ignored current Overshoot",
	)
	curve.points[1].left_control_point += Vector2(0.01, 0.02)
	_expect(
		curve.get_default_for_property(1, "left_control_point").is_equal_approx(expected_left),
		"Modified Back changed its current-Overshoot point reset default",
	)


func _test_function_parameter_changes() -> void:
	var cases := [
		[EasingCurve.TRANS.IRREGULAR, &"num_points", 7],
		[EasingCurve.TRANS.IRREGULAR, &"randomness", 1.25],
		[EasingCurve.TRANS.STEP, &"steps", 9],
		[EasingCurve.TRANS.STEP, &"y_offset", 0.2],
		[EasingCurve.TRANS.STEP, &"from_start", true],
		[EasingCurve.TRANS.POWER, &"power", 3.75],
		[EasingCurve.TRANS.ELASTIC, &"amplitude", 2.25],
		[EasingCurve.TRANS.ELASTIC, &"period", 0.55],
	]
	for test_case in cases:
		var curve := EasingCurve.new()
		curve.trans_type = test_case[0]
		var history := UndoRedo.new()
		var before := EDITOR_UNDO.capture_state(curve)
		var property_name: StringName = test_case[1]
		curve._begin_editor_parameter_edit()
		curve.set(property_name, test_case[2])
		var after := EDITOR_UNDO.capture_state(curve)
		curve._finish_editor_parameter_edit()
		_expect(
			EDITOR_UNDO.commit_applied_action(history, curve, "Change %s" % property_name, EasingCurveEditorUndo.ActionContext.new(before, after)),
			"%s parameter action was not committed" % property_name,
		)
		_verify_single_action(history, curve, before, after, "%s parameter" % property_name, 2)
		_dispose_history(history)


func _test_generate_action() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.IRREGULAR
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)
	curve._begin_editor_parameter_edit()
	curve.generate_irregular()
	var after := EDITOR_UNDO.capture_state(curve)
	curve._finish_editor_parameter_edit()
	_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Generate Easing Curve", EasingCurveEditorUndo.ActionContext.new(before, after)), "Generate action was not committed")
	_verify_single_action(history, curve, before, after, "Generate", 3)
	_dispose_history(history)


func _test_parameter_reset() -> void:
	var curve := EasingCurve.new()
	curve.trans_type = EasingCurve.TRANS.IRREGULAR
	curve.randomness = 1.0
	var history := UndoRedo.new()
	var before := EDITOR_UNDO.capture_state(curve)
	curve._begin_editor_parameter_edit()
	curve.randomness = 3.5
	var after := EDITOR_UNDO.capture_state(curve)
	curve._finish_editor_parameter_edit()
	_expect(EDITOR_UNDO.commit_applied_action(history, curve, "Reset Easing Curve Randomness", EasingCurveEditorUndo.ActionContext.new(before, after)), "Parameter reset was not committed")
	_verify_single_action(history, curve, before, after, "Parameter reset", 3)
	_dispose_history(history)

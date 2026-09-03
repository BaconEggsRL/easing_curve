extends "res://test/scripts/support/test_case.gd"

const CURVE_EDITOR := preload(
	"res://addons/easing_curve/scripts/editor/easing_curve_editor.gd"
)
const INSPECTOR_PLUGIN := preload(
	"res://addons/easing_curve/scripts/editor/inspector/easing_curve_editor_inspector_plugin.gd"
)


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_legacy_selection_path()
	_test_native_selection_and_point_options()
	_test_native_inspector_path()
	_finish("shared curve editor vertical slice")


func _test_legacy_selection_path() -> void:
	var curve := EasingCurve.new()
	var editor := CURVE_EDITOR.new() as EasingCurveEditor
	editor.set_curve(curve)
	root.add_child(editor)
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

	curve.set(&"transition", 0)
	_expect(editor.call(&"_is_point_toolbar_hidden"), "Native standard transition exposed point options")
	editor.queue_free()


func _test_native_inspector_path() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		return
	var curve := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	var inspector := INSPECTOR_PLUGIN.new()
	_expect(inspector._can_handle(curve), "Inspector plugin rejected NativeEasingCurve")
	var content := inspector.handle_easing_curve_editor(curve)
	_expect(content != null, "Inspector plugin did not build the Native Curve Editor")
	if content != null:
		root.add_child(content)
		var editor := _find_curve_editor(content)
		_expect(editor != null, "Native Inspector content omitted the shared Curve Editor")
		if editor != null:
			_expect(editor.get_backend_id() == &"native", "Native Inspector used the wrong backend")
		content.queue_free()


func _find_curve_editor(node: Node) -> EasingCurveEditor:
	if node is EasingCurveEditor:
		return node
	for child in node.get_children():
		var result := _find_curve_editor(child)
		if result != null:
			return result
	return null

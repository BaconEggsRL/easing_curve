extends "res://test/scripts/support/test_case.gd"

const BackendFactory := preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_editor_backend_factory.gd"
)


func _init() -> void:
	var legacy := EasingCurve.new()
	var legacy_backend := BackendFactory.create(legacy)
	_expect(legacy_backend != null, "legacy backend was not selected")
	_expect(legacy_backend.get_backend_id() == &"legacy", "legacy backend identity changed")
	_expect(legacy_backend.get_capabilities()[&"runtime_callable"], "legacy Callable capability is missing")
	_expect(not legacy_backend.get_capabilities()[&"callable_baking"], "legacy advertises unimplemented Callable baking")
	_expect(legacy_backend.get_capabilities()[&"point_options"], "legacy point options are missing")
	_expect(legacy_backend.get_capabilities()[&"point_geometry"], "legacy point geometry is missing")
	_expect(legacy_backend.is_point_graph(), "legacy custom curve did not expose its point graph")
	_expect(legacy_backend.get_point_count() == legacy.points.size(), "legacy backend point count changed")
	_expect(legacy_backend.get_points().size() == legacy.points.size(), "legacy backend point list changed")
	_expect(legacy_backend.find_point(legacy.points[0]) == 0, "legacy backend point lookup changed")
	_expect(is_equal_approx(legacy_backend.sample(0.0), legacy.sample(0.0)), "legacy backend sampling changed")
	var legacy_snapshot: Variant = legacy_backend.capture_snapshot()
	_expect(
		legacy_backend.apply_point_property(0, &"right_control_state", EasingCurvePoint.ControlState.LINEAR),
		"legacy backend rejected Force Linear",
	)
	_expect(legacy.points[0].right_force_linear, "legacy backend did not apply Force Linear")
	_expect(
		legacy_backend.apply_point_property(0, &"right_control_state", EasingCurvePoint.ControlState.LOCKED),
		"legacy backend rejected point locking",
	)
	_expect(legacy.points[0].locked[&"right_control_point"], "legacy backend did not apply point locking")
	_expect(
		legacy_backend.apply_point_property(0, &"handle_mode", EasingCurvePoint.HandleMode.LINKED),
		"legacy backend rejected linked handles",
	)
	_expect(
		legacy_backend.get_point_control_state(0, EasingCurvePoint.ControlSide.LEFT)
		== EasingCurvePoint.ControlState.LOCKED,
		"legacy linked handles did not share lock state",
	)
	_expect(legacy_backend.apply_snapshot(legacy_snapshot), "legacy backend rejected its own snapshot")
	_expect(not legacy.points[0].right_force_linear, "legacy backend snapshot did not restore Force Linear")
	_expect(not legacy.points[0].locked[&"right_control_point"], "legacy backend snapshot did not restore locks")

	if ClassDB.class_exists(&"NativeEasingCurve"):
		var native := ClassDB.instantiate(&"NativeEasingCurve") as Resource
		native.set(&"transition", 100)
		var native_backend := BackendFactory.create(native)
		_expect(native_backend != null, "Native backend was not selected")
		_expect(native_backend.get_backend_id() == &"native", "Native backend identity changed")
		_expect(not native_backend.get_capabilities()[&"runtime_callable"], "Native advertises per-sample Callables")
		_expect(native_backend.get_capabilities()[&"callable_baking"], "Native Callable-baking capability is missing")
		_expect(native_backend.get_capabilities()[&"point_options"], "Native point options are missing")
		_expect(native_backend.get_capabilities()[&"point_geometry"], "Native point geometry is missing")
		_expect(native_backend.is_point_graph(), "Native custom curve did not expose its point graph")
		_expect(native_backend.get_transition_ids().has(100), "Native custom transition is missing")
		_expect(not native_backend.get_transition_ids().has(102), "Native advertises unimplemented Jitter")
		_expect(native_backend.get_points().size() == native_backend.get_point_count(), "Native backend point list changed")
		var native_point: Resource = native_backend.get_point(0)
		_expect(native_backend.find_point(native_point) == 0, "Native backend point lookup changed")
		_expect(is_equal_approx(native_backend.sample(0.0), 0.0), "Native backend sampling changed")
		var native_snapshot: Variant = native_backend.capture_snapshot()
		_expect(
			native_backend.apply_point_property(0, &"right_control_state", EasingCurvePoint.ControlState.LINEAR),
			"Native backend rejected Force Linear",
		)
		_expect(native_point.get(&"right_force_linear"), "Native backend did not apply Force Linear")
		_expect(
			native_backend.apply_point_property(0, &"right_control_state", EasingCurvePoint.ControlState.LOCKED),
			"Native backend rejected point locking",
		)
		var native_locks := native_point.get(&"locked") as Dictionary
		_expect(native_locks[&"right_control_point"], "Native backend did not apply point locking")
		_expect(
			native_backend.apply_point_property(0, &"handle_mode", EasingCurvePoint.HandleMode.LINKED),
			"Native backend rejected linked handles",
		)
		_expect(
			native_backend.get_point_control_state(0, EasingCurvePoint.ControlSide.LEFT)
			== EasingCurvePoint.ControlState.LOCKED,
			"Native linked handles did not share lock state",
		)
		_expect(native_backend.apply_snapshot(native_snapshot), "Native backend rejected its own snapshot")
		_expect(not native_point.get(&"right_force_linear"), "Native backend snapshot did not restore Force Linear")
		native_locks = native_point.get(&"locked") as Dictionary
		_expect(not native_locks[&"right_control_point"], "Native backend snapshot did not restore locks")
		var original_position := native_point.get(&"position") as Vector2
		var original_left := native_point.get(&"left_control_point") as Vector2
		var original_right := native_point.get(&"right_control_point") as Vector2
		var moved_position := original_position + Vector2(0.15, 0.2)
		_expect(
			native_backend.apply_point_property(0, &"position", moved_position, true),
			"Native backend rejected a live position gesture",
		)
		_expect(native_point.get(&"position").is_equal_approx(moved_position), "Native backend did not move the point")
		_expect(
			native_point.get(&"left_control_point").is_equal_approx(original_left + moved_position - original_position)
			and native_point.get(&"right_control_point").is_equal_approx(original_right + moved_position - original_position),
			"Native backend did not translate unlocked controls with the point",
		)
		native_point.call(&"set_locked", &"position", true)
		_expect(native_backend.is_point_property_locked(0, &"position"), "Native backend did not report the position lock")
		native.set(&"transition", 0)
		_expect(not native_backend.is_point_graph(), "Native standard transition exposed point editing")

	_expect(BackendFactory.create(Resource.new()) == null, "backend factory accepted an unrelated Resource")
	_finish("curve editor backend contract")

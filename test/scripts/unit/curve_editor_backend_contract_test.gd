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
	_expect(legacy_backend.get_capabilities()[&"point_topology"], "legacy point topology is missing")
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
	_test_topology_contract(legacy, legacy_backend, "legacy")

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
		_expect(native_backend.get_capabilities()[&"point_topology"], "Native point topology is missing")
		_expect(native_backend.is_point_graph(), "Native custom curve did not expose its point graph")
		_expect(native_backend.get_transition_ids().has(100), "Native custom transition is missing")
		for transition_id: int in range(100, 109):
			_expect(
				native_backend.get_transition_ids().has(transition_id),
				"Native transition %d is missing" % transition_id,
			)
		_expect(native_backend.get_capabilities()[&"conversion"], "Native conversion capability is missing")
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
		_expect(native_backend.is_point_graph(), "Native editable preset did not expose point editing")
		native.set(&"transition", 6)
		_expect(not native_backend.is_point_graph(), "Native function transition exposed a Points section")
		var native_topology := ClassDB.instantiate(&"NativeEasingCurve") as Resource
		native_topology.set(&"transition", 100)
		_test_topology_contract(
			native_topology,
			BackendFactory.create(native_topology),
			"Native",
		)

	_expect(BackendFactory.create(Resource.new()) == null, "backend factory accepted an unrelated Resource")
	_finish("curve editor backend contract")


func _test_topology_contract(curve: Resource, backend: RefCounted, context: String) -> void:
	var initial_points: Array[Resource] = backend.get_points()
	_expect(initial_points.size() == 2, "%s topology fixture changed" % context)
	var midpoint: Resource = backend.create_point(Vector2(0.5, 0.4))
	_expect(midpoint != null, "%s point factory failed" % context)
	var publication := {&"count": 0}
	curve.changed.connect(func() -> void: publication[&"count"] += 1)
	var inserted_index: int = backend.add_point(midpoint)
	_expect(inserted_index == 1, "%s sorted insertion returned the wrong index" % context)
	_expect(backend.get_point(1) == midpoint, "%s sorted insertion lost point identity" % context)
	_expect(publication[&"count"] == 1, "%s insertion published more than once" % context)

	var inserted_snapshot: Variant = backend.capture_snapshot()
	var endpoint: Resource = backend.create_point(Vector2(0.0, 0.75))
	publication[&"count"] = 0
	_expect(backend.add_point(endpoint) == 0, "%s endpoint takeover returned the wrong index" % context)
	_expect(
		backend.get_point_count() == 3 and backend.get_point(0) == endpoint,
		"%s endpoint takeover did not replace the old endpoint" % context,
	)
	_expect(backend.find_point(initial_points[0]) == -1, "%s endpoint takeover retained the old endpoint" % context)
	_expect(publication[&"count"] == 1, "%s endpoint takeover published more than once" % context)
	publication[&"count"] = 0
	initial_points[0].set(&"position", Vector2(0.1, 0.1))
	_expect(publication[&"count"] == 0, "%s retained a connection to the detached endpoint" % context)

	publication[&"count"] = 0
	_expect(backend.remove_point(1), "%s indexed removal failed" % context)
	_expect(backend.find_point(midpoint) == -1, "%s indexed removal retained the point" % context)
	_expect(publication[&"count"] == 1, "%s indexed removal published more than once" % context)

	publication[&"count"] = 0
	_expect(backend.apply_snapshot(inserted_snapshot), "%s atomic snapshot restoration failed" % context)
	_expect(
		backend.get_points() == [initial_points[0], midpoint, initial_points[1]],
		"%s snapshot restoration did not restore exact point resources" % context,
	)
	_expect(publication[&"count"] == 1, "%s snapshot restoration published more than once" % context)

	var left_point: Resource = backend.get_point(0)
	var right_point: Resource = backend.get_point(2)
	var left_position := left_point.get(&"position") as Vector2
	var left_control := left_point.get(&"right_control_point") as Vector2
	var right_position := right_point.get(&"position") as Vector2
	var right_control := right_point.get(&"left_control_point") as Vector2
	publication[&"count"] = 0
	_expect(backend.swap_points(0, 2), "%s point swap failed" % context)
	_expect(
		backend.get_points() == [right_point, midpoint, left_point],
		"%s point swap shifted rather than exchanged resources" % context,
	)
	_expect(
		(left_point.get(&"position") as Vector2).is_equal_approx(Vector2(right_position.x, left_position.y))
		and (left_point.get(&"right_control_point") as Vector2).is_equal_approx(left_control + Vector2(right_position.x - left_position.x, 0.0)),
		"%s point swap did not translate the first point and handle" % context,
	)
	_expect(
		(right_point.get(&"position") as Vector2).is_equal_approx(Vector2(left_position.x, right_position.y))
		and (right_point.get(&"left_control_point") as Vector2).is_equal_approx(right_control + Vector2(left_position.x - right_position.x, 0.0)),
		"%s point swap did not translate the second point and handle" % context,
	)
	_expect(publication[&"count"] >= 1, "%s point swap did not publish" % context)
	_expect(backend.apply_snapshot(inserted_snapshot), "%s point-swap restoration failed" % context)

	var reversed: Array[Resource] = backend.get_points()
	reversed.reverse()
	publication[&"count"] = 0
	_expect(backend.apply_point_order(reversed) >= 0, "%s point-order application failed" % context)
	_expect(backend.get_points() == reversed, "%s point-order application lost resource order" % context)
	_expect(publication[&"count"] == 1, "%s point-order application published more than once" % context)

	var before_invalid: Variant = backend.capture_snapshot()
	var duplicate_order: Array[Resource] = backend.get_points()
	duplicate_order[1] = duplicate_order[0]
	_expect(backend.apply_point_order(duplicate_order) == -1, "%s accepted a duplicate point order" % context)
	_expect(not backend.apply_snapshot({}), "%s accepted an invalid topology snapshot" % context)
	_expect(backend.capture_snapshot() == before_invalid, "%s invalid input mutated topology" % context)
	if context == "Native":
		var native_snapshot: Dictionary = before_invalid
		var native_order: Array = native_snapshot[&"point_order"]
		var native_states: Array = native_snapshot[&"point_states"]
		publication[&"count"] = 0
		_expect(
			not curve.call(&"apply_point_topology_snapshot", native_order, native_states.slice(1)),
			"Native atomic topology accepted mismatched state count",
		)
		var duplicated_native_order := native_order.duplicate()
		duplicated_native_order[1] = duplicated_native_order[0]
		_expect(
			not curve.call(&"apply_point_topology_snapshot", duplicated_native_order, native_states),
			"Native atomic topology accepted duplicate point resources",
		)
		var partial_native_states := native_states.duplicate(true)
		partial_native_states[0] = {&"position": Vector2.ZERO}
		_expect(
			not curve.call(&"apply_point_topology_snapshot", native_order, partial_native_states),
			"Native atomic topology accepted a partial point state",
		)
		_expect(publication[&"count"] == 0, "Native invalid atomic topology published a change")
		_expect(backend.capture_snapshot() == before_invalid, "Native invalid atomic topology mutated state")

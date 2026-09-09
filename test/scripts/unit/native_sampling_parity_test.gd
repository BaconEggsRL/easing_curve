extends "res://test/scripts/support/test_case.gd"

const NATIVE_BACKEND := preload("res://addons/easing_curve/scripts/editor/backend/native_curve_editor_backend.gd")
const EDITOR := preload("res://addons/easing_curve/scripts/editor/easing_curve_editor.gd")
const CONVERTER := preload("res://addons/easing_curve/scripts/editor/backend/curve_converter.gd")
const TOLERANCE := 0.000002
const OFFSETS := [0.0, 0.1, 0.25, 0.49, 0.4999, 0.5, 0.5001, 0.51, 0.75, 1.0]


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ClassDB.class_exists(&"NativeEasingCurve"), "Native extension must be available")
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		_finish("native sampling parity")
		return
	for reset in [false, true]:
		var legacy := _curve([
			Vector2.ZERO, Vector2(0.5, 1.0 if reset else 0.0),
			Vector2(0.5, 0.0 if reset else 1.0), Vector2.ONE,
		])
		var native := _native(legacy)
		for x: float in OFFSETS:
			var expected := (2.0 * x if x <= 0.5 else 2.0 * x - 1.0) if reset else (0.0 if x <= 0.5 else 1.0)
			print("SAMPLE reset=%s x=%.7f legacy=%.9f native=%.9f expected=%.9f" % [reset, x, legacy.sample(x), native.sample(x), expected])
			_expect(absf(legacy.sample(x) - expected) <= TOLERANCE, "Legacy example expectation at %s" % x)
			_expect(absf(native.sample(x) - expected) <= TOLERANCE, "Native example reset=%s x=%s" % [reset, x])
		_check_parity(legacy, native, "reset=%s" % reset)
		# Query from both sides: the cached later segment must not own the boundary.
		for seed_x in [0.75, 0.25, 1.0, 0.5000005]:
			native.sample(seed_x)
			_expect(absf(native.sample(0.5) - legacy.sample(0.5)) <= TOLERANCE, "boundary must be independent of sampling history")
		_check_graph(legacy, native)
	_test_additional_topologies()
	_test_handles()
	_test_conversion_and_mutation()
	_finish("native sampling parity")


func _curve(positions: Array) -> EasingCurve:
	var curve := EasingCurve.new()
	curve.set_trans(EasingCurve.TRANS.CUSTOM)
	var points: Array[EasingCurvePoint] = []
	for position: Vector2 in positions:
		points.append(EasingCurvePoint.new(position))
	curve.points = points
	return curve


func _native(legacy: EasingCurve) -> NativeEasingCurve:
	var curve := NativeEasingCurve.new()
	curve.transition = NativeEasingCurve.TRANS_CUSTOM
	var points: Array[NativeEasingCurvePoint] = []
	for source in legacy.points:
		var point := NativeEasingCurvePoint.new()
		point.position = source.position
		point.left_control_point = source.left_control_point
		point.right_control_point = source.right_control_point
		point.handle_mode = source.handle_mode as NativeEasingCurvePoint.HandleMode
		point.left_force_linear = source.left_force_linear
		point.right_force_linear = source.right_force_linear
		points.append(point)
	curve.points = points
	return curve


func _check_parity(legacy: EasingCurve, native: NativeEasingCurve, label: String) -> void:
	var before := native.capture_point_states()
	var max_error := 0.0
	# Ascending, descending and interleaved queries exercise locality and lookup.
	for i in range(10001):
		var x := float(i) / 10000.0
		for offset in [x, 1.0 - x, fmod(x * 37.0, 1.0)]:
			max_error = maxf(max_error, absf(native.sample(offset) - legacy.sample(offset)))
	for x in [0.499998, 0.4999995, 0.5, 0.50000025, 0.5000005, 0.500001, 0.500002]:
		max_error = maxf(max_error, absf(native.sample(x) - legacy.sample(x)))
	_expect(max_error <= TOLERANCE, "%s parity max error %.9f" % [label, max_error])
	var copy := native.create_runtime_copy()
	_expect(before == native.capture_point_states(), "sampling/copy must preserve authored states")
	for x: float in OFFSETS:
		_expect(absf(copy.sample(x) - legacy.sample(x)) <= TOLERANCE, "%s runtime copy at %s" % [label, x])


func _check_graph(legacy: EasingCurve, native: NativeEasingCurve) -> void:
	var backend := NATIVE_BACKEND.new(native)
	var editor := EDITOR.new()
	editor.set("_backend", backend)
	var displayed := backend.get_display_points()
	_expect(displayed.size() == legacy.points.size(), "graph keeps all authored points")
	for i in range(displayed.size() - 1):
		var a := legacy.points[i]
		var b := legacy.points[i + 1]
		var controls: Array = editor.call("_get_effective_segment_controls", displayed[i], displayed[i + 1])
		for j in range(1, 20):
			var t := float(j) / 20.0
			var drawn: Vector2 = editor.call("_bezier_world_position", displayed[i], displayed[i + 1], controls[0], controls[1], t)
			if absf(b.position.x - a.position.x) <= EasingCurve.SEGMENT_X_EPSILON:
				continue # A vertical line has multiple Y values; ordered boundary policy chooses one.
			_expect(absf(native.sample(drawn.x) - drawn.y) <= TOLERANCE, "runtime follows drawn segment %s" % i)
	editor.free()


func _test_additional_topologies() -> void:
	for positions: Array in [
		[Vector2.ZERO, Vector2.ONE],
		[Vector2.ONE, Vector2.ZERO, Vector2(0.5, 0.8)],
		[Vector2(1.0, 0.2), Vector2(0.0, 0.8)],
		[Vector2(0.5, 0.2), Vector2(0.5, 0.8)],
		[Vector2(0.0, 0.2), Vector2(0.0, 0.8), Vector2.ONE],
		[Vector2.ZERO, Vector2(1.0, 0.2), Vector2(1.0, 0.8)],
		[Vector2.ZERO, Vector2(0.5, 0.2), Vector2(0.5, 0.4), Vector2(0.5, 0.8), Vector2.ONE],
		[Vector2.ZERO, Vector2(0.5000002, 0.2), Vector2(0.5, 0.8), Vector2.ONE],
		[Vector2.ZERO, Vector2(0.5, 0.2), Vector2(0.5000008, 0.8), Vector2.ONE],
		[Vector2.ZERO, Vector2(0.5, 0.2), Vector2(0.500002, 0.8), Vector2.ONE],
	]:
		var legacy := _curve(positions)
		_check_parity(legacy, _native(legacy), str(positions))


func _test_handles() -> void:
	for mode in EasingCurvePoint.HandleMode.values():
		var legacy := _curve([Vector2.ZERO, Vector2(0.5, 0.8), Vector2(0.5, 0.2), Vector2.ONE])
		for point in legacy.points:
			point.left_control_point = point.position + Vector2(-0.3, -0.4)
			point.right_control_point = point.position + Vector2(0.3, 0.4)
			point.set_handle_mode(mode)
		_check_parity(legacy, _native(legacy), "handle mode %s" % mode)
		_check_graph(legacy, _native(legacy))
	var legacy := _curve([Vector2.ZERO, Vector2(0.5, 0.8), Vector2.ONE])
	legacy.points[0].right_control_point = Vector2(2.0, -0.3)
	legacy.points[1].left_control_point = Vector2(-1.0, 1.2)
	legacy.points[1].right_control_point = Vector2(0.8, 1.3)
	legacy.points[2].left_control_point = Vector2(0.6, 0.4)
	_check_parity(legacy, _native(legacy), "crossed/clamped handles")
	_check_graph(legacy, _native(legacy))
	legacy.points[0].right_force_linear = true
	legacy.points[1].left_force_linear = true
	_check_parity(legacy, _native(legacy), "force linear")


func _test_conversion_and_mutation() -> void:
	var legacy := _curve([Vector2.ZERO, Vector2(0.5, 1.0), Vector2(0.5, 0.0), Vector2.ONE])
	var result := CONVERTER.legacy_to_native(legacy)
	var native := result.get(&"resource") as NativeEasingCurve
	_expect(native != null, "Legacy-to-Native conversion preserves duplicate-X curve")
	if native == null:
		return
	_check_parity(legacy, native, "converted duplicate-X curve")
	# Geometry edits must invalidate both the lookup cache and its fast-path flag.
	legacy.points[2].position = Vector2(0.7, 0.0)
	native.get_point(2).position = legacy.points[2].position
	_check_parity(legacy, native, "duplicate to strictly increasing")
	legacy.points[2].position = Vector2(0.5, 0.0)
	native.get_point(2).position = legacy.points[2].position
	_check_parity(legacy, native, "strictly increasing to duplicate")
	legacy.points[1].right_control_point = Vector2(0.8, -0.4)
	native.get_point(1).right_control_point = legacy.points[1].right_control_point
	_check_parity(legacy, native, "changed control")
	for reverse_value in [false, true]:
		for invert_value in [false, true]:
			native.reverse = reverse_value
			native.invert = invert_value
			for x: float in OFFSETS:
				var expected := legacy.sample(1.0 - x if reverse_value else x)
				if invert_value:
					expected = 1.0 - expected
				_expect(absf(native.sample(x) - expected) <= TOLERANCE, "Native runtime transform parity")

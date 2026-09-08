extends "res://test/scripts/support/test_case.gd"

const CONVERTER = preload("res://addons/easing_curve/scripts/editor/backend/curve_converter.gd")

func _init() -> void:
	call_deferred(&"_run")


func _reference(t: float, ease: int) -> float:
	match ease:
		0: return (3.0 * t * t - t * t * t) / 2.0
		1: return (3.0 * t - t * t * t) / 2.0
		2: return 3.0 * t * t - 2.0 * t * t * t
		3:
			return 1.5 * t - 2.0 * t * t * t if t < 0.5 else -2.0 * t * t * t + 6.0 * t * t - 4.5 * t + 1.5
	return NAN


func _run() -> void:
	var godot_curve := Curve.new()
	godot_curve.add_point(Vector2.ZERO)
	godot_curve.add_point(Vector2.ONE)
	for ease in range(4):
		var legacy := EasingCurve.new()
		legacy.ease_type = ease
		legacy.trans_type = EasingCurve.TRANS.SMOOTHSTEP
		var native := ClassDB.instantiate(&"NativeEasingCurve") as Resource
		native.set(&"ease_type", ease)
		native.set(&"transition", 109)
		_expect(legacy.has_builtin_bezier_preset() and native.call(&"is_builtin_bezier_preset"), "Smoothstep not classified as a preset")
		var count := 3 if ease == 3 else 2
		_expect(legacy.points.size() == count and native.call(&"get_point_count") == count, "Incorrect exact preset topology")
		for index in range(count):
			var point: Resource = native.call(&"get_point", index)
			for property: StringName in [&"position", &"left_control_point", &"right_control_point"]:
				_expect((point.get(property) as Vector2).is_equal_approx(legacy.points[index].get(property)), "Native/Legacy control mismatch")
		if ease == 2:
			_expect(legacy.points[0].right_control_point.is_equal_approx(Vector2(1.0 / 3.0, 0)), "Canonical first control")
			_expect(legacy.points[1].left_control_point.is_equal_approx(Vector2(2.0 / 3.0, 1)), "Canonical second control")
			_expect(legacy.sample(1e-6) / 1e-6 < 1e-5 and (1.0 - legacy.sample(1.0 - 1e-6)) / 1e-6 < 1e-5, "Canonical endpoint slopes are not zero")
		for reverse: bool in [false, true]:
			for invert: bool in [false, true]:
				legacy.reverse = reverse
				legacy.invert = invert
				native.set(&"reverse", reverse)
				native.set(&"invert", invert)
				var error_native := 0.0
				var error_legacy := 0.0
				var error_godot := 0.0
				var error_symmetry := 0.0
				var previous := -1.0
				for index in range(10001):
					var t := float(index) / 10000.0
					var x := 1.0 - t if reverse else t
					var expected := _reference(x, ease)
					if invert: expected = 1.0 - expected
					var value: float = native.call(&"sample", t)
					error_native = maxf(error_native, absf(value - expected))
					error_legacy = maxf(error_legacy, absf(legacy.sample(t) - expected))
					if not reverse and not invert:
						_expect(value >= previous - 1e-12 and value >= -1e-12 and value <= 1.0 + 1e-12, "Smoothstep lost monotonicity/bounds")
						previous = value
						if ease == 2: error_godot = maxf(error_godot, absf(godot_curve.sample(t) - expected))
						if ease == 2: error_symmetry = maxf(error_symmetry, absf(legacy.sample(t) + legacy.sample(1.0 - t) - 1.0))
				_expect(error_native <= 1e-12, "Native analytic error %.16f" % error_native)
				_expect(error_legacy <= 2e-6, "Legacy exact geometry error %.16f" % error_legacy)
				_expect(error_godot <= 2e-6, "Godot Curve disagreement %.16f" % error_godot)
				_expect(error_symmetry <= 2e-6, "Canonical symmetry changed")
				for t: float in [-1.0, 0.0, 0.5 - 1e-8, 0.5, 0.5 + 1e-8, 1.0, 2.0]:
					var x := clampf(t, 0, 1)
					if reverse: x = 1.0 - x
					var expected := _reference(x, ease)
					if invert: expected = 1.0 - expected
					_expect(absf(legacy.sample(t) - expected) <= 2e-6 and absf(float(native.call(&"sample", t)) - expected) <= 1e-12, "Edge/clamping mismatch")
				_check_round_trip(legacy, false)
				_check_round_trip(native, true)
				var converted: Resource = CONVERTER.legacy_to_native(legacy).get("resource")
				var returned: Resource = CONVERTER.native_to_legacy(native).get("resource")
				_expect(converted != null and returned != null, "Smoothstep conversion failed")
				if converted != null and returned != null:
					_expect(absf(float(converted.call(&"sample", 0.37)) - legacy.sample(0.37)) < 2e-6, "Conversion to Native changed curve")
					_expect(absf(float(returned.call(&"sample", 0.37)) - float(native.call(&"sample", 0.37))) < 2e-6, "Conversion to Legacy changed curve")
		legacy.reverse = false
		legacy.invert = false
		native.set(&"reverse", false)
		native.set(&"invert", false)
		for curve: Resource in [legacy, native]:
			var before: Dictionary = curve.call(&"get_editor_state_snapshot")
			var point: Resource = curve.call(&"get_point", 0) if curve == native else legacy.points[0]
			point.set(&"right_control_point", Vector2(0.2, 0.2))
			_expect(curve.call(&"is_selected_preset_modified"), "Edited Smoothstep not marked modified")
			var after: Dictionary = curve.call(&"get_editor_state_snapshot")
			var history := UndoRedo.new()
			history.create_action("Edit Smoothstep")
			history.add_do_method(Callable(curve, &"set_editor_state_snapshot").bind(after))
			history.add_undo_method(Callable(curve, &"set_editor_state_snapshot").bind(before))
			history.commit_action(false)
			_expect(history.get_history_count() == 1 and history.undo(), "Smoothstep Undo failed")
			_expect(absf(float(curve.call(&"sample", 0.37)) - _reference(0.37, ease)) < 2e-6, "Undo changed exact preset")
			_expect(history.redo(), "Smoothstep Redo failed")
			_check_round_trip(curve, curve == native)
			var conversion: Dictionary = CONVERTER.native_to_legacy(curve) if curve == native else CONVERTER.legacy_to_native(curve)
			var converted: Resource = conversion.get("resource")
			_expect(converted != null and absf(float(converted.call(&"sample", 0.37)) - float(curve.call(&"sample", 0.37))) < 2e-6, "Modified preset conversion changed shape")
			curve.call(&"reset_selected_preset")
			_expect(not curve.call(&"is_selected_preset_modified"), "Reset retained modified state")
			history.clear_history()
			history.free()
	_expect(absf(_reference(0.25, 2) - (1.0 - cos(PI * 0.25)) / 2.0) > 0.009, "Smoothstep confused with Sine")
	_finish("Smoothstep")


func _check_round_trip(curve: Resource, native: bool) -> void:
	var path := "res://test/_temp/smoothstep-native.tres" if native else "res://test/_temp/smoothstep-legacy.tres"
	_expect(ResourceSaver.save(curve, path) == OK, "Smoothstep save failed")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(loaded != null, "Smoothstep reload failed")
	if loaded != null:
		_expect(loaded.get(&"transition" if native else &"trans_type") == (109 if native else 21), "Serialized transition changed")
		_expect(absf(float(loaded.call(&"sample", 0.37)) - float(curve.call(&"sample", 0.37))) < 2e-6, "Round trip changed Smoothstep")

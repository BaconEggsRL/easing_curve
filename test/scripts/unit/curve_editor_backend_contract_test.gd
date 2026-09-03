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
	_expect(legacy_backend.get_point_count() == legacy.points.size(), "legacy backend point count changed")
	_expect(is_equal_approx(legacy_backend.sample(0.0), legacy.sample(0.0)), "legacy backend sampling changed")
	var legacy_snapshot: Variant = legacy_backend.capture_snapshot()
	_expect(legacy_backend.apply_snapshot(legacy_snapshot), "legacy backend rejected its own snapshot")

	if ClassDB.class_exists(&"NativeEasingCurve"):
		var native := ClassDB.instantiate(&"NativeEasingCurve") as Resource
		var native_backend := BackendFactory.create(native)
		_expect(native_backend != null, "Native backend was not selected")
		_expect(native_backend.get_backend_id() == &"native", "Native backend identity changed")
		_expect(not native_backend.get_capabilities()[&"runtime_callable"], "Native advertises per-sample Callables")
		_expect(native_backend.get_capabilities()[&"callable_baking"], "Native Callable-baking capability is missing")
		_expect(native_backend.get_transition_ids().has(100), "Native custom transition is missing")
		_expect(not native_backend.get_transition_ids().has(102), "Native advertises unimplemented Jitter")
		_expect(is_equal_approx(native_backend.sample(0.0), 0.0), "Native backend sampling changed")
		var native_snapshot: Variant = native_backend.capture_snapshot()
		_expect(native_backend.apply_snapshot(native_snapshot), "Native backend rejected its own snapshot")

	_expect(BackendFactory.create(Resource.new()) == null, "backend factory accepted an unrelated Resource")
	_finish("curve editor backend contract")

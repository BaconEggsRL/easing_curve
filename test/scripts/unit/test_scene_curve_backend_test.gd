extends "res://test/scripts/support/test_case.gd"

const TEST_SCENE := preload("res://addons/easing_curve/_test_scene/test.tscn")
const NATIVE_TRANSITION_COUNT := 5
const SAMPLE_OFFSET := 0.37


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var test_scene := TEST_SCENE.instantiate()
	root.add_child(test_scene)
	await process_frame

	var transition_dropdown := test_scene.get_node("%CurveTransDropdown") as OptionButton
	_expect(test_scene.get("use_native_curve"), "test scene does not default to native")
	_expect(test_scene.get("native_curve") is NativeEasingCurve, "native resource is missing")
	_expect(test_scene.get("_runtime_native_curve") != null, "native runtime copy is missing")
	_expect(test_scene.get("_runtime_easing_curve") == null, "legacy runtime copy is active")
	var native_runtime := test_scene.get("_runtime_native_curve") as NativeEasingCurve
	_expect(
		is_equal_approx(
			float(test_scene.call("tween_native_curve", SAMPLE_OFFSET)),
			native_runtime.sample(SAMPLE_OFFSET),
		),
		"native interpolator does not sample the native runtime resource",
	)
	_expect(
		transition_dropdown.item_count == NATIVE_TRANSITION_COUNT,
		"native transition options are incomplete",
	)

	test_scene.set("use_native_curve", false)
	await process_frame
	_expect(not test_scene.get("use_native_curve"), "legacy backend switch failed")
	_expect(test_scene.get("_runtime_native_curve") == null, "native runtime copy stayed active")
	_expect(test_scene.get("_runtime_easing_curve") != null, "legacy runtime copy is missing")
	var legacy_runtime := test_scene.get("_runtime_easing_curve") as EasingCurve
	_expect(
		is_equal_approx(
			float(test_scene.call("tween_easing_curve", SAMPLE_OFFSET)),
			legacy_runtime.sample(SAMPLE_OFFSET),
		),
		"legacy interpolator does not sample the legacy runtime resource",
	)
	_expect(
		transition_dropdown.item_count == EasingCurve.TRANS.size(),
		"legacy transition options are incomplete",
	)

	test_scene.queue_free()
	_finish("test scene curve backend")

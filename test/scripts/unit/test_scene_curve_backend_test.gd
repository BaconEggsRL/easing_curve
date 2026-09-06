extends "res://test/scripts/support/test_case.gd"

const TEST_SCENE := preload("res://addons/easing_curve/_test_scene/test.tscn")
const NATIVE_TRANSITION_COUNT := 13
const SAMPLE_OFFSET := 0.37


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_dropdown_playback(true)
	await _test_dropdown_playback(false)
	var test_scene := TEST_SCENE.instantiate()
	root.add_child(test_scene)
	await process_frame

	var transition_dropdown := test_scene.get_node("%CurveTransDropdown") as OptionButton
	_expect(test_scene.get("use_native_curve"), "test scene does not default to native")
	_expect(test_scene.get("native_curve") is NativeEasingCurve, "native resource is missing")
	_expect(test_scene.get("_runtime_native_curve") != null, "native runtime copy is missing")
	_expect(test_scene.get("_runtime_easing_curve") == null, "legacy runtime copy is active")
	var native_runtime := test_scene.get("_runtime_native_curve") as NativeEasingCurve
	var authored_native := test_scene.get("native_curve") as NativeEasingCurve
	var authored_points := authored_native.points
	var runtime_points := native_runtime.points
	_expect(runtime_points[0] != authored_points[0], "test scene runtime copy shares authored point Resources")
	var runtime_handle_before := runtime_points[0].right_control_point
	authored_points[0].right_control_point = Vector2(0.15, 0.85)
	_expect(
		runtime_points[0].right_control_point == runtime_handle_before,
		"authored point edit leaked into the active runtime curve",
	)
	test_scene.call(&"restart_runtime")
	var restarted_native := test_scene.get("_runtime_native_curve") as NativeEasingCurve
	_expect(
		restarted_native.points[0].right_control_point == authored_points[0].right_control_point,
		"manual Restart reused a stale Native runtime copy",
	)
	native_runtime = restarted_native
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
	for transition in range(Tween.TRANS_SPRING + 1):
		test_scene.set("tween_trans", transition)
		_expect(
			test_scene.call("_get_matching_curve_trans") == transition,
			"Tween transition %d does not map to the native equivalent" % transition,
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


func _test_dropdown_playback(native: bool) -> void:
	var scene := TEST_SCENE.instantiate()
	scene.set("use_native_curve", native)
	root.add_child(scene)
	await process_frame
	var trans := scene.get_node("%CurveTransDropdown") as OptionButton
	var ease := scene.get_node("%CurveEaseDropdown") as OptionButton
	var authored := scene.get("native_curve" if native else "easing_curve") as Resource
	var transition_property := &"transition" if native else &"trans_type"
	var authored_transition: int = authored.get(transition_property)
	var authored_ease: int = authored.get(&"ease_type")
	var quad := int(Tween.TRANS_QUAD) if native else int(EasingCurve.TRANS.QUAD)
	var out_ease := 1 if native else int(EasingCurve.EASE.OUT)
	_select_option(trans, quad)
	_select_option(ease, out_ease)
	await process_frame
	var runtime := scene.get("_runtime_native_curve" if native else "_runtime_easing_curve") as Resource
	_expect(int(runtime.get(transition_property)) == quad, "first curve transition selection was discarded (%s)" % native)
	_expect(int(runtime.get(&"ease_type")) == out_ease, "first curve Ease selection was discarded (%s)" % native)
	var sample_method := &"tween_native_curve" if native else &"tween_easing_curve"
	_expect(absf(float(scene.call(sample_method, 0.5)) - 0.75) < 0.002, "playback ignores curve dropdowns (%s)" % native)
	_select_option(scene.get_node("%TweenTransDropdown"), Tween.TRANS_SINE)
	(scene.get_node("%ReverseCheckButton") as CheckButton).button_pressed = true
	(scene.get_node("%ReverseCheckButton") as CheckButton).pressed.emit()
	_expect(scene.get("_runtime_native_curve" if native else "_runtime_easing_curve") == runtime, "comparison controls discarded runtime edits (%s)" % native)
	_expect(int(authored.get(transition_property)) == authored_transition and int(authored.get(&"ease_type")) == authored_ease, "playback controls modified authored curve (%s)" % native)
	var match_button := scene.get_node("%MatchTweenCheckButton") as CheckButton
	match_button.button_pressed = true
	match_button.pressed.emit()
	_expect(int(runtime.get(transition_property)) == int(scene.call("_get_matching_curve_trans")), "Match Tween did not apply (%s)" % native)
	match_button.button_pressed = false
	match_button.pressed.emit()
	_expect(scene.get("_runtime_native_curve" if native else "_runtime_easing_curve") == runtime, "disabling Match Tween discarded runtime edits (%s)" % native)
	scene.queue_free()
	await process_frame


func _select_option(dropdown: OptionButton, value: int) -> void:
	for index in dropdown.item_count:
		if int(dropdown.get_item_metadata(index)) == value:
			dropdown.select(index)
			dropdown.item_selected.emit(index)
			return
	_expect(false, "missing dropdown value %d" % value)

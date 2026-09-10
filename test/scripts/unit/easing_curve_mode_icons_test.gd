extends "res://test/scripts/support/test_case.gd"

const ICONS = preload("res://addons/easing_curve/scripts/editor/inspector/curve_mode_icons.gd")
const INSPECTOR = preload("res://addons/easing_curve/scripts/editor/inspector/inspector_curve_context.gd")

func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_expect(ICONS.TRANSITION_ICONS.size() == EasingCurve.TRANS.size(), "Transition icon catalog is incomplete")
	for name: StringName in EasingCurve.TRANS:
		_expect(ICONS.get_transition_icon(name) != null, "Lazy runtime transition icon missing: %s" % name)
	for name: StringName in EasingCurve.EASE:
		_expect(ICONS.get_ease_icon(name) != null, "Lazy runtime ease icon missing: %s" % name)
	_expect(ICONS.get_transition_icon(&"UNKNOWN") == null, "Unknown transition should not load a texture")
	_expect(ICONS.get_ease_icon(&"UNKNOWN") == null, "Unknown ease should not load a texture")
	for scale: float in [1.0, 1.5, 2.0]:
		for light: bool in [false, true]:
			var theme := Theme.new()
			theme.default_base_scale = scale
			theme.set_color(&"font_color", &"Editor", Color.BLACK if light else Color.WHITE)
			for name: StringName in EasingCurve.TRANS:
				var icon := ICONS.get_transition_icon(name, theme)
				_expect(icon != null and icon.get_size() == Vector2.ONE * roundi(16 * scale), "Transition icon missing or wrong size: %s" % name)
				_expect(icon == ICONS.get_transition_icon(name, theme), "Icon lookup missed cache")
			for name: StringName in EasingCurve.EASE:
				_expect(ICONS.get_ease_icon(name, theme) != null, "Ease icon missing")
	var theme := Theme.new()
	var builtin := GradientTexture2D.new()
	for name: StringName in ICONS.BUILTIN_TRANSITIONS.values():
		theme.set_icon(name, &"EditorIcons", builtin)
	for name: StringName in ICONS.BUILTIN_EASES.values():
		theme.set_icon(name, &"EditorIcons", builtin)
	for name: StringName in ICONS.BUILTIN_TRANSITIONS:
		_expect(ICONS.get_transition_icon(name, theme) == builtin, "Built-in transition icon not preferred")
	for name: StringName in EasingCurve.EASE:
		_expect(ICONS.get_ease_icon(name, theme) == builtin, "Built-in ease icon not preferred")
	for native: bool in [false, true]:
		var selected := 109 if native else EasingCurve.TRANS.SMOOTHSTEP
		var option: OptionButton = INSPECTOR._create_native_transition_option(selected, PackedInt32Array(ICONS.CONVERTER.NATIVE_TO_LEGACY_TRANSITIONS.keys())) if native else INSPECTOR._create_transition_option(selected)
		var seen := {}
		var old_icons := {}
		for index in option.item_count:
			if option.get_popup().is_item_separator(index): continue
			var id := option.get_item_id(index)
			_expect(not seen.has(id), "Duplicate transition ID")
			seen[id] = true
			old_icons[index] = option.get_item_icon(index)
			_expect(old_icons[index] != null, "Popup icon missing")
		_expect(seen.size() == EasingCurve.TRANS.size() and option.get_selected_id() == selected, "Popup IDs/selection changed")
		for modified: bool in [true, false]:
			if native: INSPECTOR._set_native_transition_display(option, selected, modified)
			else: INSPECTOR._set_transition_display(option, selected, modified)
			for index: int in old_icons:
				_expect(option.get_item_icon(index) == old_icons[index], "Modified label replaced icon")
		option.free()
	var ease := INSPECTOR._create_option(EasingCurve.EASE, EasingCurve.EASE.OUT_IN)
	for index in ease.item_count:
		_expect(ease.get_item_icon(index) != null and ease.get_item_id(index) == index, "Ease popup changed IDs or lost icons")
	ease.free()
	var scene := load("res://addons/easing_curve/_test_scene/test.tscn") as PackedScene
	for native: bool in [false, true]:
		var demo := scene.instantiate()
		demo.set("use_native_curve", native)
		root.add_child(demo)
		await process_frame
		for path: NodePath in [^"%CurveTransDropdown", ^"%CurveEaseDropdown", ^"%TweenTransDropdown", ^"%TweenEaseDropdown"]:
			var dropdown := demo.get_node(path) as OptionButton
			for index in dropdown.item_count:
				_expect(dropdown.get_item_icon(index) != null, "Demo dropdown icon missing")
		demo.free()
	_finish("curve mode icons")

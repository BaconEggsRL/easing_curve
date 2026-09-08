@tool
extends RefCounted
## Fixed transition artwork. Runtime callers omit the optional Editor theme.

const CONVERTER = preload("res://addons/easing_curve/scripts/editor/backend/curve_converter.gd")
const BUILTIN_TRANSITIONS := {&"CONSTANT": &"CurveConstant", &"LINEAR": &"CurveLinear", &"SMOOTHSTEP": &"CurveInOut"}
const BUILTIN_EASES := {&"IN": &"CurveIn", &"OUT": &"CurveOut", &"IN_OUT": &"CurveInOut", &"OUT_IN": &"CurveOutIn"}
static var _themed_icons: Dictionary[String, Texture2D] = {}
const TRANSITION_ICONS := {
	&"BACK": preload("res://addons/easing_curve/assets/transitions/back.svg"),
	&"BOUNCE": preload("res://addons/easing_curve/assets/transitions/bounce.svg"),
	&"CIRC": preload("res://addons/easing_curve/assets/transitions/circ.svg"),
	&"CONSTANT": preload("res://addons/easing_curve/assets/transitions/constant.svg"),
	&"CSS_CUBIC_BEZIER": preload("res://addons/easing_curve/assets/transitions/css_cubic_bezier.svg"),
	&"CSS_LINEAR": preload("res://addons/easing_curve/assets/transitions/css_linear.svg"),
	&"CUBIC": preload("res://addons/easing_curve/assets/transitions/cubic.svg"),
	&"CUSTOM": preload("res://addons/easing_curve/assets/transitions/custom.svg"),
	&"ELASTIC": preload("res://addons/easing_curve/assets/transitions/elastic.svg"),
	&"EXPO": preload("res://addons/easing_curve/assets/transitions/expo.svg"),
	&"IRREGULAR": preload("res://addons/easing_curve/assets/transitions/irregular.svg"),
	&"JITTER": preload("res://addons/easing_curve/assets/transitions/jitter.svg"),
	&"LINEAR": preload("res://addons/easing_curve/assets/transitions/linear.svg"),
	&"PHYSICS_SPRING": preload("res://addons/easing_curve/assets/transitions/physics_spring.svg"),
	&"POWER": preload("res://addons/easing_curve/assets/transitions/power.svg"),
	&"QUAD": preload("res://addons/easing_curve/assets/transitions/quad.svg"),
	&"QUART": preload("res://addons/easing_curve/assets/transitions/quart.svg"),
	&"QUINT": preload("res://addons/easing_curve/assets/transitions/quint.svg"),
	&"SINE": preload("res://addons/easing_curve/assets/transitions/sine.svg"),
	&"SMOOTHSTEP": preload("res://addons/easing_curve/assets/transitions/smoothstep.svg"),
	&"SPRING": preload("res://addons/easing_curve/assets/transitions/spring.svg"),
	&"STEP": preload("res://addons/easing_curve/assets/transitions/step.svg"),
}
const EASE_ICONS := {
	&"IN": preload("res://addons/easing_curve/assets/transitions/ease_in.svg"),
	&"OUT": preload("res://addons/easing_curve/assets/transitions/ease_out.svg"),
	&"IN_OUT": preload("res://addons/easing_curve/assets/transitions/ease_in_out.svg"),
	&"OUT_IN": preload("res://addons/easing_curve/assets/transitions/ease_out_in.svg"),
}


static func get_transition_icon(name: StringName, editor_theme: Theme = null) -> Texture2D:
	return _get_icon(name, TRANSITION_ICONS, BUILTIN_TRANSITIONS, editor_theme)


static func get_ease_icon(name: StringName, editor_theme: Theme = null) -> Texture2D:
	return _get_icon(name, EASE_ICONS, BUILTIN_EASES, editor_theme)


static func get_native_transition_icon(id: int, editor_theme: Theme = null) -> Texture2D:
	if not CONVERTER.NATIVE_TO_LEGACY_TRANSITIONS.has(id):
		return null
	return get_transition_icon(EasingCurve.TRANS.keys()[CONVERTER.NATIVE_TO_LEGACY_TRANSITIONS[id]], editor_theme)


static func _get_icon(name: StringName, fallbacks: Dictionary, builtins: Dictionary, editor_theme: Theme) -> Texture2D:
	if editor_theme != null and builtins.has(name) and editor_theme.has_icon(builtins[name], &"EditorIcons"):
		return editor_theme.get_icon(builtins[name], &"EditorIcons")
	var texture := fallbacks.get(name) as Texture2D
	if texture == null or editor_theme == null:
		return texture
	var scale := maxf(1.0, editor_theme.default_base_scale)
	var light := editor_theme.has_color(&"font_color", &"Editor") and editor_theme.get_color(&"font_color", &"Editor").get_luminance() < 0.5
	var key := "%s/%s/%s" % [name, scale, light]
	if not _themed_icons.has(key):
		var image := texture.get_image()
		if light:
			for y in image.get_height():
				for x in image.get_width():
					image.set_pixel(x, y, image.get_pixel(x, y).darkened(0.45))
		var side := roundi(16.0 * scale)
		if image.get_width() != side:
			image.resize(side, side, Image.INTERPOLATE_LANCZOS)
		_themed_icons[key] = ImageTexture.create_from_image(image)
	return _themed_icons[key]

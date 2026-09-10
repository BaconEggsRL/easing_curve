@tool
extends RefCounted
## Fixed transition artwork. Runtime callers omit the optional Editor theme.
## Keep paths here: preloading imported textures can break first-install parsing.

const CONVERTER = preload("res://addons/easing_curve/scripts/editor/backend/curve_converter.gd")
const BUILTIN_TRANSITIONS := {&"CONSTANT": &"CurveConstant", &"LINEAR": &"CurveLinear", &"SMOOTHSTEP": &"CurveInOut"}
const BUILTIN_EASES := {&"IN": &"CurveIn", &"OUT": &"CurveOut", &"IN_OUT": &"CurveInOut", &"OUT_IN": &"CurveOutIn"}
static var _themed_icons: Dictionary[String, Texture2D] = {}
const TRANSITION_ICONS := {
	&"BACK": "res://addons/easing_curve/assets/transitions/back.svg",
	&"BOUNCE": "res://addons/easing_curve/assets/transitions/bounce.svg",
	&"CIRC": "res://addons/easing_curve/assets/transitions/circ.svg",
	&"CONSTANT": "res://addons/easing_curve/assets/transitions/constant.svg",
	&"CSS_CUBIC_BEZIER": "res://addons/easing_curve/assets/transitions/css_cubic_bezier.svg",
	&"CSS_LINEAR": "res://addons/easing_curve/assets/transitions/css_linear.svg",
	&"CUBIC": "res://addons/easing_curve/assets/transitions/cubic.svg",
	&"CUSTOM": "res://addons/easing_curve/assets/transitions/custom.svg",
	&"ELASTIC": "res://addons/easing_curve/assets/transitions/elastic.svg",
	&"EXPO": "res://addons/easing_curve/assets/transitions/expo.svg",
	&"IRREGULAR": "res://addons/easing_curve/assets/transitions/irregular.svg",
	&"JITTER": "res://addons/easing_curve/assets/transitions/jitter.svg",
	&"LINEAR": "res://addons/easing_curve/assets/transitions/linear.svg",
	&"PHYSICS_SPRING": "res://addons/easing_curve/assets/transitions/physics_spring.svg",
	&"POWER": "res://addons/easing_curve/assets/transitions/power.svg",
	&"QUAD": "res://addons/easing_curve/assets/transitions/quad.svg",
	&"QUART": "res://addons/easing_curve/assets/transitions/quart.svg",
	&"QUINT": "res://addons/easing_curve/assets/transitions/quint.svg",
	&"SINE": "res://addons/easing_curve/assets/transitions/sine.svg",
	&"SMOOTHSTEP": "res://addons/easing_curve/assets/transitions/smoothstep.svg",
	&"SPRING": "res://addons/easing_curve/assets/transitions/spring.svg",
	&"STEP": "res://addons/easing_curve/assets/transitions/step.svg",
}
const EASE_ICONS := {
	&"IN": "res://addons/easing_curve/assets/transitions/ease_in.svg",
	&"OUT": "res://addons/easing_curve/assets/transitions/ease_out.svg",
	&"IN_OUT": "res://addons/easing_curve/assets/transitions/ease_in_out.svg",
	&"OUT_IN": "res://addons/easing_curve/assets/transitions/ease_out_in.svg",
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
	if not fallbacks.has(name):
		return null
	if editor_theme == null:
		return load(fallbacks[name]) as Texture2D
	var scale := maxf(1.0, editor_theme.default_base_scale)
	var light := editor_theme.has_color(&"font_color", &"Editor") and editor_theme.get_color(&"font_color", &"Editor").get_luminance() < 0.5
	var key := "%s/%s/%s" % [name, scale, light]
	if not _themed_icons.has(key):
		var texture := load(fallbacks[name]) as Texture2D
		if texture == null:
			return null
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

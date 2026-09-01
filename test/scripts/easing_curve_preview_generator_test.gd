extends "res://test/scripts/test_case.gd"

const EDITOR_HOST = preload("res://test/scripts/editor_host_test_harness.gd")
const PREVIEW_GENERATOR = preload(
	"res://addons/easing_curve/scripts/editor/easing_curve_preview_generator.gd"
)

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not EDITOR_HOST.require_editor_host("easing_curve_preview_generator_test.gd"):
		quit(1)
		return

	var generator := PREVIEW_GENERATOR.new()
	_expect(generator._handles("Resource"), "Preview generator did not handle script Resource base type")
	_expect(generator._handles("EasingCurve"), "Preview generator did not handle EasingCurve script type")
	_expect(not generator._handles("Curve"), "Preview generator intercepted built-in Curve resources")
	_expect(
		generator._generate(Resource.new(), Vector2i(64, 64), {}) == null,
		"Preview generator produced an image for an unrelated Resource",
	)

	var curve := EasingCurve.new()
	var texture := generator._generate(curve, Vector2i(64, 64), {})
	_expect(texture != null, "Preview generator returned no texture for EasingCurve")
	if texture != null:
		var image := texture.get_image()
		_expect(image.get_size() == Vector2i(64, 64), "Preview texture used the wrong dimensions")
		_expect(_count_visible_pixels(image) >= 64, "Preview texture did not contain a plotted curve")
		_expect(
			image.get_pixel(image.get_width() - 1, 0).a > 0.0,
			"Preview did not sample the curve's right endpoint",
		)

	var back_in := EasingCurve.new()
	back_in.set_trans(EasingCurve.TRANS.BACK)
	var back_in_texture := generator._generate(back_in, Vector2i(64, 64), {})
	_expect(back_in_texture != null, "Preview generator returned no Back IN texture")
	if back_in_texture != null:
		var back_in_image := back_in_texture.get_image()
		var zero_baseline_y := _find_visible_y_at_x(back_in_image, 0)
		_expect(zero_baseline_y >= 0, "Back IN preview did not draw its zero baseline endpoint")
		_expect(
			_get_max_visible_y(back_in_image) > zero_baseline_y,
			"Back IN preview clipped its undershoot below zero",
		)

	var back_out := EasingCurve.new()
	back_out.set_trans(EasingCurve.TRANS.BACK)
	back_out.set_ease(EasingCurve.EASE.OUT)
	var back_out_texture := generator._generate(back_out, Vector2i(64, 64), {})
	_expect(back_out_texture != null, "Preview generator returned no Back OUT texture")
	if back_out_texture != null:
		var back_out_image := back_out_texture.get_image()
		var one_baseline_y := _find_visible_y_at_x(
			back_out_image,
			back_out_image.get_width() - 1,
		)
		_expect(one_baseline_y >= 0, "Back OUT preview did not draw its one baseline endpoint")
		_expect(
			_get_min_visible_y(back_out_image) < one_baseline_y,
			"Back OUT preview clipped its overshoot above one",
		)

	_finish("EasingCurve preview generator")


func _count_visible_pixels(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _find_visible_y_at_x(image: Image, x: int) -> int:
	for y in range(image.get_height()):
		if image.get_pixel(x, y).a > 0.0:
			return y
	return -1


func _get_min_visible_y(image: Image) -> int:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				return y
	return -1


func _get_max_visible_y(image: Image) -> int:
	for y in range(image.get_height() - 1, -1, -1):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				return y
	return -1

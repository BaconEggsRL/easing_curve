extends SceneTree

const EDITOR_HOST = preload("res://test/scripts/editor_host_test_harness.gd")
const PREVIEW_GENERATOR = preload(
	"res://addons/easing_curve/scripts/editor/easing_curve_preview_generator.gd"
)

var _failures := 0
var _checks := 0


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

	if _failures == 0:
		print("PASS: %d EasingCurve preview generator checks" % _checks)
	else:
		push_error("FAIL: %d of %d EasingCurve preview generator checks failed" % [_failures, _checks])
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _count_visible_pixels(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count

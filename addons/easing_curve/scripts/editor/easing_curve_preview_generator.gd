@tool
extends EditorResourcePreviewGenerator

const NATIVE_RESOURCE_TYPE := "Resource"
const SCRIPT_RESOURCE_TYPE := "EasingCurve"

var line_color := Color.WHITE


func _handles(resource_type: String) -> bool:
	# Script resources are reported by their native base type in some Godot versions.
	return resource_type == NATIVE_RESOURCE_TYPE or resource_type == SCRIPT_RESOURCE_TYPE


func _generate(
		resource: Resource,
		size: Vector2i,
		_metadata: Dictionary,
) -> Texture2D:
	var source_curve := resource as EasingCurve
	if source_curve == null or size.x <= 0 or size.y <= 0:
		return null

	# Sampling may lazily initialize function-backed curves, so use a thread-local copy.
	var curve := source_curve.duplicate(true) as EasingCurve
	if curve == null:
		return null

	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var previous_y := _sample_y(curve, 0.0, size.y)
	image.set_pixel(0, previous_y, line_color)

	for x in range(1, size.x):
		var offset := float(x) / float(size.x)
		var y := _sample_y(curve, offset, size.y)
		for pixel in Geometry2D.bresenham_line(
			Vector2i(x - 1, previous_y),
			Vector2i(x, y),
		):
			image.set_pixelv(pixel, line_color)
		previous_y = y

	return ImageTexture.create_from_image(image)


func _sample_y(curve: EasingCurve, offset: float, height: int) -> int:
	var normalized_value := curve.sample(offset)
	return clampi(int(height - normalized_value * height), 0, height - 1)

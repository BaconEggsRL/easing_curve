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

	var sampled_values := PackedFloat64Array()
	var min_value := 0.0
	var max_value := 1.0
	for x in range(size.x):
		var offset := float(x) / float(maxi(size.x - 1, 1))
		var value := curve.sample(offset)
		sampled_values.append(value)
		min_value = minf(min_value, value)
		max_value = maxf(max_value, value)

	if min_value < 0.0 or max_value > 1.0:
		var padding := maxf((max_value - min_value) * 0.05, 0.001)
		min_value -= padding
		max_value += padding

	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var previous_y := _value_to_y(sampled_values[0], min_value, max_value, size.y)
	image.set_pixel(0, previous_y, line_color)

	for x in range(1, size.x):
		var y := _value_to_y(sampled_values[x], min_value, max_value, size.y)
		for pixel in Geometry2D.bresenham_line(
			Vector2i(x - 1, previous_y),
			Vector2i(x, y),
		):
			image.set_pixelv(pixel, line_color)
		previous_y = y

	return ImageTexture.create_from_image(image)


func _value_to_y(
		value: float,
		min_value: float,
		max_value: float,
		height: int,
) -> int:
	var span := maxf(max_value - min_value, 0.000001)
	var normalized_value := (value - min_value) / span
	return clampi(
		roundi((1.0 - normalized_value) * float(height - 1)),
		0,
		height - 1,
	)

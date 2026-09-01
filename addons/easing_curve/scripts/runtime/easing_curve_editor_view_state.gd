@tool
extends RefCounted
## Passive per-resource, in-session graph view state.
##
## This holder is intentionally limited to transient Curve Editor navigation
## values. It does not publish Resource.changed, participate in serialization,
## own Autofit lifecycle, or coordinate edit/Undo state.

const SLIDER_VALUE := &"slider_value"
const ZOOM := &"zoom"
const PAN := &"pan"

var slider_value: float
var zoom: Vector2
var pan: Vector2


func _init(
	default_slider_value: float,
	default_zoom: Vector2 = Vector2.ONE,
	default_pan: Vector2 = Vector2.ZERO,
) -> void:
	slider_value = default_slider_value
	zoom = default_zoom
	pan = default_pan


func to_dictionary() -> Dictionary:
	return {
		SLIDER_VALUE: slider_value,
		ZOOM: zoom,
		PAN: pan,
	}

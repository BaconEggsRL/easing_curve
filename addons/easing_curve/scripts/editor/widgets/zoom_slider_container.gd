@tool
class_name EasingCurveZoomSliderContainer
extends Control
## Zoom slider container for easing curve editor.
##
## Allows the user to click and drag slider to change zoom value.
## Clicking the autofit_btn will reset the zoom to default.

signal slider_changed
signal autofit_pressed

const ZOOM_MIN := EasingCurve.ZOOM_MIN
const ZOOM_MAX := EasingCurve.ZOOM_MAX
const ZOOM_FACTOR := EasingCurve.ZOOM_FACTOR
const ZOOM_STEPS := EasingCurve.ZOOM_STEPS
const DEFAULT_SLIDER_VALUE := EasingCurve.DEFAULT_SLIDER_VALUE
const EDITOR_THEME_CACHE = preload(
	"res://addons/easing_curve/scripts/editor/inspector/editor_theme_cache.gd"
)

@export var slider: HSlider
@export var autofit_btn: Button
@export var zoom_icon: TextureRect


func _ready():
	zoom_icon.texture = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_ZOOM
	)
	autofit_btn.icon = EDITOR_THEME_CACHE.get_icon(
		EDITOR_THEME_CACHE.ICON_ANIMATION_AUTO_FIT_BEZIER
	)

	var controls := slider.get_parent() as HBoxContainer
	if controls != null:
		custom_minimum_size.x = controls.get_combined_minimum_size().x

	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.gui_input.connect(_on_slider_gui_input)
	autofit_btn.pressed.connect(_on_autofit_btn_pressed)
	slider.value_changed.connect(_on_slider_value_changed)


func _on_slider_value_changed(value: float) -> void:
	slider_changed.emit(value)


func _on_autofit_btn_pressed() -> void:
	autofit_pressed.emit()


func _on_slider_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# --- Mouse Wheel Zoom ---
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			accept_event()
			slider.value += slider.step
			return
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			accept_event()
			slider.value -= slider.step
			return

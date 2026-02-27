@tool
class_name ZoomSliderContainer
extends Control
## Zoom slider container for easing curve editor.
##
## Allows the user to click and drag slider to change zoom value.
## Clicking the autofit_btn will reset the zoom to default.

signal slider_changed
signal autofit_pressed

const ZOOM_MIN := 0.1
const ZOOM_MAX := 10.0
const ZOOM_FACTOR := 1.2 # same as wheel multiplier
const ZOOM_STEPS := int(round(log(ZOOM_MAX / ZOOM_MIN) / log(ZOOM_FACTOR)))
const DEFAULT_SLIDER_VALUE := floor(ZOOM_STEPS / 2.0)

@export var slider: HSlider
@export var autofit_btn: Button


func _ready():
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

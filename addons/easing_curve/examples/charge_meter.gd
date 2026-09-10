extends Control
## Sampling also works for values: normalized time becomes a bounded charge percentage.

@export var curve: EasingCurve:
	set(value):
		if curve != null and curve.changed.is_connected(_on_curve_changed):
			curve.changed.disconnect(_on_curve_changed)
		curve = value
		if curve != null:
			curve.changed.connect(_on_curve_changed)
		if is_node_ready():
			_on_curve_changed()
@export_range(0.05, 10.0, 0.05) var duration := 1.5

var tween: Tween
var progress := 0.0
@onready var meter: ProgressBar = %Meter
@onready var scrubber: HSlider = %Progress


func _ready() -> void:
	reset()
	%Replay.grab_focus()


func replay() -> void:
	reset()
	tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	tween.tween_method(apply_charge, 0.0, 1.0, maxf(duration, 0.05))


func apply_charge(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	var weight := curve.sample(progress) if curve != null else progress
	meter.value = clampf(weight, 0.0, 1.0) * 100.0
	scrubber.set_value_no_signal(progress)
	%Readout.text = "Time: %.2f   Sample: %.3f   Charge: %.1f%%" % [progress, weight, meter.value]


func scrub(value: float) -> void:
	if tween != null:
		tween.kill()
	apply_charge(value)


func reset() -> void:
	scrub(0.0)


func _on_curve_changed() -> void:
	if not is_node_ready():
		return
	if tween != null and tween.is_running():
		replay()
	else:
		apply_charge(progress)

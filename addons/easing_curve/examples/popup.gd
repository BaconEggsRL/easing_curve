extends Control
## A reusable authored curve supplies the easing; Tween supplies time and interpolation.

@export var curve: EasingCurve:
	set(value):
		if curve != null and curve.changed.is_connected(replay):
			curve.changed.disconnect(replay)
		curve = value
		if curve != null:
			curve.changed.connect(replay)
		if is_node_ready():
			replay()
@export_range(0.05, 10.0, 0.05) var duration := 0.5

var tween: Tween
@onready var panel: PanelContainer = %Popup


func _ready() -> void:
	panel.pivot_offset = panel.size / 2.0
	reset()
	%Replay.grab_focus()


func replay() -> void:
	if not is_node_ready():
		return
	reset()
	tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	var motion := tween.tween_property(panel, "scale", Vector2.ONE, maxf(duration, 0.05))
	if curve != null:
		motion.set_custom_interpolator(curve.sample)


func reset() -> void:
	if tween != null:
		tween.kill()
	panel.scale = Vector2.ONE * 0.2

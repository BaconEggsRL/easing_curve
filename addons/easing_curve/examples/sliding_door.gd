extends Control
## AnimationPlayer owns the timeline. This setter maps its linear progress through a curve.

@export var curve: EasingCurve:
	set(value):
		if curve != null and curve.changed.is_connected(replay):
			curve.changed.disconnect(replay)
		curve = value
		if curve != null:
			curve.changed.connect(replay)
		if is_node_ready():
			replay()
@export_range(0.05, 10.0, 0.05) var duration := 1.5
@export var closed_position := Vector2.ZERO
@export var open_position := Vector2(280.0, 0.0)
@export_range(0.0, 1.0, 0.001) var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		if is_node_ready():
			var weight := curve.sample(progress) if curve != null else progress
			door.position = closed_position.lerp(open_position, weight)

@onready var door: PanelContainer = %Door
@onready var player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	reset()
	%Replay.grab_focus()


func replay() -> void:
	if not is_node_ready():
		return
	reset()
	player.speed_scale = 1.0 / maxf(duration, 0.05)
	player.play(&"open")


func close() -> void:
	player.speed_scale = 1.0 / maxf(duration, 0.05)
	player.play_backwards(&"open")


func reset() -> void:
	player.stop()
	progress = 0.0

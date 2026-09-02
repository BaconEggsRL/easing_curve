@tool
extends Node

@export var export_array_resource: ExportArrayResource = ExportArrayResource.new()

var points: Array = []


func _ready() -> void:
	# Set window size
	DisplayServer.window_set_size(Vector2(100, 100))
	DisplayServer.window_set_position(Vector2(1920 / 2.0, 1080 / 2.0) - Vector2(100, 100) / 2.0)
	# Connect changed signal
	# export_array_resource.changed.connect(_on_export_array_resource_changed)
	_connect_resource_signals.call_deferred()
	# Print updated points
	# print_points()


func print_points() -> void:
	points = export_array_resource.get_points_array()
	print(points)


func _connect_resource_signals():
	if export_array_resource:
		if export_array_resource.changed.is_connected(_on_export_array_resource_changed):
			export_array_resource.changed.disconnect(_on_export_array_resource_changed)

		if export_array_resource.value_changed.is_connected(_on_export_array_resource_value_changed):
			export_array_resource.value_changed.disconnect(_on_export_array_resource_value_changed)

		export_array_resource.changed.connect(_on_export_array_resource_changed)
		export_array_resource.value_changed.connect(_on_export_array_resource_value_changed)


func _on_export_array_resource_value_changed(msg: String) -> void:
	print(msg)
	pass


func _on_export_array_resource_changed() -> void:
	# print("changed")
	# print_points()
	pass


func _on_restart_pressed() -> void:
	# print("restart")
	get_tree().reload_current_scene()

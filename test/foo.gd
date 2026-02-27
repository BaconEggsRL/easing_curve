@tool
class_name Foo
extends Resource

@export var points: Array[Point] = []:
	set = _set_points


func _set_points(value) -> void:
	if points == value:
		return

	# Disconnect old
	for p in points:
		if p and p.changed.is_connected(_on_point_changed):
			p.changed.disconnect(_on_point_changed)

	points = value

	# Connect new
	for p in points:
		if p and not p.changed.is_connected(_on_point_changed):
			p.changed.connect(_on_point_changed)

	# Emit changed
	# print("Points array changed (add/remove/replace)")
	# print("points = ", points)
	#for p in points:
	#if p:
	#print(p.position, p.left_control_point, p.right_control_point)
	emit_changed()


func _on_point_changed() -> void:
	# print("point changed")
	print("points = ", points)
	emit_changed()

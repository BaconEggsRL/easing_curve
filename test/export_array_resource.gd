@tool
class_name ExportArrayResource
extends Resource

signal value_changed

# Label / Prefix
@export_group("Points/point_")
# Define properties.
@export var position := Vector2(0, 0)
@export var left_control_point := Vector2(0, 0)
# @export_enum("Free", "Linear", "Balanced", "Mirrored") var left_mode: int
@export var right_control_point := Vector2(0, 0)

# @export_enum("Free", "Linear", "Balanced", "Mirrored") var right_mode: int
# End of properties.
@export_group("")
var label: String
var prefix: String
var property_info_cache: Array[Dictionary]
var defaults: Dictionary[String, Variant]
var making_cache: bool
var values: Dictionary[StringName, Variant]
var count: int
var count_property: StringName:
	get:
		return str(prefix, "count")
var last_points: Array = []
var points: Array = []:
	set = set_points_array, get = get_points_array


func _validate_property(property: Dictionary) -> void:
	if property["name"] in defaults:
		property["usage"] = PROPERTY_USAGE_NONE


func _get_property_list() -> Array[Dictionary]:
	if making_cache:
		return []

	_ensure_cache()

	var ret: Array[Dictionary]
	ret.append(
		{
			"name": count_property,
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_ARRAY,
			"class_name": str(label, ",", prefix),
		},
	)

	var point_count = get(count_property)
	for i in point_count:
		for property in property_info_cache:
			var info: Dictionary = property.duplicate()
			var prop_name := str(prefix, i, "/", property["name"])

			# Only show left_control_point if not first point
			if property["name"] == "left_control_point" and i == 0:
				continue
			# Only show right_control_point if not last point
			if property["name"] == "right_control_point" and i == point_count - 1:
				continue

			var default = defaults[property["name"]]

			# Set property name for inspector
			info["name"] = prop_name

			# Hide if value equals default
			if values.get(prop_name, default) == default:
				info["usage"] &= ~PROPERTY_USAGE_STORAGE

			ret.append(info)

	return ret


func _property_can_revert(property: StringName) -> bool:
	return property.begins_with(prefix)


func _property_get_revert(property: StringName) -> Variant:
	var part := property.get_slice("/", 1)
	return defaults.get(part)


func _get(property: StringName) -> Variant:
	_ensure_cache()

	if property == count_property:
		return count

	if property.begins_with(prefix):
		if property in values:
			return values[property]

		var part := property.get_slice("/", 1)
		return defaults.get(part)

	return null


func _set(property: StringName, value: Variant) -> bool:
	_ensure_cache()

	# Handle changing the number of points
	if property == count_property:
		var old_count = count
		count = value

		if old_count < count:
			# Add new points with fresh Vector2 values
			for i in range(old_count, count):
				var prefix_i = str(prefix, i, "/")
				for p in property_info_cache:
					if p["usage"] & PROPERTY_USAGE_GROUP:
						continue
					var full_name = prefix_i + p["name"]
					values[full_name] = Vector2.ZERO # fresh default

		elif old_count > count:
			# Remove deleted points
			for i in range(count, old_count):
				var prefix_i = str(prefix, i, "/")
				for p in property_info_cache:
					if p["usage"] & PROPERTY_USAGE_GROUP:
						continue
					values.erase(prefix_i + p["name"])

		# Update property list and points array
		points = get_points_array()
		notify_property_list_changed()
		emit_changed()
		value_changed.emit("_set count")
		# print("Count changed:", count)
		return true

	# Handle changes to individual properties
	if property.begins_with(prefix):
		# values[property] = value
		# emit_changed()
		points = get_points_array() # rebuild points array
		# print("Property changed:", property, "new value:", value)

		# Extract the index and property name
		var parts = property.split("/")
		if parts.size() != 2:
			print("Unexpected property format:", property)
			return false

		# parts[0] is like "point_0", parts[1] is "position"
		# var index_str = parts[0].replace(prefix, "")  # "0"
		# var i = int(index_str)
		# var prop_name = parts[1]
		# print("i = ", i)
		# print("prop_name = ", prop_name)

		# Save old value
		# var old_value: Vector2 = values.get(property, Vector2.ZERO)

		# Update value
		values[property] = value
		emit_changed()
		value_changed.emit("_set property")

		# Detect Y swap
		if points.size() != last_points.size():
			return true
		var size := points.size()
		print("points = ", points)
		print("last_points = ", last_points)
		for idx in points.size():
			var next := (idx + 1) % size
			var prev := (idx - 1 + size) % size
			if points[idx] == last_points[next]:
				print("Move down")
			if points[idx] == last_points[prev]:
				print("Move up")

		return true

	return false


func set_points_array(value) -> void:
	if points == value:
		return
	last_points = points.duplicate(true)
	points = value.duplicate(true)
	emit_changed()
	value_changed.emit("set_points_array")


func get_points_array() -> Array:
	var result: Array = []

	for i in count:
		var point := { }
		for property in property_info_cache:
			if property["usage"] & PROPERTY_USAGE_GROUP:
				continue # skip PROPERTY_USAGE_GROUP entries
			var prop_name := str(prefix, i, "/", property["name"])
			point[property["name"]] = _get(prop_name)
		result.append(point)

	return result


func _ensure_cache():
	if property_info_cache.is_empty():
		making_cache = true

		var in_group: bool
		for property in get_property_list():
			var propname: String = property["name"]

			if property["usage"] & PROPERTY_USAGE_GROUP:
				if not in_group and property["name"].contains("/"):
					in_group = true
					label = propname.get_slice("/", 0)
					prefix = propname.get_slice("/", 1)
				elif in_group and property["name"].is_empty():
					break
				# continue  # skip PROPERTY_USAGE_GROUP entries

			if in_group:
				property_info_cache.append(property)
				defaults[propname] = get(propname)

		making_cache = false

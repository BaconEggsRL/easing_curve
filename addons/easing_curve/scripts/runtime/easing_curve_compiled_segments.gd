@tool
extends RefCounted

const BEZIER_SOLVER := preload(
	"res://addons/easing_curve/scripts/runtime/bezier_solver.gd"
)
const SEGMENT_X_EPSILON := 0.000001

var _geometry_revision := 0
var _compiled_revision := -1
var _segment_x_bounds := PackedVector2Array()
var _segment_control_xs := PackedVector2Array()
var _segment_y_bounds := PackedVector2Array()
var _segment_control_ys := PackedVector2Array()
var _binary_search_safe := false
var _last_segment_index := -1


func invalidate() -> void:
	_geometry_revision += 1
	_last_segment_index = -1


func supports_binary_search(point_list: Array[EasingCurvePoint]) -> bool:
	_ensure_compiled(point_list)
	return _binary_search_safe


func sample(
		point_list: Array[EasingCurvePoint],
		offset: float,
		fallback_value: float,
) -> Vector2:
	_ensure_compiled(point_list)
	if not _binary_search_safe:
		return Vector2(-1.0, fallback_value)

	var segment_count := _segment_x_bounds.size()
	var segment_index := _last_segment_index
	if segment_index >= 0 and segment_index < segment_count:
		var last_bounds := _segment_x_bounds[segment_index]
		if (
			offset >= last_bounds.x
			and offset <= last_bounds.y
			and (segment_index == 0 or offset > last_bounds.x)
		):
			return _sample_segment(segment_index, offset)

		if segment_index + 1 < segment_count:
			var next_bounds := _segment_x_bounds[segment_index + 1]
			if offset > next_bounds.x and offset <= next_bounds.y:
				segment_index += 1
				_last_segment_index = segment_index
				return _sample_segment(segment_index, offset)

		if segment_index > 0:
			var previous_index := segment_index - 1
			var previous_bounds := _segment_x_bounds[previous_index]
			if (
				offset >= previous_bounds.x
				and offset <= previous_bounds.y
				and (previous_index == 0 or offset > previous_bounds.x)
			):
				_last_segment_index = previous_index
				return _sample_segment(previous_index, offset)

	segment_index = _find_segment_index(offset)
	if segment_index < 0:
		_last_segment_index = -1
		return Vector2(-1.0, fallback_value)

	_last_segment_index = segment_index
	return _sample_segment(segment_index, offset)


func _ensure_compiled(point_list: Array[EasingCurvePoint]) -> void:
	if _compiled_revision == _geometry_revision:
		return

	_clear_compiled_segments()
	_binary_search_safe = point_list.size() >= 2
	for i in range(point_list.size() - 1):
		var a := point_list[i]
		var b := point_list[i + 1]
		if b.position.x - a.position.x <= SEGMENT_X_EPSILON:
			_binary_search_safe = false
			break

	if _binary_search_safe:
		for i in range(point_list.size() - 1):
			_append_segment(point_list[i], point_list[i + 1])

	_compiled_revision = _geometry_revision


func _clear_compiled_segments() -> void:
	_segment_x_bounds.clear()
	_segment_control_xs.clear()
	_segment_y_bounds.clear()
	_segment_control_ys.clear()
	_last_segment_index = -1


func _append_segment(a: EasingCurvePoint, b: EasingCurvePoint) -> void:
	_segment_x_bounds.append(Vector2(a.position.x, b.position.x))
	_segment_control_xs.append(BEZIER_SOLVER.get_effective_segment_control_xs(a, b))
	_segment_y_bounds.append(Vector2(a.position.y, b.position.y))
	_segment_control_ys.append(Vector2(
		a.right_control_point.y,
		b.left_control_point.y,
	))


func _find_segment_index(offset: float) -> int:
	var low := 0
	var high := _segment_x_bounds.size()
	while low < high:
		var middle := (low + high) / 2
		if offset <= _segment_x_bounds[middle].y:
			high = middle
		else:
			low = middle + 1

	if low >= _segment_x_bounds.size():
		return -1
	if offset < _segment_x_bounds[low].x:
		return -1
	return low


func _sample_segment(segment_index: int, offset: float) -> Vector2:
	var x_bounds := _segment_x_bounds[segment_index]
	var control_xs := _segment_control_xs[segment_index]
	var y_bounds := _segment_y_bounds[segment_index]
	var control_ys := _segment_control_ys[segment_index]
	var t := BEZIER_SOLVER.solve_monotonic_t(
		offset,
		x_bounds.x,
		control_xs.x,
		control_xs.y,
		x_bounds.y,
	)
	var value := BEZIER_SOLVER.bezier_interpolate(
		y_bounds.x,
		control_ys.x,
		control_ys.y,
		y_bounds.y,
		t,
	)
	return Vector2(t, value)

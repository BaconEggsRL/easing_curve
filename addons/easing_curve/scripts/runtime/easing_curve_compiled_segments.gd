@tool
extends RefCounted
## Builds immutable packed-array data for EasingCurve's hot sampling cache.
##
## Cache construction remains separate from EasingCurve mutation and sampling.
## EasingCurve owns the per-sample lookup state so sampling does not cross an
## object boundary on every call.

const BEZIER_SOLVER := preload(
	"res://addons/easing_curve/scripts/runtime/bezier_solver.gd"
)
const SEGMENT_X_EPSILON := 0.000001

const BINARY_SEARCH_SAFE := &"binary_search_safe"
const SEGMENT_X_BOUNDS := &"segment_x_bounds"
const SEGMENT_CONTROL_XS := &"segment_control_xs"
const SEGMENT_Y_BOUNDS := &"segment_y_bounds"
const SEGMENT_CONTROL_YS := &"segment_control_ys"


static func compile(point_list: Array[EasingCurvePoint]) -> Dictionary:
	var segment_x_bounds := PackedVector2Array()
	var segment_control_xs := PackedVector2Array()
	var segment_y_bounds := PackedVector2Array()
	var segment_control_ys := PackedVector2Array()
	var binary_search_safe := point_list.size() >= 2

	for i in range(point_list.size() - 1):
		var a := point_list[i]
		var b := point_list[i + 1]
		if b.position.x - a.position.x <= SEGMENT_X_EPSILON:
			binary_search_safe = false
			break

	if binary_search_safe:
		for i in range(point_list.size() - 1):
			var a := point_list[i]
			var b := point_list[i + 1]
			segment_x_bounds.append(Vector2(a.position.x, b.position.x))
			segment_control_xs.append(
				BEZIER_SOLVER.get_effective_segment_control_xs(a, b)
			)
			segment_y_bounds.append(Vector2(a.position.y, b.position.y))
			segment_control_ys.append(Vector2(
				a.right_control_point.y,
				b.left_control_point.y,
			))

	return {
		BINARY_SEARCH_SAFE: binary_search_safe,
		SEGMENT_X_BOUNDS: segment_x_bounds,
		SEGMENT_CONTROL_XS: segment_control_xs,
		SEGMENT_Y_BOUNDS: segment_y_bounds,
		SEGMENT_CONTROL_YS: segment_control_ys,
	}


func supports_binary_search(point_list: Array[EasingCurvePoint]) -> bool:
	return bool(compile(point_list)[BINARY_SEARCH_SAFE])

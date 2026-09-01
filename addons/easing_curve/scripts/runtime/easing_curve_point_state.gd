@tool
extends RefCounted
## Internal value carrier for EasingCurvePoint transition state.
##
## This type deliberately contains no transition, serialization, notification,
## or editor policy. It is passed through those separate layers as plain state.

var position := Vector2.ZERO
var left_control_point := Vector2.ZERO
var right_control_point := Vector2.ZERO
var handle_mode := 0
var locks: Dictionary[String, bool] = {
	"position": false,
	"left_control_point": false,
	"right_control_point": false,
}
var left_force_linear := false
var right_force_linear := false
var handle_display_scale := Vector2.ONE
var use_display_space_handles := true

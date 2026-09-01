@tool
extends RefCounted
## Per-resource transition state for edit sessions and change batching.
##
## This collaborator records transitions and returns publication decisions.
## EasingCurve owns every Resource mutation and notification emitted from them.

class PublicationDecision:
	var publish_curve_change := false
	var publish_parameter_change := false
	var point_data_changed := false
	var property_list_refresh_required := false


	func _init(
		should_publish_curve_change := false,
		should_publish_parameter_change := false,
		should_publish_point_data := false,
		should_publish_property_list := false,
	) -> void:
		publish_curve_change = should_publish_curve_change
		publish_parameter_change = should_publish_parameter_change
		point_data_changed = should_publish_point_data
		property_list_refresh_required = should_publish_property_list


var point_notification_suppression_depth := 0
var point_snapshot_change_pending := false
var point_snapshot_property_list_pending := false
var parameter_edit_depth := 0
var parameter_update_depth := 0
var parameter_update_change_pending := false
var applying_function_snapshot := false
var applying_editor_state_snapshot := false


func begin_point_notification_suppression() -> void:
	point_notification_suppression_depth += 1


func end_point_notification_suppression() -> void:
	point_notification_suppression_depth = maxi(
		point_notification_suppression_depth - 1,
		0,
	)


func is_point_notification_suppressed() -> bool:
	return point_notification_suppression_depth > 0


func record_point_snapshot(
	changing: bool,
	point_data_changed: bool,
	topology_changed: bool,
) -> PublicationDecision:
	if applying_editor_state_snapshot:
		_clear_point_snapshot_publication()
		return PublicationDecision.new()

	if changing:
		point_snapshot_change_pending = (
			point_snapshot_change_pending or point_data_changed
		)
		point_snapshot_property_list_pending = (
			point_snapshot_property_list_pending
			or point_data_changed
			or topology_changed
		)
		return PublicationDecision.new()

	var publish_points := point_data_changed or point_snapshot_change_pending
	# Custom Inspector point rows must refresh after completed point data even
	# when the point topology itself did not change.
	var publish_property_list := (
		publish_points
		or topology_changed
		or point_snapshot_property_list_pending
	)
	_clear_point_snapshot_publication()
	return PublicationDecision.new(
		publish_points,
		false,
		publish_points,
		publish_property_list,
	)


func begin_parameter_edit() -> void:
	parameter_edit_depth += 1


func cancel_parameter_edit() -> void:
	if parameter_edit_depth <= 0:
		return
	parameter_edit_depth -= 1
	if parameter_edit_depth == 0:
		_clear_point_snapshot_publication()


func finish_parameter_edit() -> PublicationDecision:
	if parameter_edit_depth <= 0:
		return PublicationDecision.new()
	parameter_edit_depth -= 1
	if parameter_edit_depth > 0:
		return PublicationDecision.new()
	if not point_snapshot_change_pending and not point_snapshot_property_list_pending:
		return PublicationDecision.new(false, true)

	var decision := PublicationDecision.new(
		true,
		false,
		point_snapshot_change_pending,
		point_snapshot_property_list_pending,
	)
	_clear_point_snapshot_publication()
	return decision


func is_parameter_edit_active() -> bool:
	return parameter_edit_depth > 0


func begin_parameter_update() -> void:
	parameter_update_depth += 1


func finish_parameter_update() -> bool:
	if parameter_update_depth <= 0:
		return false
	parameter_update_depth -= 1
	if parameter_update_depth > 0 or not parameter_update_change_pending:
		return false
	parameter_update_change_pending = false
	return request_parameter_publication()


func request_parameter_publication() -> bool:
	if applying_editor_state_snapshot:
		return false
	if parameter_update_depth > 0:
		parameter_update_change_pending = true
		return false
	return parameter_edit_depth == 0


func begin_function_snapshot() -> void:
	begin_parameter_edit()
	applying_function_snapshot = true


func finish_function_snapshot() -> void:
	applying_function_snapshot = false
	if parameter_edit_depth > 0:
		parameter_edit_depth -= 1


func is_applying_function_snapshot() -> bool:
	return applying_function_snapshot


func begin_editor_state_snapshot() -> void:
	applying_editor_state_snapshot = true


func finish_editor_state_snapshot() -> void:
	applying_editor_state_snapshot = false


func is_applying_editor_state_snapshot() -> bool:
	return applying_editor_state_snapshot


func _clear_point_snapshot_publication() -> void:
	point_snapshot_change_pending = false
	point_snapshot_property_list_pending = false

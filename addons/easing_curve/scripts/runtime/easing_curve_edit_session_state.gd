@tool
extends RefCounted
## Passive per-resource state for edit sessions and change batching.
##
## This holder contains state only. EasingCurve owns every transition decision,
## Resource mutation, and notification emitted around these values.

var point_notification_suppression_depth := 0
var point_snapshot_change_pending := false
var point_snapshot_property_list_pending := false
var parameter_edit_depth := 0
var parameter_update_depth := 0
var parameter_update_change_pending := false
var applying_function_snapshot := false
var applying_editor_state_snapshot := false

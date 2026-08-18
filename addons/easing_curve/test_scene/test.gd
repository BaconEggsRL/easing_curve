# @tool
extends Control
## Test Scene
##
## Test scene showcasing the EasingCurve plugin.
## Add a new EasingCurve resource to the exported properties and run the scene.
## Compare the interpolation of Godot's Tween system with the EasingCurve plugin.
## Curve point changes and exported Tween settings restart the comparison automatically.
## Curve edits preview live; confirmed changes restart using a fresh runtime copy.

const PLUGIN_CONFIG_PATH := "res://addons/easing_curve/plugin.cfg"

@export var tween_ease: Tween.EaseType = 0:
	set(value):
		if tween_ease == value:
			return
		tween_ease = value
		_restart_running_tweens()
@export var tween_trans: Tween.TransitionType = 0:
	set(value):
		if tween_trans == value:
			return
		tween_trans = value
		_restart_running_tweens()
@export_range(1, 2, 1) var easing_curve_to_use: int = 1
@export var easing_curve: EasingCurve:
	set = set_easing_curve
@export var easing_curve_2: EasingCurve:
	set = set_easing_curve_2
@export var test_curve: Curve

var points: Array[EasingCurvePoint] = []:
	set = set_points
var curve_tween: Tween
var tween_tween: Tween
var _runtime_easing_curve: EasingCurve
var _runtime_easing_curve_2: EasingCurve
var _debug_prev_curve_pos: Vector2
var _debug_prev_tween_pos: Vector2
var _debug_curve_speed: float = 0.0
var _debug_tween_speed: float = 0.0
var _debug_offset: float = 0.0
var _debug_curve_value: float = 0.0
var _debug_last_t: float = 0.0

# Nodes for Tween interpolation
@onready var tween_start_marker: Marker2D = %TweenStartMarker
@onready var tween_node: Node2D = %TweenNode
@onready var tween_end_marker: Marker2D = %TweenEndMarker

# Nodes for EasingCurve interpolation
@onready var curve_start_marker: Marker2D = %CurveStartMarker
@onready var curve_node: Node2D = %CurveNode
@onready var curve_end_marker: Marker2D = %CurveEndMarker

# Version info
@onready var version_label: Label = %VersionLabel


func _get_plugin_version() -> String:
	var config := ConfigFile.new()

	if config.load(PLUGIN_CONFIG_PATH) != OK:
		return ""

	return str(config.get_value("plugin", "version", ""))


func _ready() -> void:
	version_label.text = "Version: %s" % _get_plugin_version()
	if not Engine.is_editor_hint():
		reset_and_start()
	else:
		reset_positions()


func _restart_running_tweens() -> void:
	if is_node_ready() and not Engine.is_editor_hint():
		reset_and_start.call_deferred()


func _process(delta: float) -> void:
	# Curve-driven node speed
	if _debug_prev_curve_pos != Vector2.ZERO:
		var d = curve_node.global_position.distance_to(_debug_prev_curve_pos)
		_debug_curve_speed = d / delta

	# Built-in tween node speed
	if _debug_prev_tween_pos != Vector2.ZERO:
		var d2 = tween_node.global_position.distance_to(_debug_prev_tween_pos)
		_debug_tween_speed = d2 / delta

	_debug_prev_curve_pos = curve_node.global_position
	_debug_prev_tween_pos = tween_node.global_position

	queue_redraw()


func _draw() -> void:
	var font = ThemeDB.fallback_font
	var font_size = 14
	var y := 20

	draw_string(
		font,
		Vector2(10, y),
		"offset: %.4f" % _debug_offset,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
	)
	y += 18

	draw_string(
		font,
		Vector2(10, y),
		"t (Newton): %.4f" % _debug_last_t,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
	)
	y += 18

	draw_string(
		font,
		Vector2(10, y),
		"curve value (y): %.4f" % _debug_curve_value,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
	)
	y += 18

	draw_string(
		font,
		Vector2(10, y),
		"Curve speed: %.2f px/sec" % _debug_curve_speed,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
	)
	y += 18

	draw_string(
		font,
		Vector2(10, y),
		"Tween speed: %.2f px/sec" % _debug_tween_speed,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
	)


func kill_tweens() -> void:
	if curve_tween:
		curve_tween.kill()
	if tween_tween:
		tween_tween.kill()


func reset_positions() -> void:
	curve_node.global_position = curve_start_marker.global_position
	tween_node.global_position = tween_start_marker.global_position


func reset_and_start() -> void:
	if Engine.is_editor_hint():
		return

	kill_tweens()
	reset_positions()
	_capture_runtime_curves()

	start_tween(curve_tween, curve_end_marker, curve_node, true)
	start_tween(tween_tween, tween_end_marker, tween_node, false)

	## print("start")
	#if easing_curve:
	## print("start: ", easing_curve._irregular_points_y)
	## print("curve_mode = ", EasingCurve.CurveMode.keys()[easing_curve.curve_mode])
	## print("function_callable = ", easing_curve.function_callable)
	## print("trans_type = ", EasingCurve.TRANS.keys()[easing_curve.trans_type])
	## print("ease_type = ", EasingCurve.EASE.keys()[easing_curve.ease_type])
	#pass


func set_easing_curve(value: EasingCurve) -> void:
	if easing_curve == value:
		return
	if easing_curve != null and easing_curve.changed.is_connected(_on_easing_curve_changed):
		easing_curve.changed.disconnect(_on_easing_curve_changed)
	easing_curve = value
	if easing_curve != null and not easing_curve.changed.is_connected(_on_easing_curve_changed):
		easing_curve.changed.connect(_on_easing_curve_changed)
	reset_and_start.call_deferred()


func set_easing_curve_2(value: EasingCurve) -> void:
	if easing_curve_2 == value:
		return
	if easing_curve_2 != null and easing_curve_2.changed.is_connected(_on_easing_curve_2_changed):
		easing_curve_2.changed.disconnect(_on_easing_curve_2_changed)
	easing_curve_2 = value
	if easing_curve_2 != null and not easing_curve_2.changed.is_connected(_on_easing_curve_2_changed):
		easing_curve_2.changed.connect(_on_easing_curve_2_changed)
	reset_and_start.call_deferred()


func _capture_runtime_curves() -> void:
	_runtime_easing_curve = easing_curve.duplicate() as EasingCurve if easing_curve != null else null
	_runtime_easing_curve_2 = easing_curve_2.duplicate() as EasingCurve if easing_curve_2 != null else null


func set_points(value) -> void:
	if points == value:
		return
	points = value.duplicate(true)
	# print("test.gd set_points")
	# print("easing_curve RID: ", easing_curve.get_rid())
	# print_points()


func print_points() -> void:
	print("print_points points = ")
	if points.size() == 0:
		print("[]")
	else:
		for p in points:
			print(p.position)
	print("print_points easing_curve.points = ")
	if not easing_curve:
		print("[]")
	elif easing_curve.points.size() == 0:
		print("[]")
	else:
		for p in easing_curve.points:
			print(p.position)


func start_tween(tween_ref: Tween, end: Marker2D, node: Node2D, use_curve: bool) -> void:
	var runtime_curve := _runtime_easing_curve if easing_curve_to_use == 1 else _runtime_easing_curve_2
	if use_curve and runtime_curve == null:
		return

	var target := end.global_position
	var duration := 2.0

	# Kill existing tween
	if tween_ref:
		tween_ref.kill()

	# Create new tween
	var new_tween = create_tween()

	if use_curve:
		curve_tween = new_tween
	else:
		tween_tween = new_tween

	var position_tweener = new_tween.tween_property(node, "global_position", target, duration)

	if use_curve:
		position_tweener.set_custom_interpolator(tween_easing_curve.bind(runtime_curve))
	else:
		position_tweener.set_ease(tween_ease)
		position_tweener.set_trans(tween_trans)


func tween_easing_curve(offset: float, _curve: EasingCurve) -> float:
	_debug_offset = offset
	_debug_curve_value = _curve.sample(offset)
	_debug_last_t = _curve._last_t # store t from your sample()

	return _debug_curve_value


func tween_curve(_offset: float, _curve: Curve) -> float:
	# print("tween curve: ", _curve)
	# return _curve.sample_baked(_offset)
	return _curve.sample(_offset)


func _on_easing_curve_changed() -> void:
	reset_and_start.call_deferred()


func _on_easing_curve_2_changed() -> void:
	reset_and_start.call_deferred()


func _on_restart_pressed() -> void:
	reset_and_start()
	# get_tree().reload_current_scene()

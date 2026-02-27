# @tool
extends Control
## Test Scene
##
## Test scene showcasing the EasingCurve plugin.
## Add a new EasingCurve resource to the exported properties and run the scene.
## Compare the interpolation of Godot's Tween system with the EasingCurve plugin.
## Connect the curve's points_changed signal to _on_points_changed if you want to restart the scene automatically when the curve's preset is changed.
## Updating the curve at runtime does not yet work in all cases. Close the running scene and re-run it from the editor to see changes.

@export var tween_ease: Tween.EaseType = 0
@export var tween_trans: Tween.TransitionType = 0
@export_range(1, 2, 1) var easing_curve_to_use: int = 1
@export var easing_curve: EasingCurve:
	set = set_easing_curve
@export var easing_curve_2: EasingCurve

var points: Array[Point] = []:
	set = set_points
var curve_tween: Tween
var tween_tween: Tween
var _debug_prev_curve_pos: Vector2
var _debug_prev_tween_pos: Vector2
var _debug_curve_speed: float = 0.0
var _debug_tween_speed: float = 0.0
var _debug_offset: float = 0.0
var _debug_curve_value: float = 0.0
var _debug_last_t: float = 0.0

# @export var curve:Curve
@onready var tween_nodes_container: Node2D = $nodes/tween_nodes_container
@onready var tween_node: Sprite2D = tween_nodes_container.get_node("tween_node")
@onready var tween_start: Marker2D = tween_nodes_container.get_node("tween_start")
@onready var tween_end: Marker2D = tween_nodes_container.get_node("tween_end")
@onready var curve_nodes_container: Node2D = $nodes/curve_nodes_container
@onready var curve_node: Sprite2D = curve_nodes_container.get_node("curve_node")
@onready var curve_start: Marker2D = curve_nodes_container.get_node("curve_start")
@onready var curve_end: Marker2D = curve_nodes_container.get_node("curve_end")


func _ready() -> void:
	if not Engine.is_editor_hint():
		reset_and_start()
	else:
		reset_positions()


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
	curve_node.global_position = curve_start.global_position
	tween_node.global_position = tween_start.global_position


func reset_and_start() -> void:
	if Engine.is_editor_hint():
		return

	kill_tweens()
	reset_positions()

	start_tween(curve_tween, curve_end, curve_node, true)
	start_tween(tween_tween, tween_end, tween_node, false)

	## print("start")
	#if easing_curve:
	## print("start: ", easing_curve._irregular_points_y)
	## print("curve_mode = ", EasingCurve.CurveMode.keys()[easing_curve.curve_mode])
	## print("function_callable = ", easing_curve.function_callable)
	## print("trans_type = ", EasingCurve.TRANS.keys()[easing_curve.trans_type])
	## print("ease_type = ", EasingCurve.EASE.keys()[easing_curve.ease_type])
	#pass


func set_easing_curve(value) -> void:
	if easing_curve == value:
		return
	easing_curve = value
	if not easing_curve.points_changed.is_connected(_on_points_changed):
		easing_curve.points_changed.connect(_on_points_changed)
	reset_and_start.call_deferred()


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
	# 🚫 If this is the curve tween but we have no curve → do nothing
	if use_curve:
		if easing_curve == null:
			return

	var target := end.position
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

	var position_tweener = new_tween.tween_property(node, "position", target, duration)

	if use_curve:
		if easing_curve_to_use == 1:
			position_tweener.set_custom_interpolator(tween_easing_curve.bind(easing_curve))
		else:
			position_tweener.set_custom_interpolator(tween_easing_curve.bind(easing_curve_2))
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


func _on_points_changed(points: Array[Point]) -> void:
	# print("points changed; restarting tweens")
	reset_and_start.call_deferred()


func _on_restart_pressed() -> void:
	reset_and_start()
	# get_tree().reload_current_scene()

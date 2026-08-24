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
const MARKER_DOT_RADIUS := 8.0
const DROPDOWN_MAX_WIDTH := 120.0

@export var tween_ease: Tween.EaseType = 0:
	set(value):
		if tween_ease == value:
			return
		tween_ease = value
		#_sync_dropdowns()
		_restart_running_tweens()


@export var tween_trans: Tween.TransitionType = 0:
	set(value):
		if tween_trans == value:
			return
		tween_trans = value
		#_sync_dropdowns()
		_restart_running_tweens()

@export var easing_curve: EasingCurve = EasingCurve.new():
	set = set_easing_curve

@export var debug_curve: Curve = Curve.new()


var points: Array[EasingCurvePoint] = []:
	set = set_points
var curve_tween: Tween
var tween_tween: Tween
var _runtime_easing_curve: EasingCurve
var _debug_prev_curve_pos: Vector2
var _debug_prev_tween_pos: Vector2
var _debug_curve_speed: float = 0.0
var _debug_tween_speed: float = 0.0
var _debug_offset: float = 0.0
var _debug_curve_value: float = 0.0
var _debug_last_t: float = 0.0

func _init() -> void:
	if easing_curve != null and not easing_curve.changed.is_connected(_on_easing_curve_changed):
		easing_curve.changed.connect(_on_easing_curve_changed)

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

# In-game options
@onready var tween_ease_dropdown: OptionButton = %TweenEaseDropdown
@onready var tween_trans_dropdown: OptionButton = %TweenTransDropdown
@onready var curve_ease_dropdown: OptionButton = %CurveEaseDropdown
@onready var curve_trans_dropdown: OptionButton = %CurveTransDropdown

# Restart and reverse
@onready var restart_button: Button = %RestartButton
@onready var reverse_check_button: CheckButton = %ReverseCheckButton
@onready var match_tween_check_button: CheckButton = %MatchTweenCheckButton


var marker_overlay: MarkerOverlay
var draw_markers_on_top := false

class MarkerOverlay:
	extends Node2D

	var positions: Array[Vector2] = []
	var colors: Array[Color] = []
	var radius := 8.0

	func _draw() -> void:
		for i in positions.size():
			draw_circle(positions[i], radius, colors[i])


func _update_marker_overlay() -> void:
	if not is_instance_valid(marker_overlay):
		return

	marker_overlay.positions = [
		marker_overlay.to_local(curve_start_marker.global_position),
		marker_overlay.to_local(curve_end_marker.global_position),
		marker_overlay.to_local(tween_start_marker.global_position),
		marker_overlay.to_local(tween_end_marker.global_position),
	]

	marker_overlay.colors = [
		Color.GREEN,
		Color.RED,
		Color.GREEN,
		Color.RED,
	]

	marker_overlay.queue_redraw()


func _configure_dropdown(dropdown: OptionButton) -> void:
	dropdown.fit_to_longest_item = false
	dropdown.clip_text = true
	dropdown.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dropdown.custom_minimum_size.x = DROPDOWN_MAX_WIDTH
	dropdown.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _ready() -> void:
	if draw_markers_on_top:
		marker_overlay = MarkerOverlay.new()
		marker_overlay.z_index = 100
		add_child(marker_overlay)

	_setup_dropdowns()

	reverse_check_button.toggled.connect(_on_reverse_toggled)
	match_tween_check_button.toggled.connect(_on_match_tween_toggled)

	version_label.text = "Version: %s" % _get_plugin_version()
	if not Engine.is_editor_hint():
		reset_and_start()
	else:
		reset_positions()


func _get_plugin_version() -> String:
	var config := ConfigFile.new()

	if config.load(PLUGIN_CONFIG_PATH) != OK:
		return ""

	return str(config.get_value("plugin", "version", ""))


func _sync_dropdowns() -> void:
	if not is_node_ready():
		return

	# EasingCurve
	if easing_curve:
		curve_trans_dropdown.select(easing_curve.trans_type)
		curve_ease_dropdown.select(easing_curve.ease_type)

	# Tween
	for i in tween_trans_dropdown.item_count:
		if tween_trans_dropdown.get_item_metadata(i) == tween_trans:
			tween_trans_dropdown.select(i)
			break

	for i in tween_ease_dropdown.item_count:
		if tween_ease_dropdown.get_item_metadata(i) == tween_ease:
			tween_ease_dropdown.select(i)
			break


func _setup_dropdowns() -> void:
	_configure_dropdown(tween_ease_dropdown)
	_configure_dropdown(tween_trans_dropdown)
	_configure_dropdown(curve_ease_dropdown)
	_configure_dropdown(curve_trans_dropdown)

	# EasingCurve
	for trans_name in EasingCurve.TRANS.keys():
		curve_trans_dropdown.add_item(trans_name.capitalize())

	for ease_name in EasingCurve.EASE.keys():
		curve_ease_dropdown.add_item(ease_name.capitalize())

	if easing_curve:
		curve_trans_dropdown.select(easing_curve.trans_type)
		curve_ease_dropdown.select(easing_curve.ease_type)

	# Built-in Tween
	var tween_transitions := [
		["Linear", Tween.TRANS_LINEAR],
		["Sine", Tween.TRANS_SINE],
		["Quint", Tween.TRANS_QUINT],
		["Quart", Tween.TRANS_QUART],
		["Quad", Tween.TRANS_QUAD],
		["Expo", Tween.TRANS_EXPO],
		["Elastic", Tween.TRANS_ELASTIC],
		["Cubic", Tween.TRANS_CUBIC],
		["Circ", Tween.TRANS_CIRC],
		["Bounce", Tween.TRANS_BOUNCE],
		["Back", Tween.TRANS_BACK],
		["Spring", Tween.TRANS_SPRING],
	]

	for item in tween_transitions:
		tween_trans_dropdown.add_item(item[0])
		tween_trans_dropdown.set_item_metadata(
			tween_trans_dropdown.item_count - 1,
			item[1]
		)

	var tween_eases := [
		["In", Tween.EASE_IN],
		["Out", Tween.EASE_OUT],
		["In Out", Tween.EASE_IN_OUT],
		["Out In", Tween.EASE_OUT_IN],
	]

	for item in tween_eases:
		tween_ease_dropdown.add_item(item[0])
		tween_ease_dropdown.set_item_metadata(
			tween_ease_dropdown.item_count - 1,
			item[1]
		)

	# Select current values.
	for i in tween_trans_dropdown.item_count:
		if tween_trans_dropdown.get_item_metadata(i) == tween_trans:
			tween_trans_dropdown.select(i)
			break

	for i in tween_ease_dropdown.item_count:
		if tween_ease_dropdown.get_item_metadata(i) == tween_ease:
			tween_ease_dropdown.select(i)
			break

	curve_trans_dropdown.item_selected.connect(_on_curve_trans_selected)
	curve_ease_dropdown.item_selected.connect(_on_curve_ease_selected)
	tween_trans_dropdown.item_selected.connect(_on_tween_trans_selected)
	tween_ease_dropdown.item_selected.connect(_on_tween_ease_selected)

	_sync_dropdowns()


func _on_curve_ease_selected(index: int) -> void:
	if not _runtime_easing_curve:
		return
	_runtime_easing_curve.ease_type = index
	restart_runtime()


func _on_curve_trans_selected(index: int) -> void:
	if not _runtime_easing_curve:
		return
	_runtime_easing_curve.trans_type = index
	restart_runtime()


func _on_tween_trans_selected(index: int) -> void:
	tween_trans = tween_trans_dropdown.get_item_metadata(index)
	if match_tween_check_button.button_pressed:
		_match_curve_to_tween()


func _on_tween_ease_selected(index: int) -> void:
	tween_ease = tween_ease_dropdown.get_item_metadata(index)
	if match_tween_check_button.button_pressed:
		_match_curve_to_tween()


func _restart_running_tweens() -> void:
	if is_node_ready() and not Engine.is_editor_hint():
		restart_runtime()


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

	if draw_markers_on_top:
		_update_marker_overlay()

	queue_redraw()


func _global_to_local(global_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * global_pos


func _draw() -> void:
	# Start/end markers
	draw_circle(
		_global_to_local(curve_start_marker.global_position),
		MARKER_DOT_RADIUS,
		Color.GREEN,
	)
	draw_circle(
		_global_to_local(curve_end_marker.global_position),
		MARKER_DOT_RADIUS,
		Color.RED,
	)

	# Tween start/end markers
	draw_circle(
		_global_to_local(tween_start_marker.global_position),
		MARKER_DOT_RADIUS,
		Color.GREEN,
	)
	draw_circle(
		_global_to_local(tween_end_marker.global_position),
		MARKER_DOT_RADIUS,
		Color.RED,
	)

	# Debug text
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
	if reverse_check_button and reverse_check_button.button_pressed:
		curve_node.global_position = curve_end_marker.global_position
		tween_node.global_position = tween_end_marker.global_position
	else:
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


func restart_runtime() -> void:
	if Engine.is_editor_hint():
		return

	kill_tweens()
	reset_positions()

	start_tween(curve_tween, curve_end_marker, curve_node, true)
	start_tween(tween_tween, tween_end_marker, tween_node, false)


func set_easing_curve(value: EasingCurve) -> void:
	if easing_curve == value:
		return
	if easing_curve != null and easing_curve.changed.is_connected(_on_easing_curve_changed):
		easing_curve.changed.disconnect(_on_easing_curve_changed)
	easing_curve = value
	if easing_curve != null and not easing_curve.changed.is_connected(_on_easing_curve_changed):
		easing_curve.changed.connect(_on_easing_curve_changed)
	_sync_dropdowns()
	reset_and_start.call_deferred()


func _capture_runtime_curves() -> void:
	_runtime_easing_curve = easing_curve.duplicate() as EasingCurve if easing_curve != null else null


func set_points(value) -> void:
	if points == value:
		return
	points = value.duplicate(true)


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
	var runtime_curve := _runtime_easing_curve
	if use_curve and runtime_curve == null:
		return

	var target := end.global_position
	if reverse_check_button and reverse_check_button.button_pressed:
		target = (
			curve_start_marker.global_position
			if use_curve
			else tween_start_marker.global_position
		)

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
	_debug_last_t = _curve.get_last_solved_t()

	return _debug_curve_value


func tween_curve(_offset: float, _curve: Curve) -> float:
	return _curve.sample(_offset)


func _on_easing_curve_changed() -> void:
	_sync_dropdowns()
	reset_and_start.call_deferred()


func _on_restart_pressed() -> void:
	restart_runtime()


func _on_reverse_toggled(_enabled: bool) -> void:
	restart_runtime()


func _on_match_tween_toggled(enabled: bool) -> void:
	curve_trans_dropdown.disabled = enabled
	curve_ease_dropdown.disabled = enabled

	if enabled:
		_match_curve_to_tween()

	restart_runtime()


func _match_curve_to_tween() -> void:
	if not _runtime_easing_curve:
		return

	_runtime_easing_curve.trans_type = _get_matching_curve_trans()
	_runtime_easing_curve.ease_type = _get_matching_curve_ease()

	curve_trans_dropdown.select(_runtime_easing_curve.trans_type)
	curve_ease_dropdown.select(_runtime_easing_curve.ease_type)


func _get_matching_curve_trans() -> int:
	match tween_trans:
		Tween.TRANS_LINEAR:
			return EasingCurve.TRANS.LINEAR
		Tween.TRANS_SINE:
			return EasingCurve.TRANS.SINE
		Tween.TRANS_QUINT:
			return EasingCurve.TRANS.QUINT
		Tween.TRANS_QUART:
			return EasingCurve.TRANS.QUART
		Tween.TRANS_QUAD:
			return EasingCurve.TRANS.QUAD
		Tween.TRANS_EXPO:
			return EasingCurve.TRANS.EXPO
		Tween.TRANS_ELASTIC:
			return EasingCurve.TRANS.ELASTIC
		Tween.TRANS_CUBIC:
			return EasingCurve.TRANS.CUBIC
		Tween.TRANS_CIRC:
			return EasingCurve.TRANS.CIRC
		Tween.TRANS_BOUNCE:
			return EasingCurve.TRANS.BOUNCE
		Tween.TRANS_BACK:
			return EasingCurve.TRANS.BACK
		Tween.TRANS_SPRING:
			return EasingCurve.TRANS.SPRING

	return EasingCurve.TRANS.LINEAR


func _get_matching_curve_ease() -> int:
	match tween_ease:
		Tween.EASE_IN:
			return EasingCurve.EASE.IN
		Tween.EASE_OUT:
			return EasingCurve.EASE.OUT
		Tween.EASE_IN_OUT:
			return EasingCurve.EASE.IN_OUT
		Tween.EASE_OUT_IN:
			return EasingCurve.EASE.OUT_IN

	return EasingCurve.EASE.IN

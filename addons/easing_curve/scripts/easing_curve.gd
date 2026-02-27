@tool
@icon("uid://cgoejfwhdwmop")
class_name EasingCurve
extends Resource
## Easing Curve
##
## Main script for the EasingCurve resource.
## More info here to come.

signal points_changed
signal range_changed

enum CurveMode {
	BEZIER,
	FUNCTION,
}
enum EASE { IN, OUT, IN_OUT, OUT_IN }
enum TRANS {
	CUSTOM,
	CONSTANT,
	LINEAR,
	JITTER,
	IRREGULAR,
	STEP,
	POWER,
	QUAD,
	CUBIC,
	QUART,
	QUINT,
	EXPO,
	CIRC,
	BACK,
	ELASTIC,
	BOUNCE,
	SPRING,
	SINE,
}

const ZOOM_MIN := 0.1
const ZOOM_MAX := 10.0
const ZOOM_FACTOR := 1.2 # same as wheel multiplier
const ZOOM_STEPS := int(round(log(ZOOM_MAX / ZOOM_MIN) / log(ZOOM_FACTOR)))
const DEFAULT_SLIDER_VALUE := floor(ZOOM_STEPS / 2.0)
const min_value := 0.0
const max_value := 1.0

## Store reference to Editor Undo Redo Manager
var editor_undo_redo: EditorUndoRedoManager
## Zoom slider variables
var _last_slider_value: float = DEFAULT_SLIDER_VALUE
var _last_zoom := Vector2(1, 1)
var _last_pan := Vector2.ZERO
var _last_t := 0.0

######################################################
# EXPORTED OPTIONS
######################################################
## Option button to select Ease type
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var ease_type: EASE = EASE.IN:
	set(value):
		ease_type = value
		# print("set ease_type = ", EASE.keys()[ease_type])
		if Engine.is_editor_hint():
			_update_preset()
## Option button to select Trans type
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var trans_type: TRANS = TRANS.LINEAR:
	set(value):
		trans_type = value
		# print("set trans_type = ", TRANS.keys()[trans_type])
		if Engine.is_editor_hint():
			_update_preset()

## Store the curve mode (CurveMode.BEZIER or CurveMode.FUNCTION)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var curve_mode: CurveMode:
	set(value):
		curve_mode = value
		# print("curve_mode = ", CurveMode.keys()[curve_mode])
## Store the callable used in curve_mode == CurveMode.FUNCTION
## Has to be re-initiliazed when the resource is loaded
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var function_callable: Callable:
	set(value):
		function_callable = value
		# print("function_callable = ", function_callable)

######################################################
# CURVE EDITOR
######################################################
## Placeholder for the curve editor (replaced by the editor plugin script.)
@export var easing_curve_editor: bool
## Points list
@export var points: Array[Point] = []:
	set(value):
		points = value
		emit_changed()

######################################################
# FUNCTION PARAMETERS
######################################################
## Parameters for specific CurveMode.FUNCTION
####################
# IRREGULAR
####################
## Represents the number of random points to generate. Must be a positive integer >= 2.
## Irregular mode converges to a linear equation for num_points == 2, no matter how high the randomness is.
@export_range(2, 100, 1) var num_points: int = 3:
	set(value):
		if num_points == value:
			return
		num_points = value
		_generate_irregular()
		emit_changed()
## Controls the amplitude of random variations.
## Higher values create more dramatic jumps between steps (default: 1).
@export_range(0.0, 4.0, 0.1) var randomness: float = 3.5:
	set(value):
		if randomness == value:
			return
		randomness = value
		_generate_irregular()
		emit_changed()
## Used to regenerate the random points
@export_tool_button("Generate", "Callable")
var generate_tool_button = generate_irregular

## X positions of irregular points
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var _irregular_points_x: Array[float] = []:
	set(value):
		if _irregular_points_x == value:
			return
		_irregular_points_x = value
		emit_changed()
		# print(_irregular_points_x)

## Y positions of irregular points
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var _irregular_points_y: Array[float] = []:
	set(value):
		if _irregular_points_y == value:
			return
		_irregular_points_y = value
		emit_changed()
		# print("_irregular_points_y: ", _irregular_points_y)

####################
# STEP
####################
## Represents the number of equal steps to divide the animation into.
## Must be a positive integer.
@export_range(0, 100, 1) var steps: int = 4:
	set(value):
		if steps == value:
			return
		steps = value
		emit_changed()
## When true, the change happens at the start of each step.
## When false, the change happens at the end of each step.
@export var from_start: bool = false:
	set(value):
		if from_start == value:
			return
		from_start = value
		emit_changed()
## Adds a constant y_offset. The step function is clamped to a range of [0,1].
## When the number of steps is zero, this converges to the constant function (y = y_offset).
@export_range(0, 1, 0.001) var y_offset: float = 0.0:
	set(value):
		if y_offset == value:
			return
		y_offset = value
		emit_changed()

####################
# POWER
####################
@export_range(0.001, 1000.0, 0.001, "exp") var power: float = 2.0:
	set(value):
		if power == value:
			return
		power = value
		emit_changed()

####################
# ELASTIC
####################
@export_range(0.0, 5.0, 0.01) var amplitude: float = 1.0:
	set(value):
		if amplitude == value:
			return
		amplitude = value
		emit_changed()
@export_range(0.01, 1.0, 0.01) var period: float = 0.3:
	set(value):
		if period == value:
			return
		period = value
		emit_changed()

######################################################
# INIT
######################################################
# --- Constructor ---
#func _init():
#pass
func _init():
	if Engine.is_editor_hint():
		if points.size() == 0:
			_update_preset()
	# debug
	else:
		#print("init")
		#print("curve_mode = ", CurveMode.keys()[curve_mode])
		#print("trans_type = ", TRANS.keys()[trans_type])
		#print("ease_type = ", EASE.keys()[ease_type])
		pass
	# print("init: ", _irregular_points_x, _irregular_points_y)


func _validate_property(property: Dictionary):
	if property.name in ["num_points", "randomness", "generate_tool_button"]:
		if trans_type in [TRANS.JITTER, TRANS.IRREGULAR]:
			# enable property
			property.usage |= PROPERTY_USAGE_EDITOR
		else:
			# disable property
			property.usage &= ~PROPERTY_USAGE_EDITOR
		return

	if property.name in ["steps", "from_start", "y_offset"]:
		if trans_type == TRANS.STEP:
			# enable property
			property.usage |= PROPERTY_USAGE_EDITOR
		else:
			# disable property
			property.usage &= ~PROPERTY_USAGE_EDITOR
		return

	if property.name in ["power"]:
		if trans_type == TRANS.POWER:
			# enable property
			property.usage |= PROPERTY_USAGE_EDITOR
		else:
			# disable property
			property.usage &= ~PROPERTY_USAGE_EDITOR
		return

	if property.name in ["amplitude", "period"]:
		if trans_type == TRANS.ELASTIC:
			# enable property
			property.usage |= PROPERTY_USAGE_EDITOR
		else:
			# disable property
			property.usage &= ~PROPERTY_USAGE_EDITOR
		return


func generate_irregular() -> void:
	_generate_irregular()


func get_default_for_property(i: int, property_name: String) -> Vector2:
	var temp := EasingCurve.new()
	temp.set_ease(ease_type)
	temp.set_trans(trans_type)
	temp._update_preset()
	return temp.points[i].get(property_name)


func cubic_bezier(x0, y0, x1, y1) -> void:
	var p0 := Point.new(Vector2(0, 0))
	var p1 := Point.new(Vector2(1, 1))
	p0.right_control_point = Vector2(x0, y0)
	p1.left_control_point = Vector2(x1, y1)
	add_point(p0)
	add_point(p1)


func set_ease(_ease: EASE) -> void:
	ease_type = _ease
	_update_preset()


func set_trans(_trans: TRANS) -> void:
	trans_type = _trans
	_update_preset()


#func set_curve_elastic() -> void:
	#add_point(Point.new(Vector2(0, 0)))
#
	#add_point(Point.new(Vector2(.04, -0.0004)))
#
	#add_point(Point.new(Vector2(.08, -0.0016)))
#
	#add_point(Point.new(Vector2(.14, -0.0017)))
#
	#add_point(Point.new(Vector2(.18, 0.0004)))
#
	#add_point(Point.new(Vector2(.26, 0.0058)))
#
	#add_point(Point.new(Vector2(.28, 0.0055)))
#
	#add_point(Point.new(Vector2(.40, -0.0156)))
#
	#add_point(Point.new(Vector2(.42, -0.0164)))
#
	#add_point(Point.new(Vector2(.56, 0.0463)))
#
	#add_point(Point.new(Vector2(.58, -0.044)))
	#add_point(Point.new(Vector2(.72, .1312)))
	#add_point(Point.new(Vector2(.86, -0.3706)))
	#add_point(Point.new(Vector2(1, 1)))
#
	#auto_smooth_handles()


func printpoints():
	for i in range(points.size()):
		var p = points[i]
		print(i, ": ", p.position, " L:", p.left_control_point, " R:", p.right_control_point)


func sort_points() -> void:
	points.sort_custom(func(a, b): return a.position.x < b.position.x)
	force_update()


func swap_properties(p0: Point, p1: Point) -> void:
	var temp_position_x = p0.position.x
	p0.position.x = p1.position.x
	p1.position.x = temp_position_x

	var temp_lcp_x = p0.left_control_point.x
	p0.left_control_point.x = p1.left_control_point.x
	p1.left_control_point.x = temp_lcp_x

	var temp_rcp_x = p0.right_control_point.x
	p0.right_control_point.x = p1.right_control_point.x
	p1.right_control_point.x = temp_rcp_x


# Swap two points, either by Point references or by indices
func swap_points(a, b) -> void:
	if a is int and b is int:
		var i = a
		var j = b
		swap_points(points[i], points[j])

	elif a is Point and b is Point:
		# var p0 = a
		# var p1 = b
		#var temp_x = p0.position.x
		#p0.position.x = p1.position.x
		#p1.position.x = temp_x
		swap_properties(a, b)
		sort_points()

	else:
		push_warning("Could not swap due to type mismatch")


func add_point_with_undo(p: Point) -> void:
	if not editor_undo_redo:
		return
	editor_undo_redo.create_action("Add Point")
	editor_undo_redo.add_do_method(self, "add_point", p)
	editor_undo_redo.add_undo_method(self, "remove_point", p)
	editor_undo_redo.commit_action()


func add_point(p: Point) -> void:
	# print("adding point")
	points.append(p)
	if not p.changed.is_connected(_on_point_changed):
		p.changed.connect(_on_point_changed)

	sort_points()

	# debug print
	# print("easing_curve add_point")
	#if Engine.is_editor_hint():
	#for _p in points:
	#print(_p.position)

	points_changed.emit(points)


func remove_point_with_undo(p: Point) -> void:
	if not editor_undo_redo:
		return
	editor_undo_redo.create_action("Remove point")
	editor_undo_redo.add_do_method(self, "remove_point", p)
	editor_undo_redo.add_undo_method(self, "add_point", p)
	editor_undo_redo.commit_action()


func remove_point(p: Point) -> void:
	# print("removing point")
	if p not in points:
		return

	points.erase(p)
	if p.changed.is_connected(_on_point_changed):
		p.changed.disconnect(_on_point_changed)

	force_update()

	# debug print
	# print("easing_curve remove_point")
	#if Engine.is_editor_hint():
	#for _p in points:
	#print(_p.position)

	points_changed.emit(points)


func set_point(i, p) -> void:
	points[i] = p
	# emit_changed()
	# force_update()


func force_update() -> void:
	# Force inspector update
	points = points.duplicate(true)
	notify_changed()


func notify_changed() -> void:
	emit_changed()
	notify_property_list_changed()


## Generic callable for non-function CurveMode
func do_nothing() -> void:
	pass


func clear_function() -> void:
	if trans_type == TRANS.CUSTOM:
		return
	# print("clear function")
	curve_mode = CurveMode.BEZIER
	points.clear()
	# function_callable = do_nothing
	# points.clear()
	# notify_changed()


func set_function(func_ref: Callable):
	# print("set function")
	curve_mode = CurveMode.FUNCTION
	function_callable = func_ref
	points.clear()
	notify_changed()
	# Emit points_changed so tweens can restart
	points_changed.emit(points)


## Sample the curve, calculating f(t) given x
func sample(offset: float) -> float:
	# print("sample curve_mode = ", CurveMode.keys()[curve_mode])
	offset = clamp(offset, 0.0, 1.0)

	if curve_mode == CurveMode.FUNCTION:
		# print("func")
		if not function_callable.is_valid():
			_init_function()

		if trans_type == TRANS.IRREGULAR:
			return function_callable.call(offset, 0.0, 1.0, 1.0, _irregular_points_x, _irregular_points_y)
		if trans_type == TRANS.JITTER:
			return function_callable.call(offset, 0.0, 1.0, 1.0, num_points, randomness)
		elif trans_type == TRANS.STEP:
			return function_callable.call(offset, 0.0, 1.0, 1.0, steps, from_start, y_offset)
		elif trans_type == TRANS.ELASTIC:
			return function_callable.call(offset, 0.0, 1.0, 1.0, amplitude, period)
		elif trans_type == TRANS.POWER:
			return function_callable.call(offset, 0.0, 1.0, 1.0, power)
		else:
			return function_callable.call(offset, 0.0, 1.0, 1.0)

		return 0.0

	else:
		# print("curve")
		pass

	# existing bezier sampling logic below

	if points.size() < 2:
		return 0.0

	for i in range(points.size() - 1):
		var a = points[i]
		var b = points[i + 1]

		# Quick rejection: skip segment if offset not in its X bounds
		var min_x = min(a.position.x, b.position.x)
		var max_x = max(a.position.x, b.position.x)

		if offset < min_x or offset > max_x:
			continue

		var t = _solve_for_t(offset, a, b)

		# Validate solution
		if t >= 0.0 and t <= 1.0:
			return _bezier_interpolate(
				a.position.y,
				a.right_control_point.y,
				b.left_control_point.y,
				b.position.y,
				t,
			)

	# Fallback (should not happen if curve monotonic)
	return 0.0


##########################################################
# Catmull-Rom → Bézier conversion
func auto_smooth_handles():
	if points.size() < 2:
		return

	for i in range(points.size()):
		var p = points[i]

		var p_prev = points[max(i - 1, 0)]
		var p_next = points[min(i + 1, points.size() - 1)]

		var prev = p_prev.position.y
		var curr = p.position.y
		var next = p_next.position.y

		var is_peak = (curr > prev and curr > next)
		var is_valley = (curr < prev and curr < next)

		#var tangent = (p_next.position - p_prev.position) * 0.5
		var d1 = p.position - p_prev.position
		var d2 = p_next.position - p.position

		var len1 = d1.length()
		var len2 = d2.length()

		if len1 == 0 or len2 == 0:
			continue

		var tangent = (d1.normalized() + d2.normalized())
		tangent *= min(len1, len2)

		var handle_length = 1.0 / 3.0
		#if is_peak or is_valley:
		#handle_length *= 0.6

		p.right_control_point = p.position + tangent * handle_length
		p.left_control_point = p.position - tangent * handle_length

		p.right_control_point.x = clamp(
			p.right_control_point.x,
			p.position.x,
			points[min(i + 1, points.size() - 1)].position.x,
		)

		p.left_control_point.x = clamp(
			p.left_control_point.x,
			points[max(i - 1, 0)].position.x,
			p.position.x,
		)

	# Clamp endpoints
	points[0].left_control_point = points[0].position
	points[-1].right_control_point = points[-1].position


func generate_from_function(func_ref: Callable, resolution := 40):
	points.clear()

	for i in range(resolution + 1):
		var x = float(i) / resolution
		var y = func_ref.call(x)
		add_point(Point.new(Vector2(x, y)))


func derivative(func_ref: Callable, x: float, eps := 0.0001) -> float:
	return (func_ref.call(x + eps) - func_ref.call(x - eps)) / (2.0 * eps)


func _on_curve_editor_slider_value_changed(slider_value: float) -> void:
	_last_slider_value = slider_value
	# print("_curve._last_slider_value = ", slider_value)


func _on_curve_editor_zoom_changed(zoom: Vector2) -> void:
	_last_zoom = zoom


func _on_curve_editor_pan_changed(pan: Vector2) -> void:
	_last_pan = pan


func _generate_irregular() -> Dictionary:
	var result := { "x": [], "y": [] }
	var points_x: Array[float] = []
	var points_y: Array[float] = []

	if num_points <= 2:
		points_x = [0.0, 1.0]
		points_y = [0.0, 1.0]
		return result

	var randomness = clamp(randomness, 0.0, 4.0)

	for i in range(num_points):
		var x = float(i) / float(num_points - 1)
		points_x.append(x)

		if i == 0:
			points_y.append(0.0)
		elif i == num_points - 1:
			points_y.append(1.0)
		else:
			var linear_y = x
			var max_offset = min(linear_y, 1.0 - linear_y)
			var r = randf() * 2.0 - 1.0
			var offset = r * max_offset * (randomness / 4.0)
			points_y.append(clamp(linear_y + offset, 0.0, 1.0))

	result.x = points_x
	result.y = points_y

	_irregular_points_x = points_x
	_irregular_points_y = points_y

	return result


func _init_function() -> void:
	match trans_type:
		TRANS.JITTER:
			match ease_type:
				EASE.IN:
					set_function(Easing.Jitter.easeIn)
				EASE.OUT:
					set_function(Easing.Jitter.easeOut)
				EASE.IN_OUT:
					set_function(Easing.Jitter.easeInOut)
				EASE.OUT_IN:
					set_function(Easing.Jitter.easeOutIn)
		TRANS.IRREGULAR:
			match ease_type:
				EASE.IN:
					set_function(Easing.Irregular.easeIn)
				EASE.OUT:
					set_function(Easing.Irregular.easeOut)
				EASE.IN_OUT:
					set_function(Easing.Irregular.easeInOut)
				EASE.OUT_IN:
					set_function(Easing.Irregular.easeOutIn)
		TRANS.STEP:
			match ease_type:
				EASE.IN:
					set_function(Easing.Step.easeIn)
				EASE.OUT:
					set_function(Easing.Step.easeOut)
				EASE.IN_OUT:
					set_function(Easing.Step.easeInOut)
				EASE.OUT_IN:
					set_function(Easing.Step.easeOutIn)
		TRANS.POWER:
			match ease_type:
				EASE.IN:
					set_function(Easing.Power.easeIn)
				EASE.OUT:
					set_function(Easing.Power.easeOut)
				EASE.IN_OUT:
					set_function(Easing.Power.easeInOut)
				EASE.OUT_IN:
					set_function(Easing.Power.easeOutIn)
		TRANS.ELASTIC:
			match ease_type:
				EASE.IN:
					set_function(Easing.Elastic.easeInEx)
				EASE.OUT:
					set_function(Easing.Elastic.easeOutEx)
				EASE.IN_OUT:
					set_function(Easing.Elastic.easeInOutEx)
				EASE.OUT_IN:
					set_function(Easing.Elastic.easeOutInEx)
		TRANS.BOUNCE:
			match ease_type:
				EASE.IN:
					set_function(Easing.Bounce.easeIn)
				EASE.OUT:
					set_function(Easing.Bounce.easeOut)
				EASE.IN_OUT:
					set_function(Easing.Bounce.easeInOut)
				EASE.OUT_IN:
					set_function(Easing.Bounce.easeOutIn)
		TRANS.SPRING:
			match ease_type:
				EASE.IN:
					set_function(Easing.Spring.easeIn)
				EASE.OUT:
					set_function(Easing.Spring.easeOut)
				EASE.IN_OUT:
					set_function(Easing.Spring.easeInOut)
				EASE.OUT_IN:
					set_function(Easing.Spring.easeOutIn)


func _update_preset() -> void:
	clear_function()
	# print("trans = ", TRANS.keys()[trans_type])
	# print("ease = ", EASE.keys()[ease_type])

	match trans_type:
		TRANS.CUSTOM:
			return
		TRANS.CONSTANT:
			add_point(Point.new(Vector2(0, .5)))
			add_point(Point.new(Vector2(1, .5)))
		TRANS.LINEAR:
			add_point(Point.new(Vector2(0, 0)))
			add_point(Point.new(Vector2(1, 1)))
		TRANS.QUAD:
			match ease_type:
				EASE.IN:
					cubic_bezier(.11, 0, .5, 0)
				EASE.OUT:
					cubic_bezier(.5, 1, .89, 1)
				EASE.IN_OUT:
					cubic_bezier(.45, 0, .55, 1)
				EASE.OUT_IN:
					cubic_bezier(.55, 1, .45, 0)
		TRANS.CUBIC:
			match ease_type:
				EASE.IN:
					cubic_bezier(.32, 0, .67, 0)
				EASE.OUT:
					cubic_bezier(.33, 1, .68, 1)
				EASE.IN_OUT:
					cubic_bezier(.65, 0, .35, 1)
				EASE.OUT_IN:
					cubic_bezier(.35, 1, .65, 0)
		TRANS.QUART:
			match ease_type:
				EASE.IN:
					cubic_bezier(.5, 0, .75, 0)
				EASE.OUT:
					cubic_bezier(.25, 1, .5, 1)
				EASE.IN_OUT:
					cubic_bezier(.76, 0, .24, 1)
				EASE.OUT_IN:
					cubic_bezier(.24, 1, .76, 0)
		TRANS.QUINT:
			match ease_type:
				EASE.IN:
					cubic_bezier(.64, 0, .78, 0)
				EASE.OUT:
					cubic_bezier(.22, 1, .36, 1)
				EASE.IN_OUT:
					cubic_bezier(.83, 0, .17, 1)
				EASE.OUT_IN:
					cubic_bezier(.17, 1, .83, 0)
		TRANS.EXPO:
			match ease_type:
				EASE.IN:
					cubic_bezier(.7, 0, .84, 0)
				EASE.OUT:
					cubic_bezier(.16, 1, .3, 1)
				EASE.IN_OUT:
					cubic_bezier(.87, 0, .13, 1)
				EASE.OUT_IN:
					cubic_bezier(.13, 1, .87, 0)
		TRANS.CIRC:
			match ease_type:
				EASE.IN:
					cubic_bezier(.55, 0, 1, .45)
				EASE.OUT:
					cubic_bezier(0, .55, .45, 1)
				EASE.IN_OUT:
					cubic_bezier(.85, 0, .15, 1)
				EASE.OUT_IN:
					cubic_bezier(.15, 1, .85, 0)
		TRANS.BACK:
			match ease_type:
				EASE.IN:
					cubic_bezier(.36, 0, .66, -0.56)
				EASE.OUT:
					cubic_bezier(.34, 1.56, .64, 1)
				EASE.IN_OUT:
					cubic_bezier(.68, -0.6, .32, 1.6)
				EASE.OUT_IN:
					cubic_bezier(.32, 1.6, .68, -0.6)
		TRANS.JITTER:
			_init_function()
		TRANS.IRREGULAR:
			_init_function()
		TRANS.STEP:
			_init_function()
		TRANS.POWER:
			_init_function()
		TRANS.ELASTIC:
			_init_function()
		TRANS.BOUNCE:
			_init_function()
		TRANS.SPRING:
			_init_function()
		TRANS.SINE:
			match ease_type:
				EASE.IN:
					cubic_bezier(.12, 0, .39, 0)
				EASE.OUT:
					cubic_bezier(.61, 1, .88, 1)
				EASE.IN_OUT:
					cubic_bezier(.37, 0, .63, 1)
				EASE.OUT_IN:
					cubic_bezier(.63, 1, .37, 0)


func _on_point_changed() -> void:
	# print("point changed")
	# force_update()
	pass


# Newton-Raphson solver
func _solve_for_t(x: float, a: Point, b: Point) -> float:
	var t := x # good initial guess

	for i in 5: # usually converges in 3–4 iterations
		var x_est = _bezier_interpolate(
			a.position.x,
			a.right_control_point.x,
			b.left_control_point.x,
			b.position.x,
			t,
		)

		var dx = _bezier_derivative(
			a.position.x,
			a.right_control_point.x,
			b.left_control_point.x,
			b.position.x,
			t,
		)

		if abs(dx) < 0.000001:
			return _binary_search_t(x, a, b)

		t -= (x_est - x) / dx
		t = clamp(t, 0.0, 1.0)

	return t


func _binary_search_t(x: float, a: Point, b: Point) -> float:
	var low := 0.0
	var high := 1.0
	var mid := 0.5

	for i in range(12): # 10–15 iterations is plenty
		mid = (low + high) * 0.5

		var x_est = _bezier_interpolate(
			a.position.x,
			a.right_control_point.x,
			b.left_control_point.x,
			b.position.x,
			mid,
		)

		if x_est < x:
			low = mid
		else:
			high = mid

	return mid


func _bezier_derivative(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var omt = 1.0 - t
	return 3.0 * omt * omt * (p1 - p0) \
	+ 6.0 * omt * t * (p2 - p1) \
	+ 3.0 * t * t * (p3 - p2)


func _bezier_interpolate(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var omt = 1.0 - t
	return omt * omt * omt * p0 + 3 * omt * omt * t * p1 + 3 * omt * t * t * p2 + t * t * t * p3

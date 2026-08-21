@tool
@icon("res://addons/easing_curve/assets/icons/Curve.svg")
class_name EasingCurve
extends Resource
## Easing Curve
##
## Main script for the EasingCurve resource.
## More info here to come.

signal points_changed(points: Array[EasingCurvePoint])
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
	PHYSICS_SPRING,
	CSS_LINEAR,
	SINE,
	CSS_CUBIC_BEZIER,
}

# List of functions (non-bezier presets)
const FUNCTION_TRANSITIONS := [
	TRANS.JITTER,
	TRANS.IRREGULAR,
	TRANS.STEP,
	TRANS.POWER,
	TRANS.ELASTIC,
	TRANS.BOUNCE,
	TRANS.SPRING,
	TRANS.PHYSICS_SPRING,
	TRANS.CSS_LINEAR,
	TRANS.CSS_CUBIC_BEZIER,
]

# Normal function implementations.
const FUNCTION_CLASSES := {
	TRANS.STEP: {
		"class": EASING_LIBRARY.Step,
		"extended": false,
	},
	TRANS.POWER: {
		"class": EASING_LIBRARY.Power,
		"extended": false,
	},
	TRANS.ELASTIC: {
		"class": EASING_LIBRARY.Elastic,
		"extended": true,
	},
	TRANS.BOUNCE: {
		"class": EASING_LIBRARY.Bounce,
		"extended": true,
	},
	TRANS.SPRING: {
		"class": EASING_LIBRARY.Spring,
		"extended": true,
	},
	TRANS.PHYSICS_SPRING: {
		"class": EASING_LIBRARY.PhysicsSpring,
		"extended": true,
	},
	TRANS.CSS_LINEAR: {
		"class": EASING_LIBRARY.CSSLinear,
		"extended": true,
	},
	TRANS.CSS_CUBIC_BEZIER: {
		"class": EASING_LIBRARY.CSSCubicBezier,
		"extended": true,
	},
}


# Editable values passed to Bezier curve implementations.
# These are exported properties; see "BEZIER PARAMETERS" section below.
const BEZIER_PARAMETERS := {
	TRANS.CONSTANT: [
		&"constant_value",
	],
	TRANS.BACK: [
		&"overshoot",
	],
}


# Editable values passed to function implementations.
# These are exported properties; see "FUNCTION PARAMETERS" section below.
const FUNCTION_PARAMETERS := {
	TRANS.JITTER: [
		&"num_points",
		&"randomness",
	],
	TRANS.IRREGULAR: [
		&"num_points",
		&"randomness",
	],
	TRANS.STEP: [
		&"steps",
		&"from_start",
		&"y_offset",
	],
	TRANS.POWER: [
		&"power",
	],
	TRANS.ELASTIC: [
		&"amplitude",
		&"period",
	],
	TRANS.BOUNCE: [
		&"num_bounces",
		&"bounce_damping",
	],
	TRANS.SPRING: [
		&"frequency",
		&"decay",
	],
	TRANS.PHYSICS_SPRING: [
		&"stiffness",
		&"damping",
		&"mass",
		&"velocity",
	],
}

# Non-deferred parameters (no slider--bools for example.)
const NON_DEFERRED_FUNCTION_PARAMETERS := [
	&"from_start",
]

# Functions that use generated internal data instead of directly
# passing FUNCTION_PARAMETERS to their Callable.
const GENERATED_FUNCTION_TRANSITIONS := [
	TRANS.JITTER,
	TRANS.IRREGULAR,
]

# Extra inspector controls associated with the function
const FUNCTION_EDITOR_PROPERTIES := {
	TRANS.JITTER: [
		&"generate_tool_button",
	],
	TRANS.IRREGULAR: [
		&"generate_tool_button",
	],
	TRANS.CSS_LINEAR: [
		&"css_linear",
	],
	TRANS.CSS_CUBIC_BEZIER: [
		&"css_cubic_bezier",
	],
}

const ZOOM_MIN := 0.1
const ZOOM_MAX := 10.0
const ZOOM_FACTOR := 1.2 # same as wheel multiplier
const PRESET_GEOMETRY_TOLERANCE := 0.000001
const ZOOM_STEPS := int(round(log(ZOOM_MAX / ZOOM_MIN) / log(ZOOM_FACTOR)))
const DEFAULT_SLIDER_VALUE := floor(ZOOM_STEPS / 2.0)
const min_value := 0.0
const max_value := 1.0
const EASING_LIBRARY := preload("res://addons/easing_curve/scripts/easing.gd")
## Editor/live-debug bridge containing only primitive values, never point Resources.
const POINT_SNAPSHOT_PROPERTY := &"_point_snapshot"
const FUNCTION_SNAPSHOT_PROPERTY := &"_function_snapshot"
const EDITOR_STATE_SNAPSHOT_PROPERTY := &"_editor_state_snapshot"
const POINT_STORAGE_COUNT := &"_point_count"
const POINT_STORAGE_PREFIX := "_point_"
const POINT_PROPERTIES: Array[StringName] = [
	&"position",
	&"left_control_point",
	&"right_control_point",
	&"locked",
	&"handle_mode",
	&"left_force_linear",
	&"right_force_linear",
]

## Zoom slider variables
var _last_slider_value: float = DEFAULT_SLIDER_VALUE
var _last_zoom := Vector2(1, 1)
var _last_pan := Vector2.ZERO
var _last_t := 0.0
var _points: Array[EasingCurvePoint] = []
var _connected_points: Array[EasingCurvePoint] = []
var _point_topology: Array[EasingCurvePoint] = []
var _change_revision := 0
var _suppress_point_notifications := 0
var _point_snapshot_change_pending := false
var _point_snapshot_property_list_pending := false
var _parameter_edit_depth := 0
var _parameter_update_depth := 0
var _parameter_update_change_pending := false
var _applying_function_snapshot := false
var _applying_editor_state_snapshot := false

# ------------------
# EXPORTED OPTIONS
# ------------------
## Option button to select Ease type
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var ease_type: EASE = EASE.IN:
	set(value):
		if ease_type == value:
			return
		var revision_before := _change_revision
		ease_type = value
		if _applying_editor_state_snapshot:
			return
		if curve_mode == CurveMode.FUNCTION:
			_init_function()
		else:
			_update_preset()
		if _change_revision == revision_before:
			_notify_curve_changed(false, true)
## Option button to select Trans type
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var trans_type: TRANS = TRANS.LINEAR:
	set(value):
		if trans_type == value:
			return
		var revision_before := _change_revision
		trans_type = value
		if _applying_editor_state_snapshot:
			return
		_update_preset()
		if _change_revision == revision_before:
			_notify_curve_changed(false, true)

## Store the curve mode (CurveMode.BEZIER or CurveMode.FUNCTION)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var curve_mode: CurveMode:
	set(value):
		if curve_mode == value:
			return
		curve_mode = value
		if _applying_editor_state_snapshot:
			return
		emit_changed()
## Store the callable used in curve_mode == CurveMode.FUNCTION
## Has to be re-initiliazed when the resource is loaded
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var function_callable: Callable:
	set(value):
		if function_callable == value:
			return
		function_callable = value
		if _applying_editor_state_snapshot:
			return
		emit_changed()

# ------------------
# CURVE EDITOR
# ------------------
## Placeholder for the curve editor (replaced by the editor plugin script.)
@export var easing_curve_editor: bool


######################################################
# TRANSITION PARAMETERS
######################################################

@export_group("Transition Parameters")
# Transition parameters

######################################################
# BEZIER PARAMETERS
######################################################
## Parameters for specific CurveMode.BEZIER

# ------------------
# CONSTANT VALUE
# ------------------
## Controls the output value of the Constant preset.
@export_range(0.0, 1.0, 0.01) var constant_value: float = 0.5:
	set(value):
		if constant_value == value:
			return

		constant_value = value

		if _applying_editor_state_snapshot:
			return

		if trans_type == TRANS.CONSTANT:
			var revision_before := _change_revision
			var snapshot := get_canonical_preset_point_snapshot()

			if _parameter_edit_depth > 0:
				snapshot["changing"] = true

			set_point_snapshot(snapshot)

			if _change_revision == revision_before:
				_notify_parameter_changed()
		else:
			_notify_parameter_changed()


# ------------------
# BACK OVERSHOOT
# ------------------
## Controls how far the curve overshoots its target.[br]
## Higher values create a stronger overshoot; lower values make it more subtle.
@export_range(0.0, 5.0, 0.001) var overshoot: float = 1.70158:
	set(value):
		if overshoot == value:
			return
		overshoot = value
		if _applying_editor_state_snapshot:
			return
		if trans_type == TRANS.BACK:
			var revision_before := _change_revision
			var snapshot := get_canonical_preset_point_snapshot()
			if _parameter_edit_depth > 0:
				snapshot["changing"] = true
			set_point_snapshot(snapshot)
			if _change_revision == revision_before:
				_notify_parameter_changed()
		else:
			_notify_parameter_changed()

# ------------------
# POINTS
# ------------------
## Runtime point API. Point data is serialized through primitive properties so live
## updates do not depend on Godot's Array[Resource] change propagation.
var points: Array[EasingCurvePoint]:
	get:
		return _points
	set(value):
		_set_points(value)

######################################################
# FUNCTION PARAMETERS
######################################################
## Parameters for specific CurveMode.FUNCTION

# ------------------
# IRREGULAR
# ------------------
## Represents the number of random points to generate. Must be a positive integer >= 2.
## Irregular mode converges to a linear equation for num_points == 2, no matter how high the randomness is.
@export_range(2, 100, 1) var num_points: int = 3:
	set(value):
		if num_points == value:
			return
		num_points = value
		_update_irregular_parameter()
## Controls the amplitude of random variations.
## Higher values create more dramatic jumps between steps (default: 1).
@export_range(0.0, 4.0, 0.1) var randomness: float = 3.5:
	set(value):
		if randomness == value:
			return
		randomness = value
		_update_irregular_parameter()
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
		_notify_parameter_changed()

## Y positions of irregular points
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR)
var _irregular_points_y: Array[float] = []:
	set(value):
		if _irregular_points_y == value:
			return
		_irregular_points_y = value
		_notify_parameter_changed()

# ------------------
# STEP
# ------------------
## Represents the number of equal steps to divide the animation into.
## Must be a positive integer.
@export_range(0, 100, 1) var steps: int = 4:
	set(value):
		if steps != value:
			steps = value
			_notify_parameter_changed()
## When true, the change happens at the start of each step.
## When false, the change happens at the end of each step.
@export var from_start: bool = false:
	set(value):
		if from_start != value:
			from_start = value
			_notify_parameter_changed()
## Adds a constant y_offset. The step function is clamped to a range of [0,1].
## When the number of steps is zero, this converges to the constant function (y = y_offset).
@export_range(0, 1, 0.001) var y_offset: float = 0.0:
	set(value):
		if y_offset != value:
			y_offset = value
			_notify_parameter_changed()


# ------------------
# POWER
# ------------------
## Controls the exponent used by the Power easing function.[br]
## 1.0 is linear; 2.0 is Quad, 3.0 is Cubic, and so on. Fractional exponents are also allowed.
@export_range(0.001, 1000.0, 0.001, "exp") var power: float = 2.0:
	set(value):
		if power != value:
			power = value
			_notify_parameter_changed()


# ------------------
# ELASTIC
# ------------------
## Controls the amplitude of oscillation.[br]
## Higher values produce larger overshoots and wider motion.
@export_range(0.0, 5.0, 0.01) var amplitude: float = 1.0:
	set(value):
		if amplitude != value:
			amplitude = value
			_notify_parameter_changed()

## Controls the period of oscillation.[br]
## Lower the period to produce faster, more frequent oscillations.[br]
## Increase the period to produce slower, wider oscillations.
@export_range(0.01, 1.0, 0.01) var period: float = 0.3:
	set(value):
		if period != value:
			period = value
			_notify_parameter_changed()


# ------------------
# BOUNCE
# ------------------
## The number of bounces before settling.
@export_range(1, 10, 1) var num_bounces: int = 3:
	set(value):
		if num_bounces != value:
			num_bounces = value
			_notify_parameter_changed()

## The amount of damping to apply to each bounce.
@export_range(0.0, 100.0, 0.1) var bounce_damping: float = 75.0:
	set(value):
		if bounce_damping != value:
			bounce_damping = value
			_notify_parameter_changed()

# ------------------
# SPRING
# ------------------
## The frequency of oscillation.
@export_range(0.0, 10.0, 0.01) var frequency: float = 2.5:
	set(value):
		if frequency != value:
			frequency = value
			_notify_parameter_changed()
## The amount of oscillation decay.
@export_range(0.1, 10.0, 0.01) var decay: float = 2.2:
	set(value):
		if decay != value:
			decay = value
			_notify_parameter_changed()

# ------------------
# PHYSICS_SPRING
# ------------------
## The stiffness of the spring.
@export_range(0.0, 1000.0, 0.1) var stiffness: float = 100.0:
	set(value):
		if stiffness != value:
			stiffness = value
			_notify_parameter_changed()
## The spring damping value.
@export_range(1.0, 100.0, 0.1) var damping: float = 10.0:
	set(value):
		if damping != value:
			damping = value
			_notify_parameter_changed()
## The mass of the object attached to the spring.
@export_range(1.0, 10.0, 0.1) var mass: float = 1.0:
	set(value):
		if mass != value:
			mass = value
			_notify_parameter_changed()
## The initial velocity of the spring.
@export_range(-30.0, 30.0, 0.1) var velocity: float = 0.0:
	set(value):
		if velocity != value:
			velocity = value
			_notify_parameter_changed()

# ------------------
# CSS_LINEAR
# ------------------
## CSS linear easing function.[br]
## String format: linear(y1, y2, y3...)[br]
## Each y value defines the easing progress at that point.[br]
## By default the progress is evenly distributed in x.[br]
## Optional x% can specify where a value occurs: y x%.[br]
## Example: linear(0, 0.75 25%, 1) vs. linear(0, 0.75, 1)[br]
## Percentages must be in the [0%, 100%] range and appear in ascending order.[br]
## Y values can have any range (positive or negative.)[br]
## Example: linear(0, -0.25 25%, 1.1 75%, 1)
@export var css_linear: String = "linear(0, 1)":
	set(value):
		if css_linear == value:
			return

		css_linear = value

		var parsed := EASING_LIBRARY.CSSLinear.parse(value)
		if parsed.is_empty():
			return

		_css_linear_points = parsed
		_notify_parameter_changed()



@export_custom(
	PROPERTY_HINT_NONE,
	"",
	PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_NO_EDITOR,
)
var _css_linear_points: PackedVector2Array = PackedVector2Array([
	Vector2(0.0, 0.0),
	Vector2(1.0, 1.0),
])

# ------------------
# CSS_CUBIC_BEZIER
# ------------------
## CSS cubic-bezier easing function.[br]
## String format: cubic-bezier(x1, y1, x2, y2)[br]
## (x1, y1): First control point.[br]
## (x2, y2): Second control point.[br]
## x controls timing; x values must be in the [0, 1] range.[br]
## y controls progress; y values can have any range.[br]
## Example: cubic-bezier(0.333, 0, 0.667, -0.567) for a "Back" style curve.
@export var css_cubic_bezier: String = "cubic-bezier(0.25, 0.1, 0.25, 1)":
	set(value):
		if css_cubic_bezier == value:
			return

		css_cubic_bezier = value

		var parsed := EASING_LIBRARY.CSSCubicBezier.parse(value)
		if parsed.is_empty():
			return

		_css_cubic_bezier_controls = parsed
		_notify_parameter_changed()


@export_custom(
	PROPERTY_HINT_NONE,
	"",
	PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_NO_EDITOR,
)
var _css_cubic_bezier_controls := PackedFloat64Array([
	0.25,
	0.1,
	0.25,
	1.0,
])


######################################################
# GLOBAL TRANSFORM
######################################################

@export_group("Global Transform")

## Flips the curve horizontally.[br]
## The transform remains active when switching presets.
@export var reverse: bool = false:
	set(value):
		if reverse == value:
			return

		reverse = value

		if _applying_editor_state_snapshot:
			return

		if curve_mode == CurveMode.BEZIER:
			var snapshot := _reverse_point_snapshot(
				get_point_snapshot()
			)
			set_point_snapshot(snapshot)
			return

		_notify_parameter_changed()

## Flips the curve vertically.[br]
## The transform remains active when switching presets.
@export var invert: bool = false:
	set(value):
		if invert == value:
			return

		invert = value

		if _applying_editor_state_snapshot:
			return

		if curve_mode == CurveMode.BEZIER:
			var snapshot := _invert_point_snapshot(
				get_point_snapshot()
			)
			set_point_snapshot(snapshot)
			return

		_notify_parameter_changed()


######################################################
# INIT
######################################################
# --- Constructor ---
#func _init():
#pass
func _init() -> void:
	if _points.is_empty():
		_update_preset()


func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = [
		{
			"name": POINT_SNAPSHOT_PROPERTY,
			"type": TYPE_DICTIONARY,
			"usage": PROPERTY_USAGE_EDITOR,
		},
		{
			"name": FUNCTION_SNAPSHOT_PROPERTY,
			"type": TYPE_DICTIONARY,
			"usage": PROPERTY_USAGE_EDITOR,
		},
		{
			"name": EDITOR_STATE_SNAPSHOT_PROPERTY,
			"type": TYPE_DICTIONARY,
			"usage": PROPERTY_USAGE_EDITOR,
		},
		{
			"name": POINT_STORAGE_COUNT,
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_STORAGE,
		},
	]

	for i in range(_points.size()):
		for property_name in POINT_PROPERTIES:
			var property_type := TYPE_VECTOR2

			match property_name:
				&"locked":
					property_type = TYPE_DICTIONARY
				&"handle_mode":
					property_type = TYPE_INT
				&"left_force_linear":
					property_type = TYPE_BOOL
				&"right_force_linear":
					property_type = TYPE_BOOL

			properties.append(
				{
					"name": _get_point_storage_name(i, property_name),
					"type": property_type,
					"usage": PROPERTY_USAGE_STORAGE,
				},
			)

	return properties


func _get(property: StringName) -> Variant:
	if property == POINT_SNAPSHOT_PROPERTY:
		return get_point_snapshot()
	if property == FUNCTION_SNAPSHOT_PROPERTY:
		return get_function_snapshot()
	if property == EDITOR_STATE_SNAPSHOT_PROPERTY:
		return get_editor_state_snapshot()

	if property == POINT_STORAGE_COUNT:
		return _points.size()

	var point_property := _parse_point_storage_name(property)
	if point_property.is_empty():
		return null

	var index: int = point_property.index
	if index < 0 or index >= _points.size() or _points[index] == null:
		return null

	var value: Variant = _points[index].get(point_property.name)
	return value.duplicate(true) if value is Dictionary else value


func _set(property: StringName, value: Variant) -> bool:
	if property == POINT_SNAPSHOT_PROPERTY:
		if value is Dictionary:
			set_point_snapshot(value)
		return true
	if property == FUNCTION_SNAPSHOT_PROPERTY:
		if value is Dictionary:
			set_function_snapshot(value)
		return true
	if property == EDITOR_STATE_SNAPSHOT_PROPERTY:
		if value is Dictionary:
			set_editor_state_snapshot(value)
		return true

	if property == POINT_STORAGE_COUNT:
		_resize_points(maxi(int(value), 0))
		return true

	var point_property := _parse_point_storage_name(property)
	if point_property.is_empty():
		return false

	var index: int = point_property.index
	if index < 0:
		return false
	if index >= _points.size():
		_resize_points(index + 1)

	var point := _points[index]
	var property_name: StringName = point_property.name
	if property_name == &"locked":
		var locks: Dictionary[String, bool] = {
			"position": bool(value.get("position", false)),
			"left_control_point": bool(value.get("left_control_point", false)),
			"right_control_point": bool(value.get("right_control_point", false)),
		}
		point.locked = locks
	else:
		point.set(property_name, value)
	return true


func _get_point_storage_name(index: int, property_name: StringName) -> StringName:
	return StringName("%s%d/%s" % [POINT_STORAGE_PREFIX, index, property_name])


func _parse_point_storage_name(property: StringName) -> Dictionary:
	var property_string := String(property)
	if not property_string.begins_with(POINT_STORAGE_PREFIX):
		return {}

	var parts := property_string.trim_prefix(POINT_STORAGE_PREFIX).split("/", false, 1)
	if parts.size() != 2 or not parts[0].is_valid_int():
		return {}

	var property_name := StringName(parts[1])
	if property_name not in POINT_PROPERTIES:
		return {}

	return {"index": parts[0].to_int(), "name": property_name}


func _property_belongs_to_transition(
		property_name: StringName,
		transition: TRANS,
) -> bool:
	return (
		property_name in BEZIER_PARAMETERS.get(transition, [])
		or property_name in FUNCTION_PARAMETERS.get(transition, [])
		or property_name in FUNCTION_EDITOR_PROPERTIES.get(transition, [])
	)


func _is_bezier_property(property_name: StringName) -> bool:
	for properties in BEZIER_PARAMETERS.values():
		if property_name in properties:
			return true

	return false


func _is_function_property(property_name: StringName) -> bool:
	for properties in FUNCTION_PARAMETERS.values():
		if property_name in properties:
			return true

	for properties in FUNCTION_EDITOR_PROPERTIES.values():
		if property_name in properties:
			return true

	return false


static func is_function_transition(transition: TRANS) -> bool:
	return (
		FUNCTION_CLASSES.has(transition)
		or transition in GENERATED_FUNCTION_TRANSITIONS
	)


static func get_all_function_parameters() -> Array[StringName]:
	var result: Array[StringName] = []

	for parameters in FUNCTION_PARAMETERS.values():
		for property_name: StringName in parameters:
			if property_name not in result:
				result.append(property_name)

	return result


static func get_all_bezier_parameters() -> Array[StringName]:
	var result: Array[StringName] = []

	for parameters in BEZIER_PARAMETERS.values():
		for property_name: StringName in parameters:
			if property_name not in result:
				result.append(property_name)

	return result


static func get_all_parameters() -> Array[StringName]:
	var result := get_all_function_parameters()

	for property_name in get_all_bezier_parameters():
		if property_name not in result:
			result.append(property_name)

	return result


static func has_function_parameter_default(
		property_name: StringName,
) -> bool:
	return property_name in get_all_function_parameters()


static func has_parameter_default(property_name: StringName) -> bool:
	return property_name in get_all_parameters()


static var _default_instance: EasingCurve
static func get_function_parameter_default(
		property_name: StringName,
) -> Variant:
	if _default_instance == null:
		_default_instance = EasingCurve.new()
	return _default_instance.get(property_name)


static func get_parameter_default(property_name: StringName) -> Variant:
	if _default_instance == null:
		_default_instance = EasingCurve.new()
	return _default_instance.get(property_name)


static func is_deferred_function_parameter(
		property_name: StringName,
) -> bool:
	return (
		property_name in get_all_function_parameters()
		and property_name not in NON_DEFERRED_FUNCTION_PARAMETERS
	)


static func is_deferred_parameter(property_name: StringName) -> bool:
	return (
		property_name in get_all_parameters()
		and property_name not in NON_DEFERRED_FUNCTION_PARAMETERS
	)


static func uses_generated_function_data(
		transition: TRANS,
) -> bool:
	return transition in GENERATED_FUNCTION_TRANSITIONS


func _update_irregular_parameter() -> void:
	if _applying_function_snapshot:
		_notify_parameter_changed()
	else:
		_generate_irregular()


func _update_curve_mode() -> void:
	curve_mode = (
		CurveMode.FUNCTION
		if is_function_transition(trans_type)
		else CurveMode.BEZIER
	)


func _validate_property(property: Dictionary) -> void:
	var property_name := StringName(property.name)

	# Points are exposed to the editor but serialized separately.
	if property_name == &"points":
		property.usage |= PROPERTY_USAGE_EDITOR
		property.usage &= ~PROPERTY_USAGE_STORAGE
		return

	# Bezier-specific properties are only visible for
	# the transition that owns them.
	if _is_bezier_property(property_name):
		if _property_belongs_to_transition(property_name, trans_type):
			property.usage |= PROPERTY_USAGE_EDITOR
		else:
			property.usage &= ~PROPERTY_USAGE_EDITOR
		return

	# Function-specific properties are only visible for
	# the transition that owns them.
	if _is_function_property(property_name):
		if _property_belongs_to_transition(
			property_name,
			trans_type,
		):
			property.usage |= PROPERTY_USAGE_EDITOR
		else:
			property.usage &= ~PROPERTY_USAGE_EDITOR
		return


func generate_irregular() -> void:
	_generate_irregular()


func get_default_for_property(i: int, property_name: String) -> Vector2:
	var temp := _create_canonical_preset()

	if i < 0 or i >= temp.points.size():
		return Vector2.ZERO

	return temp.points[i].get(property_name)


func has_builtin_bezier_preset() -> bool:
	return trans_type in [
		TRANS.CONSTANT,
		TRANS.LINEAR,
		TRANS.SINE,
		TRANS.QUAD,
		TRANS.CUBIC,
		TRANS.QUART,
		TRANS.QUINT,
		TRANS.EXPO,
		TRANS.CIRC,
		TRANS.BACK,
	]


func _create_canonical_preset() -> EasingCurve:
	var preset := EasingCurve.new()
	for property_name in BEZIER_PARAMETERS.get(trans_type, []):
		preset.set(property_name, get(property_name))
	preset.set_ease(ease_type)
	preset.set_trans(trans_type)
	return preset


func get_canonical_preset_point_snapshot() -> Dictionary:
	if not has_builtin_bezier_preset():
		return {}

	var preset := _create_canonical_preset()
	var snapshot := preset.get_point_snapshot()

	if reverse:
		snapshot = _reverse_point_snapshot(snapshot)

	if invert:
		snapshot = _invert_point_snapshot(snapshot)

	return snapshot


## A modified built-in keeps its Transition/Ease origin.
## Handles both Bezier and Function presets. Custom curves are not reported.
func is_selected_preset_modified(
		tolerance: float = PRESET_GEOMETRY_TOLERANCE,
) -> bool:
	if curve_mode == CurveMode.FUNCTION:
		var default_curve := EasingCurve.new()

		for property_name in FUNCTION_PARAMETERS.get(trans_type, []):
			if get(property_name) != default_curve.get(property_name):
				return true

		for property_name in FUNCTION_EDITOR_PROPERTIES.get(trans_type, []):
			if property_name == &"generate_tool_button":
				continue
			if get(property_name) != default_curve.get(property_name):
				return true

		return false

	if not has_builtin_bezier_preset():
		return false

	return not _point_snapshot_matches(
		get_canonical_preset_point_snapshot(),
		maxf(tolerance, 0.0),
	)


func reset_selected_preset() -> bool:
	if not is_selected_preset_modified():
		return false

	if curve_mode == CurveMode.FUNCTION:
		var default_curve := EasingCurve.new()

		_parameter_update_depth += 1

		for property_name in FUNCTION_PARAMETERS.get(trans_type, []):
			set(property_name, default_curve.get(property_name))

		for property_name in FUNCTION_EDITOR_PROPERTIES.get(trans_type, []):
			if property_name == &"generate_tool_button":
				continue
			set(property_name, default_curve.get(property_name))

		_parameter_update_depth -= 1

		if _parameter_update_change_pending:
			_parameter_update_change_pending = false
			_notify_parameter_changed()

		return true

	_update_preset()
	return true


func cubic_bezier(x0, y0, x1, y1) -> void:
	var p0 := EasingCurvePoint.new(Vector2(0, 0))
	var p1 := EasingCurvePoint.new(Vector2(1, 1))
	p0.right_control_point = Vector2(x0, y0)
	p1.left_control_point = Vector2(x1, y1)
	add_point(p0)
	add_point(p1)


func cubic_bezier_pair(first_controls: Vector4, second_controls: Vector4) -> void:
	# Combined Tween modes are two normalized halves joined at their mathematical transition.
	# Scaling unit control sets around (0.5, 0.5) keeps that boundary editor-visible.
	var p0 := EasingCurvePoint.new(Vector2.ZERO)
	var midpoint := EasingCurvePoint.new(Vector2(0.5, 0.5))
	var p1 := EasingCurvePoint.new(Vector2.ONE)
	p0.right_control_point = Vector2(first_controls.x, first_controls.y) * 0.5
	midpoint.left_control_point = Vector2(first_controls.z, first_controls.w) * 0.5
	midpoint.right_control_point = Vector2(0.5, 0.5) + Vector2(second_controls.x, second_controls.y) * 0.5
	p1.left_control_point = Vector2(0.5, 0.5) + Vector2(second_controls.z, second_controls.w) * 0.5
	add_point(p0)
	add_point(midpoint)
	add_point(p1)


func _set_composed_bezier_preset(in_controls: Vector4, out_controls: Vector4) -> void:
	match ease_type:
		EASE.IN:
			cubic_bezier(in_controls.x, in_controls.y, in_controls.z, in_controls.w)
		EASE.OUT:
			cubic_bezier(out_controls.x, out_controls.y, out_controls.z, out_controls.w)
		EASE.IN_OUT:
			cubic_bezier_pair(in_controls, out_controls)
		EASE.OUT_IN:
			cubic_bezier_pair(out_controls, in_controls)


func set_ease(_ease: EASE) -> void:
	if ease_type == _ease:
		_update_preset()
	else:
		ease_type = _ease


func set_trans(_trans: TRANS) -> void:
	if trans_type == _trans:
		_update_preset()
	else:
		trans_type = _trans


func printpoints():
	for i in range(points.size()):
		var p = points[i]
		print(i, ": ", p.position, " L:", p.left_control_point, " R:", p.right_control_point)


func sort_points() -> void:
	_points.sort_custom(func(a, b): return a.position.x < b.position.x)
	_synchronize_point_connections()
	_notify_curve_changed(true, true)


func swap_properties(p0: EasingCurvePoint, p1: EasingCurvePoint) -> void:
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

	elif a is EasingCurvePoint and b is EasingCurvePoint:
		# var p0 = a
		# var p1 = b
		#var temp_x = p0.position.x
		#p0.position.x = p1.position.x
		#p1.position.x = temp_x
		swap_properties(a, b)
		sort_points()

	else:
		push_warning("Could not swap due to type mismatch")


func add_point(p: EasingCurvePoint) -> void:
	if p == null:
		return
	_points.append(p)
	_points.sort_custom(func(a, b): return a.position.x < b.position.x)
	_synchronize_point_connections()
	_notify_curve_changed(true, true)


func remove_point(p: EasingCurvePoint) -> void:
	if p not in _points:
		return

	_points.erase(p)
	_synchronize_point_connections()
	_notify_curve_changed(true, true)


func set_point(i: int, p: EasingCurvePoint) -> void:
	if i < 0 or i >= _points.size() or p == null:
		return
	_points[i] = p
	_synchronize_point_connections()
	_notify_curve_changed(true, false)


func set_point_property(i: int, property_name: StringName, value: Variant) -> void:
	if i < 0 or i >= _points.size() or property_name not in POINT_PROPERTIES:
		return
	set(_get_point_storage_name(i, property_name), value)


func set_point_locked(i: int, property_name: StringName, locked_value: bool) -> void:
	if i < 0 or i >= _points.size() or _points[i] == null:
		return
	if not _points[i].locked.has(property_name):
		return
	var locks := _points[i].locked.duplicate()
	locks[property_name] = locked_value
	set_point_property(i, &"locked", locks)


func get_point_snapshot() -> Dictionary:
	return make_point_snapshot(_points)


func make_point_snapshot(point_values: Array[EasingCurvePoint]) -> Dictionary:
	var positions := PackedVector2Array()
	var left_control_points := PackedVector2Array()
	var right_control_points := PackedVector2Array()
	var handle_modes := PackedInt32Array()
	var locks: Array[Dictionary] = []
	var left_force_linear := PackedByteArray()
	var right_force_linear := PackedByteArray()

	for point in point_values:
		if point == null:
			positions.append(Vector2.ZERO)
			left_control_points.append(Vector2.ZERO)
			right_control_points.append(Vector2.ZERO)
			handle_modes.append(EasingCurvePoint.HandleMode.FREE)
			locks.append({})
			left_force_linear.append(0)
			right_force_linear.append(0)
			continue

		positions.append(point.position)
		left_control_points.append(point.left_control_point)
		right_control_points.append(point.right_control_point)
		handle_modes.append(point.handle_mode)
		locks.append(point.locked.duplicate())
		left_force_linear.append(int(point.left_force_linear))
		right_force_linear.append(int(point.right_force_linear))

	return {
		"positions": positions,
		"left_control_points": left_control_points,
		"right_control_points": right_control_points,
		"handle_modes": handle_modes,
		"locks": locks,
		"left_force_linear": left_force_linear,
		"right_force_linear": right_force_linear,
	}


func _reverse_point_snapshot(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)

	var positions: PackedVector2Array = snapshot.get(
		"positions",
		PackedVector2Array(),
	)
	var left_controls: PackedVector2Array = snapshot.get(
		"left_control_points",
		PackedVector2Array(),
	)
	var right_controls: PackedVector2Array = snapshot.get(
		"right_control_points",
		PackedVector2Array(),
	)
	var locks: Array = snapshot.get("locks", [])
	var handle_modes: PackedInt32Array = snapshot.get(
		"handle_modes",
		PackedInt32Array(),
	)
	var left_force_linear: PackedByteArray = snapshot.get(
		"left_force_linear",
		PackedByteArray(),
	)
	var right_force_linear: PackedByteArray = snapshot.get(
		"right_force_linear",
		PackedByteArray(),
	)

	var reversed_positions := PackedVector2Array()
	var reversed_left_controls := PackedVector2Array()
	var reversed_right_controls := PackedVector2Array()
	var reversed_locks: Array[Dictionary] = []
	var reversed_handle_modes := PackedInt32Array()
	var reversed_left_force_linear := PackedByteArray()
	var reversed_right_force_linear := PackedByteArray()

	for i in range(positions.size() - 1, -1, -1):
		var position := positions[i]
		position.x = 1.0 - position.x
		reversed_positions.append(position)

		# Horizontal reversal swaps left/right handle roles.
		var left_control := right_controls[i]
		left_control.x = 1.0 - left_control.x
		reversed_left_controls.append(left_control)

		var right_control := left_controls[i]
		right_control.x = 1.0 - right_control.x
		reversed_right_controls.append(right_control)

		var lock_values: Dictionary = (
			locks[i]
			if i < locks.size() and locks[i] is Dictionary
			else {}
		)

		if i < handle_modes.size():
			reversed_handle_modes.append(handle_modes[i])

		reversed_left_force_linear.append(
			right_force_linear[i]
			if i < right_force_linear.size()
			else 0
		)

		reversed_right_force_linear.append(
			left_force_linear[i]
			if i < left_force_linear.size()
			else 0
		)

		# Handle locks swap for the same reason as the handles.
		reversed_locks.append({
			"position": bool(lock_values.get("position", false)),
			"left_control_point": bool(
				lock_values.get("right_control_point", false)
			),
			"right_control_point": bool(
				lock_values.get("left_control_point", false)
			),
		})

	result["positions"] = reversed_positions
	result["left_control_points"] = reversed_left_controls
	result["right_control_points"] = reversed_right_controls
	result["locks"] = reversed_locks
	result["handle_modes"] = reversed_handle_modes
	result["left_force_linear"] = reversed_left_force_linear
	result["right_force_linear"] = reversed_right_force_linear

	return result


func _invert_point_snapshot(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)

	var positions: PackedVector2Array = snapshot.get(
		"positions",
		PackedVector2Array(),
	)
	var left_controls: PackedVector2Array = snapshot.get(
		"left_control_points",
		PackedVector2Array(),
	)
	var right_controls: PackedVector2Array = snapshot.get(
		"right_control_points",
		PackedVector2Array(),
	)

	var inverted_positions := PackedVector2Array()
	var inverted_left_controls := PackedVector2Array()
	var inverted_right_controls := PackedVector2Array()

	for position in positions:
		var transformed := position
		transformed.y = 1.0 - transformed.y
		inverted_positions.append(transformed)

	for control in left_controls:
		var transformed := control
		transformed.y = 1.0 - transformed.y
		inverted_left_controls.append(transformed)

	for control in right_controls:
		var transformed := control
		transformed.y = 1.0 - transformed.y
		inverted_right_controls.append(transformed)

	result["positions"] = inverted_positions
	result["left_control_points"] = inverted_left_controls
	result["right_control_points"] = inverted_right_controls

	return result


func set_point_snapshot(snapshot: Dictionary) -> void:
	var positions: PackedVector2Array = snapshot.get("positions", PackedVector2Array())
	var left_control_points: PackedVector2Array = snapshot.get("left_control_points", PackedVector2Array())
	var right_control_points: PackedVector2Array = snapshot.get("right_control_points", PackedVector2Array())
	var handle_modes: PackedInt32Array = snapshot.get("handle_modes", PackedInt32Array())
	var left_force_linear: PackedByteArray = snapshot.get(
		"left_force_linear",
		PackedByteArray(),
	)
	var right_force_linear: PackedByteArray = snapshot.get(
		"right_force_linear",
		PackedByteArray(),
	)
	var locks: Array = snapshot.get("locks", [])
	var changing := bool(snapshot.get("changing", false))
	var topology_changed := positions.size() != _points.size() or _points.has(null)
	var point_data_changed := _point_snapshot_differs(
		positions,
		left_control_points,
		right_control_points,
		handle_modes,
		locks,
		left_force_linear,
		right_force_linear,
	)
	_suppress_point_notifications += 1
	if not topology_changed:
		for i in range(positions.size()):
			var point := _points[i]

			# Disable per-side force state while restoring exact geometry.
			point.set_force_linear_state(false, false, false)

			# Temporarily use Free so restoring one handle does not
			# modify the opposite handle.
			point.handle_mode = EasingCurvePoint.HandleMode.FREE

			point.position = positions[i]

			if i < left_control_points.size():
				point.left_control_point = left_control_points[i]

			if i < right_control_points.size():
				point.right_control_point = right_control_points[i]

			if i < handle_modes.size():
				point.handle_mode = handle_modes[i]

			# Restore the stored state without modifying restored geometry.
			point.set_force_linear_state(
				bool(left_force_linear[i])
					if i < left_force_linear.size()
					else false,
				bool(right_force_linear[i])
					if i < right_force_linear.size()
					else false,
				false,
			)

			if i < locks.size() and locks[i] is Dictionary:
				var lock_values: Dictionary = locks[i]
				_points[i].locked = {
					"position": bool(lock_values.get("position", false)),
					"left_control_point": bool(lock_values.get("left_control_point", false)),
					"right_control_point": bool(lock_values.get("right_control_point", false)),
				}
	else:
		var new_points: Array[EasingCurvePoint] = []
		for i in range(positions.size()):
			var point := EasingCurvePoint.new(positions[i])

			point.set_force_linear_state(false, false, false)

			if i < left_control_points.size():
				point.left_control_point = left_control_points[i]

			if i < right_control_points.size():
				point.right_control_point = right_control_points[i]

			if i < handle_modes.size():
				point.handle_mode = handle_modes[i]

			point.set_force_linear_state(
				bool(left_force_linear[i])
					if i < left_force_linear.size()
					else false,
				bool(right_force_linear[i])
					if i < right_force_linear.size()
					else false,
				false,
			)

			if i < locks.size() and locks[i] is Dictionary:
				var lock_values: Dictionary = locks[i]
				point.locked = {
					"position": bool(lock_values.get("position", false)),
					"left_control_point": bool(lock_values.get("left_control_point", false)),
					"right_control_point": bool(lock_values.get("right_control_point", false)),
				}
			new_points.append(point)
		_disconnect_point_signals()
		_points = new_points
		_synchronize_point_connections()
	_suppress_point_notifications -= 1

	if _applying_editor_state_snapshot:
		_point_snapshot_change_pending = false
		_point_snapshot_property_list_pending = false
		return

	if changing:
		_point_snapshot_change_pending = _point_snapshot_change_pending or point_data_changed
		_point_snapshot_property_list_pending = _point_snapshot_property_list_pending or topology_changed
		return

	var notify_points := point_data_changed or _point_snapshot_change_pending
	var notify_property_list := topology_changed or _point_snapshot_property_list_pending
	_point_snapshot_change_pending = false
	_point_snapshot_property_list_pending = false
	if notify_points:
		_notify_curve_changed(true, notify_property_list)


func get_editor_state_snapshot() -> Dictionary:
	return {
		"ease_type": ease_type,
		"trans_type": trans_type,
		"curve_mode": curve_mode,
		"from_start": from_start,
		"reverse": reverse,
		"invert": invert,
		"bezier_parameter_snapshot": _get_bezier_parameter_snapshot(),
		"point_snapshot": get_point_snapshot(),
		"function_snapshot": get_function_snapshot(),
	}


func _get_bezier_parameter_snapshot() -> Dictionary:
	var snapshot := {}

	for property_name in get_all_bezier_parameters():
		snapshot[property_name] = get(property_name)

	return snapshot


func set_editor_state_snapshot(snapshot: Dictionary) -> void:
	var snapshot_ease := int(snapshot.get("ease_type", ease_type))
	var snapshot_trans := int(snapshot.get("trans_type", trans_type))
	var snapshot_mode := int(snapshot.get("curve_mode", curve_mode))
	var snapshot_from_start := bool(snapshot.get("from_start", from_start))
	var snapshot_reverse := bool(snapshot.get("reverse", reverse))
	var snapshot_invert := bool(snapshot.get("invert", invert))
	var bezier_parameter_snapshot: Dictionary = snapshot.get(
		"bezier_parameter_snapshot",
		_get_bezier_parameter_snapshot(),
	)
	var point_snapshot: Dictionary = snapshot.get("point_snapshot", get_point_snapshot())
	var function_snapshot: Dictionary = snapshot.get("function_snapshot", get_function_snapshot())

	var positions: PackedVector2Array = point_snapshot.get("positions", PackedVector2Array())
	var left_control_points: PackedVector2Array = point_snapshot.get("left_control_points", PackedVector2Array())
	var right_control_points: PackedVector2Array = point_snapshot.get("right_control_points", PackedVector2Array())
	var handle_modes: PackedInt32Array = point_snapshot.get("handle_modes", PackedInt32Array())
	var locks: Array = point_snapshot.get("locks", [])
	var left_force_linear: PackedByteArray = point_snapshot.get("left_force_linear", PackedByteArray())
	var right_force_linear: PackedByteArray = point_snapshot.get("right_force_linear", PackedByteArray())
	var topology_changed := positions.size() != _points.size() or _points.has(null)
	var point_data_changed := _point_snapshot_differs(
		positions,
		left_control_points,
		right_control_points,
		handle_modes,
		locks,
		left_force_linear,
		right_force_linear,
	)
	var locks_changed := _point_snapshot_locks_differ(locks)
	var bezier_parameters_changed := (
		_get_bezier_parameter_snapshot() != bezier_parameter_snapshot
	)
	var function_changed := get_function_snapshot() != function_snapshot
	var scalar_changed := (
		ease_type != snapshot_ease
		or trans_type != snapshot_trans
		or curve_mode != snapshot_mode
		or from_start != snapshot_from_start
		or reverse != snapshot_reverse
		or invert != snapshot_invert
		or bezier_parameters_changed
	)
	if not point_data_changed and not function_changed and not scalar_changed:
		return

	var property_list_changed := (
		topology_changed
		or locks_changed
		or ease_type != snapshot_ease
		or trans_type != snapshot_trans
		or curve_mode != snapshot_mode
	)

	_applying_editor_state_snapshot = true
	ease_type = snapshot_ease
	trans_type = snapshot_trans
	curve_mode = snapshot_mode
	function_callable = Callable()
	from_start = snapshot_from_start
	reverse = snapshot_reverse
	invert = snapshot_invert
	for property_name in get_all_bezier_parameters():
		if bezier_parameter_snapshot.has(property_name):
			set(property_name, bezier_parameter_snapshot[property_name])
	set_function_snapshot(function_snapshot)
	set_point_snapshot(point_snapshot)
	if curve_mode == CurveMode.FUNCTION and trans_type != TRANS.CUSTOM:
		_init_function()
	_applying_editor_state_snapshot = false
	_notify_curve_changed(point_data_changed, property_list_changed)


func _get_generated_function_snapshot() -> Dictionary:
	return {
		"generated_points_x": PackedFloat64Array(
			_irregular_points_x
		),
		"generated_points_y": PackedFloat64Array(
			_irregular_points_y
		),
	}

func get_function_snapshot() -> Dictionary:
	var snapshot := {}

	for property_name in get_all_function_parameters():
		snapshot[property_name] = get(property_name)

	snapshot.merge(
		_get_generated_function_snapshot()
	)

	return snapshot


func _parse_generated_function_snapshot(
		snapshot: Dictionary,
) -> Dictionary:
	return {
		"points_x": _function_snapshot_float_array(
			snapshot.get(
				"generated_points_x",
				PackedFloat64Array(_irregular_points_x),
			),
		),
		"points_y": _function_snapshot_float_array(
			snapshot.get(
				"generated_points_y",
				PackedFloat64Array(_irregular_points_y),
			),
		),
	}


func set_function_snapshot(snapshot: Dictionary) -> void:
	var generated := _parse_generated_function_snapshot(snapshot)
	var snapshot_points_x: Array[float] = generated["points_x"]
	var snapshot_points_y: Array[float] = generated["points_y"]

	var force_notify := bool(snapshot.get("force_notify", false))
	var changed := false

	for property_name in get_all_function_parameters():
		if not snapshot.has(property_name):
			continue
		var current_value: Variant = get(property_name)
		var snapshot_value: Variant = snapshot[property_name]
		if current_value is float:
			if not is_equal_approx(
				float(current_value),
				float(snapshot_value),
			):
				changed = true
				break
		elif current_value != snapshot_value:
			changed = true
			break

	if (
		not changed
		and (
			_irregular_points_x != snapshot_points_x
			or _irregular_points_y != snapshot_points_y
		)
	):
		changed = true

	if not changed and not force_notify:
		return

	_parameter_edit_depth += 1
	_applying_function_snapshot = true

	for property_name in get_all_function_parameters():
		if snapshot.has(property_name):
			set(property_name, snapshot[property_name])

	_irregular_points_x = snapshot_points_x
	_irregular_points_y = snapshot_points_y

	_applying_function_snapshot = false
	_parameter_edit_depth -= 1
	_notify_parameter_changed()


func _function_snapshot_float_array(value: Variant) -> Array[float]:
	var result: Array[float] = []
	if value is Array or value is PackedFloat32Array or value is PackedFloat64Array:
		for item in value:
			result.append(float(item))
	return result


func _point_snapshot_differs(
		positions: PackedVector2Array,
		left_control_points: PackedVector2Array,
		right_control_points: PackedVector2Array,
		handle_modes: PackedInt32Array,
		locks: Array,
		left_force_linear: PackedByteArray,
		right_force_linear: PackedByteArray,
) -> bool:
	if positions.size() != _points.size() or _points.has(null):
		return true
	for i in range(positions.size()):
		var point := _points[i]
		if point.position != positions[i]:
			return true
		if i < left_control_points.size() and point.left_control_point != left_control_points[i]:
			return true
		if i < right_control_points.size() and point.right_control_point != right_control_points[i]:
			return true
		if i < handle_modes.size() and point.handle_mode != handle_modes[i]:
			return true
		if i < locks.size() and locks[i] is Dictionary:
			var lock_values: Dictionary = locks[i]
			for property_name in POINT_PROPERTIES.slice(0, 3):
				if bool(point.locked.get(property_name, false)) != bool(lock_values.get(property_name, false)):
					return true
		var snapshot_left_force := (
			bool(left_force_linear[i])
			if i < left_force_linear.size()
			else false
		)
		var snapshot_right_force := (
			bool(right_force_linear[i])
			if i < right_force_linear.size()
			else false
		)
		if point.left_force_linear != snapshot_left_force:
			return true
		if point.right_force_linear != snapshot_right_force:
			return true
	return false


func _point_snapshot_locks_differ(locks: Array) -> bool:
	if locks.size() != _points.size():
		return true
	for i in range(locks.size()):
		if locks[i] is not Dictionary or _points[i] == null:
			return true
		var lock_values: Dictionary = locks[i]
		for property_name in POINT_PROPERTIES.slice(0, 3):
			if bool(_points[i].locked.get(property_name, false)) != bool(lock_values.get(property_name, false)):
				return true
	return false


func _point_snapshot_matches(snapshot: Dictionary, tolerance: float) -> bool:
	var positions: PackedVector2Array = snapshot.get("positions", PackedVector2Array())
	var left_control_points: PackedVector2Array = snapshot.get("left_control_points", PackedVector2Array())
	var right_control_points: PackedVector2Array = snapshot.get("right_control_points", PackedVector2Array())
	var locks: Array = snapshot.get("locks", [])
	if (
		positions.size() != _points.size()
		or left_control_points.size() != _points.size()
		or right_control_points.size() != _points.size()
		or locks.size() != _points.size()
		or _points.has(null)
	):
		return false

	for i in range(_points.size()):
		var point := _points[i]
		if not _vectors_equal_with_tolerance(point.position, positions[i], tolerance):
			return false
		if not _vectors_equal_with_tolerance(point.left_control_point, left_control_points[i], tolerance):
			return false
		if not _vectors_equal_with_tolerance(point.right_control_point, right_control_points[i], tolerance):
			return false
		if locks[i] is not Dictionary:
			return false
		var lock_values: Dictionary = locks[i]
		for property_name in POINT_PROPERTIES.slice(0, 3):
			if bool(point.locked.get(property_name, false)) != bool(lock_values.get(property_name, false)):
				return false
	return true


func _vectors_equal_with_tolerance(a: Vector2, b: Vector2, tolerance: float) -> bool:
	return absf(a.x - b.x) <= tolerance and absf(a.y - b.y) <= tolerance


func force_update() -> void:
	_synchronize_point_connections()
	_notify_curve_changed(true, true)


func notify_changed() -> void:
	_notify_curve_changed(false, true)


func _set_points(value: Array[EasingCurvePoint]) -> void:
	if _point_arrays_match(_points, value):
		_synchronize_point_connections()
		return

	_disconnect_point_signals()
	_points = value
	_synchronize_point_connections()
	_notify_curve_changed(true, true)


func _resize_points(new_size: int) -> void:
	if new_size == _points.size():
		_synchronize_point_connections()
		return

	while _points.size() > new_size:
		_points.pop_back()
	while _points.size() < new_size:
		_points.append(EasingCurvePoint.new())

	_synchronize_point_connections()
	_notify_curve_changed(true, true)


func _clear_points() -> void:
	if _points.is_empty():
		return
	_points.clear()
	_synchronize_point_connections()
	_notify_curve_changed(true, true)


func _synchronize_point_connections() -> bool:
	var topology_changed := not _point_arrays_match(_point_topology, _points)
	var current_points: Array[EasingCurvePoint] = []
	for point in _points:
		if point != null and point not in current_points:
			current_points.append(point)

	for point in _connected_points:
		if point != null and point not in current_points and point.changed.is_connected(_on_point_changed):
			point.changed.disconnect(_on_point_changed)

	for point in current_points:
		if not point.changed.is_connected(_on_point_changed):
			point.changed.connect(_on_point_changed)

	_connected_points = current_points
	_point_topology = _points.duplicate()
	return topology_changed


func _disconnect_point_signals() -> void:
	for point in _connected_points:
		if point != null and point.changed.is_connected(_on_point_changed):
			point.changed.disconnect(_on_point_changed)
	_connected_points.clear()
	_point_topology.clear()


func _point_arrays_match(a: Array[EasingCurvePoint], b: Array[EasingCurvePoint]) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


func _notify_curve_changed(point_data_changed: bool, property_list_changed: bool) -> void:
	_change_revision += 1
	if property_list_changed:
		notify_property_list_changed()
	if point_data_changed:
		points_changed.emit(_points)
	emit_changed()


func _begin_editor_parameter_edit() -> void:
	_parameter_edit_depth += 1


func _cancel_editor_parameter_edit() -> void:
	if _parameter_edit_depth <= 0:
		return
	_parameter_edit_depth -= 1
	if _parameter_edit_depth == 0:
		_point_snapshot_change_pending = false
		_point_snapshot_property_list_pending = false


func _finish_editor_parameter_edit() -> void:
	if _parameter_edit_depth <= 0:
		return
	_parameter_edit_depth -= 1
	if _parameter_edit_depth == 0 and (
		_point_snapshot_change_pending
		or _point_snapshot_property_list_pending
	):
		var point_data_changed := _point_snapshot_change_pending
		var property_list_changed := _point_snapshot_property_list_pending
		_point_snapshot_change_pending = false
		_point_snapshot_property_list_pending = false
		_notify_curve_changed(point_data_changed, property_list_changed)
		return
	_notify_parameter_changed()


func _notify_parameter_changed() -> void:
	if _applying_editor_state_snapshot:
		return
	if _parameter_update_depth > 0:
		_parameter_update_change_pending = true
		return
	if _parameter_edit_depth > 0:
		return
	emit_changed()


## Generic callable for non-function CurveMode
func do_nothing() -> void:
	pass


func clear_function() -> void:
	if trans_type == TRANS.CUSTOM:
		if curve_mode == CurveMode.FUNCTION:
			curve_mode = CurveMode.BEZIER
			function_callable = Callable()
			if _points.size() < 2:
				_clear_points()
				add_point(EasingCurvePoint.new(Vector2.ZERO))
				add_point(EasingCurvePoint.new(Vector2.ONE))
		return
	curve_mode = CurveMode.BEZIER
	function_callable = Callable()
	_clear_points()


func set_function(func_ref: Callable):
	curve_mode = CurveMode.FUNCTION
	function_callable = func_ref
	_clear_points()
	if _applying_editor_state_snapshot:
		return
	_notify_curve_changed(false, true)


func _get_function_arguments(offset: float) -> Array:
	var args: Array = [
		offset,
		0.0,
		1.0,
		1.0,
	]

	if uses_generated_function_data(trans_type):
		args.append(_irregular_points_x)
		args.append(_irregular_points_y)
	elif trans_type == TRANS.CSS_LINEAR:
		args.append(_css_linear_points)
	elif trans_type == TRANS.CSS_CUBIC_BEZIER:
		args.append(_css_cubic_bezier_controls)
	else:
		for property_name in FUNCTION_PARAMETERS.get(trans_type, []):
			args.append(get(property_name))

	return args



func _sample_raw(offset: float) -> float:
	if _synchronize_point_connections():
		_notify_curve_changed(true, true)

	if curve_mode == CurveMode.FUNCTION:
		if not function_callable.is_valid():
			_init_function()
		return function_callable.callv(
			_get_function_arguments(offset)
		)

	if points.size() < 2:
		return 0.0

	for i in range(points.size() - 1):
		var a = points[i]
		var b = points[i + 1]

		var min_x = min(a.position.x, b.position.x)
		var max_x = max(a.position.x, b.position.x)

		if offset < min_x or offset > max_x:
			continue

		var t = _solve_for_t(offset, a, b)

		if t >= 0.0 and t <= 1.0:
			return _bezier_interpolate(
				a.position.y,
				a.right_control_point.y,
				b.left_control_point.y,
				b.position.y,
				t,
			)

	return 0.0


## Sample the curve, calculating f(t) given x.
func sample(offset: float) -> float:
	offset = clampf(offset, 0.0, 1.0)

	# Function transforms are applied at sample time because functions have no
	# editable geometry. Bézier transforms are already baked into their points,
	# so applying them here would transform the curve twice.
	if curve_mode == CurveMode.FUNCTION:
		if reverse:
			offset = 1.0 - offset

		var result := _sample_raw(offset)

		if invert:
			result = 1.0 - result

		return result

	return _sample_raw(offset)


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
	_clear_points()

	for i in range(resolution + 1):
		var x = float(i) / resolution
		var y = func_ref.call(x)
		add_point(EasingCurvePoint.new(Vector2(x, y)))


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
	_parameter_update_depth += 1
	var result := { "x": [], "y": [] }
	var points_x: Array[float] = []
	var points_y: Array[float] = []

	if trans_type == TRANS.JITTER:
		var jitter_steps := maxi(num_points, 1)
		for i in range(jitter_steps + 1):
			var x := float(i) / float(jitter_steps)
			points_x.append(x)
			if i == 0:
				points_y.append(0.0)
			elif i == jitter_steps:
				points_y.append(1.0)
			else:
				var offset := (randf() - 0.5) * randomness / float(jitter_steps)
				points_y.append(clampf(x + offset, 0.0, 1.0))
	elif num_points <= 2:
		points_x = [0.0, 1.0]
		points_y = [0.0, 1.0]
	else:
		var clamped_randomness := clampf(randomness, 0.0, 4.0)

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
				var offset = r * max_offset * (clamped_randomness / 4.0)
				points_y.append(clampf(linear_y + offset, 0.0, 1.0))

	result.x = points_x
	result.y = points_y

	_irregular_points_x = points_x
	_irregular_points_y = points_y
	_notify_parameter_changed()
	_parameter_update_depth -= 1
	if _parameter_update_depth == 0 and _parameter_update_change_pending:
		_parameter_update_change_pending = false
		_notify_parameter_changed()

	return result


func _set_easing_class_function(
		easing_class,
		use_extended: bool,
) -> void:
	var method_name := ""

	match ease_type:
		EASE.IN:
			method_name = "easeIn"
		EASE.OUT:
			method_name = "easeOut"
		EASE.IN_OUT:
			method_name = "easeInOut"
		EASE.OUT_IN:
			method_name = "easeOutIn"

	if use_extended:
		method_name += "Ex"

	set_function(Callable(easing_class, method_name))


func _init_function() -> void:
	if trans_type == TRANS.JITTER:
		if (
			_irregular_points_x.size() != num_points + 1
			or _irregular_points_y.size() != num_points + 1
		):
			_generate_irregular()

		_set_easing_class_function(
			EASING_LIBRARY.Irregular,
			false,
		)
		return

	if trans_type == TRANS.IRREGULAR:
		if (
			_irregular_points_x.size() != num_points
			or _irregular_points_y.size() != num_points
		):
			_generate_irregular()

		_set_easing_class_function(
			EASING_LIBRARY.Irregular,
			false,
		)
		return

	var config: Dictionary = FUNCTION_CLASSES.get(
		trans_type,
		{},
	)

	if config.is_empty():
		return

	_set_easing_class_function(
		config["class"],
		config["extended"],
	)


func _update_preset() -> void:
	clear_function()
	_update_curve_mode()

	if curve_mode == CurveMode.FUNCTION:
		_init_function()
		return

	match trans_type:
		TRANS.CUSTOM:
			return
		TRANS.CONSTANT:
			add_point(EasingCurvePoint.new(Vector2(0, constant_value)))
			add_point(EasingCurvePoint.new(Vector2(1, constant_value)))
		TRANS.LINEAR:
			add_point(EasingCurvePoint.new(Vector2(0, 0)))
			add_point(EasingCurvePoint.new(Vector2(1, 1)))
		TRANS.SINE:
			# A sine graph is not polynomial; these handles are optimized approximations.
			_set_composed_bezier_preset(
				Vector4(.361149818, -.000326393, .673540771, .486909956),
				Vector4(.326459229, .513090014, .638850212, 1.0003264),
			)
		TRANS.QUAD:
			# Degree elevation makes each quadratic half an exact cubic Bézier.
			_set_composed_bezier_preset(
				Vector4(1.0 / 3.0, 0, 2.0 / 3.0, 1.0 / 3.0),
				Vector4(1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1),
			)
		TRANS.CUBIC:
			# Cubic easing is exact. OUT_IN simplifies to one global cubic, so it needs no midpoint.
			match ease_type:
				EASE.IN:
					cubic_bezier(1.0 / 3.0, 0, 2.0 / 3.0, 0)
				EASE.OUT:
					cubic_bezier(1.0 / 3.0, 1, 2.0 / 3.0, 1)
				EASE.IN_OUT:
					cubic_bezier_pair(
						Vector4(1.0 / 3.0, 0, 2.0 / 3.0, 0),
						Vector4(1.0 / 3.0, 1, 2.0 / 3.0, 1),
					)
				EASE.OUT_IN:
					cubic_bezier(1.0 / 3.0, 1, 2.0 / 3.0, 0)
		TRANS.QUART:
			# Degree-four and degree-five graphs require optimized cubic approximations.
			_set_composed_bezier_preset(
				Vector4(.439210773, .004901892, .732221782, -.067109145),
				Vector4(.267778218, 1.06710911, .560789227, .995098114),
			)
		TRANS.QUINT:
			_set_composed_bezier_preset(
				Vector4(.522905409, .010620826, .775169373, -.113423072),
				Vector4(.224830627, 1.11342311, .477094591, .989379168),
			)
		TRANS.EXPO:
			# Godot's endpoint corrections introduce small discontinuities that continuous geometry cannot copy.
			_set_composed_bezier_preset(
				Vector4(.632421792, .015909066, .846576214, -.060294569),
				Vector4(.153921053, 1.0531143, .359647602, .985371113),
			)
		TRANS.CIRC:
			# A polynomial cubic can only approximate a circular arc.
			_set_composed_bezier_preset(
				Vector4(.565830648, .002238899, .999889314, .459180534),
				Vector4(.000110686, .540819466, .434169352, .99776113),
			)
		TRANS.BACK:
			# Back is cubic; combined modes are exact pieces, with Godot's larger IN_OUT overshoot.
			match ease_type:
				EASE.IN:
					cubic_bezier(1.0 / 3.0, 0, 2.0 / 3.0, -overshoot / 3.0)
				EASE.OUT:
					cubic_bezier(1.0 / 3.0, 1.0 + overshoot / 3.0, 2.0 / 3.0, 1)
				EASE.IN_OUT:
					var in_out_overshoot := overshoot * 1.525
					cubic_bezier_pair(
						Vector4(1.0 / 3.0, 0, 2.0 / 3.0, -in_out_overshoot / 3.0),
						Vector4(1.0 / 3.0, 1.0 + in_out_overshoot / 3.0, 2.0 / 3.0, 1),
					)
				EASE.OUT_IN:
					cubic_bezier_pair(
						Vector4(1.0 / 3.0, 1.0 + overshoot / 3.0, 2.0 / 3.0, 1),
						Vector4(1.0 / 3.0, 0, 2.0 / 3.0, -overshoot / 3.0),
					)

	# Apply persistent global transforms to newly generated Bézier presets.
	if reverse or invert:
		var snapshot := get_point_snapshot()

		if reverse:
			snapshot = _reverse_point_snapshot(snapshot)

		if invert:
			snapshot = _invert_point_snapshot(snapshot)

		set_point_snapshot(snapshot)


func _on_point_changed() -> void:
	if _suppress_point_notifications > 0:
		return
	_synchronize_point_connections()
	_notify_curve_changed(true, false)


# Newton-Raphson solver with a binary-search fallback for flat handles.
func _solve_for_t(x: float, a: EasingCurvePoint, b: EasingCurvePoint) -> float:
	var segment_width := b.position.x - a.position.x
	var t := clampf((x - a.position.x) / segment_width, 0.0, 1.0) if not is_zero_approx(segment_width) else 0.5

	for _iteration in range(12):
		var x_est := _bezier_interpolate(
			a.position.x,
			a.right_control_point.x,
			b.left_control_point.x,
			b.position.x,
			t,
		)
		var error := x_est - x
		if absf(error) <= 0.00000001:
			_last_t = t
			return t

		var dx := _bezier_derivative(
			a.position.x,
			a.right_control_point.x,
			b.left_control_point.x,
			b.position.x,
			t,
		)

		if absf(dx) < 0.00000001:
			break

		var next_t := t - error / dx
		if next_t < 0.0 or next_t > 1.0:
			break
		t = next_t

	t = _binary_search_t(x, a, b)
	_last_t = t
	return t


func _binary_search_t(x: float, a: EasingCurvePoint, b: EasingCurvePoint) -> float:
	var low := 0.0
	var high := 1.0
	var mid := 0.5

	for _iteration in range(32):
		mid = (low + high) * 0.5

		var x_est = _bezier_interpolate(
			a.position.x,
			a.right_control_point.x,
			b.left_control_point.x,
			b.position.x,
			mid,
		)
		if absf(x_est - x) <= 0.00000001:
			break

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

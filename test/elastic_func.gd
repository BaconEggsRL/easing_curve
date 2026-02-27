@tool
class_name ElasticFunction
extends Control

enum EASE {
	IN,
	OUT,
	IN_OUT,
	OUT_IN,
}

# --- Elastic parameters ---
@export_range(0.0, 5.0, 0.01) var amplitude: float = 1.0:
	set(value):
		amplitude = value
		_update_preview()
@export_range(0.01, 1.0, 0.01) var period: float = 0.3:
	set(value):
		period = value
		_update_preview()
@export_range(0.1, 2.0, 0.01) var duration: float = 1.0:
	set(value):
		duration = value
		_update_preview()
@export var mode: EASE = EASE.IN: # 0=In, 1=Out, 2=InOut, 3=OutIn
	set(value):
		mode = value
		_update_preview()

var points: Array[Vector2] = []
var STEPS: int = 100


func _ready():
	_update_preview()


func _draw():
	if points.size() < 2:
		return
	for i in range(points.size() - 1):
		draw_line(
			points[i] * Vector2(size.x, -size.y) + Vector2(0, size.y),
			points[i + 1] * Vector2(size.x, -size.y) + Vector2(0, size.y),
			Color(0, 1, 0),
			2,
		)


# ------------------------
# Elastic easing functions
# ------------------------
func ease_out(t, b, c, d, a, p):
	if t == 0:
		return b
	t /= d
	if t == 1:
		return b + c
	var s = p / 4
	return a * pow(2, -10 * t) * sin((t * d - s) * 2.0 * PI / p) + c + b


func ease_in(t, b, c, d, a, p):
	if t == 0:
		return b
	t /= d
	if t == 1:
		return b + c
	var s = p / 4
	t -= 1
	return -a * pow(2, 10 * t) * sin((t * d - s) * 2.0 * PI / p) + b


func ease_in_out(t, b, c, d, a, p):
	if t == 0:
		return b
	t /= d / 2
	if t == 2:
		return b + c
	var s = p / 4
	if t < 1:
		t -= 1
		return -0.5 * (a * pow(2, 10 * t) * sin((t * d - s) * 2.0 * PI / p)) + b
	t -= 1
	return a * pow(2, -10 * t) * sin((t * d - s) * 2.0 * PI / p) * 0.5 + c + b


func ease_out_in(t, b, c, d, a, p):
	if t < d / 2:
		return ease_out(t * 2, b, c / 2, d, a, p)
	return ease_in(t * 2 - d, b + c / 2, c / 2, d, a, p)


func _update_preview():
	points.clear()

	# Compute steps dynamically: enough samples per period
	var steps_per_period: int = 20
	var num_periods: float = duration / period
	var steps: int = max(int(num_periods * steps_per_period), 2)

	for i in range(steps + 1):
		var t = float(i) / steps * duration
		var y
		match mode:
			0:
				y = ease_in(t, 0, 1, duration, amplitude, period)
			1:
				y = ease_out(t, 0, 1, duration, amplitude, period)
			2:
				y = ease_in_out(t, 0, 1, duration, amplitude, period)
			3:
				y = ease_out_in(t, 0, 1, duration, amplitude, period)
		points.append(Vector2(t, y))
	queue_redraw()

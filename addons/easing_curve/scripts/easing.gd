# Easing Library

# This is a Godot Script (GDScript) (http://www.godotengine.org/) port of the Robert Penner's equations for easing. You can find much more information about it on http://robertpenner.com/easing/.

# This library is based off:
# * https://github.com/EmmanuelOga/easing
# * https://github.com/jesusgollonet/processing-penner-easing


# Disclaimer for Robert Penner's Easing Equations license:

# TERMS OF USE - EASING EQUATIONS

# Open source under the BSD License.

# Copyright © 2001 Robert Penner
# All rights reserved.

# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
#    * Neither the name of the author nor the names of contributors may be used to endorse or promote products derived from this software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."""


# Usage:
#
#	onready var Easing = preload("easing.gd")
#
#	func testEasing():
#		var startValue = 0.0
#		var endValue = 1.0
#		var change = 1.0
#		var duration = 1.0
#
#		print(Easing.Cubic.easeOut(0, startValue, change, duration))						# --> 0
#		print(Easing.Cubic.easeOut(duration / 4.0, startValue, change, duration))			# --> 0.578125
#		print(Easing.Cubic.easeOut(duration / 2.0, startValue, change, duration))			# --> 0.875
#		print(Easing.Cubic.easeOut(duration / (3.0/4.0), startValue, change, duration))		# --> 1.037037
#		print(Easing.Cubic.easeOut(duration, startValue, change, duration))					# --> 1


# All easing functions take these parameters:
# t = time     should go from 0 to duration
# b = begin    value of the property being ease.
# c = change   ending value of the property - beginning value of the property
# d = duration
#
# Some functions allow additional modifiers, like the elastic functions
# which also can receive an amplitud and a period parameters (defaults
# are included)

class_name Easing

static var interpolators := [
	[Linear.easeIn, Linear.easeOut, Linear.easeInOut, Linear.easeOutIn],
	[Sine.easeIn, Sine.easeOut, Sine.easeInOut, Sine.easeOutIn],
	[Quint.easeIn, Quint.easeOut, Quint.easeInOut, Quint.easeOutIn],
	[Quart.easeIn, Quart.easeOut, Quart.easeInOut, Quart.easeOutIn],
	[Quad.easeIn, Quad.easeOut, Quad.easeInOut, Quad.easeOutIn],
	[Expo.easeIn, Expo.easeOut, Expo.easeInOut, Expo.easeOutIn],
	[Elastic.easeIn, Elastic.easeOut, Elastic.easeInOut, Elastic.easeOutIn],
	[Cubic.easeIn, Cubic.easeOut, Cubic.easeInOut, Cubic.easeOutIn],
	[Circ.easeIn, Circ.easeOut, Circ.easeInOut, Circ.easeOutIn],
	[Bounce.easeIn, Bounce.easeOut, Bounce.easeInOut, Bounce.easeOutIn],
	[Back.easeIn, Back.easeOut, Back.easeInOut, Back.easeOutIn],
	[Spring.easeIn, Spring.easeOut, Spring.easeInOut, Spring.easeOutIn],
]


class Linear:
	static func easeIn(t, b, c, d):
		return c * t / d + b

	static func easeOut(t, b, c, d):
		return easeIn(t, b, c, d)

	static func easeInOut(t, b, c, d):
		return easeIn(t, b, c, d)

	static func easeOutIn(t, b, c, d):
		return easeIn(t, b, c, d)


class Sine:
	static func easeIn(t, b, c, d):
		return -c * cos(t / d * (PI / 2)) + c + b

	static func easeOut(t, b, c, d):
		return c * sin(t / d * (PI / 2)) + b

	static func easeInOut(t, b, c, d):
		return -c / 2 * (cos(PI * t / d) - 1) + b

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)


class Quint:
	static func easeIn(t, b, c, d):
		t = t / d
		return c * t * t * t * t * t + b

	static func easeOut(t, b, c, d):
		t = t / d - 1
		return c * (t * t * t * t * t + 1) + b

	static func easeInOut(t, b, c, d):
		t = (t / (d / 2))
		if (t < 1):
			return c / 2 * t * t * t * t * t + b
		else:
			t = t - 2
			return c / 2 * (t * t * t * t * t + 2) + b

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)


class Quart:
	static func easeIn(t, b, c, d):
		t = t / d
		return c * t * t * t * t + b

	static func easeOut(t, b, c, d):
		t = t / d - 1
		return -c * (t * t * t * t - 1) + b

	static func easeInOut(t, b, c, d):
		t = (t / (d / 2))
		if (t < 1):
			return c / 2 * t * t * t * t + b
		else:
			t = t - 2
			return -c / 2 * (t * t * t * t - 2) + b

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)


class Quad:
	static func easeIn(t, b, c, d):
		t = t / d
		return c * t * t + b

	static func easeOut(t, b, c, d):
		t = t / d
		return -c * t * (t - 2) + b

	static func easeInOut(t, b, c, d):
		t = (t / (d / 2))
		if (t < 1):
			return c / 2 * t * t + b
		else:
			t -= 1
			return -c / 2 * (t * (t - 2) - 1) + b

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)


class Expo:
	static func easeIn(t, b, c, d):
		if (t == 0):
			return b
		else:
			return c * pow(2, 10 * (t / d - 1)) + b

	static func easeOut(t, b, c, d):
		if (t == d):
			return b + c
		else:
			return c * (-pow(2, -10 * t / d) + 1) + b

	static func easeInOut(t, b, c, d):
		if (t == 0):
			return b
		if (t == d):
			return b + c
		t = (t / (d / 2))
		if (t < 1):
			return c / 2 * pow(2, 10 * (t - 1)) + b
		else:
			t = t - 1
			return c / 2 * (-pow(2, -10 * t) + 2) + b

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)


class Elastic:
	static func easeIn(t, b, c, d):
		if (t == 0):
			return b
		t = t / d
		if (t == 1):
			return b + c
		var p = d * 0.3
		var a = c
		var s = p / 4
		t = t - 1
		return -(a * pow(2, 10 * t) * sin((t * d - s) * (2 * PI) / p)) + b

	static func easeInEx(t, b, c, d, a, p):
		var s
		if (t == 0):
			return b
		t = t / d
		if (t == 1):
			return b + c
		if (a < abs(c)):
			a = c
			s = p / 4
		else:
			s = p / (2 * PI) * asin(c / a)
		t = t - 1
		return -(a * pow(2, 10 * t) * sin((t * d - s) * (2 * PI) / p)) + b

	static func easeOut(t, b, c, d):
		if (t == 0):
			return b
		t = t / d
		if (t == 1):
			return b + c
		var p = d * 0.4
		var a = c
		var s = p / 4
		return (a * pow(2, -10 * t) * sin((t * d - s) * (2 * PI) / p) + c + b)

	static func easeOutEx(t, b, c, d, a, p):
		var s
		if (t == 0):
			return b
		t = t / d
		if (t == 1):
			return b + c
		if (a < abs(c)):
			a = c
			s = p / 4
		else:
			s = p / (2 * PI) * asin(c / a)
		return (a * pow(2, -10 * t) * sin((t * d - s) * (2 * PI) / p) + c + b)

	static func easeInOut(t, b, c, d):
		if (t == 0):
			return b
		t = (t / (d / 2))
		if (t == 2):
			return b + c
		var p = d * (0.3 * 1.5)
		var a = c
		var s = p / 4
		if (t < 1):
			t = t - 1
			return -0.5 * (a * pow(2, 10 * t) * sin((t * d - s) * (2 * PI) / p)) + b
		else:
			t = t - 1
			return a * pow(2, -10 * t) * sin((t * d - s) * (2 * PI) / p) * 0.5 + c + b

	static func easeInOutEx(t, b, c, d, a, p):
		if (t == 0):
			return b
		t = (t / (d / 2))
		if (t == 2):
			return b + c
		p = p * 1.5  # match godot easing_equations.h
		var s = p / 4
		if (t < 1):
			t = t - 1
			return -0.5 * (a * pow(2, 10 * t) * sin((t * d - s) * (2 * PI) / p)) + b
		else:
			t = t - 1
			return a * pow(2, -10 * t) * sin((t * d - s) * (2 * PI) / p) * 0.5 + c + b

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)

	static func easeOutInEx(t, b, c, d, a, p):
		a = a * 0.5  # match godot easing_equations.h
		if (t < d / 2):
			return easeOutEx(t * 2, b, c / 2, d, a, p)
		var h = c / 2
		return easeInEx(t * 2 - d, b + h, h, d, a, p)




class Cubic:
	static func easeIn(t, b, c, d):
		t = t / d
		return c * t * t * t + b;

	static func easeOut(t, b, c, d):
		t = t / d - 1
		return c * (t * t * t + 1) + b

	static func easeInOut(t, b, c, d):
		t = (t / (d / 2))
		if (t < 1):
			return c / 2 * t * t * t + b
		else:
			t = t - 2
			return c / 2 * (t * t * t + 2) + b

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)


class Circ:
	static func easeIn(t, b, c, d):
		t = t / d
		return -c * (sqrt(1 - t * t) - 1) + b

	static func easeOut(t, b, c, d):
		t = t / d - 1
		return c * sqrt(1 - t * t) + b

	static func easeInOut(t, b, c, d):
		t = (t / (d / 2))
		if (t < 1):
			return -c / 2 * (sqrt(1 - t * t) - 1) + b
		else:
			t = t - 2
			return c / 2 * (sqrt(1 - t * t) + 1) + b

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)


class Bounce:
	static func easeIn(t, b, c, d):
		if b is Vector2:
			return c - easeOut(d - t, Vector2.ZERO, c, d) + b
		return c - easeOut(d - t, 0, c, d) + b

	static func easeOut(t, b, c, d):
		t = t / d
		if (t < (1 / 2.75)):
			return c * (7.5625 * t * t) + b
		elif (t < (2 / 2.75)):
			t = t - (1.5 / 2.75)
			return c * (7.5625 * t * t + 0.75) + b
		elif (t < (2.5 / 2.75)):
			t = t - (2.25 / 2.75)
			return c * (7.5625 * t * t + 0.9375) + b
		else:
			t = t - (2.625 / 2.75)
			return c * (7.5625 * t * t + 0.984375) + b

	static func easeInOut(t, b, c, d):
		if b is Vector2:
			if (t < (d / 2)):
				return easeIn (t * 2, Vector2.ZERO, c, d) * 0.5 + b
			else:
				return easeOut (t * 2 - d, Vector2.ZERO, c, d) * 0.5 + c * 0.5 + b
		if (t < (d / 2)):
			return easeIn (t * 2, 0, c, d) * 0.5 + b
		else:
			return easeOut (t * 2 - d, 0, c, d) * 0.5 + c * 0.5 + b

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)


class Back:
	static func easeIn(t, b, c, d, s = 1.70158):
		t = t / d
		return c * t * t * ((s + 1) * t - s) + b

	static func easeOut(t, b, c, d, s = 1.70158):
		t = t / d  - 1
		return c * (t * t * ((s + 1) * t + s) + 1) + b

	static func easeInOut(t, b, c, d, s = 1.70158):
		t = (t / (d / 2))
		if (t < 1):
			s = s * 1.525
			return c / 2 * (t * t * ((s + 1 ) * t - s)) + b;
		else:
			t = t - 2
			s = s * 1.525
			return c / 2 * (t * t * ((s + 1) * t + s) + 2) + b

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)


class Spring:
	static func easeIn(t, b, c, d):
		return c - Spring.easeOut(d - t, 0, c, d) + b

	static func easeOut(t, b, c, d):
		var t_norm = t / d
		var s = 1.0 - t_norm
		var t_calc = (sin(t_norm * PI * (0.2 + 2.5 * t_norm * t_norm * t_norm)) * pow(s, 2.2) + t_norm) * (1.0 + (1.2 * s))
		return c * t_calc + b

	static func easeInOut(t, b, c, d):
		if (t < d / 2):
			return easeIn(t * 2, b, c / 2, d)
		var h = c / 2
		return easeOut(t * 2 - d, b + h, h, d)

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)


class Power:

	static func easeIn(t, b, c, d, p):
		t = clamp(t / d, 0.0, 1.0)
		return b + c * pow(t, p)

	static func easeOut(t, b, c, d, p):
		t = clamp(t / d, 0.0, 1.0)
		return b + c * (1.0 - pow(1.0 - t, p))

	static func easeInOut(t, b, c, d, p):
		t = clamp(t / d, 0.0, 1.0)

		if t < 0.5:
			return b + c * 0.5 * pow(t * 2.0, p)
		else:
			return b + c * (1.0 - 0.5 * pow((1.0 - t) * 2.0, p))

	static func easeOutIn(t, b, c, d, p):
		if t < d / 2.0:
			return easeOut(t * 2.0, b, c / 2.0, d, p)
		var h = c / 2.0
		return easeIn(t * 2.0 - d, b + h, h, d, p)


class Step:

	static func _step(x: float, steps: int, from_start: bool) -> float:
		if from_start:
			# CSS: steps(n, start)
			return ceil(x * steps) / steps
		else:
			# CSS: steps(n, end)
			return floor(x * steps) / steps

	static func easeIn(t, b, c, d, steps:int, from_start:bool, y_offset:float):
		var x = clamp(t / d, 0.0, 1.0)
		var y: float
		if steps <= 0:
			# Constant mode
			y = clamp(y_offset, 0.0, 1.0)
		else:
			y = _step(x, steps, from_start) + y_offset
			y = clamp(y, 0.0, 1.0)
		return b + c * y

	static func easeOut(t, b, c, d, steps:int, from_start:bool, y_offset:float):
		return easeIn(t, b, c, d, steps, from_start, y_offset)

	static func easeInOut(t, b, c, d, steps:int, from_start:bool, y_offset:float):
		return easeIn(t, b, c, d, steps, from_start, y_offset)

	static func easeOutIn(t, b, c, d, steps:int, from_start:bool, y_offset:float):
		return easeIn(t, b, c, d, steps, from_start, y_offset)



class Jitter:

	static func _get_point(i: int, steps: int, randomness: float) -> float:
		# Force start and end to be exact
		if i <= 0:
			return 0.0
		if i >= steps:
			return 1.0

		# Generate a random variation for this step
		var r = (randf() - 0.5) * randomness / steps

		# Base linear position
		var base = float(i) / steps

		return clamp(base + r, 0.0, 1.0)


	static func easeIn(t: float, b: float, c: float, d: float, steps: int, randomness: float = 1.0) -> float:
		if steps <= 0:
			# Treat 0 steps as constant
			return b

		var x = clamp(t / d, 0.0, 1.0)

		# Which step are we in?
		var scaled = x * steps
		var index = int(floor(scaled))
		var local_t = scaled - index

		# Generate random points for the current step and the next
		var y0 = _get_point(index, steps, randomness)
		var y1 = _get_point(index + 1, steps, randomness)

		# Linear interpolate between points
		var y = lerp(y0, y1, local_t)

		return b + c * y


	static func easeOut(t: float, b: float, c: float, d: float, steps: int, randomness: float = 1.0) -> float:
		# Flip easeIn
		return b + c - easeIn(t, 0, c, d, steps, randomness)


	static func easeInOut(t: float, b: float, c: float, d: float, steps: int, randomness: float = 1.0) -> float:
		if t < d / 2.0:
			return easeIn(t * 2.0, b, c / 2.0, d, steps, randomness)
		return easeOut((t * 2.0) - d, b + c / 2.0, c / 2.0, d, steps, randomness)


	static func easeOutIn(t: float, b: float, c: float, d: float, steps: int, randomness: float = 1.0) -> float:
		if t < d / 2.0:
			return easeOut(t * 2.0, b, c / 2.0, d, steps, randomness)
		return easeIn((t * 2.0) - d, b + c / 2.0, c / 2.0, d, steps, randomness)


class Irregular:
	# Store precomputed points
	#static var _points_x: Array = []
	#static var _points_y: Array = []
	#static var _last_num_points: int = 0
	#static var _last_randomness: float = -1.0
#
	#static func _compute_points(num_points:int, randomness:float) -> void:
#
		#if num_points <= 2:
			#_points_x = [0.0, 1.0]
			#_points_y = [0.0, 1.0]
			#_last_num_points = num_points
			#_last_randomness = randomness
			#return
#
		#randomness = clamp(randomness, 0.0, 4.0)
#
		#_points_x = []
		#_points_y = []
#
		#for i in range(num_points):
			#var x = float(i) / float(num_points - 1)
			#_points_x.append(x)
#
			#if i == 0:
				#_points_y.append(0.0)
			#elif i == num_points - 1:
				#_points_y.append(1.0)
			#else:
				## random offset at interior points only
				#var linear_y = x
				#var max_offset = min(linear_y, 1.0 - linear_y)
				## Compute random float using set RandomNumberGenerator seed
				#var r = randf() * 2.0 - 1.0  # -1..1
				#var offset = r * max_offset * (randomness / 4.0)
				#_points_y.append(clamp(linear_y + offset, 0.0, 1.0))
#
		#_last_num_points = num_points
		#_last_randomness = randomness
#
		#print(_points_x, _points_y)

	#static func easeIn(t, b, c, d, num_points:int, randomness:float):
		## Linear fallback
		#if num_points <= 2:
			#var x = clamp(t / d, 0.0, 1.0)
			#return b + c * x
#
		## recompute points only if num_points or randomness changed
		#if num_points != _last_num_points or randomness != _last_randomness:
			#_compute_points(num_points, randomness)
#
		#var x = clamp(t / d, 0.0, 1.0)
#
		## find which segment t falls in
		#for i in range(_points_x.size() - 1):
			#if x >= _points_x[i] and x <= _points_x[i + 1]:
				#var local_t = (x - _points_x[i]) / (_points_x[i + 1] - _points_x[i])
				#var y = lerp(_points_y[i], _points_y[i + 1], local_t)
				#return b + c * y
#
		## fallback
		#return b + c * x

	static func easeIn(t, b, c, d, points_x:Array, points_y:Array):
		var x = clamp(t / d, 0.0, 1.0)

		for i in range(points_x.size() - 1):
			if x >= points_x[i] and x <= points_x[i + 1]:
				var local_t = (x - points_x[i]) / (points_x[i + 1] - points_x[i])
				var y = lerp(points_y[i], points_y[i + 1], local_t)
				return b + c * y

		return b + c * x


	static func easeOut(t: float, b: float, c: float, d: float, points_x:Array, points_y:Array) -> float:
		# Flip easeIn
		return b + c - easeIn(t, 0, c, d, points_x, points_y)


	static func easeInOut(t: float, b: float, c: float, d: float, points_x:Array, points_y:Array) -> float:
		if t < d / 2.0:
			return easeIn(t * 2.0, b, c / 2.0, d, points_x, points_y)
		return easeOut((t * 2.0) - d, b + c / 2.0, c / 2.0, d, points_x, points_y)


	static func easeOutIn(t: float, b: float, c: float, d: float, points_x:Array, points_y:Array) -> float:
		if t < d / 2.0:
			return easeOut(t * 2.0, b, c / 2.0, d, points_x, points_y)
		return easeIn((t * 2.0) - d, b + c / 2.0, c / 2.0, d, points_x, points_y)

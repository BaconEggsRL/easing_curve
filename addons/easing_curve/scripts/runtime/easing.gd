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
#	onready var EasingCurveEasing = preload("easing.gd")
#
#	func testEasing():
#		var startValue = 0.0
#		var endValue = 1.0
#		var change = 1.0
#		var duration = 1.0
#
#		print(EasingCurveEasing.Cubic.easeOut(0, startValue, change, duration))						# --> 0
#		print(EasingCurveEasing.Cubic.easeOut(duration / 4.0, startValue, change, duration))			# --> 0.578125
#		print(EasingCurveEasing.Cubic.easeOut(duration / 2.0, startValue, change, duration))			# --> 0.875
#		print(EasingCurveEasing.Cubic.easeOut(duration / (3.0/4.0), startValue, change, duration))		# --> 1.037037
#		print(EasingCurveEasing.Cubic.easeOut(duration, startValue, change, duration))					# --> 1


# All easing functions take these parameters:
# t = time     should go from 0 to duration
# b = begin    value of the property being ease.
# c = change   ending value of the property - beginning value of the property
# d = duration
#
# Some functions allow additional modifiers, like the elastic functions
# which also can receive an amplitud and a period parameters (defaults
# are included)

class_name EasingCurveEasing

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
			return c * pow(2, 10 * (t / d - 1)) + b - c * 0.001

	static func easeOut(t, b, c, d):
		if (t == d):
			return b + c
		else:
			return c * 1.001 * (-pow(2, -10 * t / d) + 1) + b

	static func easeInOut(t, b, c, d):
		if (t == 0):
			return b
		if (t == d):
			return b + c
		t = (t / (d / 2))
		if (t < 1):
			return c / 2 * pow(2, 10 * (t - 1)) + b - c * 0.0005
		else:
			t = t - 1
			return c / 2 * 1.0005 * (-pow(2, -10 * t) + 2) + b

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
		var p = d * 0.3
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

	static func easeInEx(t, b, c, d, frequency, decay):
		return c - easeOutEx(
			d - t,
			0,
			c,
			d,
			frequency,
			decay
		) + b

	static func easeOut(t, b, c, d):
		t = t / d - 1
		return c * (t * t * t + 1) + b

	static func easeOutEx(t, b, c, d, frequency, decay):
		var t_norm = t / d
		var s = 1.0 - t_norm
		var t_calc = (
			sin(
				t_norm * PI *
				(0.2 + frequency * t_norm * t_norm * t_norm)
			)
			* pow(s, decay)
			+ t_norm
		) * (1.0 + (1.2 * s))
		return c * t_calc + b

	static func easeInOut(t, b, c, d):
		t = (t / (d / 2))
		if (t < 1):
			return c / 2 * t * t * t + b
		else:
			t = t - 2
			return c / 2 * (t * t * t + 2) + b

	static func easeInOutEx(t, b, c, d, frequency, decay):
		if t < d / 2:
			return easeInEx(
				t * 2,
				b,
				c / 2,
				d,
				frequency,
				decay
			)
		var h = c / 2
		return easeOutEx(
			t * 2 - d,
			b + h,
			h,
			d,
			frequency,
			decay
		)

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)

	static func easeOutInEx(t, b, c, d, frequency, decay):
		if t < d / 2:
			return easeOutEx(
				t * 2,
				b,
				c / 2,
				d,
				frequency,
				decay
			)
		var h = c / 2
		return easeInEx(
			t * 2 - d,
			b + h,
			h,
			d,
			frequency,
			decay
		)


class Circ:
	static func easeIn(t, b, c, d):
		t = Vector2(t / d, 0.0).x
		return -c * (sqrt(1 - t * t) - 1) + b

	static func easeOut(t, b, c, d):
		t = Vector2(t / d - 1.0, 0.0).x
		return c * sqrt(1 - t * t) + b

	static func easeInOut(t, b, c, d):
		t = Vector2(t / (d / 2), 0.0).x
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
				return easeIn(t * 2, Vector2.ZERO, c, d) * 0.5 + b
			else:
				return easeOut(t * 2 - d, Vector2.ZERO, c, d) * 0.5 + c * 0.5 + b
		if (t < (d / 2)):
			return easeIn(t * 2, 0, c, d) * 0.5 + b
		else:
			return easeOut(t * 2 - d, 0, c, d) * 0.5 + c * 0.5 + b

	static func easeOutIn(t, b, c, d):
		if (t < d / 2):
			return easeOut(t * 2, b, c / 2, d)
		var h = c / 2
		return easeIn(t * 2 - d, b + h, h, d)


	# ------------------
	# EXTENDED
	# ------------------

	static func easeInEx(
		t,
		b,
		c,
		d,
		num_bounces: int = 3,
		bounce_damping: float = 75.0
	):

		return _easeInEx(
			t,
			b,
			c,
			d,
			num_bounces,
			bounce_damping
		)


	static func easeOutEx(
		t,
		b,
		c,
		d,
		num_bounces: int = 3,
		bounce_damping: float = 75.0
	):

		return _easeOutEx(
			t,
			b,
			c,
			d,
			num_bounces,
			bounce_damping
		)


	static func easeInOutEx(
		t,
		b,
		c,
		d,
		num_bounces: int = 3,
		bounce_damping: float = 75.0
	):

		return _easeInOutEx(
			t,
			b,
			c,
			d,
			num_bounces,
			bounce_damping
		)


	static func easeOutInEx(
		t,
		b,
		c,
		d,
		num_bounces: int = 3,
		bounce_damping: float = 75.0
	):

		return _easeOutInEx(
			t,
			b,
			c,
			d,
			num_bounces,
			bounce_damping
		)


	# ------------------
	# EXTENDED INTERNAL
	# ------------------

	static func _easeInEx(
		t,
		b,
		c,
		d,
		num_bounces: int,
		bounce_damping: float
	):
		if b is Vector2:
			return (
				c
				- _easeOutEx(
					d - t,
					Vector2.ZERO,
					c,
					d,
					num_bounces,
					bounce_damping
				)
				+ b
			)

		return (
			c
			- _easeOutEx(
				d - t,
				0,
				c,
				d,
				num_bounces,
				bounce_damping
			)
			+ b
		)


	static func _easeOutEx(
		t,
		b,
		c,
		d,
		num_bounces: int,
		bounce_damping: float
	):
		if d == 0:
			return b + c

		num_bounces = maxi(num_bounces, 1)

		var retention := clampf(
			1.0 - bounce_damping / 100.0,
			0.0,
			1.0
		)

		var duration_retention := sqrt(retention)

		# Calculate the total relative duration:
		#
		# initial fall = 1
		# bounce 1    = 1
		# bounce 2    = duration_retention
		# bounce 3    = duration_retention^2
		# ...
		var total_duration := 1.0
		var bounce_duration := 1.0

		for _i in range(num_bounces):
			total_duration += bounce_duration
			bounce_duration *= duration_retention

		var progress := clampf(
			float(t) / float(d),
			0.0,
			1.0
		)

		var scaled_t := progress * total_duration

		# Initial fall.
		if scaled_t < 1.0:
			return c * scaled_t * scaled_t + b

		# Successive bounces.
		var bounce_start := 1.0
		bounce_duration = 1.0
		var bounce_amplitude := retention

		for i in range(num_bounces):
			var bounce_end := bounce_start + bounce_duration

			if scaled_t <= bounce_end or i == num_bounces - 1:
				if is_zero_approx(bounce_duration):
					return b + c

				var local_t := clampf(
					(scaled_t - bounce_start) / bounce_duration,
					0.0,
					1.0
				)

				# -1 -> 0 -> +1 across the bounce.
				var parabola_t := local_t * 2.0 - 1.0

				# Starts at the target, falls away by bounce_amplitude,
				# then returns to the target.
				var value := (
					1.0
					- bounce_amplitude
					+ bounce_amplitude * parabola_t * parabola_t
				)

				return c * value + b

			bounce_start = bounce_end
			bounce_duration *= duration_retention
			bounce_amplitude *= retention

		return b + c


	static func _easeInOutEx(
		t,
		b,
		c,
		d,
		num_bounces: int,
		bounce_damping: float
	):
		if b is Vector2:
			if t < d / 2:
				return (
					_easeInEx(
						t * 2,
						Vector2.ZERO,
						c,
						d,
						num_bounces,
						bounce_damping
					)
					* 0.5
					+ b
				)

			return (
				_easeOutEx(
					t * 2 - d,
					Vector2.ZERO,
					c,
					d,
					num_bounces,
					bounce_damping
				)
				* 0.5
				+ c * 0.5
				+ b
			)

		if t < d / 2:
			return (
				_easeInEx(
					t * 2,
					0,
					c,
					d,
					num_bounces,
					bounce_damping
				)
				* 0.5
				+ b
			)

		return (
			_easeOutEx(
				t * 2 - d,
				0,
				c,
				d,
				num_bounces,
				bounce_damping
			)
			* 0.5
			+ c * 0.5
			+ b
		)


	static func _easeOutInEx(
		t,
		b,
		c,
		d,
		num_bounces: int,
		bounce_damping: float
	):
		if t < d / 2:
			return _easeOutEx(
				t * 2,
				b,
				c / 2,
				d,
				num_bounces,
				bounce_damping
			)

		var h = c / 2

		return _easeInEx(
			t * 2 - d,
			b + h,
			h,
			d,
			num_bounces,
			bounce_damping
		)




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
		return easeInEx(t, b, c, d, 2.5, 2.2)

	static func easeOut(t, b, c, d):
		return easeOutEx(t, b, c, d, 2.5, 2.2)

	static func easeInOut(t, b, c, d):
		return easeInOutEx(t, b, c, d, 2.5, 2.2)

	static func easeOutIn(t, b, c, d):
		return easeOutInEx(t, b, c, d, 2.5, 2.2)


	static func easeInEx(t, b, c, d, frequency, decay):
		return c - easeOutEx(
			d - t,
			0,
			c,
			d,
			frequency,
			decay
		) + b


	static func easeOutEx(t, b, c, d, frequency, decay):
		var t_norm = t / d
		var s = 1.0 - t_norm

		var t_calc = (
			sin(
				t_norm
				* PI
				* (
					0.2
					+ frequency
					* t_norm
					* t_norm
					* t_norm
				)
			)
			* pow(s, decay)
			+ t_norm
		) * (1.0 + (1.2 * s))

		return c * t_calc + b


	static func easeInOutEx(t, b, c, d, frequency, decay):
		if t < d / 2:
			return easeInEx(
				t * 2,
				b,
				c / 2,
				d,
				frequency,
				decay
			)

		var h = c / 2

		return easeOutEx(
			t * 2 - d,
			b + h,
			h,
			d,
			frequency,
			decay
		)


	static func easeOutInEx(t, b, c, d, frequency, decay):
		if t < d / 2:
			return easeOutEx(
				t * 2,
				b,
				c / 2,
				d,
				frequency,
				decay
			)

		var h = c / 2

		return easeInEx(
			t * 2 - d,
			b + h,
			h,
			d,
			frequency,
			decay
		)


class PhysicsSpring:
	static func easeIn(t, b, c, d):
		return easeInEx(
			t,
			b,
			c,
			d,
			100.0, # stiffness
			10.0,  # damping
			1.0,   # mass
			0.0,   # velocity
		)


	static func easeOut(t, b, c, d):
		return easeOutEx(
			t,
			b,
			c,
			d,
			100.0, # stiffness
			10.0,  # damping
			1.0,   # mass
			0.0,   # velocity
		)


	static func easeInOut(t, b, c, d):
		return easeInOutEx(
			t,
			b,
			c,
			d,
			100.0,
			10.0,
			1.0,
			0.0,
		)


	static func easeOutIn(t, b, c, d):
		return easeOutInEx(
			t,
			b,
			c,
			d,
			100.0,
			10.0,
			1.0,
			0.0,
		)


	static func easeOutEx(
		t,
		b,
		c,
		d,
		stiffness,
		damping,
		mass,
		velocity,
	):
		if d <= 0.0:
			return b + c

		var time = t / d

		if time <= 0.0:
			return b
		if time >= 1.0:
			return b + c

		stiffness = maxf(float(stiffness), 0.000001)
		damping = maxf(float(damping), 0.0)
		mass = maxf(float(mass), 0.000001)
		velocity = float(velocity)

		var response := _spring_response(
			time,
			stiffness,
			damping,
			mass,
			velocity,
		)

		return b + c * response


	static func easeInEx(
		t,
		b,
		c,
		d,
		stiffness,
		damping,
		mass,
		velocity,
	):
		return c - easeOutEx(
			d - t,
			0.0,
			c,
			d,
			stiffness,
			damping,
			mass,
			velocity,
		) + b


	static func easeInOutEx(
		t,
		b,
		c,
		d,
		stiffness,
		damping,
		mass,
		velocity,
	):
		if t < d / 2.0:
			return easeInEx(
				t * 2.0,
				b,
				c / 2.0,
				d,
				stiffness,
				damping,
				mass,
				velocity,
			)

		var h = c / 2.0

		return easeOutEx(
			t * 2.0 - d,
			b + h,
			h,
			d,
			stiffness,
			damping,
			mass,
			velocity,
		)


	static func easeOutInEx(
		t,
		b,
		c,
		d,
		stiffness,
		damping,
		mass,
		velocity,
	):
		if t < d / 2.0:
			return easeOutEx(
				t * 2.0,
				b,
				c / 2.0,
				d,
				stiffness,
				damping,
				mass,
				velocity,
			)

		var h = c / 2.0

		return easeInEx(
			t * 2.0 - d,
			b + h,
			h,
			d,
			stiffness,
			damping,
			mass,
			velocity,
		)


	static func _spring_response(
		time: float,
		stiffness: float,
		damping: float,
		mass: float,
		velocity: float,
	) -> float:
		var natural_frequency := sqrt(stiffness / mass)
		var damping_ratio := damping / (
			2.0 * sqrt(stiffness * mass)
		)

		# We solve displacement from the target.
		# Initial displacement is -1:
		#   position = 0
		#   target = 1
		var initial_displacement := -1.0

		var displacement: float

		if damping_ratio < 1.0 - 0.000001:
			# Underdamped: oscillates around the target.
			var damped_frequency := (
				natural_frequency
				* sqrt(1.0 - damping_ratio * damping_ratio)
			)

			var a := initial_displacement

			var b := (
				velocity
				+ damping_ratio
				* natural_frequency
				* initial_displacement
			) / damped_frequency

			displacement = (
				exp(
					-damping_ratio
					* natural_frequency
					* time
				)
				* (
					a * cos(damped_frequency * time)
					+ b * sin(damped_frequency * time)
				)
			)

		elif damping_ratio > 1.0 + 0.000001:
			# Overdamped: no oscillation.
			var root := sqrt(
				damping_ratio * damping_ratio - 1.0
			)

			var r1 := (
				-natural_frequency
				* (damping_ratio - root)
			)

			var r2 := (
				-natural_frequency
				* (damping_ratio + root)
			)

			var c1 := (
				velocity
				- r2 * initial_displacement
			) / (r1 - r2)

			var c2 := initial_displacement - c1

			displacement = (
				c1 * exp(r1 * time)
				+ c2 * exp(r2 * time)
			)

		else:
			# Critically damped: fastest return without oscillation.
			var a := initial_displacement

			var b := (
				velocity
				+ natural_frequency
				* initial_displacement
			)

			displacement = (
				(a + b * time)
				* exp(-natural_frequency * time)
			)

		return 1.0 + displacement





class CSSLinear:
	static func easeInEx(t, b, c, d, points):
		if points.is_empty():
			return b

		var x = t / d
		var y := sample(x, points)

		return b + c * y


	static func easeOutEx(t, b, c, d, points):
		return easeInEx(t, b, c, d, points)


	static func easeInOutEx(t, b, c, d, points):
		return easeInEx(t, b, c, d, points)


	static func easeOutInEx(t, b, c, d, points):
		return easeInEx(t, b, c, d, points)


	static func sample(
		x: float,
		points: PackedVector2Array,
	) -> float:
		if points.size() == 1:
			return points[0].y

		# CSS favors the last point when multiple points have
		# the same input position.
		for i in range(points.size() - 1, -1, -1):
			if is_equal_approx(x, points[i].x):
				return points[i].y

		var a: Vector2
		var b: Vector2

		if x < points[0].x:
			a = points[0]
			b = points[1]

			if is_equal_approx(a.x, b.x):
				return a.y

		elif x > points[-1].x:
			a = points[-2]
			b = points[-1]

			if is_equal_approx(a.x, b.x):
				return b.y

		else:
			for i in range(points.size() - 1):
				if points[i].x < x and x < points[i + 1].x:
					a = points[i]
					b = points[i + 1]
					break

		var weight := (x - a.x) / (b.x - a.x)
		return lerpf(a.y, b.y, weight)


	static func parse(source: String) -> PackedVector2Array:
		var text := source.strip_edges()

		if not text.begins_with("linear(") or not text.ends_with(")"):
			return PackedVector2Array()

		text = text.substr(7, text.length() - 8)

		var entries := text.split(",", false)
		if entries.size() < 2:
			return PackedVector2Array()

		var outputs: Array[float] = []
		var positions: Array = []

		for entry in entries:
			var parts := entry.strip_edges().split(" ", false)

			if parts.is_empty():
				return PackedVector2Array()

			if not parts[0].is_valid_float():
				return PackedVector2Array()

			var output := float(parts[0])
			var entry_positions: Array[float] = []

			for i in range(1, parts.size()):
				var part := parts[i]

				if not part.ends_with("%"):
					return PackedVector2Array()

				var number := part.trim_suffix("%")

				if not number.is_valid_float():
					return PackedVector2Array()

				entry_positions.append(float(number) / 100.0)

			if entry_positions.size() > 2:
				return PackedVector2Array()

			if entry_positions.size() == 2:
				outputs.append(output)
				positions.append(entry_positions[0])

				outputs.append(output)
				positions.append(entry_positions[1])
			else:
				outputs.append(output)
				positions.append(
					entry_positions[0]
					if entry_positions.size() == 1
					else null
				)

		_resolve_positions(positions)

		var points := PackedVector2Array()

		for i in outputs.size():
			points.append(
				Vector2(
					float(positions[i]),
					outputs[i],
				)
			)

		return points


	static func _resolve_positions(positions: Array) -> void:
		if positions.is_empty():
			return

		# First/last unspecified positions become 0%/100%.
		if positions[0] == null:
			positions[0] = 0.0

		if positions[-1] == null:
			positions[-1] = 1.0

		# CSS input positions cannot move backwards.
		var last_explicit := float(positions[0])

		for i in range(1, positions.size()):
			if positions[i] != null:
				positions[i] = maxf(
					float(positions[i]),
					last_explicit,
				)
				last_explicit = float(positions[i])

		# Evenly distribute each run of omitted positions.
		var start := 0

		while start < positions.size() - 1:
			var end := start + 1

			while end < positions.size() and positions[end] == null:
				end += 1

			if end >= positions.size():
				break

			var missing := end - start - 1

			if missing > 0:
				var x0 := float(positions[start])
				var x1 := float(positions[end])

				for j in range(1, missing + 1):
					positions[start + j] = lerpf(
						x0,
						x1,
						float(j) / float(missing + 1),
					)

			start = end







class CSSCubicBezier:
	static func easeInEx(
		t: float,
		b: float,
		c: float,
		d: float,
		controls: PackedFloat64Array
	) -> float:
		if controls.size() != 4 or is_zero_approx(d):
			return b

		var x := clampf(t / d, 0.0, 1.0)
		var y := sample(x, controls)

		return b + c * y


	static func easeOutEx(
		t: float,
		b: float,
		c: float,
		d: float,
		controls: PackedFloat64Array
	) -> float:
		return easeInEx(t, b, c, d, controls)


	static func easeInOutEx(
		t: float,
		b: float,
		c: float,
		d: float,
		controls: PackedFloat64Array
	) -> float:
		return easeInEx(t, b, c, d, controls)


	static func easeOutInEx(
		t: float,
		b: float,
		c: float,
		d: float,
		controls: PackedFloat64Array
	) -> float:
		return easeInEx(t, b, c, d, controls)


	static func sample(
		x: float,
		controls: PackedFloat64Array,
	) -> float:
		if controls.size() != 4:
			return x
		if x <= 0.0:
			return 0.0
		if x >= 1.0:
			return 1.0

		var lower := 0.0
		var upper := 1.0

		for _iteration in range(32):
			var parameter := (lower + upper) * 0.5
			if _cubic_coordinate(parameter, controls[0], controls[2]) < x:
				lower = parameter
			else:
				upper = parameter

		return _cubic_coordinate(
			(lower + upper) * 0.5,
			controls[1],
			controls[3],
		)


	static func parse(source: String) -> PackedFloat64Array:
		var text := source.strip_edges()

		if not text.to_lower().begins_with("cubic-bezier(") or not text.ends_with(")"):
			return PackedFloat64Array()

		text = text.substr(13, text.length() - 14)
		var entries := text.split(",", true)
		if entries.size() != 4:
			return PackedFloat64Array()

		var controls := PackedFloat64Array()
		for entry in entries:
			var token := entry.strip_edges()
			if not token.is_valid_float():
				return PackedFloat64Array()

			var value := float(token)
			if is_nan(value) or is_inf(value):
				return PackedFloat64Array()
			controls.append(value)

		if (
			controls[0] < 0.0
			or controls[0] > 1.0
			or controls[2] < 0.0
			or controls[2] > 1.0
		):
			return PackedFloat64Array()

		return controls


	static func _cubic_coordinate(
		parameter: float,
		control_1: float,
		control_2: float,
	) -> float:
		var inverse := 1.0 - parameter
		return (
			3.0 * inverse * inverse * parameter * control_1
			+ 3.0 * inverse * parameter * parameter * control_2
			+ parameter * parameter * parameter
		)


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

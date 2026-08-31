@tool
extends RefCounted

const SOLVE_EPSILON := 0.00000001
const NEWTON_ITERATIONS := 8
const BINARY_ITERATIONS := 32


static func get_effective_segment_control_xs(
		a: EasingCurvePoint,
		b: EasingCurvePoint,
) -> Vector2:
	var out_x := clampf(
		a.right_control_point.x,
		minf(a.position.x, b.position.x),
		maxf(a.position.x, b.position.x),
	)
	var in_x := clampf(
		b.left_control_point.x,
		minf(a.position.x, b.position.x),
		maxf(a.position.x, b.position.x),
	)
	var increasing := b.position.x >= a.position.x
	if (increasing and out_x > in_x) or (not increasing and out_x < in_x):
		var shared_x := (out_x + in_x) * 0.5
		out_x = shared_x
		in_x = shared_x
	return Vector2(out_x, in_x)


static func get_effective_segment_controls(
		a: EasingCurvePoint,
		b: EasingCurvePoint,
) -> Array[Vector2]:
	var out_control := a.right_control_point
	var in_control := b.left_control_point
	var control_xs := get_effective_segment_control_xs(a, b)
	out_control.x = control_xs.x
	in_control.x = control_xs.y
	return [out_control, in_control]


# Allocation-free solver for the monotonic X controls used by runtime sampling.
static func solve_monotonic_segment_t(
		x: float,
		a: EasingCurvePoint,
		b: EasingCurvePoint,
) -> float:
	var control_xs := get_effective_segment_control_xs(a, b)
	return solve_monotonic_t(
		x,
		a.position.x,
		control_xs.x,
		control_xs.y,
		b.position.x,
	)


static func solve_monotonic_t(
		x: float,
		p0: float,
		p1: float,
		p2: float,
		p3: float,
) -> float:
	if absf(x - p0) <= SOLVE_EPSILON:
		return 0.0
	if absf(x - p3) <= SOLVE_EPSILON:
		return 1.0

	var segment_width := p3 - p0
	if is_zero_approx(segment_width):
		return 0.5

	var increasing := segment_width > 0.0
	var low := 0.0
	var high := 1.0
	var t := clampf((x - p0) / segment_width, 0.0, 1.0)

	for _iteration in range(NEWTON_ITERATIONS):
		var x_est := bezier_interpolate(p0, p1, p2, p3, t)
		var error := x_est - x
		if absf(error) <= SOLVE_EPSILON:
			return t

		if (x_est < x) == increasing:
			low = t
		else:
			high = t

		var derivative := bezier_derivative(p0, p1, p2, p3, t)
		if absf(derivative) <= SOLVE_EPSILON:
			break

		var next_t := t - error / derivative
		if next_t <= low or next_t >= high:
			break
		t = next_t

	for _iteration in range(BINARY_ITERATIONS):
		t = (low + high) * 0.5
		var x_est := bezier_interpolate(p0, p1, p2, p3, t)
		if absf(x_est - x) <= SOLVE_EPSILON:
			break
		if (x_est < x) == increasing:
			low = t
		else:
			high = t

	return t


# Diagnostic solver retained for callers that need branch metadata.
static func solve_for_t(
		x: float,
		a: EasingCurvePoint,
		b: EasingCurvePoint,
		out_control: Vector2,
		in_control: Vector2,
) -> Dictionary:
	var segment_width := b.position.x - a.position.x
	var seed := clampf((x - a.position.x) / segment_width, 0.0, 1.0) if not is_zero_approx(segment_width) else 0.5
	var roots := find_x_roots(x, a.position.x, out_control.x, in_control.x, b.position.x)

	if not roots.is_empty():
		# The first monotonic interval is the deterministic branch policy.
		return roots[0]

	var t := seed

	for _iteration in range(12):
		var x_est := bezier_interpolate(
			a.position.x,
			out_control.x,
			in_control.x,
			b.position.x,
			t,
		)
		var error := x_est - x
		if absf(error) <= SOLVE_EPSILON:
			return {"t": t, "branch": -1, "branch_count": 0}

		var dx := bezier_derivative(
			a.position.x,
			out_control.x,
			in_control.x,
			b.position.x,
			t,
		)

		if absf(dx) < SOLVE_EPSILON:
			break

		var next_t := t - error / dx
		if next_t < 0.0 or next_t > 1.0:
			break
		t = next_t

	t = binary_search_t(x, a.position.x, out_control.x, in_control.x, b.position.x)
	return {"t": t, "branch": -1, "branch_count": 0}


static func find_x_roots(
		x: float,
		p0: float,
		p1: float,
		p2: float,
		p3: float,
) -> Array[Dictionary]:
	var coefficient_a := -p0 + 3.0 * p1 - 3.0 * p2 + p3
	var coefficient_b := 3.0 * p0 - 6.0 * p1 + 3.0 * p2
	var coefficient_c := -3.0 * p0 + 3.0 * p1
	var bounds: Array[float] = [0.0, 1.0]
	var derivative_a := 3.0 * coefficient_a
	var derivative_b := 2.0 * coefficient_b

	if absf(derivative_a) <= SOLVE_EPSILON:
		if absf(derivative_b) > SOLVE_EPSILON:
			append_x_root_bound(bounds, -coefficient_c / derivative_b)
	else:
		var discriminant := derivative_b * derivative_b - 4.0 * derivative_a * coefficient_c
		if discriminant >= 0.0:
			var root_delta := sqrt(discriminant)
			append_x_root_bound(bounds, (-derivative_b - root_delta) / (2.0 * derivative_a))
			append_x_root_bound(bounds, (-derivative_b + root_delta) / (2.0 * derivative_a))

	bounds.sort()
	var roots: Array[Dictionary] = []
	var branch_count := bounds.size() - 1
	for i in range(bounds.size() - 1):
		var low := bounds[i]
		var high := bounds[i + 1]
		var low_error := bezier_interpolate(p0, p1, p2, p3, low) - x
		var high_error := bezier_interpolate(p0, p1, p2, p3, high) - x

		if absf(low_error) <= SOLVE_EPSILON:
			append_x_root(roots, low, i, branch_count)
		if absf(high_error) <= SOLVE_EPSILON:
			append_x_root(roots, high, i, branch_count)
		if low_error * high_error < 0.0:
			for _iteration in range(40):
				var middle := (low + high) * 0.5
				var middle_error := bezier_interpolate(p0, p1, p2, p3, middle) - x
				if absf(middle_error) <= SOLVE_EPSILON:
					low = middle
					high = middle
					break
				if low_error * middle_error < 0.0:
					high = middle
				else:
					low = middle
					low_error = middle_error
			append_x_root(roots, (low + high) * 0.5, i, branch_count)

	return roots


static func append_x_root_bound(bounds: Array[float], value: float) -> void:
	if value > 0.0 and value < 1.0:
		bounds.append(value)


static func append_x_root(
		roots: Array[Dictionary],
		value: float,
		branch: int,
		branch_count: int,
) -> void:
	for root in roots:
		if is_equal_approx(root["t"], value):
			return
	roots.append({
		"t": value,
		"branch": branch,
		"branch_count": branch_count,
	})


static func binary_search_t(x: float, p0: float, p1: float, p2: float, p3: float) -> float:
	var low := 0.0
	var high := 1.0
	var mid := 0.5

	var increasing := p3 >= p0
	for _iteration in range(BINARY_ITERATIONS):
		mid = (low + high) * 0.5

		var x_est = bezier_interpolate(
			p0,
			p1,
			p2,
			p3,
			mid,
		)
		if absf(x_est - x) <= SOLVE_EPSILON:
			break

		if (x_est < x) == increasing:
			low = mid
		else:
			high = mid

	return mid


static func bezier_derivative(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var omt = 1.0 - t
	return 3.0 * omt * omt * (p1 - p0) \
	+ 6.0 * omt * t * (p2 - p1) \
	+ 3.0 * t * t * (p3 - p2)


static func bezier_interpolate(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var omt = 1.0 - t
	return omt * omt * omt * p0 + 3 * omt * omt * t * p1 + 3 * omt * t * t * p2 + t * t * t * p3

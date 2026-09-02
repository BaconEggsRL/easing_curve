#include "native_easing_curve.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

#include <algorithm>
#include <cmath>

namespace godot {

namespace {
constexpr double PI = 3.14159265358979323846;
constexpr double SOLVE_EPSILON = 0.00000001;
constexpr double SEGMENT_X_EPSILON = 0.000001;
constexpr int NEWTON_ITERATIONS = 8;
constexpr int BINARY_ITERATIONS = 32;
} // namespace

void NativeEasingCurve::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_transition", "transition"), &NativeEasingCurve::set_transition);
	ClassDB::bind_method(D_METHOD("get_transition"), &NativeEasingCurve::get_transition);
	ClassDB::bind_method(D_METHOD("set_ease_type", "ease_type"), &NativeEasingCurve::set_ease_type);
	ClassDB::bind_method(D_METHOD("get_ease_type"), &NativeEasingCurve::get_ease_type);
	ClassDB::bind_method(D_METHOD("set_amplitude", "amplitude"), &NativeEasingCurve::set_amplitude);
	ClassDB::bind_method(D_METHOD("get_amplitude"), &NativeEasingCurve::get_amplitude);
	ClassDB::bind_method(D_METHOD("set_period", "period"), &NativeEasingCurve::set_period);
	ClassDB::bind_method(D_METHOD("get_period"), &NativeEasingCurve::get_period);
	ClassDB::bind_method(D_METHOD("set_points", "points"), &NativeEasingCurve::set_points);
	ClassDB::bind_method(D_METHOD("get_points"), &NativeEasingCurve::get_points);
	ClassDB::bind_method(D_METHOD("add_point", "point"), &NativeEasingCurve::add_point);
	ClassDB::bind_method(D_METHOD("remove_point", "index"), &NativeEasingCurve::remove_point);
	ClassDB::bind_method(D_METHOD("cubic_bezier", "x1", "y1", "x2", "y2"), &NativeEasingCurve::cubic_bezier);
	ClassDB::bind_method(D_METHOD("sample", "offset"), &NativeEasingCurve::sample);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "transition", PROPERTY_HINT_ENUM, "Linear,Sine,Cubic,Elastic,Custom"), "set_transition", "get_transition");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ease_type", PROPERTY_HINT_ENUM, "In,Out,In Out,Out In"), "set_ease_type", "get_ease_type");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "amplitude", PROPERTY_HINT_RANGE, "0.001,10.0,0.001,or_greater"), "set_amplitude", "get_amplitude");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "period", PROPERTY_HINT_RANGE, "0.001,2.0,0.001,or_greater"), "set_period", "get_period");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "points", PROPERTY_HINT_ARRAY_TYPE, "NativeEasingCurvePoint"), "set_points", "get_points");

	BIND_ENUM_CONSTANT(TRANS_LINEAR);
	BIND_ENUM_CONSTANT(TRANS_SINE);
	BIND_ENUM_CONSTANT(TRANS_CUBIC);
	BIND_ENUM_CONSTANT(TRANS_ELASTIC);
	BIND_ENUM_CONSTANT(TRANS_CUSTOM);
	BIND_ENUM_CONSTANT(EASE_IN);
	BIND_ENUM_CONSTANT(EASE_OUT);
	BIND_ENUM_CONSTANT(EASE_IN_OUT);
	BIND_ENUM_CONSTANT(EASE_OUT_IN);
}

NativeEasingCurve::NativeEasingCurve() {
	cubic_bezier(1.0 / 3.0, 0.0, 2.0 / 3.0, 1.0);
	transition = TRANS_CUBIC;
}

NativeEasingCurve::~NativeEasingCurve() {
	disconnect_points();
}

void NativeEasingCurve::set_transition(Transition p_transition) {
	if (transition == p_transition) {
		return;
	}
	transition = p_transition;
	emit_changed();
}

NativeEasingCurve::Transition NativeEasingCurve::get_transition() const {
	return transition;
}

void NativeEasingCurve::set_ease_type(EaseType p_ease_type) {
	if (ease_type == p_ease_type) {
		return;
	}
	ease_type = p_ease_type;
	emit_changed();
}

NativeEasingCurve::EaseType NativeEasingCurve::get_ease_type() const {
	return ease_type;
}

void NativeEasingCurve::set_amplitude(double p_amplitude) {
	const double value = std::max(p_amplitude, 0.001);
	if (amplitude == value) {
		return;
	}
	amplitude = value;
	emit_changed();
}

double NativeEasingCurve::get_amplitude() const {
	return amplitude;
}

void NativeEasingCurve::set_period(double p_period) {
	const double value = std::max(p_period, 0.001);
	if (period == value) {
		return;
	}
	period = value;
	emit_changed();
}

double NativeEasingCurve::get_period() const {
	return period;
}

void NativeEasingCurve::set_points(const TypedArray<NativeEasingCurvePoint> &p_points) {
	disconnect_points();
	points = TypedArray<NativeEasingCurvePoint>(p_points.duplicate());
	reconnect_points();
	compile_segments();
	emit_changed();
}

TypedArray<NativeEasingCurvePoint> NativeEasingCurve::get_points() const {
	return TypedArray<NativeEasingCurvePoint>(points.duplicate());
}

void NativeEasingCurve::add_point(const Ref<NativeEasingCurvePoint> &p_point) {
	if (p_point.is_null()) {
		return;
	}
	TypedArray<NativeEasingCurvePoint> updated(points.duplicate());
	updated.append(p_point);
	set_points(updated);
}

void NativeEasingCurve::remove_point(int64_t p_index) {
	if (p_index < 0 || p_index >= points.size()) {
		return;
	}
	TypedArray<NativeEasingCurvePoint> updated(points.duplicate());
	updated.remove_at(p_index);
	set_points(updated);
}

void NativeEasingCurve::cubic_bezier(double p_x1, double p_y1, double p_x2, double p_y2) {
	Ref<NativeEasingCurvePoint> start;
	start.instantiate();
	start->set_right_control_point(Vector2(p_x1, p_y1));

	Ref<NativeEasingCurvePoint> end;
	end.instantiate();
	end->set_position(Vector2(1.0, 1.0));
	end->set_left_control_point(Vector2(p_x2, p_y2));

	TypedArray<NativeEasingCurvePoint> updated;
	updated.append(start);
	updated.append(end);
	set_points(updated);
	set_transition(TRANS_CUSTOM);
}

double NativeEasingCurve::sample(double p_offset) {
	const double offset = std::clamp(p_offset, 0.0, 1.0);
	return transition == TRANS_CUSTOM ? sample_custom(offset) : sample_builtin(offset);
}

void NativeEasingCurve::reconnect_points() {
	const Callable changed_callback = callable_mp(this, &NativeEasingCurve::on_point_changed);
	for (int64_t index = 0; index < points.size(); ++index) {
		Ref<NativeEasingCurvePoint> point = points[index];
		if (point.is_null()) {
			continue;
		}
		if (!point->is_connected("changed", changed_callback)) {
			point->connect("changed", changed_callback);
		}
		connected_points.push_back(point);
	}
}

void NativeEasingCurve::disconnect_points() {
	const Callable changed_callback = callable_mp(this, &NativeEasingCurve::on_point_changed);
	for (const Ref<NativeEasingCurvePoint> &point : connected_points) {
		if (point.is_valid() && point->is_connected("changed", changed_callback)) {
			point->disconnect("changed", changed_callback);
		}
	}
	connected_points.clear();
}

void NativeEasingCurve::on_point_changed() {
	compile_segments();
	emit_changed();
}

void NativeEasingCurve::compile_segments() {
	std::vector<Ref<NativeEasingCurvePoint>> ordered_points;
	ordered_points.reserve(points.size());
	for (int64_t index = 0; index < points.size(); ++index) {
		Ref<NativeEasingCurvePoint> point = points[index];
		if (point.is_valid()) {
			ordered_points.push_back(point);
		}
	}

	std::stable_sort(ordered_points.begin(), ordered_points.end(), [](const Ref<NativeEasingCurvePoint> &p_left, const Ref<NativeEasingCurvePoint> &p_right) {
		return p_left->get_position().x < p_right->get_position().x;
	});

	segments.clear();
	segments.reserve(ordered_points.size() > 1 ? ordered_points.size() - 1 : 0);
	for (size_t index = 0; index + 1 < ordered_points.size(); ++index) {
		const Ref<NativeEasingCurvePoint> &start = ordered_points[index];
		const Ref<NativeEasingCurvePoint> &end = ordered_points[index + 1];
		const Vector2 start_position = start->get_position();
		const Vector2 end_position = end->get_position();
		if (end_position.x - start_position.x <= SEGMENT_X_EPSILON) {
			continue;
		}

		double out_x = std::clamp(static_cast<double>(start->get_right_control_point().x), static_cast<double>(start_position.x), static_cast<double>(end_position.x));
		double in_x = std::clamp(static_cast<double>(end->get_left_control_point().x), static_cast<double>(start_position.x), static_cast<double>(end_position.x));
		if (out_x > in_x) {
			const double shared_x = (out_x + in_x) * 0.5;
			out_x = shared_x;
			in_x = shared_x;
		}

		segments.push_back({
			start_position.x,
			out_x,
			in_x,
			end_position.x,
			start_position.y,
			start->get_right_control_point().y,
			end->get_left_control_point().y,
			end_position.y,
		});
	}
	last_segment_index = -1;
}

double NativeEasingCurve::sample_builtin(double p_offset) const {
	switch (ease_type) {
		case EASE_IN:
			return sample_transition_in(p_offset);
		case EASE_OUT:
			return sample_transition_out(p_offset);
		case EASE_IN_OUT:
			if (transition == TRANS_ELASTIC) {
				return sample_elastic_in_out(p_offset);
			}
			return p_offset < 0.5 ? sample_transition_in(p_offset * 2.0) * 0.5 : 0.5 + sample_transition_out(p_offset * 2.0 - 1.0) * 0.5;
		case EASE_OUT_IN:
			return p_offset < 0.5 ? sample_transition_out(p_offset * 2.0) * 0.5 : 0.5 + sample_transition_in(p_offset * 2.0 - 1.0) * 0.5;
	}
	return p_offset;
}

double NativeEasingCurve::sample_transition_in(double p_offset) const {
	switch (transition) {
		case TRANS_SINE:
			return 1.0 - std::cos(p_offset * PI * 0.5);
		case TRANS_CUBIC:
			return p_offset * p_offset * p_offset;
		case TRANS_ELASTIC:
			return sample_elastic_in(p_offset);
		case TRANS_LINEAR:
		case TRANS_CUSTOM:
			return p_offset;
	}
	return p_offset;
}

double NativeEasingCurve::sample_transition_out(double p_offset) const {
	switch (transition) {
		case TRANS_SINE:
			return std::sin(p_offset * PI * 0.5);
		case TRANS_CUBIC: {
			const double shifted = p_offset - 1.0;
			return shifted * shifted * shifted + 1.0;
		}
		case TRANS_ELASTIC:
			return sample_elastic_out(p_offset);
		case TRANS_LINEAR:
		case TRANS_CUSTOM:
			return p_offset;
	}
	return p_offset;
}

double NativeEasingCurve::sample_elastic_in(double p_offset) const {
	if (p_offset == 0.0 || p_offset == 1.0) {
		return p_offset;
	}
	double adjusted_amplitude = amplitude;
	double phase;
	if (adjusted_amplitude < 1.0) {
		adjusted_amplitude = 1.0;
		phase = period * 0.25;
	} else {
		phase = period / (2.0 * PI) * std::asin(1.0 / adjusted_amplitude);
	}
	const double shifted = p_offset - 1.0;
	return -(adjusted_amplitude * std::pow(2.0, 10.0 * shifted) * std::sin((shifted - phase) * (2.0 * PI) / period));
}

double NativeEasingCurve::sample_elastic_out(double p_offset) const {
	if (p_offset == 0.0 || p_offset == 1.0) {
		return p_offset;
	}
	double adjusted_amplitude = amplitude;
	double phase;
	if (adjusted_amplitude < 1.0) {
		adjusted_amplitude = 1.0;
		phase = period * 0.25;
	} else {
		phase = period / (2.0 * PI) * std::asin(1.0 / adjusted_amplitude);
	}
	return adjusted_amplitude * std::pow(2.0, -10.0 * p_offset) * std::sin((p_offset - phase) * (2.0 * PI) / period) + 1.0;
}

double NativeEasingCurve::sample_elastic_in_out(double p_offset) const {
	if (p_offset == 0.0 || p_offset == 1.0) {
		return p_offset;
	}
	const double in_out_period = period * 1.5;
	const double phase = in_out_period * 0.25;
	double normalized = p_offset * 2.0;
	if (normalized < 1.0) {
		normalized -= 1.0;
		return -0.5 * amplitude * std::pow(2.0, 10.0 * normalized) * std::sin((normalized - phase) * (2.0 * PI) / in_out_period);
	}
	normalized -= 1.0;
	return amplitude * std::pow(2.0, -10.0 * normalized) * std::sin((normalized - phase) * (2.0 * PI) / in_out_period) * 0.5 + 1.0;
}

double NativeEasingCurve::sample_custom(double p_offset) {
	if (segments.empty()) {
		return 0.0;
	}

	if (last_segment_index >= 0 && last_segment_index < static_cast<int64_t>(segments.size())) {
		const Segment &last = segments[last_segment_index];
		if (p_offset >= last.x0 && p_offset <= last.x3) {
			const double t = solve_monotonic_t(p_offset, last);
			return bezier(last.y0, last.y1, last.y2, last.y3, t);
		}
	}

	const auto found = std::lower_bound(segments.begin(), segments.end(), p_offset, [](const Segment &p_segment, double p_value) {
		return p_segment.x3 < p_value;
	});
	if (found == segments.end() || p_offset < found->x0) {
		return 0.0;
	}

	last_segment_index = static_cast<int64_t>(std::distance(segments.begin(), found));
	const double t = solve_monotonic_t(p_offset, *found);
	return bezier(found->y0, found->y1, found->y2, found->y3, t);
}

double NativeEasingCurve::bezier(double p0, double p1, double p2, double p3, double p_t) {
	const double inverse = 1.0 - p_t;
	return inverse * inverse * inverse * p0 + 3.0 * inverse * inverse * p_t * p1 + 3.0 * inverse * p_t * p_t * p2 + p_t * p_t * p_t * p3;
}

double NativeEasingCurve::bezier_derivative(double p0, double p1, double p2, double p3, double p_t) {
	const double inverse = 1.0 - p_t;
	return 3.0 * inverse * inverse * (p1 - p0) + 6.0 * inverse * p_t * (p2 - p1) + 3.0 * p_t * p_t * (p3 - p2);
}

double NativeEasingCurve::solve_monotonic_t(double p_x, const Segment &p_segment) {
	if (std::abs(p_x - p_segment.x0) <= SOLVE_EPSILON) {
		return 0.0;
	}
	if (std::abs(p_x - p_segment.x3) <= SOLVE_EPSILON) {
		return 1.0;
	}

	double low = 0.0;
	double high = 1.0;
	double t = std::clamp((p_x - p_segment.x0) / (p_segment.x3 - p_segment.x0), 0.0, 1.0);
	for (int iteration = 0; iteration < NEWTON_ITERATIONS; ++iteration) {
		const double estimate = bezier(p_segment.x0, p_segment.x1, p_segment.x2, p_segment.x3, t);
		const double error = estimate - p_x;
		if (std::abs(error) <= SOLVE_EPSILON) {
			return t;
		}
		if (estimate < p_x) {
			low = t;
		} else {
			high = t;
		}
		const double derivative = bezier_derivative(p_segment.x0, p_segment.x1, p_segment.x2, p_segment.x3, t);
		if (std::abs(derivative) <= SOLVE_EPSILON) {
			break;
		}
		const double next_t = t - error / derivative;
		if (next_t <= low || next_t >= high) {
			break;
		}
		t = next_t;
	}

	for (int iteration = 0; iteration < BINARY_ITERATIONS; ++iteration) {
		t = (low + high) * 0.5;
		const double estimate = bezier(p_segment.x0, p_segment.x1, p_segment.x2, p_segment.x3, t);
		if (std::abs(estimate - p_x) <= SOLVE_EPSILON) {
			break;
		}
		if (estimate < p_x) {
			low = t;
		} else {
			high = t;
		}
	}
	return t;
}

} // namespace godot

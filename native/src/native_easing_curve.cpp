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
constexpr double BACK_OVERSHOOT = 1.70158;
constexpr int NEWTON_ITERATIONS = 8;
constexpr int BINARY_ITERATIONS = 32;

bool is_valid_transition(NativeEasingCurve::Transition p_transition) {
	return (p_transition >= NativeEasingCurve::TRANS_LINEAR && p_transition <= NativeEasingCurve::TRANS_SPRING) || p_transition == NativeEasingCurve::TRANS_CUSTOM;
}

bool is_valid_ease_type(NativeEasingCurve::EaseType p_ease_type) {
	return p_ease_type >= NativeEasingCurve::EASE_IN && p_ease_type <= NativeEasingCurve::EASE_OUT_IN;
}
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
	ClassDB::bind_method(D_METHOD("set_format_version", "format_version"), &NativeEasingCurve::set_format_version);
	ClassDB::bind_method(D_METHOD("get_format_version"), &NativeEasingCurve::get_format_version);
	ClassDB::bind_method(D_METHOD("set_points", "points"), &NativeEasingCurve::set_points);
	ClassDB::bind_method(D_METHOD("get_points"), &NativeEasingCurve::get_points);
	ClassDB::bind_method(D_METHOD("add_point", "point"), &NativeEasingCurve::add_point);
	ClassDB::bind_method(D_METHOD("remove_point", "index"), &NativeEasingCurve::remove_point);
	ClassDB::bind_method(D_METHOD("create_runtime_copy"), &NativeEasingCurve::create_runtime_copy);
	ClassDB::bind_method(D_METHOD("cubic_bezier", "x1", "y1", "x2", "y2"), &NativeEasingCurve::cubic_bezier);
	ClassDB::bind_method(D_METHOD("sample", "offset"), &NativeEasingCurve::sample);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "transition", PROPERTY_HINT_ENUM, "Linear:0,Sine:1,Quint:2,Quart:3,Quad:4,Expo:5,Elastic:6,Cubic:7,Circ:8,Bounce:9,Back:10,Spring:11,Custom:100"), "set_transition", "get_transition");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ease_type", PROPERTY_HINT_ENUM, "In,Out,In Out,Out In"), "set_ease_type", "get_ease_type");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "amplitude", PROPERTY_HINT_RANGE, "1.0,10.0,0.001,or_greater"), "set_amplitude", "get_amplitude");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "period", PROPERTY_HINT_RANGE, "0.01,2.0,0.001,or_greater"), "set_period", "get_period");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "format_version", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_format_version", "get_format_version");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "points", PROPERTY_HINT_ARRAY_TYPE, "NativeEasingCurvePoint"), "set_points", "get_points");
	ADD_SIGNAL(MethodInfo("points_changed", PropertyInfo(Variant::ARRAY, "points", PROPERTY_HINT_ARRAY_TYPE, "NativeEasingCurvePoint")));

	BIND_CONSTANT(FORMAT_VERSION);
	BIND_ENUM_CONSTANT(TRANS_LINEAR);
	BIND_ENUM_CONSTANT(TRANS_SINE);
	BIND_ENUM_CONSTANT(TRANS_QUINT);
	BIND_ENUM_CONSTANT(TRANS_QUART);
	BIND_ENUM_CONSTANT(TRANS_QUAD);
	BIND_ENUM_CONSTANT(TRANS_EXPO);
	BIND_ENUM_CONSTANT(TRANS_ELASTIC);
	BIND_ENUM_CONSTANT(TRANS_CUBIC);
	BIND_ENUM_CONSTANT(TRANS_CIRC);
	BIND_ENUM_CONSTANT(TRANS_BOUNCE);
	BIND_ENUM_CONSTANT(TRANS_BACK);
	BIND_ENUM_CONSTANT(TRANS_SPRING);
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
	if (!is_valid_transition(p_transition) || transition == p_transition) {
		return;
	}
	transition = p_transition;
	emit_changed();
}

NativeEasingCurve::Transition NativeEasingCurve::get_transition() const {
	return transition;
}

void NativeEasingCurve::set_ease_type(EaseType p_ease_type) {
	if (!is_valid_ease_type(p_ease_type) || ease_type == p_ease_type) {
		return;
	}
	ease_type = p_ease_type;
	emit_changed();
}

NativeEasingCurve::EaseType NativeEasingCurve::get_ease_type() const {
	return ease_type;
}

void NativeEasingCurve::set_amplitude(double p_amplitude) {
	if (!std::isfinite(p_amplitude)) {
		return;
	}
	const double value = std::max(p_amplitude, 1.0);
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
	if (!std::isfinite(p_period)) {
		return;
	}
	const double value = std::max(p_period, 0.01);
	if (period == value) {
		return;
	}
	period = value;
	emit_changed();
}

double NativeEasingCurve::get_period() const {
	return period;
}

void NativeEasingCurve::set_format_version(int64_t p_format_version) {
	if (p_format_version <= 0 || format_version == p_format_version) {
		return;
	}
	format_version = p_format_version;
	emit_changed();
}

int64_t NativeEasingCurve::get_format_version() const {
	return format_version;
}

void NativeEasingCurve::set_points(const TypedArray<NativeEasingCurvePoint> &p_points) {
	disconnect_points();
	points = TypedArray<NativeEasingCurvePoint>(p_points.duplicate());
	reconnect_points();
	compile_segments();
	emit_points_changed();
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

Ref<NativeEasingCurve> NativeEasingCurve::create_runtime_copy() const {
	Ref<NativeEasingCurve> runtime_copy;
	runtime_copy.instantiate();
	runtime_copy->set_format_version(format_version);
	runtime_copy->set_transition(transition);
	runtime_copy->set_ease_type(ease_type);
	runtime_copy->set_amplitude(amplitude);
	runtime_copy->set_period(period);
	runtime_copy->set_points(duplicate_points());
	return runtime_copy;
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
	if (!std::isfinite(p_offset)) {
		return 0.0;
	}
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

void NativeEasingCurve::emit_points_changed() {
	emit_signal("points_changed", get_points());
	emit_changed();
}

void NativeEasingCurve::on_point_changed() {
	compile_segments();
	emit_points_changed();
}

TypedArray<NativeEasingCurvePoint> NativeEasingCurve::duplicate_points() const {
	TypedArray<NativeEasingCurvePoint> duplicated;
	for (int64_t index = 0; index < points.size(); ++index) {
		Ref<NativeEasingCurvePoint> source = points[index];
		if (source.is_null()) {
			duplicated.append(Variant());
			continue;
		}

		Ref<NativeEasingCurvePoint> copy;
		copy.instantiate();
		copy->set_position(source->get_position());
		copy->set_left_control_point(source->get_left_control_point());
		copy->set_right_control_point(source->get_right_control_point());
		duplicated.append(copy);
	}
	return duplicated;
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
	std::vector<Ref<NativeEasingCurvePoint>> unique_points;
	unique_points.reserve(ordered_points.size());
	for (const Ref<NativeEasingCurvePoint> &point : ordered_points) {
		if (!unique_points.empty() && std::abs(point->get_position().x - unique_points.back()->get_position().x) <= SEGMENT_X_EPSILON) {
			unique_points.back() = point;
		} else {
			unique_points.push_back(point);
		}
	}

	segments.clear();
	segments.reserve(unique_points.size() > 1 ? unique_points.size() - 1 : 0);
	for (size_t index = 0; index + 1 < unique_points.size(); ++index) {
		const Ref<NativeEasingCurvePoint> &start = unique_points[index];
		const Ref<NativeEasingCurvePoint> &end = unique_points[index + 1];
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
			if (transition == TRANS_BACK) {
				return sample_back_in_out(p_offset);
			}
			if (transition == TRANS_EXPO) {
				return sample_expo_in_out(p_offset);
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
		case TRANS_QUINT: {
			const double squared = p_offset * p_offset;
			return squared * squared * p_offset;
		}
		case TRANS_QUART: {
			const double squared = p_offset * p_offset;
			return squared * squared;
		}
		case TRANS_QUAD:
			return p_offset * p_offset;
		case TRANS_EXPO:
			return p_offset == 0.0 ? 0.0 : std::pow(2.0, 10.0 * (p_offset - 1.0)) - 0.001;
		case TRANS_CUBIC:
			return p_offset * p_offset * p_offset;
		case TRANS_ELASTIC:
			return sample_elastic_in(p_offset);
		case TRANS_CIRC:
			return 1.0 - std::sqrt(std::max(0.0, 1.0 - p_offset * p_offset));
		case TRANS_BOUNCE:
			return 1.0 - sample_bounce_out(1.0 - p_offset);
		case TRANS_BACK:
			return p_offset * p_offset * ((BACK_OVERSHOOT + 1.0) * p_offset - BACK_OVERSHOOT);
		case TRANS_SPRING:
			return 1.0 - sample_spring_out(1.0 - p_offset);
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
		case TRANS_QUINT: {
			const double shifted = p_offset - 1.0;
			const double squared = shifted * shifted;
			return squared * squared * shifted + 1.0;
		}
		case TRANS_QUART: {
			const double shifted = p_offset - 1.0;
			const double squared = shifted * shifted;
			return 1.0 - squared * squared;
		}
		case TRANS_QUAD:
			return -p_offset * (p_offset - 2.0);
		case TRANS_EXPO:
			return p_offset == 1.0 ? 1.0 : 1.001 * (1.0 - std::pow(2.0, -10.0 * p_offset));
		case TRANS_CUBIC: {
			const double shifted = p_offset - 1.0;
			return shifted * shifted * shifted + 1.0;
		}
		case TRANS_ELASTIC:
			return sample_elastic_out(p_offset);
		case TRANS_CIRC: {
			const double shifted = p_offset - 1.0;
			return std::sqrt(std::max(0.0, 1.0 - shifted * shifted));
		}
		case TRANS_BOUNCE:
			return sample_bounce_out(p_offset);
		case TRANS_BACK: {
			const double shifted = p_offset - 1.0;
			return shifted * shifted * ((BACK_OVERSHOOT + 1.0) * shifted + BACK_OVERSHOOT) + 1.0;
		}
		case TRANS_SPRING:
			return sample_spring_out(p_offset);
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

double NativeEasingCurve::sample_back_in_out(double p_offset) {
	const double overshoot = BACK_OVERSHOOT * 1.525;
	double normalized = p_offset * 2.0;
	if (normalized < 1.0) {
		return 0.5 * normalized * normalized * ((overshoot + 1.0) * normalized - overshoot);
	}
	normalized -= 2.0;
	return 0.5 * (normalized * normalized * ((overshoot + 1.0) * normalized + overshoot) + 2.0);
}

double NativeEasingCurve::sample_expo_in_out(double p_offset) {
	if (p_offset == 0.0 || p_offset == 1.0) {
		return p_offset;
	}
	double normalized = p_offset * 2.0;
	if (normalized < 1.0) {
		return 0.5 * std::pow(2.0, 10.0 * (normalized - 1.0)) - 0.0005;
	}
	normalized -= 1.0;
	return 0.5 * 1.0005 * (-std::pow(2.0, -10.0 * normalized) + 2.0);
}

double NativeEasingCurve::sample_bounce_out(double p_offset) {
	if (p_offset < 1.0 / 2.75) {
		return 7.5625 * p_offset * p_offset;
	}
	if (p_offset < 2.0 / 2.75) {
		const double shifted = p_offset - 1.5 / 2.75;
		return 7.5625 * shifted * shifted + 0.75;
	}
	if (p_offset < 2.5 / 2.75) {
		const double shifted = p_offset - 2.25 / 2.75;
		return 7.5625 * shifted * shifted + 0.9375;
	}
	const double shifted = p_offset - 2.625 / 2.75;
	return 7.5625 * shifted * shifted + 0.984375;
}

double NativeEasingCurve::sample_spring_out(double p_offset) {
	const double inverse = 1.0 - p_offset;
	const double oscillation = std::sin(p_offset * PI * (0.2 + 2.5 * p_offset * p_offset * p_offset));
	return (oscillation * std::pow(inverse, 2.2) + p_offset) * (1.0 + 1.2 * inverse);
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

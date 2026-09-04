#include "native_easing_curve.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

#include <algorithm>
#include <cmath>
#include <limits>

namespace godot {

namespace {
constexpr double PI = 3.14159265358979323846;
constexpr double SOLVE_EPSILON = 0.00000001;
constexpr double SEGMENT_X_EPSILON = 0.000001;
constexpr int NEWTON_ITERATIONS = 8;
constexpr int BINARY_ITERATIONS = 32;

bool is_valid_transition(NativeEasingCurve::Transition p_transition) {
	return (p_transition >= NativeEasingCurve::TRANS_LINEAR && p_transition <= NativeEasingCurve::TRANS_SPRING) ||
			p_transition == NativeEasingCurve::TRANS_CUSTOM || p_transition == NativeEasingCurve::TRANS_CONSTANT ||
			p_transition == NativeEasingCurve::TRANS_STEP || p_transition == NativeEasingCurve::TRANS_POWER ||
			p_transition == NativeEasingCurve::TRANS_PHYSICS_SPRING;
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
	ClassDB::bind_method(D_METHOD("set_constant_value", "value"), &NativeEasingCurve::set_constant_value);
	ClassDB::bind_method(D_METHOD("get_constant_value"), &NativeEasingCurve::get_constant_value);
	ClassDB::bind_method(D_METHOD("set_overshoot", "overshoot"), &NativeEasingCurve::set_overshoot);
	ClassDB::bind_method(D_METHOD("get_overshoot"), &NativeEasingCurve::get_overshoot);
	ClassDB::bind_method(D_METHOD("set_steps", "steps"), &NativeEasingCurve::set_steps);
	ClassDB::bind_method(D_METHOD("get_steps"), &NativeEasingCurve::get_steps);
	ClassDB::bind_method(D_METHOD("set_from_start", "from_start"), &NativeEasingCurve::set_from_start);
	ClassDB::bind_method(D_METHOD("is_from_start"), &NativeEasingCurve::is_from_start);
	ClassDB::bind_method(D_METHOD("set_y_offset", "y_offset"), &NativeEasingCurve::set_y_offset);
	ClassDB::bind_method(D_METHOD("get_y_offset"), &NativeEasingCurve::get_y_offset);
	ClassDB::bind_method(D_METHOD("set_power", "power"), &NativeEasingCurve::set_power);
	ClassDB::bind_method(D_METHOD("get_power"), &NativeEasingCurve::get_power);
	ClassDB::bind_method(D_METHOD("set_frequency", "frequency"), &NativeEasingCurve::set_frequency);
	ClassDB::bind_method(D_METHOD("get_frequency"), &NativeEasingCurve::get_frequency);
	ClassDB::bind_method(D_METHOD("set_decay", "decay"), &NativeEasingCurve::set_decay);
	ClassDB::bind_method(D_METHOD("get_decay"), &NativeEasingCurve::get_decay);
	ClassDB::bind_method(D_METHOD("set_stiffness", "stiffness"), &NativeEasingCurve::set_stiffness);
	ClassDB::bind_method(D_METHOD("get_stiffness"), &NativeEasingCurve::get_stiffness);
	ClassDB::bind_method(D_METHOD("set_damping", "damping"), &NativeEasingCurve::set_damping);
	ClassDB::bind_method(D_METHOD("get_damping"), &NativeEasingCurve::get_damping);
	ClassDB::bind_method(D_METHOD("set_mass", "mass"), &NativeEasingCurve::set_mass);
	ClassDB::bind_method(D_METHOD("get_mass"), &NativeEasingCurve::get_mass);
	ClassDB::bind_method(D_METHOD("set_velocity", "velocity"), &NativeEasingCurve::set_velocity);
	ClassDB::bind_method(D_METHOD("get_velocity"), &NativeEasingCurve::get_velocity);
	ClassDB::bind_method(D_METHOD("set_reverse", "reverse"), &NativeEasingCurve::set_reverse);
	ClassDB::bind_method(D_METHOD("is_reverse"), &NativeEasingCurve::is_reverse);
	ClassDB::bind_method(D_METHOD("set_invert", "invert"), &NativeEasingCurve::set_invert);
	ClassDB::bind_method(D_METHOD("is_invert"), &NativeEasingCurve::is_invert);
	ClassDB::bind_method(D_METHOD("set_format_version", "format_version"), &NativeEasingCurve::set_format_version);
	ClassDB::bind_method(D_METHOD("get_format_version"), &NativeEasingCurve::get_format_version);
	ClassDB::bind_method(D_METHOD("get_format_status"), &NativeEasingCurve::get_format_status);
	ClassDB::bind_method(D_METHOD("is_format_supported"), &NativeEasingCurve::is_format_supported);
	ClassDB::bind_method(D_METHOD("set_points", "points"), &NativeEasingCurve::set_points);
	ClassDB::bind_method(D_METHOD("get_points"), &NativeEasingCurve::get_points);
	ClassDB::bind_method(D_METHOD("get_point_count"), &NativeEasingCurve::get_point_count);
	ClassDB::bind_method(D_METHOD("get_point", "index"), &NativeEasingCurve::get_point);
	ClassDB::bind_method(D_METHOD("set_point", "index", "point"), &NativeEasingCurve::set_point);
	ClassDB::bind_method(D_METHOD("insert_point", "index", "point"), &NativeEasingCurve::insert_point);
	ClassDB::bind_method(D_METHOD("add_point", "point"), &NativeEasingCurve::add_point);
	ClassDB::bind_method(D_METHOD("remove_point", "index"), &NativeEasingCurve::remove_point);
	ClassDB::bind_method(D_METHOD("clear_points"), &NativeEasingCurve::clear_points);
	ClassDB::bind_method(D_METHOD("capture_point_states"), &NativeEasingCurve::capture_point_states);
	ClassDB::bind_method(D_METHOD("apply_point_states", "states"), &NativeEasingCurve::apply_point_states);
	ClassDB::bind_method(D_METHOD("apply_point_topology_snapshot", "point_order", "point_states"), &NativeEasingCurve::apply_point_topology_snapshot);
	ClassDB::bind_method(D_METHOD("create_runtime_copy"), &NativeEasingCurve::create_runtime_copy);
	ClassDB::bind_method(D_METHOD("cubic_bezier", "x1", "y1", "x2", "y2"), &NativeEasingCurve::cubic_bezier);
	ClassDB::bind_method(D_METHOD("bake_callable", "callable", "resolution"), &NativeEasingCurve::bake_callable, DEFVAL(40));
	ClassDB::bind_method(D_METHOD("sample", "offset"), &NativeEasingCurve::sample);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "transition", PROPERTY_HINT_ENUM, "Linear:0,Sine:1,Quint:2,Quart:3,Quad:4,Expo:5,Elastic:6,Cubic:7,Circ:8,Bounce:9,Back:10,Spring:11,Custom:100,Constant:101,Step:104,Power:105,Physics Spring:106"), "set_transition", "get_transition");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ease_type", PROPERTY_HINT_ENUM, "In,Out,In Out,Out In"), "set_ease_type", "get_ease_type");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "amplitude", PROPERTY_HINT_RANGE, "1.0,10.0,0.001,or_greater"), "set_amplitude", "get_amplitude");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "period", PROPERTY_HINT_RANGE, "0.01,2.0,0.001,or_greater"), "set_period", "get_period");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "constant_value", PROPERTY_HINT_RANGE, "0.0,1.0,0.001"), "set_constant_value", "get_constant_value");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "overshoot", PROPERTY_HINT_RANGE, "0.0,5.0,0.001"), "set_overshoot", "get_overshoot");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "steps", PROPERTY_HINT_RANGE, "0,100,1"), "set_steps", "get_steps");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "from_start"), "set_from_start", "is_from_start");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "y_offset", PROPERTY_HINT_RANGE, "0.0,1.0,0.001"), "set_y_offset", "get_y_offset");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "power", PROPERTY_HINT_RANGE, "0.001,1000.0,0.001,exp"), "set_power", "get_power");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "frequency", PROPERTY_HINT_RANGE, "0.0,10.0,0.001"), "set_frequency", "get_frequency");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "decay", PROPERTY_HINT_RANGE, "0.1,10.0,0.001"), "set_decay", "get_decay");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "stiffness", PROPERTY_HINT_RANGE, "0.000001,1000.0,0.1"), "set_stiffness", "get_stiffness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "damping", PROPERTY_HINT_RANGE, "0.0,100.0,0.1"), "set_damping", "get_damping");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mass", PROPERTY_HINT_RANGE, "0.000001,10.0,0.1"), "set_mass", "get_mass");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "velocity", PROPERTY_HINT_RANGE, "-30.0,30.0,0.1,or_less,or_greater"), "set_velocity", "get_velocity");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "reverse"), "set_reverse", "is_reverse");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "invert"), "set_invert", "is_invert");
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
	BIND_ENUM_CONSTANT(TRANS_CONSTANT);
	BIND_ENUM_CONSTANT(TRANS_JITTER);
	BIND_ENUM_CONSTANT(TRANS_IRREGULAR);
	BIND_ENUM_CONSTANT(TRANS_STEP);
	BIND_ENUM_CONSTANT(TRANS_POWER);
	BIND_ENUM_CONSTANT(TRANS_PHYSICS_SPRING);
	BIND_ENUM_CONSTANT(TRANS_CSS_LINEAR);
	BIND_ENUM_CONSTANT(TRANS_CSS_CUBIC_BEZIER);
	BIND_ENUM_CONSTANT(EASE_IN);
	BIND_ENUM_CONSTANT(EASE_OUT);
	BIND_ENUM_CONSTANT(EASE_IN_OUT);
	BIND_ENUM_CONSTANT(EASE_OUT_IN);
	BIND_ENUM_CONSTANT(FORMAT_STATUS_INVALID);
	BIND_ENUM_CONSTANT(FORMAT_STATUS_OLDER);
	BIND_ENUM_CONSTANT(FORMAT_STATUS_CURRENT);
	BIND_ENUM_CONSTANT(FORMAT_STATUS_NEWER);
}

NativeEasingCurve::NativeEasingCurve() {
	cubic_bezier(1.0 / 3.0, 0.0, 2.0 / 3.0, 1.0);
	transition = TRANS_LINEAR;
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

void NativeEasingCurve::set_constant_value(double p_value) {
	if (!std::isfinite(p_value)) {
		return;
	}
	const double value = std::clamp(p_value, 0.0, 1.0);
	if (constant_value == value) {
		return;
	}
	constant_value = value;
	emit_changed();
}

double NativeEasingCurve::get_constant_value() const { return constant_value; }

void NativeEasingCurve::set_overshoot(double p_overshoot) {
	if (!std::isfinite(p_overshoot)) {
		return;
	}
	const double value = std::clamp(p_overshoot, 0.0, 5.0);
	if (overshoot == value) {
		return;
	}
	overshoot = value;
	emit_changed();
}

double NativeEasingCurve::get_overshoot() const { return overshoot; }

void NativeEasingCurve::set_steps(int64_t p_steps) {
	const int64_t value = std::clamp<int64_t>(p_steps, 0, 100);
	if (steps == value) {
		return;
	}
	steps = value;
	emit_changed();
}

int64_t NativeEasingCurve::get_steps() const { return steps; }

void NativeEasingCurve::set_from_start(bool p_from_start) {
	if (from_start == p_from_start) {
		return;
	}
	from_start = p_from_start;
	emit_changed();
}

bool NativeEasingCurve::is_from_start() const { return from_start; }

void NativeEasingCurve::set_y_offset(double p_y_offset) {
	if (!std::isfinite(p_y_offset)) {
		return;
	}
	const double value = std::clamp(p_y_offset, 0.0, 1.0);
	if (y_offset == value) {
		return;
	}
	y_offset = value;
	emit_changed();
}

double NativeEasingCurve::get_y_offset() const { return y_offset; }

void NativeEasingCurve::set_power(double p_power) {
	if (!std::isfinite(p_power)) {
		return;
	}
	const double value = std::max(p_power, 0.001);
	if (power == value) {
		return;
	}
	power = value;
	emit_changed();
}

double NativeEasingCurve::get_power() const { return power; }

void NativeEasingCurve::set_frequency(double p_frequency) {
	if (!std::isfinite(p_frequency)) {
		return;
	}
	const double value = std::clamp(p_frequency, 0.0, 10.0);
	if (frequency == value) {
		return;
	}
	frequency = value;
	emit_changed();
}

double NativeEasingCurve::get_frequency() const { return frequency; }

void NativeEasingCurve::set_decay(double p_decay) {
	if (!std::isfinite(p_decay)) {
		return;
	}
	const double value = std::max(p_decay, 0.1);
	if (decay == value) {
		return;
	}
	decay = value;
	emit_changed();
}

double NativeEasingCurve::get_decay() const { return decay; }

void NativeEasingCurve::set_stiffness(double p_stiffness) {
	if (!std::isfinite(p_stiffness)) {
		return;
	}
	const double value = std::max(p_stiffness, 0.000001);
	if (stiffness == value) {
		return;
	}
	stiffness = value;
	emit_changed();
}

double NativeEasingCurve::get_stiffness() const { return stiffness; }

void NativeEasingCurve::set_damping(double p_damping) {
	if (!std::isfinite(p_damping)) {
		return;
	}
	const double value = std::max(p_damping, 0.0);
	if (damping == value) {
		return;
	}
	damping = value;
	emit_changed();
}

double NativeEasingCurve::get_damping() const { return damping; }

void NativeEasingCurve::set_mass(double p_mass) {
	if (!std::isfinite(p_mass)) {
		return;
	}
	const double value = std::max(p_mass, 0.000001);
	if (mass == value) {
		return;
	}
	mass = value;
	emit_changed();
}

double NativeEasingCurve::get_mass() const { return mass; }

void NativeEasingCurve::set_velocity(double p_velocity) {
	if (!std::isfinite(p_velocity) || velocity == p_velocity) {
		return;
	}
	velocity = p_velocity;
	emit_changed();
}

double NativeEasingCurve::get_velocity() const { return velocity; }

void NativeEasingCurve::set_reverse(bool p_reverse) {
	if (reverse == p_reverse) {
		return;
	}
	reverse = p_reverse;
	emit_changed();
}

bool NativeEasingCurve::is_reverse() const { return reverse; }

void NativeEasingCurve::set_invert(bool p_invert) {
	if (invert == p_invert) {
		return;
	}
	invert = p_invert;
	emit_changed();
}

bool NativeEasingCurve::is_invert() const { return invert; }

void NativeEasingCurve::set_format_version(int64_t p_format_version) {
	if (format_version == p_format_version) {
		return;
	}
	format_version = p_format_version;
	emit_changed();
}

int64_t NativeEasingCurve::get_format_version() const {
	return format_version;
}

NativeEasingCurve::FormatStatus NativeEasingCurve::get_format_status() const {
	if (format_version <= 0) {
		return FORMAT_STATUS_INVALID;
	}
	if (format_version < FORMAT_VERSION) {
		return FORMAT_STATUS_OLDER;
	}
	if (format_version > FORMAT_VERSION) {
		return FORMAT_STATUS_NEWER;
	}
	return FORMAT_STATUS_CURRENT;
}

bool NativeEasingCurve::is_format_supported() const {
	return get_format_status() == FORMAT_STATUS_CURRENT;
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

int64_t NativeEasingCurve::get_point_count() const {
	return points.size();
}

Ref<NativeEasingCurvePoint> NativeEasingCurve::get_point(int64_t p_index) const {
	if (p_index < 0 || p_index >= points.size()) {
		return Ref<NativeEasingCurvePoint>();
	}
	return points[p_index];
}

bool NativeEasingCurve::set_point(int64_t p_index, const Ref<NativeEasingCurvePoint> &p_point) {
	if (p_index < 0 || p_index >= points.size() || p_point.is_null()) {
		return false;
	}
	if (Ref<NativeEasingCurvePoint>(points[p_index]) == p_point) {
		return true;
	}
	TypedArray<NativeEasingCurvePoint> updated(points.duplicate());
	updated[p_index] = p_point;
	set_points(updated);
	return true;
}

bool NativeEasingCurve::insert_point(int64_t p_index, const Ref<NativeEasingCurvePoint> &p_point) {
	if (p_index < 0 || p_index > points.size() || p_point.is_null()) {
		return false;
	}
	TypedArray<NativeEasingCurvePoint> updated(points.duplicate());
	updated.insert(p_index, p_point);
	set_points(updated);
	return true;
}

bool NativeEasingCurve::add_point(const Ref<NativeEasingCurvePoint> &p_point) {
	if (p_point.is_null()) {
		return false;
	}
	TypedArray<NativeEasingCurvePoint> updated(points.duplicate());
	updated.append(p_point);
	set_points(updated);
	return true;
}

bool NativeEasingCurve::remove_point(int64_t p_index) {
	if (p_index < 0 || p_index >= points.size()) {
		return false;
	}
	TypedArray<NativeEasingCurvePoint> updated(points.duplicate());
	updated.remove_at(p_index);
	set_points(updated);
	return true;
}

void NativeEasingCurve::clear_points() {
	if (points.is_empty()) {
		return;
	}
	set_points(TypedArray<NativeEasingCurvePoint>());
}

Array NativeEasingCurve::capture_point_states() const {
	Array states;
	states.resize(points.size());
	for (int64_t index = 0; index < points.size(); ++index) {
		Ref<NativeEasingCurvePoint> point = points[index];
		states[index] = point.is_valid() ? point->capture_state() : Dictionary();
	}
	return states;
}

bool NativeEasingCurve::apply_point_states(const Array &p_states) {
	if (p_states.size() != points.size()) {
		return false;
	}
	for (int64_t index = 0; index < points.size(); ++index) {
		Ref<NativeEasingCurvePoint> point = points[index];
		if (point.is_null() || p_states[index].get_type() != Variant::DICTIONARY) {
			return false;
		}
		Ref<NativeEasingCurvePoint> validator;
		validator.instantiate();
		if (!validator->apply_state(p_states[index])) {
			return false;
		}
	}

	applying_point_states = true;
	point_state_changed_while_applying = false;
	for (int64_t index = 0; index < points.size(); ++index) {
		Ref<NativeEasingCurvePoint> point = points[index];
		point->apply_state(p_states[index]);
	}
	applying_point_states = false;
	if (point_state_changed_while_applying) {
		compile_segments();
		emit_points_changed();
	}
	return true;
}

bool NativeEasingCurve::apply_point_topology_snapshot(const Array &p_point_order, const Array &p_point_states) {
	if (p_point_order.size() != p_point_states.size()) {
		return false;
	}

	TypedArray<NativeEasingCurvePoint> validated_points;
	validated_points.resize(p_point_order.size());
	bool changed = p_point_order.size() != points.size();
	for (int64_t index = 0; index < p_point_order.size(); ++index) {
		Ref<NativeEasingCurvePoint> point = p_point_order[index];
		if (point.is_null() || p_point_states[index].get_type() != Variant::DICTIONARY) {
			return false;
		}
		const Dictionary state = p_point_states[index];
		const Variant state_position = state.get(StringName("position"), Variant());
		const Variant state_left = state.get(StringName("left_control_point"), Variant());
		const Variant state_right = state.get(StringName("right_control_point"), Variant());
		const Variant state_mode = state.get(StringName("handle_mode"), Variant());
		const Variant state_left_linear = state.get(StringName("left_force_linear"), Variant());
		const Variant state_right_linear = state.get(StringName("right_force_linear"), Variant());
		const Variant state_locks = state.get(StringName("locked"), Variant());
		if (state_position.get_type() != Variant::VECTOR2 || state_left.get_type() != Variant::VECTOR2 || state_right.get_type() != Variant::VECTOR2 || state_mode.get_type() != Variant::INT || state_left_linear.get_type() != Variant::BOOL || state_right_linear.get_type() != Variant::BOOL || state_locks.get_type() != Variant::DICTIONARY) {
			return false;
		}
		for (int64_t previous = 0; previous < index; ++previous) {
			if (Ref<NativeEasingCurvePoint>(validated_points[previous]) == point) {
				return false;
			}
		}

		Ref<NativeEasingCurvePoint> validator;
		validator.instantiate();
		if (!validator->apply_state(state)) {
			return false;
		}
		validated_points[index] = point;
		if (!changed && (Ref<NativeEasingCurvePoint>(points[index]) != point || point->capture_state() != state)) {
			changed = true;
		}
	}

	if (!changed) {
		return true;
	}

	disconnect_points();
	points = validated_points;
	for (int64_t index = 0; index < points.size(); ++index) {
		Ref<NativeEasingCurvePoint> point = points[index];
		point->apply_state(p_point_states[index]);
	}
	reconnect_points();
	compile_segments();
	emit_points_changed();
	return true;
}

Ref<NativeEasingCurve> NativeEasingCurve::create_runtime_copy() const {
	Ref<NativeEasingCurve> runtime_copy;
	runtime_copy.instantiate();
	runtime_copy->set_format_version(get_format_version());
	runtime_copy->set_transition(transition);
	runtime_copy->set_ease_type(ease_type);
	runtime_copy->set_amplitude(amplitude);
	runtime_copy->set_period(period);
	runtime_copy->set_constant_value(constant_value);
	runtime_copy->set_overshoot(overshoot);
	runtime_copy->set_steps(steps);
	runtime_copy->set_from_start(from_start);
	runtime_copy->set_y_offset(y_offset);
	runtime_copy->set_power(power);
	runtime_copy->set_frequency(frequency);
	runtime_copy->set_decay(decay);
	runtime_copy->set_stiffness(stiffness);
	runtime_copy->set_damping(damping);
	runtime_copy->set_mass(mass);
	runtime_copy->set_velocity(velocity);
	runtime_copy->set_reverse(reverse);
	runtime_copy->set_invert(invert);
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

bool NativeEasingCurve::bake_callable(const Callable &p_callable, int64_t p_resolution) {
	if (!p_callable.is_valid() || p_resolution < 1 || p_resolution > 4096) {
		return false;
	}

	std::vector<Vector2> samples;
	samples.reserve(p_resolution + 1);
	for (int64_t index = 0; index <= p_resolution; ++index) {
		const double x = static_cast<double>(index) / p_resolution;
		const Variant result = p_callable.call(x);
		if (result.get_type() != Variant::FLOAT && result.get_type() != Variant::INT) {
			return false;
		}
		const double y = result;
		if (!std::isfinite(y)) {
			return false;
		}
		samples.emplace_back(static_cast<real_t>(x), static_cast<real_t>(y));
	}

	std::vector<Ref<NativeEasingCurvePoint>> baked_points;
	baked_points.reserve(samples.size());
	for (const Vector2 &sample_position : samples) {
		Ref<NativeEasingCurvePoint> point;
		point.instantiate();
		point->set_position(sample_position);
		baked_points.push_back(point);
	}
	for (size_t index = 0; index + 1 < baked_points.size(); ++index) {
		const Vector2 delta = samples[index + 1] - samples[index];
		baked_points[index]->set_right_control_point(samples[index] + delta / 3.0);
		baked_points[index + 1]->set_left_control_point(samples[index] + delta * (2.0 / 3.0));
	}

	TypedArray<NativeEasingCurvePoint> baked_array;
	for (const Ref<NativeEasingCurvePoint> &point : baked_points) {
		baked_array.append(point);
	}
	set_points(baked_array);
	set_transition(TRANS_CUSTOM);
	return true;
}

double NativeEasingCurve::sample(double p_offset) {
	if (!is_format_supported()) {
		return std::numeric_limits<double>::quiet_NaN();
	}
	if (!std::isfinite(p_offset)) {
		return 0.0;
	}
	double offset = std::clamp(p_offset, 0.0, 1.0);
	if (reverse) {
		offset = 1.0 - offset;
	}
	double result = transition == TRANS_CUSTOM ? sample_custom(offset) : sample_builtin(offset);
	if (invert) {
		result = 1.0 - result;
	}
	return result;
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
	if (applying_point_states) {
		point_state_changed_while_applying = true;
		return;
	}
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
		copy->apply_state(source->capture_state());
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
	if (transition == TRANS_CONSTANT) {
		return constant_value;
	}
	if (transition == TRANS_STEP) {
		return sample_step(p_offset);
	}
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
			return p_offset * p_offset * ((overshoot + 1.0) * p_offset - overshoot);
		case TRANS_SPRING:
			return 1.0 - sample_spring_out(1.0 - p_offset);
		case TRANS_POWER:
			return std::pow(p_offset, power);
		case TRANS_PHYSICS_SPRING:
			return 1.0 - sample_physics_spring_out(1.0 - p_offset);
		case TRANS_LINEAR:
		case TRANS_CUSTOM:
		case TRANS_CONSTANT:
		case TRANS_STEP:
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
			return shifted * shifted * ((overshoot + 1.0) * shifted + overshoot) + 1.0;
		}
		case TRANS_SPRING:
			return sample_spring_out(p_offset);
		case TRANS_POWER:
			return 1.0 - std::pow(1.0 - p_offset, power);
		case TRANS_PHYSICS_SPRING:
			return sample_physics_spring_out(p_offset);
		case TRANS_LINEAR:
		case TRANS_CUSTOM:
		case TRANS_CONSTANT:
		case TRANS_STEP:
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

double NativeEasingCurve::sample_back_in_out(double p_offset) const {
	const double in_out_overshoot = overshoot * 1.525;
	double normalized = p_offset * 2.0;
	if (normalized < 1.0) {
		return 0.5 * normalized * normalized * ((in_out_overshoot + 1.0) * normalized - in_out_overshoot);
	}
	normalized -= 2.0;
	return 0.5 * (normalized * normalized * ((in_out_overshoot + 1.0) * normalized + in_out_overshoot) + 2.0);
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

double NativeEasingCurve::sample_spring_out(double p_offset) const {
	const double inverse = 1.0 - p_offset;
	const double oscillation = std::sin(p_offset * PI * (0.2 + frequency * p_offset * p_offset * p_offset));
	return (oscillation * std::pow(inverse, decay) + p_offset) * (1.0 + 1.2 * inverse);
}

double NativeEasingCurve::sample_physics_spring_out(double p_offset) const {
	if (p_offset <= 0.0 || p_offset >= 1.0) {
		return p_offset;
	}
	const double natural_frequency = std::sqrt(stiffness / mass);
	const double damping_ratio = damping / (2.0 * std::sqrt(stiffness * mass));
	constexpr double initial_displacement = -1.0;
	double displacement;
	if (damping_ratio < 1.0 - 0.000001) {
		const double damped_frequency = natural_frequency * std::sqrt(1.0 - damping_ratio * damping_ratio);
		const double coefficient = (velocity + damping_ratio * natural_frequency * initial_displacement) / damped_frequency;
		displacement = std::exp(-damping_ratio * natural_frequency * p_offset) *
				(initial_displacement * std::cos(damped_frequency * p_offset) + coefficient * std::sin(damped_frequency * p_offset));
	} else if (damping_ratio > 1.0 + 0.000001) {
		const double root = std::sqrt(damping_ratio * damping_ratio - 1.0);
		const double r1 = -natural_frequency * (damping_ratio - root);
		const double r2 = -natural_frequency * (damping_ratio + root);
		const double c1 = (velocity - r2 * initial_displacement) / (r1 - r2);
		const double c2 = initial_displacement - c1;
		displacement = c1 * std::exp(r1 * p_offset) + c2 * std::exp(r2 * p_offset);
	} else {
		const double coefficient = velocity + natural_frequency * initial_displacement;
		displacement = (initial_displacement + coefficient * p_offset) * std::exp(-natural_frequency * p_offset);
	}
	return 1.0 + displacement;
}

double NativeEasingCurve::sample_step(double p_offset) const {
	if (steps <= 0) {
		return y_offset;
	}
	const double stepped = (from_start ? std::ceil(p_offset * steps) : std::floor(p_offset * steps)) / steps;
	return std::clamp(stepped + y_offset, 0.0, 1.0);
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

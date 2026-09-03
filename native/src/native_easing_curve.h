#ifndef EASING_CURVE_NATIVE_EASING_CURVE_H
#define EASING_CURVE_NATIVE_EASING_CURVE_H

#include "native_easing_curve_point.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <vector>

namespace godot {

class NativeEasingCurve : public Resource {
	GDCLASS(NativeEasingCurve, Resource)

public:
	enum {
		FORMAT_VERSION = 2,
	};

	enum Transition {
		TRANS_LINEAR = 0,
		TRANS_SINE = 1,
		TRANS_QUINT = 2,
		TRANS_QUART = 3,
		TRANS_QUAD = 4,
		TRANS_EXPO = 5,
		TRANS_ELASTIC = 6,
		TRANS_CUBIC = 7,
		TRANS_CIRC = 8,
		TRANS_BOUNCE = 9,
		TRANS_BACK = 10,
		TRANS_SPRING = 11,
		TRANS_CUSTOM = 100,
		TRANS_CONSTANT = 101,
		TRANS_JITTER = 102,
		TRANS_IRREGULAR = 103,
		TRANS_STEP = 104,
		TRANS_POWER = 105,
		TRANS_PHYSICS_SPRING = 106,
		TRANS_CSS_LINEAR = 107,
		TRANS_CSS_CUBIC_BEZIER = 108,
	};

	enum EaseType {
		EASE_IN = 0,
		EASE_OUT = 1,
		EASE_IN_OUT = 2,
		EASE_OUT_IN = 3,
	};

private:
	struct Segment {
		double x0;
		double x1;
		double x2;
		double x3;
		double y0;
		double y1;
		double y2;
		double y3;
	};

	Transition transition = TRANS_CUBIC;
	EaseType ease_type = EASE_IN;
	double amplitude = 1.0;
	double period = 0.3;
	double constant_value = 0.5;
	double overshoot = 1.70158;
	int64_t steps = 4;
	bool from_start = false;
	double y_offset = 0.0;
	double power = 2.0;
	double frequency = 2.5;
	double decay = 2.2;
	double stiffness = 100.0;
	double damping = 10.0;
	double mass = 1.0;
	double velocity = 0.0;
	bool reverse = false;
	bool invert = false;
	int64_t format_version = FORMAT_VERSION;
	TypedArray<NativeEasingCurvePoint> points;
	std::vector<Ref<NativeEasingCurvePoint>> connected_points;
	std::vector<Segment> segments;
	int64_t last_segment_index = -1;
	bool applying_point_states = false;
	bool point_state_changed_while_applying = false;

	void reconnect_points();
	void disconnect_points();
	void emit_points_changed();
	void compile_segments();
	void on_point_changed();
	TypedArray<NativeEasingCurvePoint> duplicate_points() const;

	double sample_builtin(double p_offset) const;
	double sample_custom(double p_offset);
	double sample_transition_in(double p_offset) const;
	double sample_transition_out(double p_offset) const;
	double sample_elastic_in(double p_offset) const;
	double sample_elastic_out(double p_offset) const;
	double sample_elastic_in_out(double p_offset) const;
	double sample_back_in_out(double p_offset) const;
	static double sample_expo_in_out(double p_offset);
	static double sample_bounce_out(double p_offset);
	double sample_spring_out(double p_offset) const;
	double sample_physics_spring_out(double p_offset) const;
	double sample_step(double p_offset) const;

	static double bezier(double p0, double p1, double p2, double p3, double p_t);
	static double bezier_derivative(double p0, double p1, double p2, double p3, double p_t);
	static double solve_monotonic_t(double p_x, const Segment &p_segment);

protected:
	static void _bind_methods();

public:
	NativeEasingCurve();
	~NativeEasingCurve();

	void set_transition(Transition p_transition);
	Transition get_transition() const;

	void set_ease_type(EaseType p_ease_type);
	EaseType get_ease_type() const;

	void set_amplitude(double p_amplitude);
	double get_amplitude() const;

	void set_period(double p_period);
	double get_period() const;
	void set_constant_value(double p_value);
	double get_constant_value() const;
	void set_overshoot(double p_overshoot);
	double get_overshoot() const;
	void set_steps(int64_t p_steps);
	int64_t get_steps() const;
	void set_from_start(bool p_from_start);
	bool is_from_start() const;
	void set_y_offset(double p_y_offset);
	double get_y_offset() const;
	void set_power(double p_power);
	double get_power() const;
	void set_frequency(double p_frequency);
	double get_frequency() const;
	void set_decay(double p_decay);
	double get_decay() const;
	void set_stiffness(double p_stiffness);
	double get_stiffness() const;
	void set_damping(double p_damping);
	double get_damping() const;
	void set_mass(double p_mass);
	double get_mass() const;
	void set_velocity(double p_velocity);
	double get_velocity() const;
	void set_reverse(bool p_reverse);
	bool is_reverse() const;
	void set_invert(bool p_invert);
	bool is_invert() const;
	void set_format_version(int64_t p_format_version);
	int64_t get_format_version() const;

	void set_points(const TypedArray<NativeEasingCurvePoint> &p_points);
	TypedArray<NativeEasingCurvePoint> get_points() const;
	int64_t get_point_count() const;
	Ref<NativeEasingCurvePoint> get_point(int64_t p_index) const;
	bool set_point(int64_t p_index, const Ref<NativeEasingCurvePoint> &p_point);
	bool insert_point(int64_t p_index, const Ref<NativeEasingCurvePoint> &p_point);
	bool add_point(const Ref<NativeEasingCurvePoint> &p_point);
	bool remove_point(int64_t p_index);
	void clear_points();
	Array capture_point_states() const;
	bool apply_point_states(const Array &p_states);
	Ref<NativeEasingCurve> create_runtime_copy() const;

	void cubic_bezier(double p_x1, double p_y1, double p_x2, double p_y2);
	bool bake_callable(const Callable &p_callable, int64_t p_resolution = 40);
	double sample(double p_offset);
};

} // namespace godot

VARIANT_ENUM_CAST(godot::NativeEasingCurve::Transition);
VARIANT_ENUM_CAST(godot::NativeEasingCurve::EaseType);

#endif // EASING_CURVE_NATIVE_EASING_CURVE_H

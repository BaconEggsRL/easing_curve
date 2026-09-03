#ifndef EASING_CURVE_NATIVE_EASING_CURVE_H
#define EASING_CURVE_NATIVE_EASING_CURVE_H

#include "native_easing_curve_point.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <vector>

namespace godot {

class NativeEasingCurve : public Resource {
	GDCLASS(NativeEasingCurve, Resource)

public:
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
	EaseType ease_type = EASE_OUT;
	double amplitude = 1.0;
	double period = 0.3;
	TypedArray<NativeEasingCurvePoint> points;
	std::vector<Ref<NativeEasingCurvePoint>> connected_points;
	std::vector<Segment> segments;
	int64_t last_segment_index = -1;

	void reconnect_points();
	void disconnect_points();
	void compile_segments();
	void on_point_changed();

	double sample_builtin(double p_offset) const;
	double sample_custom(double p_offset);
	double sample_transition_in(double p_offset) const;
	double sample_transition_out(double p_offset) const;
	double sample_elastic_in(double p_offset) const;
	double sample_elastic_out(double p_offset) const;
	double sample_elastic_in_out(double p_offset) const;
	static double sample_back_in_out(double p_offset);
	static double sample_expo_in_out(double p_offset);
	static double sample_bounce_out(double p_offset);
	static double sample_spring_out(double p_offset);

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

	void set_points(const TypedArray<NativeEasingCurvePoint> &p_points);
	TypedArray<NativeEasingCurvePoint> get_points() const;
	void add_point(const Ref<NativeEasingCurvePoint> &p_point);
	void remove_point(int64_t p_index);

	void cubic_bezier(double p_x1, double p_y1, double p_x2, double p_y2);
	double sample(double p_offset);
};

} // namespace godot

VARIANT_ENUM_CAST(godot::NativeEasingCurve::Transition);
VARIANT_ENUM_CAST(godot::NativeEasingCurve::EaseType);

#endif // EASING_CURVE_NATIVE_EASING_CURVE_H

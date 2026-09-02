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
		TRANS_LINEAR,
		TRANS_SINE,
		TRANS_CUBIC,
		TRANS_ELASTIC,
		TRANS_CUSTOM,
	};

	enum EaseType {
		EASE_IN,
		EASE_OUT,
		EASE_IN_OUT,
		EASE_OUT_IN,
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

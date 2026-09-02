#ifndef EASING_CURVE_NATIVE_EASING_CURVE_POINT_H
#define EASING_CURVE_NATIVE_EASING_CURVE_POINT_H

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class NativeEasingCurvePoint : public Resource {
	GDCLASS(NativeEasingCurvePoint, Resource)

private:
	Vector2 position;
	Vector2 left_control_point;
	Vector2 right_control_point;

protected:
	static void _bind_methods();

public:
	void set_position(const Vector2 &p_position);
	Vector2 get_position() const;

	void set_left_control_point(const Vector2 &p_control_point);
	Vector2 get_left_control_point() const;

	void set_right_control_point(const Vector2 &p_control_point);
	Vector2 get_right_control_point() const;
};

} // namespace godot

#endif // EASING_CURVE_NATIVE_EASING_CURVE_POINT_H

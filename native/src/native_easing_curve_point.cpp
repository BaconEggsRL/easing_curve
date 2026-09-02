#include "native_easing_curve_point.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void NativeEasingCurvePoint::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_position", "position"), &NativeEasingCurvePoint::set_position);
	ClassDB::bind_method(D_METHOD("get_position"), &NativeEasingCurvePoint::get_position);
	ClassDB::bind_method(D_METHOD("set_left_control_point", "control_point"), &NativeEasingCurvePoint::set_left_control_point);
	ClassDB::bind_method(D_METHOD("get_left_control_point"), &NativeEasingCurvePoint::get_left_control_point);
	ClassDB::bind_method(D_METHOD("set_right_control_point", "control_point"), &NativeEasingCurvePoint::set_right_control_point);
	ClassDB::bind_method(D_METHOD("get_right_control_point"), &NativeEasingCurvePoint::get_right_control_point);

	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "position"), "set_position", "get_position");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "left_control_point"), "set_left_control_point", "get_left_control_point");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "right_control_point"), "set_right_control_point", "get_right_control_point");
}

void NativeEasingCurvePoint::set_position(const Vector2 &p_position) {
	if (!p_position.is_finite() || position == p_position) {
		return;
	}

	const Vector2 delta = p_position - position;
	position = p_position;
	left_control_point += delta;
	right_control_point += delta;
	emit_changed();
}

Vector2 NativeEasingCurvePoint::get_position() const {
	return position;
}

void NativeEasingCurvePoint::set_left_control_point(const Vector2 &p_control_point) {
	if (!p_control_point.is_finite() || left_control_point == p_control_point) {
		return;
	}

	left_control_point = p_control_point;
	emit_changed();
}

Vector2 NativeEasingCurvePoint::get_left_control_point() const {
	return left_control_point;
}

void NativeEasingCurvePoint::set_right_control_point(const Vector2 &p_control_point) {
	if (!p_control_point.is_finite() || right_control_point == p_control_point) {
		return;
	}

	right_control_point = p_control_point;
	emit_changed();
}

Vector2 NativeEasingCurvePoint::get_right_control_point() const {
	return right_control_point;
}

} // namespace godot

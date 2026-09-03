#ifndef EASING_CURVE_NATIVE_EASING_CURVE_POINT_H
#define EASING_CURVE_NATIVE_EASING_CURVE_POINT_H

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class NativeEasingCurvePoint : public Resource {
	GDCLASS(NativeEasingCurvePoint, Resource)

private:
public:
	enum HandleMode {
		HANDLE_FREE = 0,
		HANDLE_LINEAR = 1,
		HANDLE_BALANCED = 2,
		HANDLE_MIRRORED = 3,
		HANDLE_LINKED = 4,
	};

private:
	static constexpr double DEFAULT_HANDLE_LENGTH = 0.1;
	Vector2 position;
	Vector2 left_control_point;
	Vector2 right_control_point;
	HandleMode handle_mode = HANDLE_FREE;
	bool left_force_linear = false;
	bool right_force_linear = false;
	Dictionary locked;

	bool is_lockable_property(const StringName &p_property_name) const;
	bool is_control_force_linear(bool p_left) const;
	void set_default_control(bool p_left);
	void apply_force_linear_geometry();
	void set_control_point(bool p_left, const Vector2 &p_control_point);
	static double safe_length(const Vector2 &p_vector);
	static Vector2 safe_direction(const Vector2 &p_vector);

protected:
	static void _bind_methods();

public:
	NativeEasingCurvePoint();

	void set_position(const Vector2 &p_position);
	Vector2 get_position() const;

	void set_left_control_point(const Vector2 &p_control_point);
	Vector2 get_left_control_point() const;

	void set_right_control_point(const Vector2 &p_control_point);
	Vector2 get_right_control_point() const;

	void set_handle_mode(HandleMode p_handle_mode);
	HandleMode get_handle_mode() const;

	void set_left_force_linear(bool p_enabled);
	bool is_left_force_linear() const;
	void set_right_force_linear(bool p_enabled);
	bool is_right_force_linear() const;

	void set_locks(const Dictionary &p_locked);
	Dictionary get_locks() const;
	void set_locked(const StringName &p_property_name, bool p_enabled);
	bool is_lock_active(const StringName &p_property_name) const;

	Dictionary capture_state() const;
	bool apply_state(const Dictionary &p_state);
};

} // namespace godot

VARIANT_ENUM_CAST(godot::NativeEasingCurvePoint::HandleMode);

#endif // EASING_CURVE_NATIVE_EASING_CURVE_POINT_H

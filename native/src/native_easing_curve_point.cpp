#include "native_easing_curve_point.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

namespace godot {

void NativeEasingCurvePoint::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_position", "position"), &NativeEasingCurvePoint::set_position);
	ClassDB::bind_method(D_METHOD("get_position"), &NativeEasingCurvePoint::get_position);
	ClassDB::bind_method(D_METHOD("set_left_control_point", "control_point"), &NativeEasingCurvePoint::set_left_control_point);
	ClassDB::bind_method(D_METHOD("get_left_control_point"), &NativeEasingCurvePoint::get_left_control_point);
	ClassDB::bind_method(D_METHOD("set_right_control_point", "control_point"), &NativeEasingCurvePoint::set_right_control_point);
	ClassDB::bind_method(D_METHOD("get_right_control_point"), &NativeEasingCurvePoint::get_right_control_point);
	ClassDB::bind_method(D_METHOD("set_handle_mode", "handle_mode"), &NativeEasingCurvePoint::set_handle_mode);
	ClassDB::bind_method(D_METHOD("get_handle_mode"), &NativeEasingCurvePoint::get_handle_mode);
	ClassDB::bind_method(D_METHOD("set_left_force_linear", "enabled"), &NativeEasingCurvePoint::set_left_force_linear);
	ClassDB::bind_method(D_METHOD("is_left_force_linear"), &NativeEasingCurvePoint::is_left_force_linear);
	ClassDB::bind_method(D_METHOD("set_right_force_linear", "enabled"), &NativeEasingCurvePoint::set_right_force_linear);
	ClassDB::bind_method(D_METHOD("is_right_force_linear"), &NativeEasingCurvePoint::is_right_force_linear);
	ClassDB::bind_method(D_METHOD("set_locks", "locked"), &NativeEasingCurvePoint::set_locks);
	ClassDB::bind_method(D_METHOD("get_locks"), &NativeEasingCurvePoint::get_locks);
	ClassDB::bind_method(D_METHOD("set_locked", "property_name", "enabled"), &NativeEasingCurvePoint::set_locked);
	ClassDB::bind_method(D_METHOD("is_lock_active", "property_name"), &NativeEasingCurvePoint::is_lock_active);
	ClassDB::bind_method(D_METHOD("capture_state"), &NativeEasingCurvePoint::capture_state);
	ClassDB::bind_method(D_METHOD("apply_state", "state"), &NativeEasingCurvePoint::apply_state);

	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "position"), "set_position", "get_position");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "left_control_point"), "set_left_control_point", "get_left_control_point");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "right_control_point"), "set_right_control_point", "get_right_control_point");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "handle_mode", PROPERTY_HINT_ENUM, "Free,Linear,Balanced,Mirrored,Linked"), "set_handle_mode", "get_handle_mode");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "left_force_linear", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_left_force_linear", "is_left_force_linear");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "right_force_linear", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_right_force_linear", "is_right_force_linear");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "locked", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_locks", "get_locks");
	ADD_SIGNAL(MethodInfo("lock_changed", PropertyInfo(Variant::STRING_NAME, "property_name"), PropertyInfo(Variant::BOOL, "locked")));

	BIND_ENUM_CONSTANT(HANDLE_FREE);
	BIND_ENUM_CONSTANT(HANDLE_LINEAR);
	BIND_ENUM_CONSTANT(HANDLE_BALANCED);
	BIND_ENUM_CONSTANT(HANDLE_MIRRORED);
	BIND_ENUM_CONSTANT(HANDLE_LINKED);
}

NativeEasingCurvePoint::NativeEasingCurvePoint() {
	locked[StringName("position")] = false;
	locked[StringName("left_control_point")] = false;
	locked[StringName("right_control_point")] = false;
}

void NativeEasingCurvePoint::set_position(const Vector2 &p_position) {
	if (!p_position.is_finite() || position == p_position) {
		return;
	}

	const Vector2 delta = p_position - position;
	const bool left_locked = is_lock_active(StringName("left_control_point"));
	const bool right_locked = is_lock_active(StringName("right_control_point"));
	position = p_position;
	if (!left_locked) {
		left_control_point += delta;
	}
	if (!right_locked) {
		right_control_point += delta;
	}
	emit_changed();
}

Vector2 NativeEasingCurvePoint::get_position() const {
	return position;
}

void NativeEasingCurvePoint::set_left_control_point(const Vector2 &p_control_point) {
	set_control_point(true, p_control_point);
}

Vector2 NativeEasingCurvePoint::get_left_control_point() const {
	return left_control_point;
}

void NativeEasingCurvePoint::set_right_control_point(const Vector2 &p_control_point) {
	set_control_point(false, p_control_point);
}

Vector2 NativeEasingCurvePoint::get_right_control_point() const {
	return right_control_point;
}

void NativeEasingCurvePoint::set_handle_mode(HandleMode p_handle_mode) {
	if (p_handle_mode < HANDLE_FREE || p_handle_mode > HANDLE_LINKED || handle_mode == p_handle_mode) {
		return;
	}

	Vector2 next_left = left_control_point;
	Vector2 next_right = right_control_point;
	if (p_handle_mode == HANDLE_LINEAR) {
		next_left = position;
		next_right = position;
	} else if (handle_mode == HANDLE_LINEAR) {
		next_left = position + Vector2(-DEFAULT_HANDLE_LENGTH, 0.0);
		next_right = position + Vector2(DEFAULT_HANDLE_LENGTH, 0.0);
		if (p_handle_mode == HANDLE_LINKED) {
			next_left = next_right;
		}
	} else if (p_handle_mode == HANDLE_BALANCED) {
		const double left_length = safe_length(next_left - position);
		const double right_length = safe_length(next_right - position);
		const Vector2 direction = safe_direction(left_length > right_length ? position - next_left : next_right - position);
		next_left = position - direction * left_length;
		next_right = position + direction * right_length;
	} else if (p_handle_mode == HANDLE_MIRRORED) {
		const double left_length = safe_length(next_left - position);
		const double right_length = safe_length(next_right - position);
		const bool use_left = left_length > right_length;
		const Vector2 direction = safe_direction(use_left ? position - next_left : next_right - position);
		const double length = std::max(std::max(left_length, right_length), DEFAULT_HANDLE_LENGTH);
		next_left = position - direction * length;
		next_right = position + direction * length;
	} else if (p_handle_mode == HANDLE_LINKED) {
		next_left = safe_length(next_left - position) > safe_length(next_right - position) ? next_left : next_right;
		next_right = next_left;
	}

	handle_mode = p_handle_mode;
	left_control_point = next_left;
	right_control_point = next_right;
	apply_force_linear_geometry();
	emit_changed();
}

NativeEasingCurvePoint::HandleMode NativeEasingCurvePoint::get_handle_mode() const {
	return handle_mode;
}

void NativeEasingCurvePoint::set_left_force_linear(bool p_enabled) {
	if (left_force_linear == p_enabled) {
		return;
	}
	left_force_linear = p_enabled;
	if (handle_mode == HANDLE_LINKED) {
		if (left_force_linear || right_force_linear) {
			left_control_point = position;
			right_control_point = position;
		} else {
			left_control_point = position + Vector2(DEFAULT_HANDLE_LENGTH, 0.0);
			right_control_point = left_control_point;
		}
	} else if (handle_mode == HANDLE_FREE) {
		if (p_enabled) {
			left_control_point = position;
		} else {
			set_default_control(true);
		}
	}
	emit_changed();
}

bool NativeEasingCurvePoint::is_left_force_linear() const {
	return left_force_linear;
}

void NativeEasingCurvePoint::set_right_force_linear(bool p_enabled) {
	if (right_force_linear == p_enabled) {
		return;
	}
	right_force_linear = p_enabled;
	if (handle_mode == HANDLE_LINKED) {
		if (left_force_linear || right_force_linear) {
			left_control_point = position;
			right_control_point = position;
		} else {
			left_control_point = position + Vector2(DEFAULT_HANDLE_LENGTH, 0.0);
			right_control_point = left_control_point;
		}
	} else if (handle_mode == HANDLE_FREE) {
		if (p_enabled) {
			right_control_point = position;
		} else {
			set_default_control(false);
		}
	}
	emit_changed();
}

bool NativeEasingCurvePoint::is_right_force_linear() const {
	return right_force_linear;
}

void NativeEasingCurvePoint::set_locks(const Dictionary &p_locked) {
	Dictionary normalized;
	for (const StringName property_name : { StringName("position"), StringName("left_control_point"), StringName("right_control_point") }) {
		normalized[property_name] = static_cast<bool>(p_locked.get(property_name, false));
	}
	if (locked == normalized) {
		return;
	}
	locked = normalized;
	emit_changed();
}

Dictionary NativeEasingCurvePoint::get_locks() const {
	return locked.duplicate(true);
}

void NativeEasingCurvePoint::set_locked(const StringName &p_property_name, bool p_enabled) {
	if (!is_lockable_property(p_property_name) || static_cast<bool>(locked.get(p_property_name, false)) == p_enabled) {
		return;
	}
	locked[p_property_name] = p_enabled;
	emit_signal("lock_changed", p_property_name, p_enabled);
	emit_changed();
}

bool NativeEasingCurvePoint::is_lock_active(const StringName &p_property_name) const {
	if (!is_lockable_property(p_property_name)) {
		return false;
	}
	if (p_property_name != StringName("position") && handle_mode != HANDLE_FREE && handle_mode != HANDLE_LINKED) {
		return false;
	}
	return static_cast<bool>(locked.get(p_property_name, false));
}

Dictionary NativeEasingCurvePoint::capture_state() const {
	Dictionary state;
	state[StringName("position")] = position;
	state[StringName("left_control_point")] = left_control_point;
	state[StringName("right_control_point")] = right_control_point;
	state[StringName("handle_mode")] = static_cast<int64_t>(handle_mode);
	state[StringName("left_force_linear")] = left_force_linear;
	state[StringName("right_force_linear")] = right_force_linear;
	state[StringName("locked")] = get_locks();
	return state;
}

bool NativeEasingCurvePoint::apply_state(const Dictionary &p_state) {
	const Vector2 next_position = p_state.get(StringName("position"), position);
	const Vector2 next_left = p_state.get(StringName("left_control_point"), left_control_point);
	const Vector2 next_right = p_state.get(StringName("right_control_point"), right_control_point);
	const int64_t next_mode_value = p_state.get(StringName("handle_mode"), static_cast<int64_t>(handle_mode));
	if (!next_position.is_finite() || !next_left.is_finite() || !next_right.is_finite() || next_mode_value < HANDLE_FREE || next_mode_value > HANDLE_LINKED) {
		return false;
	}

	Dictionary next_locks = p_state.get(StringName("locked"), locked);
	Dictionary normalized_locks;
	for (const StringName property_name : { StringName("position"), StringName("left_control_point"), StringName("right_control_point") }) {
		normalized_locks[property_name] = static_cast<bool>(next_locks.get(property_name, false));
	}
	const bool next_left_force_linear = p_state.get(StringName("left_force_linear"), left_force_linear);
	const bool next_right_force_linear = p_state.get(StringName("right_force_linear"), right_force_linear);
	if (position == next_position && left_control_point == next_left && right_control_point == next_right && handle_mode == next_mode_value && left_force_linear == next_left_force_linear && right_force_linear == next_right_force_linear && locked == normalized_locks) {
		return true;
	}

	position = next_position;
	left_control_point = next_left;
	right_control_point = next_right;
	handle_mode = static_cast<HandleMode>(next_mode_value);
	left_force_linear = next_left_force_linear;
	right_force_linear = next_right_force_linear;
	locked = normalized_locks;
	emit_changed();
	return true;
}

bool NativeEasingCurvePoint::is_lockable_property(const StringName &p_property_name) const {
	return p_property_name == StringName("position") || p_property_name == StringName("left_control_point") || p_property_name == StringName("right_control_point");
}

bool NativeEasingCurvePoint::is_control_force_linear(bool p_left) const {
	if (handle_mode == HANDLE_LINKED) {
		return left_force_linear || right_force_linear;
	}
	return p_left ? left_force_linear : right_force_linear;
}

void NativeEasingCurvePoint::set_default_control(bool p_left) {
	if (p_left) {
		left_control_point = position + Vector2(-DEFAULT_HANDLE_LENGTH, 0.0);
	} else {
		right_control_point = position + Vector2(DEFAULT_HANDLE_LENGTH, 0.0);
	}
}

void NativeEasingCurvePoint::apply_force_linear_geometry() {
	if (handle_mode != HANDLE_FREE && handle_mode != HANDLE_LINKED) {
		return;
	}
	if (handle_mode == HANDLE_LINKED && (left_force_linear || right_force_linear)) {
		left_control_point = position;
		right_control_point = position;
		return;
	}
	if (left_force_linear) {
		left_control_point = position;
	}
	if (right_force_linear) {
		right_control_point = position;
	}
}

void NativeEasingCurvePoint::set_control_point(bool p_left, const Vector2 &p_control_point) {
	if (!p_control_point.is_finite()) {
		return;
	}
	const Vector2 value = is_control_force_linear(p_left) ? position : p_control_point;
	Vector2 next_left = left_control_point;
	Vector2 next_right = right_control_point;
	if (handle_mode == HANDLE_LINEAR) {
		next_left = position;
		next_right = position;
	} else if (handle_mode == HANDLE_LINKED) {
		next_left = value;
		next_right = value;
	} else {
		if (p_left) {
			next_left = value;
		} else {
			next_right = value;
		}
		if (handle_mode == HANDLE_BALANCED) {
			const Vector2 moved_delta = value - position;
			const double opposite_length = safe_length((p_left ? right_control_point : left_control_point) - position);
			const Vector2 balanced = position + safe_direction(-moved_delta) * opposite_length;
			if (p_left) {
				next_right = balanced;
			} else {
				next_left = balanced;
			}
		} else if (handle_mode == HANDLE_MIRRORED) {
			const Vector2 mirrored = position - (value - position);
			if (p_left) {
				next_right = mirrored;
			} else {
				next_left = mirrored;
			}
		}
	}
	if (left_control_point == next_left && right_control_point == next_right) {
		return;
	}
	left_control_point = next_left;
	right_control_point = next_right;
	emit_changed();
}

double NativeEasingCurvePoint::safe_length(const Vector2 &p_vector) {
	if (!p_vector.is_finite()) {
		return 0.0;
	}
	const double max_component = std::max(std::abs(static_cast<double>(p_vector.x)), std::abs(static_cast<double>(p_vector.y)));
	if (max_component <= 0.00000001) {
		return 0.0;
	}
	const Vector2 scaled = p_vector / max_component;
	return max_component * std::sqrt(static_cast<double>(scaled.x) * scaled.x + static_cast<double>(scaled.y) * scaled.y);
}

Vector2 NativeEasingCurvePoint::safe_direction(const Vector2 &p_vector) {
	const double length = safe_length(p_vector);
	return length <= 0.00000001 ? Vector2(1.0, 0.0) : p_vector / length;
}

} // namespace godot

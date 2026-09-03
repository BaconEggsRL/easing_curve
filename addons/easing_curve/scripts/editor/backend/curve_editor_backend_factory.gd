@tool
extends RefCounted

const LegacyBackend := preload(
	"res://addons/easing_curve/scripts/editor/backend/legacy_curve_editor_backend.gd"
)
const NativeBackend := preload(
	"res://addons/easing_curve/scripts/editor/backend/native_curve_editor_backend.gd"
)


static func create(resource: Resource) -> RefCounted:
	if NativeBackend.supports(resource):
		return NativeBackend.new(resource)
	if LegacyBackend.supports(resource):
		return LegacyBackend.new(resource)
	return null

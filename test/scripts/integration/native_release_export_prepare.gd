extends SceneTree

const BUILTIN_PATH := "res://builtin_native_curve.tres"
const CUSTOM_PATH := "res://custom_native_curve.tres"
const SAMPLE_OFFSET := 0.37


func _init() -> void:
	call_deferred(&"_prepare_resources")


func _prepare_resources() -> void:
	if not ClassDB.class_exists(&"NativeEasingCurve"):
		push_error("NativeEasingCurve is unavailable while preparing export fixtures")
		quit(1)
		return

	var builtin := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	builtin.set(&"transition", Tween.TRANS_SINE)
	builtin.set(&"ease_type", Tween.EASE_IN_OUT)
	if ResourceSaver.save(builtin, BUILTIN_PATH) != OK:
		push_error("Could not save the built-in Native curve fixture")
		quit(1)
		return

	var custom := ClassDB.instantiate(&"NativeEasingCurve") as Resource
	custom.call(&"cubic_bezier", 0.15, 0.85, 0.75, 0.1)
	custom.set_meta(&"validation_sample", custom.call(&"sample", SAMPLE_OFFSET))
	if ResourceSaver.save(custom, CUSTOM_PATH) != OK:
		push_error("Could not save the custom Native curve fixture")
		quit(1)
		return

	print("PREPARED: Native release export fixtures")
	quit()

extends "res://tween.gd"
## Same sprite, counts, target, duration and Tween scheduling as pinned upstream.
## Only the easing callback differs. See test/docs/GODOT_TWEEN_BENCHMARK.md.


func benchmark_native_100_properties() -> Node:
	return _curve_properties(_make_curve(true))


func benchmark_legacy_100_properties() -> Node:
	return _curve_properties(_make_curve(false))


func benchmark_native_1000_methods() -> Node:
	return _curve_methods(_make_curve(true))


func benchmark_legacy_1000_methods() -> Node:
	return _curve_methods(_make_curve(false))


func _make_curve(native: bool) -> Resource:
	var curve: Resource
	if native:
		curve = ClassDB.instantiate(&"NativeEasingCurve") as Resource
		curve.set(&"transition", 0)
	else:
		curve = EasingCurve.new()
		curve.set(&"trans_type", EasingCurve.TRANS.LINEAR)
	curve.set(&"ease_type", 0)
	return curve


func _curve_properties(curve: Resource) -> Node:
	var node := Node.new()
	node.set_meta(&"benchmark_curve", curve)
	var sample := Callable(curve, &"sample")
	var tween := node.create_tween()
	for _index in 100:
		var sprite := Sprite2D.new()
		sprite.position = Vector2(randf_range(0.0, viewport_size.x), randf_range(0.0, viewport_size.y))
		sprite.texture = ICON
		node.add_child(sprite)
		tween.parallel().tween_property(sprite, "position", half_viewport_size, 5).set_custom_interpolator(sample)
	return node


func _curve_methods(curve: Resource) -> Node:
	var node := Node.new()
	node.set_meta(&"benchmark_curve", curve)
	var sample := Callable(curve, &"sample")
	for _index in 1000:
		var tween := node.create_tween()
		var sprite := Sprite2D.new()
		sprite.position = Vector2(randf_range(0.0, viewport_size.x), randf_range(0.0, viewport_size.y))
		sprite.texture = ICON
		node.add_child(sprite)
		# MethodTweener has no custom interpolator. Both curve APIs use this adapter.
		# rotate() adds the angle each invocation, exactly as the upstream workload.
		tween.tween_method(func(progress: float) -> void: sprite.rotate(0.01 * float(sample.call(progress))), 0.0, 1.0, 5)
	return node

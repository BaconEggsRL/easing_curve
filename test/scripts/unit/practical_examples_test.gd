extends "res://test/scripts/support/test_case.gd"

const BASE := "res://addons/easing_curve/examples/"

func _init() -> void:
	call_deferred(&"_run")

func _run() -> void:
	for slug in ["popup", "sliding_door", "charge_meter"]:
		var packed := load(BASE + slug + ".tscn") as PackedScene
		_expect(packed != null, slug + " scene loads")
		if packed == null:
			continue
		var example := packed.instantiate()
		root.add_child(example)
		await process_frame
		var curve: EasingCurve = example.curve
		_expect(curve != null, slug + " has a portable authored curve")
		_expect(is_equal_approx(curve.sample(0.0), 0.0), slug + " starts at zero")
		_expect(is_equal_approx(curve.sample(1.0), 1.0), slug + " ends at one")
		example.replay()
		if slug == "sliding_door":
			var player: AnimationPlayer = example.player
			player.advance(example.duration * 0.5)
			_expect(example.door.position.is_equal_approx(example.closed_position.lerp(example.open_position, curve.sample(0.5))), "door samples timeline progress")
			player.advance(example.duration)
			_expect(example.door.position.is_equal_approx(example.open_position), "door opens")
			example.close()
			player.advance(example.duration)
			_expect(example.door.position.is_equal_approx(example.closed_position), "backwards playback closes door")
		else:
			var old_tween: Tween = example.tween
			example.replay()
			_expect(not old_tween.is_valid(), slug + " cancels previous Tween")
			example.tween.pause()
			example.tween.custom_step(example.duration * 0.5)
			if slug == "popup":
				var expected := Vector2.ONE * lerpf(0.2, 1.0, curve.sample(0.5))
				_expect(example.panel.scale.is_equal_approx(expected), "popup uses custom interpolator")
				example.tween.custom_step(example.duration)
				_expect(example.panel.scale.is_equal_approx(Vector2.ONE), "popup completes")
			else:
				_expect(is_equal_approx(example.meter.value, curve.sample(0.5) * 100.0), "meter samples at midpoint")
				example.tween.custom_step(example.duration)
				_expect(is_equal_approx(example.meter.value, 100.0), "meter completes")
		var replacement := EasingCurve.new()
		example.curve = replacement
		var method := &"_on_curve_changed" if slug == "charge_meter" else &"replay"
		_expect(not curve.changed.is_connected(Callable(example, method)), slug + " disconnects old resource")
		_expect(replacement.changed.is_connected(Callable(example, method)), slug + " observes replacement resource")
		example.replay()
		if slug == "sliding_door":
			example.player.advance(example.duration * 0.5)
			replacement.trans_type = EasingCurve.TRANS.QUAD
			_expect(is_zero_approx(example.progress), "curve edit resets door progress")
		else:
			var previous: Tween = example.tween
			replacement.trans_type = EasingCurve.TRANS.QUAD
			_expect(not previous.is_valid(), slug + " curve edit restarts playback")
		if slug == "charge_meter":
			example.scrub(0.5)
			replacement.trans_type = EasingCurve.TRANS.CONSTANT
			replacement.constant_value = 1.5
			_expect(is_equal_approx(example.progress, 0.5), "stationary meter keeps scrub progress on edit")
			_expect(is_equal_approx(example.meter.value, 100.0), "meter clamps overshoot")
			replacement.constant_value = -0.5
			_expect(is_zero_approx(example.meter.value), "meter clamps undershoot")
			example.curve = null
			example.scrub(0.5)
			_expect(is_equal_approx(example.meter.value, 50.0), "missing curve uses linear fallback")
		example.reset()
		example.queue_free()
		await process_frame
	_finish("practical example")

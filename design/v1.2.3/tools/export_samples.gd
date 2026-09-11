extends SceneTree
## Design data only. Run in an isolated host with the portable addon and docs samples.

func _init() -> void:
	var text := FileAccess.get_file_as_string("res://docs/curve_samples.js")
	var json := text.substr(text.find("= ") + 2).strip_edges().trim_suffix(";")
	var existing: Dictionary = JSON.parse_string(json)
	var samples := {
		"back": existing.popup,
		"smoothstep": existing.sliding_door,
		"css": existing.charge_meter,
	}
	var transitions := {
		"linear": EasingCurve.TRANS.LINEAR,
		"cubic": EasingCurve.TRANS.CUBIC,
		"elastic": EasingCurve.TRANS.ELASTIC,
		"spring": EasingCurve.TRANS.SPRING,
		"bounce": EasingCurve.TRANS.BOUNCE,
	}
	for key: String in transitions:
		var curve := EasingCurve.new()
		curve.trans_type = transitions[key]
		curve.ease_type = EasingCurve.EASE.OUT
		var values: Array[float] = []
		for index in range(257):
			var value := curve.sample(float(index) / 256.0)
			if not is_finite(value):
				push_error("Nonfinite sample: " + key)
				quit(1)
				return
			values.append(value)
		samples[key] = values
	var output := FileAccess.open("res://curve_samples.js", FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string("// Back, Smoothstep, CSS copied from docs/curve_samples.js. Others: Legacy defaults, Ease Out, 257 samples, Godot " + Engine.get_version_info().string + ".\nconst CURVE_SAMPLES = " + JSON.stringify(samples) + ";\nif (typeof module !== 'undefined') module.exports = CURVE_SAMPLES;\n")
	print("PASS: eight finite design sample tables, three reused unchanged")
	quit()

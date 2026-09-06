@tool
extends VBoxContainer

const CONVERTER := preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_converter.gd"
)
const CONVERSION_RESULT := preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_conversion_result.gd"
)
const REPORT_FIELDS_PER_LINE := 3

var _source: Resource
var _converted_resource: Resource
var _dialog: ConfirmationDialog


class HorizontallyShrinkableButton:
	extends Button

	func _get_minimum_size() -> Vector2:
		return Vector2.ZERO


class CappedButtonRow:
	extends Container

	var preferred_width := 0.0
	var preferred_height := 0.0


	func set_button(button: Button, preferred_size: Vector2) -> void:
		preferred_width = preferred_size.x
		preferred_height = preferred_size.y
		clip_contents = true
		add_child(button)
		update_minimum_size()


	func _get_minimum_size() -> Vector2:
		return Vector2(0.0, preferred_height)


	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN or get_child_count() == 0:
			return
		var button := get_child(0) as Control
		var button_width := minf(size.x, preferred_width)
		fit_child_in_rect(
			button,
			Rect2(
				maxf(0.0, (size.x - button_width) * 0.5),
				0.0,
				button_width,
				size.y,
			),
		)


func setup(source: Resource) -> void:
	_source = source
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_native := source != null and source.get_class() == &"NativeEasingCurve"
	var convert_button := HorizontallyShrinkableButton.new()
	convert_button.text = "Convert to Legacy Copy" if is_native else "Convert to Native Copy"
	convert_button.tooltip_text = "Create a separate unsaved resource; the source is never replaced."
	convert_button.clip_text = true
	convert_button.pressed.connect(_convert.bind(false))
	add_child(_create_button_row(convert_button, &"ConvertButtonRow"))

	if (
		not is_native
		and source is EasingCurve
		and source.curve_mode == EasingCurve.CurveMode.FUNCTION
		and source.trans_type == EasingCurve.TRANS.CUSTOM
	):
		var bake_button := HorizontallyShrinkableButton.new()
		bake_button.text = "Bake Callable to Native Copy"
		bake_button.tooltip_text = "Explicitly bake the live Callable into 40 Native points."
		bake_button.clip_text = true
		bake_button.pressed.connect(_convert.bind(true))
		add_child(_create_button_row(bake_button, &"BakeButtonRow"))

	_dialog = ConfirmationDialog.new()
	_dialog.title = "Easing Curve Conversion"
	_dialog.ok_button_text = "Open Unsaved Copy"
	_dialog.confirmed.connect(_open_converted_resource, CONNECT_DEFERRED)
	add_child(_dialog)


func _create_button_row(button: Button, row_name: StringName) -> CappedButtonRow:
	var measurement := Button.new()
	measurement.text = button.text
	var preferred_size := measurement.get_combined_minimum_size()
	measurement.free()
	var row := CappedButtonRow.new()
	row.name = row_name
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_button(button, preferred_size)
	return row


func _convert(allow_callable_bake: bool) -> void:
	if _source == null:
		return
	var result := (
		CONVERTER.native_to_legacy(_source)
		if _source.get_class() == &"NativeEasingCurve"
		else CONVERTER.legacy_to_native(_source as EasingCurve, allow_callable_bake)
	)
	_converted_resource = result.get(CONVERSION_RESULT.KEY_RESOURCE) as Resource
	if not CONVERSION_RESULT.is_success(result):
		_dialog.ok_button_text = "Close"
		_dialog.dialog_text = "Conversion was not created.\n%s" % _format_report(result)
		_dialog.get_ok_button().disabled = false
		_dialog.popup_centered()
		return
	var outcome := "exact"
	if CONVERSION_RESULT.is_lossy(result):
		outcome = "baked"
	_dialog.ok_button_text = "Open Unsaved Copy"
	_dialog.dialog_text = (
		"A separate %s conversion is ready.\n"
		+ "The source resource was not changed.\n"
		+ "Review the unsaved copy before choosing a path and saving it.\n\n%s"
	) % [outcome, _format_report(result)]
	_dialog.popup_centered()


func _format_report(result: Dictionary) -> String:
	var lines := PackedStringArray()
	var fields := result.get(CONVERSION_RESULT.KEY_FIELDS, {}) as Dictionary
	for field_outcome: StringName in CONVERSION_RESULT.FIELD_OUTCOMES:
		var names: Array[String] = []
		for field: Variant in fields:
			if fields[field] == field_outcome:
				names.append(String(field))
		names.sort()
		if not names.is_empty():
			lines.append("%s (%d):" % [String(field_outcome).capitalize(), names.size()])
			for first_index in range(0, names.size(), REPORT_FIELDS_PER_LINE):
				var field_names := names.slice(
					first_index,
					mini(first_index + REPORT_FIELDS_PER_LINE, names.size()),
				)
				lines.append("  %s" % ", ".join(field_names))
	var warnings: PackedStringArray = result.get(CONVERSION_RESULT.KEY_WARNINGS, PackedStringArray())
	var errors: PackedStringArray = result.get(CONVERSION_RESULT.KEY_ERRORS, PackedStringArray())
	for warning: String in warnings:
		lines.append("Warning: %s" % warning)
	for error: String in errors:
		lines.append("Error: %s" % error)
	return "\n".join(lines)


func _open_converted_resource() -> void:
	if _converted_resource != null:
		EditorInterface.edit_resource(_converted_resource)

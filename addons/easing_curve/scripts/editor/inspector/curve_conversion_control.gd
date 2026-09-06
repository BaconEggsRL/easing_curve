@tool
extends VBoxContainer

const CONVERTER := preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_converter.gd"
)
const CONVERSION_RESULT := preload(
	"res://addons/easing_curve/scripts/editor/backend/curve_conversion_result.gd"
)

var _source: Resource
var _converted_resource: Resource
var _dialog: ConfirmationDialog


func setup(source: Resource) -> void:
	_source = source
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_native := source != null and source.get_class() == &"NativeEasingCurve"
	var convert_button := Button.new()
	convert_button.text = "Convert to Legacy Copy" if is_native else "Convert to Native Copy"
	convert_button.tooltip_text = "Create a separate unsaved resource; the source is never replaced."
	convert_button.pressed.connect(_convert.bind(false))
	add_child(convert_button)

	if (
		not is_native
		and source is EasingCurve
		and source.curve_mode == EasingCurve.CurveMode.FUNCTION
		and source.trans_type == EasingCurve.TRANS.CUSTOM
	):
		var bake_button := Button.new()
		bake_button.text = "Bake Callable to Native Copy"
		bake_button.tooltip_text = "Explicitly bake the live Callable into 40 Native points."
		bake_button.pressed.connect(_convert.bind(true))
		add_child(bake_button)

	_dialog = ConfirmationDialog.new()
	_dialog.title = "Easing Curve Conversion"
	_dialog.ok_button_text = "Open Unsaved Copy"
	_dialog.confirmed.connect(_open_converted_resource)
	add_child(_dialog)


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
		"A separate %s conversion is ready. The source resource was not changed.\n"
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
			lines.append(
				"%s (%d): %s" % [
					String(field_outcome).capitalize(),
					names.size(),
					", ".join(names),
				]
			)
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

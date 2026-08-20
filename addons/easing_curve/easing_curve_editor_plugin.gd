@tool
extends EditorPlugin
## EasingCurve EditorPlugin
##
## Main script for the EasingCurve plugin.
## Instantiates the EasingCurve EditorInspectorPlugin.
## Detects when an EasingCurve resource has been saved, and changes the trans_type to CUSTOM.
## This prevents _update_preset() from running when the resource is initialized; keeping the user's custom settings intact.

const EasingCurveEditorInspectorPlugin = preload("uid://bqic40cwwnu7l")
const EasingCurveUpdateChecker = preload(
	"res://addons/easing_curve/scripts/update_checker.gd"
)

var easing_curve_editor_inspector_plugin
var update_checker: EasingCurveUpdateChecker
var editor_undo_redo: EditorUndoRedoManager = get_undo_redo()

var _pending_update := {}


func _enter_tree() -> void:
	resource_saved.connect(_on_resource_saved)

	easing_curve_editor_inspector_plugin = EasingCurveEditorInspectorPlugin.new()
	if easing_curve_editor_inspector_plugin:
		easing_curve_editor_inspector_plugin.editor_undo_redo = editor_undo_redo
		add_inspector_plugin(easing_curve_editor_inspector_plugin)

	update_checker = EasingCurveUpdateChecker.new()
	add_child(update_checker)
	update_checker.update_available.connect(_on_update_available)
	update_checker.check(get_plugin_version())

	add_tool_menu_item(
		"Easing Curve: Disable Update Checks"
		if _update_checks_enabled()
		else "Easing Curve: Enable Update Checks",
		_toggle_update_checks
	)


func _exit_tree() -> void:
	resource_saved.disconnect(_on_resource_saved)

	if easing_curve_editor_inspector_plugin:
		remove_inspector_plugin(easing_curve_editor_inspector_plugin)

	if update_checker:
		update_checker.queue_free()

	remove_tool_menu_item(
		"Easing Curve: Disable Update Checks"
		if _update_checks_enabled()
		else "Easing Curve: Enable Update Checks"
	)


func _enable_plugin() -> void:
	pass


func _disable_plugin() -> void:
	pass


func _on_resource_saved(resource: Resource) -> void:
	if resource is not EasingCurve:
		return

	if (
		resource.curve_mode == EasingCurve.CurveMode.BEZIER
		and resource.trans_type != EasingCurve.TRANS.CUSTOM
	):
		resource.trans_type = EasingCurve.TRANS.CUSTOM


func _on_update_available(
	current_version: String,
	latest_version: String,
	release_url: String
) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Easing Curve Update Available"
	dialog.dialog_text = (
		"Easing Curve %s is available.\n\n"
		+ "Installed version: %s"
	) % [latest_version, current_version]

	dialog.ok_button_text = "View Update"
	dialog.cancel_button_text = "Later"
	dialog.exclusive = false

	var ignore_button := dialog.add_button(
		"Ignore This Version",
		true,
		"ignore_version"
	)

	dialog.custom_action.connect(
		func(action: StringName):
			if action != "ignore_version":
				return

			EditorInterface.get_editor_settings().set_setting(
				EasingCurveUpdateChecker.SETTING_IGNORE_VERSION,
				latest_version
			)

			dialog.queue_free()
	)

	dialog.confirmed.connect(
		func():
			OS.shell_open(release_url)
			dialog.queue_free()
	)

	dialog.canceled.connect(dialog.queue_free)

	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()



func _update_checks_enabled() -> bool:
	var settings := EditorInterface.get_editor_settings()

	if not settings.has_setting(
		EasingCurveUpdateChecker.SETTING_ENABLED
	):
		return true

	return settings.get_setting(
		EasingCurveUpdateChecker.SETTING_ENABLED
	)



func _toggle_update_checks() -> void:
	var enabled := _update_checks_enabled()

	EditorInterface.get_editor_settings().set_setting(
		EasingCurveUpdateChecker.SETTING_ENABLED,
		not enabled
	)

	remove_tool_menu_item(
		"Easing Curve: Disable Update Checks"
		if enabled
		else "Easing Curve: Enable Update Checks"
	)

	add_tool_menu_item(
		"Easing Curve: Enable Update Checks"
		if enabled
		else "Easing Curve: Disable Update Checks",
		_toggle_update_checks
	)

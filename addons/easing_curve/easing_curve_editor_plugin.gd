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

const PLUGIN_CONFIG_PATH := "res://addons/easing_curve/plugin.cfg"
const UPDATE_CHECKS_ENABLE_MENU := "Easing Curve: Enable Update Checks"
const UPDATE_CHECKS_DISABLE_MENU := "Easing Curve: Disable Update Checks"

var easing_curve_editor_inspector_plugin
var update_checker: EasingCurveUpdateChecker
var editor_undo_redo: EditorUndoRedoManager = get_undo_redo()

var _last_update_checks_enabled := true


func _on_editor_settings_changed() -> void:
	var enabled := _update_checks_enabled()

	if enabled and not _last_update_checks_enabled:
		if update_checker:
			update_checker.check(_get_current_plugin_version())

	_last_update_checks_enabled = enabled
	_refresh_update_checker_menu()


func _enter_tree() -> void:
	resource_saved.connect(_on_resource_saved)

	easing_curve_editor_inspector_plugin = EasingCurveEditorInspectorPlugin.new()
	if easing_curve_editor_inspector_plugin:
		easing_curve_editor_inspector_plugin.editor_undo_redo = editor_undo_redo
		add_inspector_plugin(easing_curve_editor_inspector_plugin)

	update_checker = EasingCurveUpdateChecker.new()
	add_child(update_checker)
	update_checker.setup_editor_settings()
	_last_update_checks_enabled = _update_checks_enabled()
	update_checker.update_available.connect(_on_update_available)
	update_checker.check(_get_current_plugin_version())

	var editor_settings := EditorInterface.get_editor_settings()
	if not editor_settings.settings_changed.is_connected(
		_on_editor_settings_changed
	):
		editor_settings.settings_changed.connect(
			_on_editor_settings_changed
		)

	_refresh_update_checker_menu()


func _exit_tree() -> void:
	resource_saved.disconnect(_on_resource_saved)

	var editor_settings := EditorInterface.get_editor_settings()

	if editor_settings.settings_changed.is_connected(
		_on_editor_settings_changed
	):
		editor_settings.settings_changed.disconnect(
			_on_editor_settings_changed
	)

	if easing_curve_editor_inspector_plugin:
		remove_inspector_plugin(easing_curve_editor_inspector_plugin)

	if update_checker:
		update_checker.queue_free()

	remove_tool_menu_item(UPDATE_CHECKS_ENABLE_MENU)
	remove_tool_menu_item(UPDATE_CHECKS_DISABLE_MENU)


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

			var settings := EditorInterface.get_editor_settings()

			var ignored_versions: PackedStringArray = settings.get_setting(
				EasingCurveUpdateChecker.SETTING_IGNORED_VERSIONS
			)

			if not ignored_versions.has(latest_version):
				ignored_versions.append(latest_version)

			settings.set_setting(
				EasingCurveUpdateChecker.SETTING_IGNORED_VERSIONS,
				ignored_versions
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
	var settings := EditorInterface.get_editor_settings()
	var was_enabled := _update_checks_enabled()
	var enabled := not was_enabled

	settings.set_setting(
		EasingCurveUpdateChecker.SETTING_ENABLED,
		enabled
	)

	_refresh_update_checker_menu()

	if enabled and update_checker:
		update_checker.check(_get_current_plugin_version())


func _refresh_update_checker_menu() -> void:
	remove_tool_menu_item(UPDATE_CHECKS_ENABLE_MENU)
	remove_tool_menu_item(UPDATE_CHECKS_DISABLE_MENU)

	add_tool_menu_item(
		UPDATE_CHECKS_DISABLE_MENU
		if _update_checks_enabled()
		else UPDATE_CHECKS_ENABLE_MENU,
		_toggle_update_checks
	)


func _get_current_plugin_version() -> String:
	var config := ConfigFile.new()
	var error := config.load(PLUGIN_CONFIG_PATH)

	if error != OK:
		push_warning(
			"Easing Curve update check: Failed to read plugin.cfg."
		)
		return get_plugin_version()

	return str(
		config.get_value(
			"plugin",
			"version",
			get_plugin_version()
		)
	)

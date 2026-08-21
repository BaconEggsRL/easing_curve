@tool
extends EditorPlugin


const PLUGIN_NAME := "GDQuest GDScript Formatter"
const PLUGIN_PREFIX := "gdquest_gdscript_formatter/"


func _enable_plugin() -> void:
	var removed := erase_settings_with_prefix(PLUGIN_PREFIX)

	print(
		"Finished removing %s settings. Removed: %d"
		% [PLUGIN_NAME, removed]
	)


static func erase_settings_with_prefix(prefix: String) -> int:
	var settings := EditorInterface.get_editor_settings()
	var removed := 0

	for property in settings.get_property_list():
		var setting_name := str(property.get("name", ""))

		if setting_name.begins_with(prefix):
			print("Removing EditorSetting: ", setting_name)
			settings.erase(setting_name)
			removed += 1

	return removed

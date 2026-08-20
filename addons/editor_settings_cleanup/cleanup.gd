@tool
extends EditorPlugin


func _enter_tree() -> void:
	var settings := EditorInterface.get_editor_settings()

	for property in settings.get_property_list():
		var setting_name := str(property.get("name", ""))

		if setting_name.begins_with("gdquest_gdscript_formatter/"):
			print("Removing stale EditorSetting: ", setting_name)
			settings.erase(setting_name)

	print("Finished removing GDQuest GDScript Formatter settings.")

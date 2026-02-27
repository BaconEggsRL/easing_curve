@tool
extends EditorPlugin

const USE_EXTERNAL_EDITOR := &"text_editor/external/use_external_editor"

var editor_settings:EditorSettings
var checkbutton:CheckButton


func _enter_tree() -> void:
	editor_settings = EditorInterface.get_editor_settings()
	checkbutton = CheckButton.new()
	checkbutton.button_pressed = editor_settings.get(USE_EXTERNAL_EDITOR)
	checkbutton.text = "Use External Editor"
	checkbutton.tooltip_text = "Shortcut for “Editor Settings/Text Editor/Externals/Use External Editor” setting"
	checkbutton.pressed.connect(func(): editor_settings.set(USE_EXTERNAL_EDITOR, checkbutton.button_pressed))
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, checkbutton)


func _exit_tree() -> void:
	remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, checkbutton)
	checkbutton.free()

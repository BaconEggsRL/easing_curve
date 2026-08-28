@tool
extends ImageTexture


@export var icon: StringName = &"Curve":
	set(value):
		icon = value

		if not Engine.is_editor_hint():
			return

		# EditorInterface.get_editor_theme() is unsafe during some
		# --editor --headless initialization paths in Godot 4.7.1.
		if DisplayServer.get_name() == "headless":
			return

		var editor_theme := EditorInterface.get_editor_theme()
		if editor_theme == null:
			return

		if not editor_theme.has_icon(icon, &"EditorIcons"):
			return

		var texture := editor_theme.get_icon(icon, &"EditorIcons")
		if texture == null:
			return

		var image := texture.get_image()
		if image != null and not image.is_empty():
			set_image(image)

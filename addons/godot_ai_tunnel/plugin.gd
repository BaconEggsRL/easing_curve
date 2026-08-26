@tool
extends EditorPlugin

const SETTING_PREFIX := "godot_ai_tunnel/"
const SETTING_ENABLED := SETTING_PREFIX + "enabled"
const SETTING_EXECUTABLE_PATH := SETTING_PREFIX + "executable_path"
const SETTING_PROFILE := SETTING_PREFIX + "profile"
const SETTING_HEALTH_LISTEN_ADDR := SETTING_PREFIX + "health_listen_addr"

const METADATA_SECTION := "godot_ai_tunnel"
const METADATA_MANAGED_PID := "managed_pid"

const DEFAULT_ENABLED := true
const DEFAULT_PROFILE := "godot-ai"
const DEFAULT_HEALTH_LISTEN_ADDR := "127.0.0.1:18080"

var _tunnel_pid := -1


func _enter_tree() -> void:
	if OS.get_name() != "Windows":
		return

	var settings := EditorInterface.get_editor_settings()
	if settings == null:
		push_warning("Godot AI Tunnel | EditorSettings unavailable")
		return

	_register_settings(settings)

	if not bool(settings.get_setting(SETTING_ENABLED)):
		print("Godot AI Tunnel | disabled in Editor Settings")
		return

	var executable := str(settings.get_setting(SETTING_EXECUTABLE_PATH)).strip_edges()
	if executable.is_empty():
		push_warning(
			"Godot AI Tunnel | configure Editor Settings > "
			+ SETTING_EXECUTABLE_PATH
		)
		return

	if not FileAccess.file_exists(executable):
		push_error(
			"Godot AI Tunnel | tunnel-client.exe not found: %s"
			% executable
		)
		return

	_stop_stale_managed_tunnel(settings)
	_start_tunnel(
		executable,
		str(settings.get_setting(SETTING_PROFILE)),
		str(settings.get_setting(SETTING_HEALTH_LISTEN_ADDR)),
		settings,
	)


func _exit_tree() -> void:
	_stop_tunnel()


func _register_settings(settings: EditorSettings) -> void:
	_register_setting(settings, SETTING_ENABLED, DEFAULT_ENABLED)
	_register_setting(settings, SETTING_EXECUTABLE_PATH, "")
	_register_setting(settings, SETTING_PROFILE, DEFAULT_PROFILE)
	_register_setting(
		settings,
		SETTING_HEALTH_LISTEN_ADDR,
		DEFAULT_HEALTH_LISTEN_ADDR,
	)

	settings.add_property_info({
		"name": SETTING_EXECUTABLE_PATH,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_GLOBAL_FILE,
		"hint_string": "*.exe",
	})


func _register_setting(
	settings: EditorSettings,
	name: String,
	default_value: Variant,
) -> void:
	if not settings.has_setting(name):
		settings.set_setting(name, default_value)
	settings.set_initial_value(name, default_value, false)


func _start_tunnel(
	executable: String,
	profile: String,
	health_listen_addr: String,
	settings: EditorSettings,
) -> void:
	print("Godot AI Tunnel | starting tunnel-client...")

	_tunnel_pid = OS.create_process(
		executable,
		PackedStringArray([
			"run",
			"--profile",
			profile,
			"--health.listen-addr",
			health_listen_addr,
		]),
		false,
	)

	print(
		"Godot AI Tunnel | tunnel-client launch returned PID %d"
		% _tunnel_pid
	)

	if _tunnel_pid <= 0:
		push_error("Godot AI Tunnel | failed to start tunnel-client")
		return

	settings.set_project_metadata(
		METADATA_SECTION,
		METADATA_MANAGED_PID,
		_tunnel_pid,
	)
	print(
		"Godot AI Tunnel | started tunnel-client (PID %d)"
		% _tunnel_pid
	)


func _stop_tunnel() -> void:
	if _tunnel_pid <= 0:
		return

	if OS.is_process_running(_tunnel_pid):
		print(
			"Godot AI Tunnel | stopping tunnel-client (PID %d)"
			% _tunnel_pid
		)
		OS.kill(_tunnel_pid)

	var settings := EditorInterface.get_editor_settings()
	if settings != null:
		settings.set_project_metadata(
			METADATA_SECTION,
			METADATA_MANAGED_PID,
			0,
		)

	_tunnel_pid = -1


func _stop_stale_managed_tunnel(settings: EditorSettings) -> void:
	var stale_pid := int(
		settings.get_project_metadata(
			METADATA_SECTION,
			METADATA_MANAGED_PID,
			0,
		)
	)
	if stale_pid <= 0:
		return

	if OS.is_process_running(stale_pid):
		print(
			"Godot AI Tunnel | stopping stale managed tunnel (PID %d)"
			% stale_pid
		)
		OS.kill(stale_pid)

	settings.set_project_metadata(
		METADATA_SECTION,
		METADATA_MANAGED_PID,
		0,
	)

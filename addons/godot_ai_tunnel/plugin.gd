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
var _owns_tunnel := false


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

	var profile := str(settings.get_setting(SETTING_PROFILE))
	var health_listen_addr := str(settings.get_setting(SETTING_HEALTH_LISTEN_ADDR))
	var existing_pid := _find_health_listener_pid(health_listen_addr)

	if existing_pid > 0:
		if not _pid_is_tunnel_client(existing_pid):
			push_error(
				"Godot AI Tunnel | health port is already owned by "
				+ "a non-tunnel process (PID %d)" % existing_pid
			)
			return

		_tunnel_pid = existing_pid
		_owns_tunnel = false
		settings.set_project_metadata(
			METADATA_SECTION,
			METADATA_MANAGED_PID,
			0,
		)
		print(
			"Godot AI Tunnel | adopted existing tunnel-client (PID %d)"
			% _tunnel_pid
		)
		return

	_start_tunnel(
		executable,
		profile,
		health_listen_addr,
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

	_owns_tunnel = true
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

	if not _owns_tunnel:
		print(
			"Godot AI Tunnel | leaving adopted tunnel-client running (PID %d)"
			% _tunnel_pid
		)
		_tunnel_pid = -1
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
	_owns_tunnel = false


func _pid_is_tunnel_client(pid: int) -> bool:
	var output: Array = []
	var command := (
		"$p = Get-Process -Id %d -ErrorAction SilentlyContinue; "
		+ "if ($p) { Write-Output $p.ProcessName }"
	) % pid

	var exit_code := OS.execute(
		"powershell.exe",
		PackedStringArray([
			"-NoProfile",
			"-NonInteractive",
			"-Command",
			command,
		]),
		output,
		true,
		false,
	)

	if exit_code != 0 or output.is_empty():
		return false

	return str(output[0]).strip_edges().to_lower() == "tunnel-client"


func _find_health_listener_pid(health_listen_addr: String) -> int:
	var separator := health_listen_addr.rfind(":")
	if separator < 0 or separator == health_listen_addr.length() - 1:
		push_warning(
			"Godot AI Tunnel | invalid health listen address: %s"
			% health_listen_addr
		)
		return 0

	var port_text := health_listen_addr.substr(separator + 1)
	if not port_text.is_valid_int():
		push_warning(
			"Godot AI Tunnel | invalid health listen port: %s"
			% port_text
		)
		return 0

	var port := int(port_text)
	var output: Array = []
	var command := (
		"$c = Get-NetTCPConnection -State Listen -LocalPort %d "
		+ "-ErrorAction SilentlyContinue | Select-Object -First 1; "
		+ "if ($c) { Write-Output $c.OwningProcess }"
	) % port

	var exit_code := OS.execute(
		"powershell.exe",
		PackedStringArray([
			"-NoProfile",
			"-NonInteractive",
			"-Command",
			command,
		]),
		output,
		true,
		false,
	)

	if exit_code != 0 or output.is_empty():
		return 0

	var pid_text := str(output[0]).strip_edges()
	if not pid_text.is_valid_int():
		return 0

	return int(pid_text)

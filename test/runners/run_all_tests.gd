extends SceneTree

## Native full-suite runner. It keeps each test in a separate Godot process so
## editor-host state and test artifacts cannot leak between suites.

const SUITE_TIMEOUT_SECONDS := 60.0
const POLL_DELAY_MSEC := 25
const RUNNER_TEMP_PATH := "res://test/_temp/runner"

const SUITES := [
	{"name": "css_linear_test.gd", "editor": false},
	{"name": "easing_curve_editor_rmb_delete_test.gd", "editor": false},
	{"name": "easing_curve_manual_reorder_test.gd", "editor": false},
	{"name": "easing_curve_transform_test.gd", "editor": false},
	{"name": "easing_curve_v105_regression_test.gd", "editor": false},
	{"name": "runtime_curve_updates_test.gd", "editor": false},
	{"name": "serialization_transition_contract_test.gd", "editor": false},
	{"name": "tween_equivalence_test.gd", "editor": false},
	{"name": "easing_curve_control_editability_test.gd", "editor": true},
	{"name": "easing_curve_preview_generator_test.gd", "editor": true},
	{"name": "easing_curve_editor_position_x_drag_test.gd", "editor": true},
	{"name": "easing_curve_linear_control_alias_test.gd", "editor": true},
	{"name": "easing_curve_points_list_add_editor_test.gd", "editor": true},
	{"name": "easing_curve_points_list_reorder_editor_test.gd", "editor": true},
	{"name": "easing_curve_point_state_characterization_test.gd", "editor": true},
	{"name": "easing_curve_selection_refresh_characterization_test.gd", "editor": true},
	{"name": "easing_curve_editor_gesture_characterization_test.gd", "editor": true},
	{"name": "editor_undo_redo_test.gd", "editor": true},
]

var _project_root := ""
var _runner_temp_directory := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_project_root = ProjectSettings.globalize_path("res://")
	_runner_temp_directory = ProjectSettings.globalize_path(RUNNER_TEMP_PATH)
	DirAccess.make_dir_recursive_absolute(_runner_temp_directory)

	var results: Array[Dictionary] = []
	for suite: Dictionary in SUITES:
		results.append(await _run_suite(suite))

	print("\n=== Test summary ===")
	for result in results:
		print(
			"%s [%s]: exit=%d timeout=%s pass_marker=%s script_error=%s %s" % [
				result.name,
				result.mode,
				result.exit_code,
				result.timed_out,
				result.pass_marker,
				result.script_error,
				"PASS" if result.passed else "FAIL",
			]
		)

	var failures := results.filter(func(result: Dictionary) -> bool: return not result.passed)
	if failures.is_empty():
		_remove_directory_if_empty(_runner_temp_directory)
		print("All %d suites passed." % results.size())
		quit(0)
		return

	print("%d of %d suites failed. Preserved artifacts under %s." % [
		failures.size(), results.size(), RUNNER_TEMP_PATH,
	])
	quit(1)


func _run_suite(suite: Dictionary) -> Dictionary:
	var suite_name: String = suite.name
	var mode := "editor-host" if suite.editor else "headless"
	print("\n=== %s [%s] ===" % [suite_name, mode])

	var suite_temp_directory := _runner_temp_directory.path_join(
		"%s-%s" % [suite_name.get_basename(), _new_artifact_id()]
	)
	DirAccess.make_dir_recursive_absolute(suite_temp_directory)
	var stdout_path := suite_temp_directory.path_join("stdout.txt")
	var stderr_path := suite_temp_directory.path_join("stderr.txt")
	var godot_log_path := suite_temp_directory.path_join("godot.log")
	var suite_appdata_path := suite_temp_directory.path_join("appdata")
	DirAccess.make_dir_recursive_absolute(suite_appdata_path)
	var arguments := PackedStringArray(["--headless"])
	if suite.editor:
		arguments.append("--editor")
	arguments.append_array([
		"--path", _project_root,
		"--script", "res://test/scripts/%s" % suite_name,
		"--log-file", godot_log_path,
	])

	var had_appdata := OS.has_environment("APPDATA")
	var previous_appdata := OS.get_environment("APPDATA")
	OS.set_environment("APPDATA", suite_appdata_path)
	var process := OS.execute_with_pipe(OS.get_executable_path(), arguments, false)
	var stdout := ""
	var stderr := ""
	var exit_code := -1
	var timed_out := false
	if process.is_empty():
		stderr = "Could not start Godot process."
	else:
		var pid: int = process.pid
		var stdio: FileAccess = process.stdio
		var stderr_pipe: FileAccess = process.stderr
		var deadline := Time.get_ticks_msec() + int(SUITE_TIMEOUT_SECONDS * 1000.0)
		while OS.is_process_running(pid):
			stdout += _read_pipe(stdio)
			stderr += _read_pipe(stderr_pipe)
			if Time.get_ticks_msec() >= deadline:
				timed_out = true
				print("Timed out after %d seconds; terminating PID %d." % [SUITE_TIMEOUT_SECONDS, pid])
				_terminate_process(pid)
				break
			await create_timer(float(POLL_DELAY_MSEC) / 1000.0).timeout
		stdout += _drain_pipe(stdio)
		stderr += _drain_pipe(stderr_pipe)
		if not timed_out:
			exit_code = OS.get_process_exit_code(pid)
	if had_appdata:
		OS.set_environment("APPDATA", previous_appdata)
	else:
		OS.unset_environment("APPDATA")

	_write_text(stdout_path, stdout)
	_write_text(stderr_path, stderr)
	if not stdout.is_empty():
		print(stdout.strip_edges())
	if not stderr.is_empty():
		print(stderr.strip_edges())

	var has_pass := _has_pass_marker(stdout) or _has_pass_marker(stderr)
	var has_script_error := stdout.contains("SCRIPT ERROR:") or stderr.contains("SCRIPT ERROR:")
	var passed := not timed_out and exit_code == 0 and has_pass and not has_script_error
	var result := {
		"name": suite_name,
		"mode": mode,
		"exit_code": exit_code,
		"timed_out": timed_out,
		"pass_marker": has_pass,
		"script_error": has_script_error,
		"passed": passed,
	}
	if passed:
		_remove_tree(suite_temp_directory)
	else:
		print("Preserved temp artifacts: %s" % suite_temp_directory)
	return result


func _read_pipe(pipe: FileAccess) -> String:
	var bytes := pipe.get_buffer(65536)
	return bytes.get_string_from_utf8()


func _drain_pipe(pipe: FileAccess) -> String:
	var output := ""
	while true:
		var chunk := _read_pipe(pipe)
		if chunk.is_empty():
			return output
		output += chunk
	return output


func _terminate_process(pid: int) -> void:
	if OS.get_name() == "Windows":
		OS.execute("taskkill.exe", ["/PID", str(pid), "/T", "/F"])
	else:
		OS.kill(pid)


func _has_pass_marker(output: String) -> bool:
	for line in output.split("\n"):
		if line.strip_edges().begins_with("PASS:"):
			return true
	return false


func _write_text(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(contents)


func _remove_tree(path: String) -> void:
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _remove_directory_if_empty(path: String) -> void:
	if DirAccess.get_files_at(path).is_empty() and DirAccess.get_directories_at(path).is_empty():
		DirAccess.remove_absolute(path)


func _new_artifact_id() -> String:
	return "%d-%d" % [Time.get_ticks_usec(), randi()]

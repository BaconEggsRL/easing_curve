@tool
class_name EasingCurveUpdateChecker
extends Node
## Checks GitHub for newer Easing Curve releases when the editor plugin loads.
##
## Update checks can be enabled or disabled from:
## Project >> Tools >> Easing Curve: Enable/Disable Update Checks
##
## Update checker settings can also be viewed or edited from:
## Editor >> Editor Settings >> Easing Curve >> Update Checker
##
## Settings:
## - Enabled:
##   Controls whether Easing Curve checks GitHub for updates automatically.
##
## - Ignored Versions:
##   Release versions that should not trigger an update notification.
##   Ignoring a version only suppresses that specific release; newer releases
##   can still trigger an update notification.
##
## When a newer release is found, update_available is emitted with the
## installed version, latest version, and GitHub release URL.
##
## Network, HTTP, and JSON failures are reported as warnings/errors but do not
## prevent the plugin itself from loading.

const DEBUG_UPDATE_CHECKER := false

const SETTING_ENABLED := "easing_curve/update_checker/enabled"
const SETTING_IGNORED_VERSIONS := "easing_curve/update_checker/ignored_versions"

const UPDATE_CHECKS_ENABLE_MENU := "Easing Curve: Enable Update Checks"
const UPDATE_CHECKS_DISABLE_MENU := "Easing Curve: Disable Update Checks"

const LATEST_RELEASE_URL := (
	"https://api.github.com/repos/BaconEggsRL/easing_curve/releases/latest"
)

## Emitted when a newer, non-ignored Easing Curve release is available.
signal update_available(
	current_version: String,
	latest_version: String,
	release_url: String
)

var _request: HTTPRequest


## Registers the update checker preferences in Editor Settings.
## This should be called before check().
func setup_editor_settings() -> void:
	var settings := EditorInterface.get_editor_settings()

	if not settings.has_setting(SETTING_ENABLED):
		settings.set_setting(SETTING_ENABLED, true)

	settings.set_initial_value(
		SETTING_ENABLED,
		true,
		false
	)

	settings.add_property_info({
		"name": SETTING_ENABLED,
		"type": TYPE_BOOL,
	})

	if not settings.has_setting(SETTING_IGNORED_VERSIONS):
		settings.set_setting(
			SETTING_IGNORED_VERSIONS,
			PackedStringArray()
		)

	settings.set_initial_value(
		SETTING_IGNORED_VERSIONS,
		PackedStringArray(),
		false
	)

	settings.add_property_info({
		"name": SETTING_IGNORED_VERSIONS,
		"type": TYPE_PACKED_STRING_ARRAY,
	})


## Checks GitHub for the latest Easing Curve release.
## Does nothing when automatic update checks are disabled.
func check(current_version: String) -> void:
	var settings := EditorInterface.get_editor_settings()

	if settings.has_setting(SETTING_ENABLED):
		if not settings.get_setting(SETTING_ENABLED):
			return

	if _request != null:
		return

	_request = HTTPRequest.new()
	add_child(_request)

	_request.request_completed.connect(
		_on_request_completed.bind(current_version)
	)

	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"User-Agent: Easing-Curve-Godot-Plugin",
	])

	var error := _request.request(
		LATEST_RELEASE_URL,
		headers
	)

	if error != OK:
		_cleanup()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	current_version: String
) -> void:
	var body_text := body.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning(
			"Easing Curve update check request failed: %d" % result
		)
		_cleanup()
		return

	if response_code != 200:
		push_warning(
			"Easing Curve update check failed.\n"
			+ "HTTP %d\n%s"
			% [response_code, body_text]
		)
		_cleanup()
		return

	var json := JSON.new()
	var error := json.parse(body_text)

	if error != OK:
		push_error(
			"Easing Curve update check: Failed to parse GitHub response.\n"
			+ "JSON error: %s at line %d\n" % [
				json.get_error_message(),
				json.get_error_line(),
			]
			+ "Response:\n"
			+ body_text
		)
		_cleanup()
		return

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		_cleanup()
		return

	var latest_version := str(data.get("tag_name", ""))
	var release_url := str(data.get("html_url", ""))

	if DEBUG_UPDATE_CHECKER:
		print(
			"Easing Curve update check: current=%s, latest=%s"
			% [current_version, latest_version]
		)

	if latest_version.is_empty():
		if DEBUG_UPDATE_CHECKER:
			print("Easing Curve update check: latest release version was empty.")
		_cleanup()
		return

	if _is_newer_version(latest_version, current_version):
		var settings := EditorInterface.get_editor_settings()

		var ignored_versions: PackedStringArray = settings.get_setting(
			SETTING_IGNORED_VERSIONS
		)

		if ignored_versions.has(latest_version):
			if DEBUG_UPDATE_CHECKER:
				print(
					"Easing Curve update check: %s is ignored."
					% latest_version
				)

			_cleanup()
			return

		if DEBUG_UPDATE_CHECKER:
			print("Easing Curve update check: update available.")
		update_available.emit(
			current_version,
			latest_version,
			release_url
		)
	else:
		if DEBUG_UPDATE_CHECKER:
			print("Easing Curve update check: plugin is up to date.")

	_cleanup()


func _cleanup() -> void:
	if _request == null:
		return

	_request.queue_free()
	_request = null


func _is_newer_version(latest: String, current: String) -> bool:
	var latest_parts := _parse_version(latest)
	var current_parts := _parse_version(current)

	for i in range(3):
		if latest_parts[i] > current_parts[i]:
			return true

		if latest_parts[i] < current_parts[i]:
			return false

	return false


func _parse_version(version: String) -> Array[int]:
	version = version.strip_edges()

	if version.begins_with("v"):
		version = version.substr(1)

	var raw_parts := version.split(".")
	var parts: Array[int] = [0, 0, 0]

	for i in range(mini(raw_parts.size(), 3)):
		parts[i] = int(raw_parts[i])

	return parts

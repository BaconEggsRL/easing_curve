@tool
class_name EasingCurveUpdateChecker
extends Node


const DEBUG_UPDATE_CHECKER := false


const LATEST_RELEASE_URL := (
	"https://api.github.com/repos/BaconEggsRL/easing_curve/releases/latest"
)


signal update_available(
	current_version: String,
	latest_version: String,
	release_url: String
)


var _request: HTTPRequest


func check(current_version: String) -> void:
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

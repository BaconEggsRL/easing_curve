extends SceneTree

var _failures := 0
var _checks := 0


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error(message)


func _finish(suite_label: String) -> void:
	_finish_with_messages(
		"%d %s checks" % [_checks, suite_label],
		"%d of %d %s checks failed" % [_failures, _checks, suite_label],
	)


func _finish_with_messages(success_message: String, failure_message: String) -> void:
	if _failures == 0:
		print("PASS: %s" % success_message)
	else:
		push_error("FAIL: %s" % failure_message)
	quit(_failures)

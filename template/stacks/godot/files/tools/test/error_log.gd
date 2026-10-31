extends Logger
## Keeps every error Godot reports, so the test runner can fail the test that caused it.
##
## Errors are push_error() calls, failed engine checks and script runtime errors. Warnings
## are left to Godot's own output.

var _mutex := Mutex.new()
var _errors: PackedStringArray = []


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	script_backtraces: Array[ScriptBacktrace],
) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var message := code if rationale.is_empty() else rationale
	# A script's own error (a parse or runtime error) names its line; an engine error
	# names engine source, so the script line that called the engine is more useful.
	var where := "%s:%d" % [file.trim_prefix("res://"), line]
	if not file.begins_with("res://"):
		where = "%s:%d in %s" % [file, line, function]
		for backtrace: ScriptBacktrace in script_backtraces:
			if backtrace.get_frame_count() > 0:
				where = "%s:%d" % [
					backtrace.get_frame_file(0).trim_prefix("res://"),
					backtrace.get_frame_line(0),
				]
				break
	_mutex.lock()
	_errors.append("%s (%s)" % [message, where])
	_mutex.unlock()


## The errors reported since the last call, oldest first. Forgets them.
func take() -> PackedStringArray:
	_mutex.lock()
	var taken := _errors
	_errors = []
	_mutex.unlock()
	return taken

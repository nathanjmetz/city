class_name TelemetryLogger
extends Logger
## Catches the engine's errors and warnings, script errors included, for
## Telemetry. The engine may call this from any thread, so it only queues;
## Telemetry picks the queue up on the main thread.

var _lock := Mutex.new()
var _queue: Array = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var trace := ""
	for bt in script_backtraces:
		if bt.get_frame_count() > 0:
			trace = bt.format(0, 0).left(1200)
			# push_error() and friends report the engine's file: use the script's.
			if not file.begins_with("res://"):
				file = bt.get_frame_file(0)
				line = bt.get_frame_line(0)
			break
	_lock.lock()
	if _queue.size() < 200:
		_queue.append({"fn": function, "file": file, "line": line, "msg": (rationale if rationale != "" else code).left(300),
			"type": ["error", "warning", "script", "shader"][clampi(error_type, 0, 3)], "trace": trace})
	_lock.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


func take() -> Array:
	_lock.lock()
	var out := _queue
	_queue = []
	_lock.unlock()
	return out

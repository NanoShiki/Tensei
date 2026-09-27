extends RefCounted

# JSONL 业务日志；引擎错误另见同目录 godot.log。
static var directory := OS.get_environment("TENSEI_LOG_DIR") if not OS.get_environment("TENSEI_LOG_DIR").is_empty() else "user://logs"
static var session := ""
static var context: Dictionary = {}
static var sequence := 0
static var part := 0
static var file: FileAccess
static var max_bytes := 2 * 1024 * 1024
static var max_files := 10
static var failed := false

static func event(category: String, action: String, data: Dictionary = {}, level: String = "INFO") -> void:
	if failed: return
	if session.is_empty(): session = str(int(Time.get_unix_time_from_system() * 1000000)) + "-" + Crypto.new().generate_random_bytes(4).hex_encode()
	if file == null or file.get_position() >= max_bytes:
		if file != null: file.close()
		if DirAccess.make_dir_recursive_absolute(directory) != OK:
			_fail()
			return
		part += 1
		file = FileAccess.open(directory + "/events-" + session + "-%04d.jsonl" % part, FileAccess.WRITE)
		if file == null:
			_fail()
			return
		var paths: Array[String] = []
		for name in DirAccess.get_files_at(directory):
			if name.begins_with("events-") and name.ends_with(".jsonl"): paths.append(name)
		paths.sort()
		while paths.size() > max_files:
			DirAccess.remove_absolute(directory + "/" + paths.pop_front())
	sequence += 1
	file.store_line(JSON.stringify({"schema": 1, "utc": Time.get_datetime_string_from_system(true),
		"elapsed_ms": Time.get_ticks_msec(), "session": session, "sequence": sequence,
		"level": level, "category": category, "event": action, "context": context, "data": data}))
	file.flush()
	if file.get_error() != OK: _fail()

static func _fail() -> void:
	failed = true
	push_error("业务日志写入失败；请检查 user://logs 的磁盘空间与权限。游戏继续运行。")

static func close() -> void:
	if file != null: file.close()
	file = null

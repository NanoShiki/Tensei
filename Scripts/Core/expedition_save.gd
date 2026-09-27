extends RefCounted

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const VERSION := 1
const CONTENT_VERSION := "demo-map-1"
# 两代文件交替写入；提交失败时上一代始终可读。
var base_path := "user://expedition"
var message := ""

func _checksum(payload: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	return context.finish().hex_encode()

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 8 * 1024 * 1024: return {"invalid": true}
	var data: Variant = file.get_var(false)
	if not data is Dictionary: return {"invalid": true}
	if data.get("version") != VERSION or data.get("content_version") != CONTENT_VERSION:
		return {"incompatible": true}
	if not data.get("generation") is int or data.generation < 1: return {"invalid": true}
	if not data.get("payload") is PackedByteArray or not data.get("checksum") is String: return {"invalid": true}
	if _checksum(data.payload) != data.checksum: return {"invalid": true}
	var restored := Run.from_save(bytes_to_var(data.payload))
	if restored == null: return {"invalid": true}
	return {"generation": data.generation, "run": restored, "path": path}

func inspect() -> Dictionary:
	var best: Dictionary = {}
	var damaged := false
	for suffix in [".0.save", ".1.save"]:
		var candidate := _read(base_path + suffix)
		if candidate.has("incompatible"):
			message = "存档版本或内容版本不兼容。原档已保留。"
			return {}
		if candidate.has("invalid"): damaged = true
		if candidate.get("generation", 0) > best.get("generation", 0): best = candidate
	message = ""
	if best.is_empty():
		message = "存档损坏或无法读取。原档已保留。" if damaged else "尚无可继续的旅程"
	elif damaged:
		message = "一份存档无法读取，将恢复另一份完整存档。"
	return best

func save_run(run: RefCounted) -> bool:
	var snapshot: Dictionary = run.save_data()
	if snapshot.is_empty():
		message = "请在战斗结束后的探索地图保存。"
		return false
	var previous := inspect()
	if previous.is_empty() and message != "尚无可继续的旅程": return false
	var generation: int = previous.get("generation", 0) + 1
	var target := base_path + (".0.save" if generation % 2 == 1 else ".1.save")
	var temporary := base_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		message = "保存失败：无法写入文件。请检查磁盘空间和目录权限，留在地图重试。"
		return false
	var payload := var_to_bytes(snapshot)
	file.store_var({"version": VERSION, "content_version": CONTENT_VERSION, "generation": generation,
		"payload": payload, "checksum": _checksum(payload)}, false)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or not _read(temporary).has("run"):
		message = "保存校验失败。之前的存档已保留，请重试。"
		return false
	if FileAccess.file_exists(target):
		error = DirAccess.remove_absolute(target)
	if error == OK: error = DirAccess.rename_absolute(temporary, target)
	if error != OK:
		message = "保存提交失败。之前的存档已保留，请重试。"
		return false
	message = "旅程已保存。"
	return true

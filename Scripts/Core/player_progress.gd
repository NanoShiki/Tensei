extends RefCounted

const Log = preload("res://Scripts/Core/game_log.gd")
const VERSION := 1
const CONTENT_VERSION := "demo-familia-1"
var base_path := "user://player.familia"
var data: Dictionary = {}
var message := ""

static func initial() -> Dictionary:
	return {"player_id": Crypto.new().generate_random_bytes(16).hex_encode(), "familias": {"dawn": {"contribution": 0, "squire_xp": 0, "events": {}}}}

static func valid(snapshot: Variant) -> bool:
	if not snapshot is Dictionary or not snapshot.get("player_id") is String or not snapshot.get("familias") is Dictionary: return false
	if snapshot.player_id.length() != 32 or not snapshot.player_id.is_valid_hex_number(false): return false
	if snapshot.familias.size() != 1 or not snapshot.familias.get("dawn") is Dictionary: return false
	var guild: Dictionary = snapshot.familias.dawn
	if not guild.get("contribution") is int or not guild.get("squire_xp") is int or not guild.get("events") is Dictionary: return false
	if guild.contribution < 0 or guild.events.size() > 20000 or guild.contribution != guild.events.size() or guild.squire_xp != guild.contribution * 2: return false
	for id in guild.events:
		if not id is String or id.is_empty() or id.length() > 300 or typeof(guild.events[id]) != TYPE_BOOL or not guild.events[id]: return false
	return true

func _checksum(payload: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	return context.finish().hex_encode()

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 8 * 1024 * 1024: return {"invalid": true}
	var envelope: Variant = file.get_var(false)
	if not envelope is Dictionary: return {"invalid": true}
	if envelope.get("version") != VERSION or envelope.get("content_version") != CONTENT_VERSION: return {"incompatible": true}
	if not envelope.get("generation") is int or envelope.generation < 1: return {"invalid": true}
	if not envelope.get("payload") is PackedByteArray or not envelope.get("checksum") is String: return {"invalid": true}
	if _checksum(envelope.payload) != envelope.checksum: return {"invalid": true}
	var snapshot: Variant = bytes_to_var(envelope.payload)
	if not valid(snapshot): return {"invalid": true}
	return {"generation": envelope.generation, "data": snapshot, "path": path}

func inspect() -> Dictionary:
	var best: Dictionary = {}
	var damaged := false
	for suffix in [".0.save", ".1.save"]:
		var candidate := _read(base_path + suffix)
		if candidate.has("incompatible"):
			message = "共享眷族档案版本不兼容，原文件保留。"
			return {}
		if candidate.has("invalid"): damaged = true
		if candidate.get("generation", 0) > best.get("generation", 0): best = candidate
	message = "共享档案损坏或无法读取，原文件保留。" if damaged and best.is_empty() else ("共享档案恢复了另一份完整备份。" if damaged else "")
	return best

func refresh() -> bool:
	var stored := inspect()
	if stored.is_empty(): return false
	data = stored.data.duplicate(true)
	return true

func ensure() -> bool:
	var stored := inspect()
	if not stored.is_empty():
		data = stored.data.duplicate(true)
		return true
	if not message.is_empty(): return false
	return _commit(initial(), {})

func _commit(candidate: Dictionary, previous: Dictionary) -> bool:
	if not valid(candidate):
		message = "共享成长数据无效，未提交。"
		return false
	var generation: int = previous.get("generation", 0) + 1
	var target := base_path + (".0.save" if generation % 2 == 1 else ".1.save")
	var temporary := base_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		message = "共享成长无法写入，请检查存储后重试。"
		return false
	var payload := var_to_bytes(candidate)
	file.store_var({"version": VERSION, "content_version": CONTENT_VERSION, "generation": generation, "payload": payload, "checksum": _checksum(payload)}, false)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or not _read(temporary).has("data"):
		DirAccess.remove_absolute(temporary)
		message = "共享成长校验失败，上一份档案保留。"
		return false
	if FileAccess.file_exists(target): error = DirAccess.remove_absolute(target)
	if error == OK: error = DirAccess.rename_absolute(temporary, target)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		message = "共享成长提交失败，上一份档案保留。"
		return false
	data = candidate.duplicate(true)
	message = ""
	return true

func award_victory(event_id: String, player_id: String) -> bool:
	var previous := inspect()
	var before: Dictionary = previous.get("data", {}).duplicate(true)
	var success := false
	var duplicate := false
	if previous.is_empty() or before.get("player_id") != player_id:
		if message.is_empty(): message = "共享眷族档案缺失或归属不符，成长等待重试。"
	elif event_id.is_empty() or event_id.length() > 300:
		message = "成长事件标识无效。"
	else:
		var candidate := before.duplicate(true)
		if candidate.familias.dawn.events.has(event_id):
			message = ""
			data = before.duplicate(true)
			duplicate = true
			success = true
		else:
			candidate.familias.dawn.events[event_id] = true
			candidate.familias.dawn.contribution += 1
			candidate.familias.dawn.squire_xp += 2
			success = _commit(candidate, previous)
	Log.event("familia", "victory_growth", {"id": event_id, "success": success, "duplicate": duplicate, "reason": message, "before": before, "after": data.duplicate(true)}, "INFO" if success else "ERROR")
	return success

func companion() -> Dictionary:
	if data.is_empty(): return {}
	var xp: int = data.familias.dawn.squire_xp
	var level := 1
	for threshold in [10, 25, 50, 85]:
		if xp >= threshold: level += 1
	return {"id": "squire", "name": "见习卫士", "hp": 28 + 3 * (level - 1), "max_hp": 28 + 3 * (level - 1), "ac": 13, "attack": 4, "dex": 1, "surge": 1, "weapon": "training_sword", "level": level, "experience": xp}

func guild_level() -> int:
	if data.is_empty(): return 1
	var contribution: int = data.familias.dawn.contribution
	return 3 if contribution >= 8 else (2 if contribution >= 3 else 1)

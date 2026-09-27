extends RefCounted

const Store = preload("res://Scripts/Core/expedition_save.gd")
var base_path := "user://expedition"
var message := ""

func _id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _valid_id(value: String) -> bool:
	if value == "legacy": return true
	if value.length() != 32: return false
	for letter in value:
		if not letter in "0123456789abcdef": return false
	return true

func new_profile(label: String) -> Dictionary:
	var clean := label.strip_edges().left(32)
	return {"id": _id(), "name": clean if not clean.is_empty() else "洛恩", "character_id": "lorn"}

func _store(profile_id: String, record_id: String) -> RefCounted:
	var store := Store.new()
	store.base_path = base_path if profile_id == "legacy" and record_id == "legacy" else base_path + ".profiles/" + profile_id + "/" + record_id
	return store

func read_record(profile_id: String, record_id: String) -> Dictionary:
	if not _valid_id(profile_id) or not _valid_id(record_id):
		message = "无效的角色或存档标识。"
		return {}
	var store := _store(profile_id, record_id)
	var record: Dictionary = store.inspect()
	message = store.message
	if record.is_empty(): return {}
	if profile_id == "legacy" and record_id == "legacy":
		record.metadata = {"profile": {"id": "legacy", "name": "洛恩 · 旧版角色", "character_id": "lorn"},
			"record_id": "legacy", "name": "旧版安全点（只读）", "saved_at": int(FileAccess.get_modified_time(record.path)) * 1000000}
	else:
		var meta: Dictionary = record.metadata
		if not meta.get("profile") is Dictionary or not meta.get("name") is String or not meta.get("saved_at") is int:
			message = "存档目录信息损坏，原文件已保留。"
			return {}
		if meta.get("record_id") != record_id or meta.profile.get("id") != profile_id or meta.profile.get("character_id") != "lorn" or not meta.profile.get("name") is String:
			message = "存档归属不匹配，原文件已保留。"
			return {}
	record["warning"] = message
	return record

func list_records(profile_id: String) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if not _valid_id(profile_id): return records
	var ids: Dictionary = {}
	var directory := base_path + ".profiles/" + profile_id
	if DirAccess.dir_exists_absolute(directory):
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".0.save") or file.ends_with(".1.save"):
				var record_id := file.left(-7)
				if _valid_id(record_id): ids[record_id] = true
	if profile_id == "legacy" and (FileAccess.file_exists(base_path + ".0.save") or FileAccess.file_exists(base_path + ".1.save")):
		ids["legacy"] = true
	for record_id in ids:
		var record := read_record(profile_id, record_id)
		if record.is_empty(): record = {"error": message}
		record["profile_id"] = profile_id
		record["record_id"] = record_id
		records.append(record)
	records.sort_custom(func(a: Dictionary, b: Dictionary):
		var first: int = a.get("metadata", {}).get("saved_at", 0)
		var second: int = b.get("metadata", {}).get("saved_at", 0)
		return first > second if first != second else a.record_id < b.record_id)
	return records

func list_profiles() -> Array[Dictionary]:
	var ids: Array[String] = []
	var directory := base_path + ".profiles"
	if DirAccess.dir_exists_absolute(directory):
		for folder in DirAccess.get_directories_at(directory):
			if _valid_id(folder): ids.append(folder)
	if (FileAccess.file_exists(base_path + ".0.save") or FileAccess.file_exists(base_path + ".1.save")) and not "legacy" in ids:
		ids.append("legacy")
	ids.sort()
	var profiles: Array[Dictionary] = []
	for profile_id in ids:
		var records := list_records(profile_id)
		if records.is_empty(): continue
		var profile := {"id": profile_id, "name": "无法读取的角色 · " + profile_id.left(6), "character_id": "lorn"}
		for record in records:
			if record.has("run"):
				profile = record.metadata.profile.duplicate(true)
				break
		profile["count"] = records.size()
		profiles.append(profile)
	return profiles

func _remember(profile_id: String, record_id: String) -> void:
	# 快捷入口索引不含进度；丢失时可从各记录重建，写入失败不撤销已成功保存的记录。
	var config := ConfigFile.new()
	config.set_value("recent", "profile", profile_id)
	config.set_value("recent", "record", record_id)
	var temporary := base_path + ".recent.tmp"
	var target := base_path + ".recent.cfg"
	var error := config.save(temporary)
	if error == OK and FileAccess.file_exists(target): error = DirAccess.remove_absolute(target)
	if error == OK: error = DirAccess.rename_absolute(temporary, target)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		message = "记录可用，但最近游玩入口未更新；请从“读取存档”选择。"

func inspect() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(base_path + ".recent.cfg") == OK:
		var profile_id: Variant = config.get_value("recent", "profile", "")
		var record_id: Variant = config.get_value("recent", "record", "")
		if profile_id is String and record_id is String:
			return read_record(profile_id, record_id)
	var newest: Dictionary = {}
	var failure := "尚无可继续的旅程"
	for profile in list_profiles():
		for record in list_records(profile.id):
			if record.has("error"):
				failure = record.error
				continue
			if newest.is_empty() or record.metadata.saved_at > newest.metadata.saved_at: newest = record
	message = failure if newest.is_empty() else newest.warning
	return newest

func load_record(profile_id: String, record_id: String) -> Dictionary:
	var record := read_record(profile_id, record_id)
	if not record.is_empty(): _remember(profile_id, record_id)
	return record

func save_record(run: RefCounted, profile: Dictionary, label: String, record_id: String = "") -> String:
	message = ""
	if not profile.get("id") is String or not _valid_id(profile.id) or not profile.get("name") is String or profile.get("character_id") != "lorn":
		message = "请先创建或读取一个角色档案。"
		return ""
	var clean := label.strip_edges().left(32)
	if clean.is_empty():
		message = "请输入存档名称。"
		return ""
	if run == null or run.save_data().is_empty():
		message = "请在战斗结束后的探索地图保存。"
		return ""
	if not record_id.is_empty():
		if record_id == "legacy" or read_record(profile.id, record_id).is_empty():
			message = "无法覆盖这条记录。旧版存档请另存为新记录。"
			return ""
	else:
		record_id = _id()
	var directory: String = base_path + ".profiles/" + profile.id
	if FileAccess.file_exists(base_path + ".profiles") or DirAccess.make_dir_recursive_absolute(directory) != OK:
		message = "保存失败：无法创建角色存档目录。"
		return ""
	var store := _store(profile.id, record_id)
	var metadata := {"profile": profile.duplicate(true), "record_id": record_id, "name": clean, "saved_at": int(Time.get_unix_time_from_system() * 1000000)}
	if not store.save_run(run, metadata):
		message = store.message
		return ""
	message = "旅程已保存。"
	_remember(profile.id, record_id)
	return record_id

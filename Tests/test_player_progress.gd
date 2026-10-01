extends SceneTree

const Progress = preload("res://Scripts/Core/player_progress.gd")
var failures := 0
var base := "user://test-familia-" + Crypto.new().generate_random_bytes(8).hex_encode()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func write_data(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(value)
	file.close()

func _initialize() -> void:
	var phase := OS.get_environment("TENSEI_FAMILIA_TEST_PHASE")
	if not phase.is_empty():
		_restart_check(phase)
		return
	var progress := Progress.new()
	progress.base_path = base
	check(progress.ensure() and not progress.data.player_id.is_empty(), "首次建立稳定玩家共享身份")
	var player_id: String = progress.data.player_id
	for i in range(5): check(progress.award_victory("encounter-" + str(i), player_id), "提交独立遭遇成长")
	check(progress.companion().level == 2 and progress.companion().max_hp == 31 and progress.guild_level() == 2, "队友与组织分别成长")
	var before: Dictionary = progress.data.duplicate(true)
	var generation: int = progress.inspect().generation
	check(progress.award_victory("encounter-0", player_id) and progress.data == before and progress.inspect().generation == generation, "重复遭遇不重复成长或写盘")
	var restarted := Progress.new()
	restarted.base_path = base
	check(restarted.refresh() and restarted.data == before, "重新实例恢复共享成长")
	check(not progress.award_victory("new", "wrong-player") and progress.data == before, "不同玩家归属不能写共享成长")
	# 最新代校验损坏，旧代保留身份并可回退。
	var path: String = progress.inspect().path
	var file := FileAccess.open(path, FileAccess.READ)
	var envelope: Dictionary = file.get_var(false)
	file.close()
	envelope.checksum = "invalid"
	write_data(path, envelope)
	check(restarted.refresh() and restarted.data.player_id == player_id and restarted.data.familias.dawn.contribution == 4, "校验损坏恢复上一完整代")
	# 任一代新版本均禁止降级读写，字节保持。
	var preserved := FileAccess.get_file_as_bytes(path)
	envelope.version = 99
	write_data(path, envelope)
	preserved = FileAccess.get_file_as_bytes(path)
	check(not restarted.ensure() and FileAccess.get_file_as_bytes(path) == preserved, "不兼容代不被初始化覆盖")
	var blocked := Progress.new()
	blocked.base_path = base + "-blocked"
	DirAccess.make_dir_absolute(blocked.base_path + ".tmp")
	check(not blocked.ensure() and blocked.data.is_empty(), "写入失败不产生内存假成长")
	DirAccess.remove_absolute(blocked.base_path + ".tmp")
	var invalid := Progress.initial()
	invalid.familias.dawn.contribution = 1
	check(not Progress.valid(invalid), "贡献与事件账本不一致拒绝")
	var team := Progress.new()
	team.base_path = base + "-team"
	var legacy := Progress.initial()
	legacy.familias.erase("ember")
	legacy.familias.dawn.erase("scout_xp")
	legacy.familias.dawn.events = {"legacy": true}
	legacy.familias.dawn.contribution = 1
	legacy.familias.dawn.squire_xp = 2
	var payload := var_to_bytes(legacy)
	write_data(team.base_path + ".0.save", {"version": 1, "content_version": "demo-familia-1", "generation": 1, "payload": payload, "checksum": team._checksum(payload)})
	var original := FileAccess.get_file_as_bytes(team.base_path + ".0.save")
	check(team.ensure() and team.data.player_id == legacy.player_id and team.data.familias.dawn.scout_xp == 0 and team.data.familias.dawn.events.legacy == ["squire"], "旧共享档案保持身份并补独立游侠成长")
	check(FileAccess.get_file_as_bytes(team.base_path + ".0.save") == original, "读取迁移只在内存且保留原文件")
	var previous := Progress.new()
	previous.base_path = base + "-previous"
	var old_two := team.data.duplicate(true)
	old_two.familias.erase("ember")
	payload = var_to_bytes(old_two)
	write_data(previous.base_path + ".0.save", {"version": 1, "content_version": "demo-familia-2", "generation": 1, "payload": payload, "checksum": previous._checksum(payload)})
	original = FileAccess.get_file_as_bytes(previous.base_path + ".0.save")
	check(previous.refresh() and previous.data.familias.dawn == old_two.familias.dawn and previous.data.familias.ember.contribution == 0, "旧参战名单档案补独立炉心记录且晨行账本不变")
	check(FileAccess.get_file_as_bytes(previous.base_path + ".0.save") == original, "旧第二版共享读取保留原字节")
	invalid = previous.data.duplicate(true)
	invalid.familias.ember.events["bad"] = 1
	invalid.familias.ember.contribution = 1
	check(not Progress.valid(invalid), "拒绝非法专业贡献账本")
	for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(previous.base_path + suffix)
	check(team.award_victory("scout-only", legacy.player_id, ["scout"]) and team.data.familias.dawn.scout_xp == 2 and team.data.familias.dawn.squire_xp == 2, "仅游侠参战不增加卫士经验")
	check(team.award_victory("both", legacy.player_id, ["squire", "scout"]) and team.data.familias.dawn.contribution == 3 and team.data.familias.dawn.scout_xp == 4 and team.data.familias.dawn.squire_xp == 4, "两队友胜利组织贡献一次、各人经验分别增加")
	var shared_before: Dictionary = team.data.duplicate(true)
	check(team.award_victory("both", legacy.player_id, ["scout"]) and team.data == shared_before, "同一事件改参战名单重试也不重复成长")
	check(not team.award_victory("wrong-members", legacy.player_id, ["scout", "scout"]) and team.data == shared_before, "重复参战成员拒绝原子提交")
	invalid = team.data.duplicate(true)
	invalid.familias.dawn.scout_xp += 2
	check(not Progress.valid(invalid), "队友经验须与对应参战账本一致")
	for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(team.base_path + suffix)
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(base + suffix): DirAccess.remove_absolute(base + suffix)
	print("PLAYER PROGRESS CHECKS: ", failures, " failures")
	quit(1 if failures else 0)

func _restart_check(phase: String) -> void:
	var progress := Progress.new()
	progress.base_path = OS.get_environment("TENSEI_FAMILIA_TEST_PATH")
	assert(progress.base_path.begins_with("user://test-familia-"))
	if phase == "write":
		check(progress.ensure(), "独立进程建立共享身份")
		for i in range(5): check(progress.award_victory("restart-" + str(i), progress.data.player_id, ["squire", "scout"]), "独立进程写入两位队友共享成长")
		check(progress.award_forge(Progress.forge_event("legacy"), progress.data.player_id), "独立进程写入锻造贡献")
	else:
		check(progress.refresh() and progress.companion().level == 2 and progress.companion("scout").level == 2 and progress.guild_level() == 2, "新进程恢复玩家身份、两位队友与组织成长")
		var generation: int = progress.inspect().generation
		check(progress.award_victory("restart-0", progress.data.player_id) and progress.inspect().generation == generation, "新进程恢复去重账本")
		check(progress.data.familias.ember.contribution == 1 and progress.award_forge(Progress.forge_event("legacy"), progress.data.player_id) and progress.inspect().generation == generation, "新进程恢复锻造贡献和去重且不重复写盘")
		for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(progress.base_path + suffix)
	print("FAMILIA RESTART CHECKS: ", failures, " failures")
	quit(1 if failures else 0)

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
		for i in range(5): check(progress.award_victory("restart-" + str(i), progress.data.player_id), "独立进程写入共享成长")
	else:
		check(progress.refresh() and progress.companion().level == 2 and progress.guild_level() == 2, "新进程恢复玩家身份、卫士和组织成长")
		var generation: int = progress.inspect().generation
		check(progress.award_victory("restart-0", progress.data.player_id) and progress.inspect().generation == generation, "新进程恢复去重账本")
		for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(progress.base_path + suffix)
	print("FAMILIA RESTART CHECKS: ", failures, " failures")
	quit(1 if failures else 0)

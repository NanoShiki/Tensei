extends Node
const Log = preload("res://Scripts/Core/game_log.gd")

const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
const FloorRun = preload("res://Scripts/Exploration/floor_run.gd")
const MENU_SCENE := "res://Scenes/UI/main_menu.tscn"
const BATTLE_SCENE := "res://Scenes/Battle/battle.tscn"
var active_character: Dictionary = {}
var run: RefCounted
var show_map := false
var saves := preload("res://Scripts/Core/save_library.gd").new()
var progress := preload("res://Scripts/Core/player_progress.gd").new()
var familia_message := ""
var profile: Dictionary = {}
var active_record_id := ""
var _pending_scene := ""

func continue_exploration() -> bool:
	var saved: Dictionary = saves.inspect()
	if saved.is_empty(): return false
	return load_exploration(saved.metadata.profile.id, saved.metadata.record_id)

func load_exploration(profile_id: String, record_id: String) -> bool:
	var saved: Dictionary = saves.read_record(profile_id, record_id)
	if saved.is_empty(): return false
	var candidate: Dictionary = saved.run.character
	if candidate.familia_id == "dawn" and (not progress.refresh() or progress.data.get("player_id") != candidate.player_id):
		saves.message = "无法读取：共享眷族档案缺失、损坏或归属不符。请恢复同一玩家的共享备份。" + progress.message
		Log.event("flow", "load_rejected", {"profile_id": profile_id, "record_id": record_id, "reason": saves.message}, "WARN")
		return false
	saved = saves.load_record(profile_id, record_id)
	if saved.is_empty(): return false
	run = saved.run
	profile = saved.metadata.profile.duplicate(true)
	active_record_id = record_id
	Log.context = {"profile_id": profile.id, "record_id": record_id, "run_id": run.run_id}
	Log.event("flow", "loaded", run.log_state())
	active_character = run.character.duplicate(true)
	retry_growth()
	show_map = true
	_change_scene(BATTLE_SCENE)
	return true

func _ready() -> void:
	Log.event("session", "start", {"engine": Engine.get_version_info().string, "build": "demo-patrol-1", "platform": OS.get_name()})
	print("诊断日志目录：", ProjectSettings.globalize_path(Log.directory))
	var gm = preload("res://Scripts/Debug/gm_panel.gd").new()
	add_child(gm)

func _exit_tree() -> void:
	Log.event("session", "end")
	Log.close()

func start_battle(character_id: String) -> void:
	Log.context = {"mode": "battle_demo"}
	run = null
	show_map = false
	active_character = CharacterLibrary.resolve(character_id)
	_change_scene(BATTLE_SCENE)

func start_exploration(profile_name: String = "洛恩") -> void:
	run = FloorRun.new()
	run.setup(randi())
	profile = saves.new_profile(profile_name)
	active_record_id = ""
	active_character = run.character.duplicate(true)
	Log.context = {"profile_id": profile.id, "run_id": run.run_id}
	Log.event("flow", "new_character", run.log_state())
	show_map = true
	_change_scene(BATTLE_SCENE)

func start_character(profile_name: String = "洛恩") -> void:
	start_exploration(profile_name)
	run.phase = "city"
	run.message = "欢迎来到城市。先从第一层出发，收集 3 铁片与 6 金币打造铁剑。"
	Log.event("flow", "city_ready", run.log_state())

func return_to_menu() -> void:
	_change_scene(MENU_SCENE)

func party_companion() -> Dictionary:
	if run == null or not run.character.party_enlisted or progress.data.get("player_id") != run.character.player_id: return {}
	var member: Dictionary = progress.companion()
	member.hp = mini(run.character.party_hp, member.max_hp)
	return member

func familia_service(action: String) -> bool:
	if run == null: return false
	var before: Dictionary = run.log_state()
	var shared_before: Dictionary = progress.data.duplicate(true)
	var hero: Dictionary = run.character
	var success := false
	familia_message = ""
	if run.phase != "city" or not run.pending.is_empty(): familia_message = "请在城市整备时调整编队。"
	elif action == "join":
		if not hero.familia_id.is_empty(): familia_message = "已加入眷族。"
		elif hero.quests.hunt != "claimed": familia_message = "先交付初次讨伐委托，获得加入资格。"
		elif not progress.ensure(): familia_message = progress.message
		else:
			hero.familia_id = "dawn"
			hero.player_id = progress.data.player_id
			success = true
			familia_message = "已加入晨行眷族。可以招募见习卫士。"
	elif hero.familia_id != "dawn" or not progress.refresh() or progress.data.get("player_id") != hero.player_id:
		familia_message = "共享档案不可用或归属不符，请恢复备份。" + progress.message
	elif action == "enlist" and not hero.party_enlisted:
		hero.party_enlisted = true
		hero.party_hp = progress.companion().max_hp
		success = true
		familia_message = "见习卫士已编入队伍。本版免费招募。"
	elif action == "dismiss" and hero.party_enlisted:
		hero.party_enlisted = false
		hero.party_hp = 0
		success = true
		familia_message = "卫士已留在城市，共享成长保留。"
	elif action == "retry":
		success = retry_growth()
		familia_message = "成长记录已同步。" if success else progress.message
	else: familia_message = "当前操作条件不满足。"
	Log.context["run_id"] = run.run_id
	Log.event("familia", "service", {"action": action, "success": success, "reason": familia_message, "before": before, "after": run.log_state(), "shared_before": shared_before, "shared_after": progress.data.duplicate(true)}, "INFO" if success else "WARN")
	return success

func retry_growth() -> bool:
	if run == null or run.character.growth_pending.is_empty(): return true
	var before: Array = run.character.growth_pending.duplicate()
	for event_id in before:
		if not progress.award_victory(event_id, run.character.player_id): break
		run.character.growth_pending.erase(event_id)
	var success: bool = run.character.growth_pending.is_empty()
	Log.event("familia", "sync", {"success": success, "before": before, "after": run.character.growth_pending.duplicate(), "reason": progress.message}, "INFO" if success else "WARN")
	return success

func settle_battle(hero: Dictionary, ally: Dictionary, victory: bool) -> bool:
	if run == null or run.pending.is_empty(): return false
	var settled := hero.duplicate(true)
	if not ally.is_empty():
		settled.party_hp = ally.hp
		if victory:
			var event_id: String = run.node(run.pending).key + "/clear/" + str(run.node(run.pending).clear_count + 1)
			if event_id not in settled.growth_pending: settled.growth_pending.append(event_id)
	if not run.finish_battle(settled, victory, not ally.is_empty()): return false
	retry_growth()
	if not run.character.growth_pending.is_empty(): run.message += " 共享成长待重试，请保存当前记录。"
	active_character = run.character.duplicate(true)
	return true

func city_service(action: String) -> bool:
	var member := party_companion()
	return run != null and run.city_service(action, member.get("max_hp", 0))

func guild_level() -> int:
	if run == null or run.character.familia_id != "dawn" or not progress.refresh() or progress.data.get("player_id") != run.character.player_id: return 0
	return progress.guild_level()

func _change_scene(path: String) -> void:
	if not _pending_scene.is_empty(): return
	_pending_scene = path
	_commit_scene.call_deferred()

func _commit_scene() -> void:
	# 按钮可能属于 Window 视口，等当前输入事件分发结束后再移除旧场景。
	var path := _pending_scene
	_pending_scene = ""
	var error := get_tree().change_scene_to_file(path)
	Log.event("flow", "scene_change", {"scene": path, "error": error}, "INFO" if error == OK else "ERROR")
	if error != OK: push_error("场景切换失败：%s（%s）" % [path, error_string(error)])

extends Node
const Log = preload("res://Scripts/Core/game_log.gd")

const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
const FloorRun = preload("res://Scripts/Exploration/floor_run.gd")
const Familias = preload("res://Scripts/Character/familia_library.gd")
const Weapons = preload("res://Scripts/Character/weapon_library.gd")
const Commerce = preload("res://Scripts/Character/commerce_library.gd")
const Armors = preload("res://Scripts/Character/armor_library.gd")
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
	if not candidate.player_id.is_empty() and (not progress.refresh() or progress.data.get("player_id") != candidate.player_id):
		saves.message = "无法读取：共享眷族档案缺失、损坏或归属不符。请恢复同一玩家的共享备份。" + progress.message
		Log.event("flow", "load_rejected", {"profile_id": profile_id, "record_id": record_id, "reason": saves.message}, "WARN")
		return false
	for event in candidate.forge_pending:
		if event != progress.forge_event(profile_id, event.get_slice("/", 3)):
			saves.message = "无法读取：锻造贡献不属于此角色档案。"
			Log.event("flow", "load_rejected", {"profile_id": profile_id, "record_id": record_id, "reason": saves.message}, "WARN")
			return false
	for event in candidate.commerce_pending:
		if event != progress.commerce_event(profile_id, event.get_slice("/", 3)):
			saves.message = "无法读取：商贸贡献不属于此角色档案。"
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
	active_character = run.character.duplicate(true)
	show_map = true
	_change_scene(BATTLE_SCENE)
	return true

func _ready() -> void:
	Log.event("session", "start", {"engine": Engine.get_version_info().string, "build": "demo-armor-1", "platform": OS.get_name()})
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

func party_companion(id: String = "squire") -> Dictionary:
	var prefix := "party" if id == "squire" else "scout"
	if id not in ["squire", "scout"] or run == null or run.character.familia_id != "dawn" or not run.character[prefix + "_enlisted"] or progress.data.get("player_id") != run.character.player_id: return {}
	var member: Dictionary = progress.companion(id)
	member.hp = mini(run.character[prefix + "_hp"], member.max_hp)
	return member

func familia_service(action: String) -> bool:
	if run == null: return false
	var before: Dictionary = run.log_state()
	var shared_before: Dictionary = progress.data.duplicate(true)
	var hero: Dictionary = run.character
	var success := false
	familia_message = ""
	if run.phase != "city" or not run.pending.is_empty(): familia_message = "请在城市整备时调整编队。"
	elif action in ["join", "join_ember", "join_harbor"]:
		success = _join_familia({"join": "dawn", "join_ember": "ember", "join_harbor": "harbor"}[action])
	elif hero.player_id.is_empty() or not progress.refresh() or progress.data.get("player_id") != hero.player_id:
		familia_message = "共享档案不可用或归属不符，请恢复备份。" + progress.message
	elif action == "retry":
		success = retry_growth()
		familia_message = "成长记录已同步。" if success else progress.message
	elif hero.familia_id != "dawn":
		familia_message = "当前眷族不提供晨行远征队友，请先转回晨行。"
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
	elif action == "enlist_scout" and not hero.scout_enlisted:
		if progress.guild_level() < 2: familia_message = "晨行眷族等级 2 后可招募见习游侠。"
		else:
			hero.scout_enlisted = true
			hero.scout_hp = progress.companion("scout").max_hp
			success = true
			familia_message = "见习游侠已编入队伍。本版免费招募。"
	elif action == "dismiss_scout" and hero.scout_enlisted:
		hero.scout_enlisted = false
		hero.scout_hp = 0
		success = true
		familia_message = "游侠已留在城市，共享成长保留。"
	else: familia_message = "当前操作条件不满足。"
	if success: active_character = hero.duplicate(true)
	Log.context["run_id"] = run.run_id
	Log.event("familia", "service", {"action": action, "success": success, "reason": familia_message, "before": before, "after": run.log_state(), "shared_before": shared_before, "shared_after": progress.data.duplicate(true)}, "INFO" if success else "WARN")
	return success

func _join_familia(target: String) -> bool:
	var hero: Dictionary = run.character
	if hero.familia_id == target: familia_message = "已加入此眷族。"
	elif not Familias.qualified(hero, target): familia_message = "加入资格：" + str(Familias.ENTRIES[target].qualification) + "。"
	elif hero.hp <= 0: familia_message = "请先在旅店恢复主角，再调整眷族归属。"
	elif not hero.growth_pending.is_empty() or not hero.forge_pending.is_empty() or not hero.commerce_pending.is_empty(): familia_message = "请先同步待提交成长与专业贡献，再转会。"
	elif hero.player_id.is_empty() and not progress.ensure(): familia_message = progress.message
	elif not hero.player_id.is_empty() and (not progress.refresh() or progress.data.get("player_id") != hero.player_id): familia_message = "共享档案不可用或归属不符，请恢复备份。"
	else:
		hero.familia_id = target
		hero.player_id = progress.data.player_id
		hero.party_enlisted = false
		hero.party_hp = 0
		hero.scout_enlisted = false
		hero.scout_hp = 0
		active_character = hero.duplicate(true)
		familia_message = "已加入%s。旧组织成长保留，晨行队友留在城市；Demo 免费转会。请手动保存。" % Familias.name_for(target)
		return true
	return false

func retry_growth() -> bool:
	if run == null: return true
	if run.character.growth_pending.is_empty() and run.character.forge_pending.is_empty() and run.character.commerce_pending.is_empty(): return true
	var reasons := PackedStringArray()
	if not retry_forge(): reasons.append(progress.message)
	if not retry_commerce(): reasons.append(progress.message)
	if not run.character.growth_pending.is_empty():
		var before: Array = run.character.growth_pending.duplicate()
		for event in before:
			if not progress.award_victory(event.id, run.character.player_id, event.members): break
			run.character.growth_pending.erase(event)
		var success: bool = run.character.growth_pending.is_empty()
		if not success: reasons.append(progress.message)
		Log.event("familia", "sync", {"success": success, "before": before, "after": run.character.growth_pending.duplicate(), "reason": progress.message}, "INFO" if success else "WARN")
	progress.message = " ".join(reasons)
	return reasons.is_empty()

func retry_commerce() -> bool:
	if run == null or run.character.commerce_pending.is_empty(): return true
	var before: Array = run.character.commerce_pending.duplicate()
	for event in before:
		if event != progress.commerce_event(profile.get("id", ""), event.get_slice("/", 3)):
			progress.message = "商贸贡献不属于当前角色档案。"
			break
		if not progress.award_commerce(event, run.character.player_id): break
		run.character.commerce_pending.erase(event)
	var success: bool = run.character.commerce_pending.is_empty()
	Log.event("commerce", "sync", {"success": success, "before": before, "after": run.character.commerce_pending.duplicate(), "reason": progress.message}, "INFO" if success else "WARN")
	return success

func retry_forge() -> bool:
	if run == null or run.character.forge_pending.is_empty(): return true
	var before: Array = run.character.forge_pending.duplicate()
	for event in before:
		if event != progress.forge_event(profile.get("id", ""), event.get_slice("/", 3)):
			progress.message = "锻造贡献不属于当前角色档案。"
			break
		if not progress.award_forge(event, run.character.player_id): break
		run.character.forge_pending.erase(event)
	var success: bool = run.character.forge_pending.is_empty()
	Log.event("workshop", "sync", {"success": success, "before": before, "after": run.character.forge_pending.duplicate(), "reason": progress.message}, "INFO" if success else "WARN")
	return success

func settle_battle(hero: Dictionary, ally: Dictionary, victory: bool, scout: Dictionary = {}) -> bool:
	if run == null or run.pending.is_empty(): return false
	var settled := hero.duplicate(true)
	var members: Array = []
	if not ally.is_empty():
		settled.party_hp = ally.hp
		members.append("squire")
	if not scout.is_empty():
		settled.scout_hp = scout.hp
		members.append("scout")
	if victory and not members.is_empty():
		var event_id: String = run.node(run.pending).key + "/clear/" + str(run.node(run.pending).clear_count + 1)
		if not settled.growth_pending.any(func(event: Dictionary): return event.id == event_id):
			settled.growth_pending.append({"id": event_id, "members": members})
	if not run.finish_battle(settled, victory, not members.is_empty()): return false
	retry_growth()
	if not run.character.growth_pending.is_empty(): run.message += " 共享成长待重试，请保存当前记录。"
	active_character = run.character.duplicate(true)
	return true

func quest_service(id: String, action: String) -> bool:
	if run == null: return false
	# UI 只能提交意图；每次操作读取并核对共享档案归属。
	return run.quest_service(id, action, guild_level())

func city_service(action: String) -> bool:
	if run == null: return false
	if action in ["forge", "forge_tempered", "forge_armor"]: return _forge_service({"forge": "iron_sword", "forge_tempered": "tempered_sword", "forge_armor": "iron_armor"}[action])
	var member := party_companion()
	var scout := party_companion("scout")
	return run != null and run.city_service(action, member.get("max_hp", 0), scout.get("max_hp", 0))

func forge_reason(recipe_id: String = "iron_sword") -> String:
	if run == null or run.phase != "city" or not run.pending.is_empty(): return "请在城市工坊制作。"
	if not run.character.forge_pending.is_empty(): return "请先同步待提交锻造贡献。"
	if recipe_id == "iron_armor": return Armors.reason(run.character, recipe_id)
	return Weapons.reason(run.character, recipe_id, guild_level() if recipe_id == "tempered_sword" else 0)

func equip_weapon(id: String) -> bool:
	if run == null: return false
	var success: bool = run.equip_weapon(id)
	if success: active_character = run.character.duplicate(true)
	return success

func equip_armor(id: String) -> bool:
	if run == null or get_tree().paused: return false
	var success: bool = run.equip_armor(id)
	if success: active_character = run.character.duplicate(true)
	return success

func _station_limits(action: String) -> Array:
	if run == null or action != "rest": return [0, 0]
	if run.character.party_enlisted or run.character.scout_enlisted:
		if not progress.refresh() or progress.data.get("player_id") != run.character.player_id: return [0, 0]
	return [party_companion().get("max_hp", 0), party_companion("scout").get("max_hp", 0)]

func station_reason(action: String) -> String:
	if run == null: return "请先开始探索。"
	var limits := _station_limits(action)
	return run.station_reason(action, limits[0], limits[1])

func station_service(action: String) -> bool:
	if run == null: return false
	var limits := _station_limits(action)
	var success: bool = run.station_service(action, limits[0], limits[1])
	if success: active_character = run.character.duplicate(true)
	return success

func _forge_service(recipe_id: String) -> bool:
	var before: Dictionary = run.log_state()
	var success := false
	var event_id: String = progress.forge_event(profile.get("id", ""), recipe_id)
	var hero: Dictionary = run.character
	var reason := forge_reason(recipe_id)
	if not reason.is_empty(): run.message = reason
	elif not progress.valid_forge_event(event_id): run.message = "角色身份无效。"
	elif hero.player_id.is_empty() and not progress.ensure(): run.message = progress.message
	elif not hero.player_id.is_empty() and (not progress.refresh() or progress.data.get("player_id") != hero.player_id):
		run.message = "共享档案不可用或归属不符，请恢复备份后打造。" + progress.message
	else:
		if run.city_service({"iron_sword": "forge", "tempered_sword": "forge_tempered", "iron_armor": "forge_armor"}[recipe_id], 0, 0, progress.guild_level("ember")):
			hero.player_id = progress.data.player_id
			hero.forge_pending.append(event_id)
			success = true
			if retry_forge(): run.message += " 炉心贡献已同步（同角色同配方只计一次）。"
			else: run.message += " 炉心贡献待同步，请保存当前记录；恢复存储后重试。"
			active_character = hero.duplicate(true)
	Log.event("workshop", "craft", {"id": event_id, "recipe": recipe_id, "ember_level": progress.guild_level("ember") if not progress.data.is_empty() else 0, "success": success, "reason": run.message, "before": before, "after": run.log_state(), "player_id": progress.data.get("player_id", "")}, "INFO" if success else "WARN")
	return success

func guild_level() -> int:
	if run == null or run.character.familia_id.is_empty() or not progress.refresh() or progress.data.get("player_id") != run.character.player_id: return 0
	return progress.guild_level(run.character.familia_id)

func commerce_reason(id: String) -> String:
	if run == null or run.phase != "city" or not run.pending.is_empty(): return "请在城市交付订单。"
	return Commerce.reason(run.character, id, guild_level() if id == "member_bundle" else 0)

func trade_service(id: String, quantity: int) -> bool:
	if run == null or get_tree().paused: return false
	var success: bool = run.city_trade(id, quantity)
	if success: active_character = run.character.duplicate(true)
	return success

func commerce_service(id: String) -> bool:
	if run == null: return false
	var before: Dictionary = run.log_state()
	var success := false
	var event_id: String = progress.commerce_event(profile.get("id", ""), id)
	var hero: Dictionary = run.character
	var reason := commerce_reason(id)
	if not reason.is_empty(): run.message = reason
	elif not progress.valid_commerce_event(event_id): run.message = "角色或订单身份无效。"
	elif hero.player_id.is_empty() and not progress.ensure(): run.message = progress.message
	elif not hero.player_id.is_empty() and (not progress.refresh() or progress.data.get("player_id") != hero.player_id): run.message = "共享档案不可用或归属不符，请恢复备份。"
	else:
		if run.commerce_service(id, progress.guild_level("harbor")):
			hero.player_id = progress.data.player_id
			hero.commerce_pending.append(event_id)
			success = true
			if retry_commerce(): run.message += " 集市贡献已同步（同角色同订单只计一次）。"
			else: run.message += " 集市贡献待同步，请保存当前记录并恢复存储后重试。"
			active_character = hero.duplicate(true)
	Log.event("commerce", "exchange", {"id": id, "event_id": event_id, "success": success, "reason": run.message, "harbor_level": progress.guild_level("harbor") if not progress.data.is_empty() else 0, "player_id": progress.data.get("player_id", ""), "before": before, "after": run.log_state()}, "INFO" if success else "WARN")
	return success

func commerce_status() -> String:
	if run == null: return ""
	var hero: Dictionary = run.character
	if hero.player_id.is_empty(): return "集市眷族：供货订单对所有归属开放；实际交付贡献 +1，同角色同订单只计一次。"
	if not progress.refresh() or progress.data.get("player_id") != hero.player_id: return "集市共享档案不可用，请恢复同一玩家备份。"
	return "集市等级 %d · 贡献 %d · 待同步 %d；同角色同订单只计一次。" % [progress.guild_level("harbor"), progress.data.familias.harbor.contribution, hero.commerce_pending.size()]

func workshop_status() -> String:
	if run == null: return ""
	var hero: Dictionary = run.character
	if hero.player_id.is_empty(): return "炉心工坊：实际打造 +1 共享贡献，无需加入；同角色同配方只计一次。"
	if not progress.refresh() or progress.data.get("player_id") != hero.player_id: return "炉心共享档案不可用，请恢复同一玩家备份。"
	return "炉心等级 %d · 贡献 %d · 待同步 %d；实际打造 +1，同角色同配方只计一次。" % [progress.guild_level("ember"), progress.data.familias.ember.contribution, hero.forge_pending.size()]

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

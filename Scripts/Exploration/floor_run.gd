extends RefCounted

const Log = preload("res://Scripts/Core/game_log.gd")
const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
var floor_number := 1
var total_floors := 30
var seed_value := 1
var run_id := ""
# 历史层与当前层共享运行时节点；对外查看历史使用深拷贝快照。
var _floors: Dictionary = {}
var route: Array[String] = []
var nodes: Array[Dictionary] = []
var current := "entry"
var pending := ""
var completed := false
var failed := false
var phase := "descending"
var deepest_floor := 1
var steps_taken := 0
var battles_won := 0
var return_route: Array[String] = []
var _locations: Dictionary = {}
var _summary: Dictionary = {}
var character: Dictionary = CharacterLibrary.resolve()
var message := "沿连线选择下一个节点。每层拥有独立路线。"

func setup(run_seed: int, count: int = 30, expedition_id: String = "") -> void:
	seed_value = run_seed
	run_id = expedition_id if not expedition_id.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()
	total_floors = maxi(1, count)
	floor_number = 1
	completed = false
	failed = false
	phase = "descending"
	deepest_floor = 1
	steps_taken = 0
	battles_won = 0
	return_route.clear()
	_locations.clear()
	_summary.clear()
	_floors.clear()
	route.clear()
	nodes = []
	character = CharacterLibrary.resolve()
	message = "沿连线选择下一个节点。每层拥有独立路线。"
	generate_floor()

func generate_floor() -> void:
	# 重复请求不会重掷已生成楼层，也不会清空当前路线或待结算战斗。
	if _floors.has(floor_number): return
	nodes = []
	current = "entry"
	pending = ""
	var random := RandomNumberGenerator.new()
	random.seed = seed_value + floor_number * 997
	nodes.append({"id": "entry", "kind": "entry", "step": 0, "lane": 1, "next": ["1a", "1b"], "done": true})
	for step in range(1, 4):
		for lane in range(2):
			var id := "%d%s" % [step, "a" if lane == 0 else "b"]
			var kind := "battle" if step == 1 else str(["battle", "rest", "cache"][random.randi_range(0, 2)])
			# 每层保留可选休整路线；另一条路线由种子决定。
			if step == 2 and lane == 1: kind = "rest"
			var next: Array = ["exit"] if step == 3 else ["%da" % (step + 1), "%db" % (step + 1)]
			nodes.append({"id": id, "kind": kind, "step": step, "lane": lane * 2, "next": next, "done": false})
	nodes.append({"id": "exit", "kind": "exit", "step": 4, "lane": 1, "next": [], "done": false})
	for item in nodes:
		item["key"] = node_key(floor_number, item.id)
		item["visited"] = item.id == "entry"
		item["cleared"] = false
		item["reward_claimed"] = false
		item["enemy_active"] = item.kind == "battle"
		item["respawn_in"] = 0
		item["respawn_total"] = 0
		item["clear_count"] = 0
		_locations[item.key] = {"key": item.key, "floor": floor_number, "id": item.id}
	_floors[floor_number] = nodes
	deepest_floor = maxi(deepest_floor, floor_number)
	route.append(node_key(floor_number, "entry"))

func node_key(level: int, id: String) -> String:
	return "%s/floor/%d/node/%s" % [run_id, level, id]

func floor_snapshot(level: int) -> Array:
	# 快照仅供读取；修改返回值不会改写历史、奖励或当前地图。
	return _floors.get(level, []).duplicate(true)

func node(id: String) -> Dictionary:
	for item in nodes:
		if item.id == id: return item
	return {}

func can_enter(id: String) -> bool:
	return phase == "descending" and not failed and pending.is_empty() and character.hp > 0 and id in node(current).get("next", []) and not node(id).is_empty()

func _advance_step() -> void:
	steps_taken += 1
	for level_nodes in _floors.values():
		for item in level_nodes:
			if item.kind == "battle" and not item.enemy_active and item.respawn_in > 0:
				item.respawn_in -= 1
				if item.respawn_in == 0: item.enemy_active = true

func _arrive(item: Dictionary) -> String:
	item.visited = true
	if item.kind == "battle" and item.enemy_active:
		pending = item.id
		return "battle"
	item.done = true
	current = item.id
	_record_position(item.key)
	if item.kind == "rest" and not item.reward_claimed:
		item.reward_claimed = true
		character.hp = mini(character.max_hp, character.hp + 10)
		message = "营地休整：恢复 10 生命。"
	elif item.kind == "cache" and not item.reward_claimed:
		item.reward_claimed = true
		character.potions += 1
		message = "找到补给：获得 1 瓶治疗药水。"
	return str(item.kind)

func _record_position(key: String) -> void:
	if phase == "returning": return_route.append(key)
	else: route.append(key)

func enter(id: String) -> String:
	var before := log_state()
	var result := _enter(id)
	Log.context["run_id"] = run_id
	Log.event("exploration", "enter", {"input": {"id": id}, "success": not result.is_empty(), "before": before, "after": log_state()}, "INFO" if not result.is_empty() else "WARN")
	return result

func _enter(id: String) -> String:
	if not can_enter(id): return ""
	_advance_step()
	var item := node(id)
	var result := _arrive(item)
	if item.kind == "exit":
		if floor_number == total_floors:
			completed = true
			message = "已抵达最深层出口。可以选择返程路线返回城市。"
		else:
			_load_floor(floor_number + 1)
			message = "抵达第 %d 层，生命与药水延续。" % floor_number
	return result

func _load_floor(level: int) -> void:
	floor_number = level
	if _floors.has(level):
		nodes = _floors[level]
		current = "entry"
		route.append(node_key(level, "entry"))
	else:
		generate_floor()

func can_descend_floor() -> bool:
	return phase == "descending" and current == "exit" and floor_number < total_floors and pending.is_empty() and not failed and character.hp > 0

func descend_floor(expected_floor: int) -> bool:
	var before := log_state()
	var result := _descend_floor(expected_floor)
	Log.context["run_id"] = run_id
	Log.event("exploration", "descend_floor", {"input": {"expected_floor": expected_floor}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _descend_floor(expected_floor: int) -> bool:
	if not can_descend_floor() or floor_number != expected_floor: return false
	_advance_step()
	_load_floor(floor_number + 1)
	message = "抵达第 %d 层，保留原地图与探索状态。" % floor_number
	return true

func finish_battle(hero: Dictionary, victory: bool) -> bool:
	var before := log_state()
	var result := _finish_battle(hero, victory)
	Log.context["run_id"] = run_id
	Log.event("exploration", "finish_battle", {"input": {"hero": hero, "victory": victory}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _finish_battle(hero: Dictionary, victory: bool) -> bool:
	if pending.is_empty(): return false
	var was_captain := is_captain_node(pending)
	var previously_defeated: bool = character.get("captain_defeated", false)
	character = hero.duplicate(true)
	character.captain_defeated = previously_defeated
	if victory:
		if was_captain: character.captain_defeated = true
		current = pending
		node(current).done = true
		node(current).cleared = true
		var item := node(current)
		item.enemy_active = false
		item.clear_count += 1
		battles_won += 1
		character.gold += 3
		character.scrap += 1
		var random := RandomNumberGenerator.new()
		random.seed = seed_value + floor_number * 997 + int(item.step) * 101 + int(item.lane) * 17 + int(item.clear_count) * 7919
		item.respawn_total = random.randi_range(3, 5)
		item.respawn_in = item.respawn_total
		_record_position(item.key)
		message = "战斗胜利：金币 +3、铁片 +1。此处怪物将在再走 %d 步后刷新。" % item.respawn_in
		if was_captain:
			message = "已击败守关队长！阶段目标达成，可以自由返程回城。金币 +3、铁片 +1。"
			Log.event("objective", "captain_defeated", {"run_id": run_id, "first_clear": not previously_defeated})
	else:
		failed = true
		phase = "failed"
		message = "探索失败。返回主菜单可开始新旅程。"
	pending = ""
	return true

func can_begin_return() -> bool:
	return phase == "descending" and not failed and pending.is_empty() and character.hp > 0 and not route.is_empty()

func begin_return() -> bool:
	var before := log_state()
	var result := _begin_return()
	Log.context["run_id"] = run_id
	Log.event("exploration", "begin_return", {"input": {}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _begin_return() -> bool:
	if not can_begin_return(): return false
	phase = "returning"
	return_route.append(node(current).key)
	message = "已开始返程。沿向上连线自由选路，每走一步推进怪物刷新。"
	return true

func can_begin_descent() -> bool:
	return phase == "returning" and not failed and pending.is_empty() and character.hp > 0

func begin_descent() -> bool:
	var before := log_state()
	var result := _begin_descent()
	Log.context["run_id"] = run_id
	Log.event("exploration", "begin_descent", {"input": {}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _begin_descent() -> bool:
	if not can_begin_descent(): return false
	phase = "descending"
	message = "已转向深入。可以沿连线再次经过已到访节点。"
	return true

func return_targets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if phase != "returning" or not pending.is_empty() or character.hp <= 0: return result
	if current == "entry":
		if floor_number == 1:
			result.append({"key": run_id + "/city", "floor": 0, "id": "city"})
		else:
			result.append(_locations[node_key(floor_number - 1, "exit")].duplicate(true))
	else:
		for item in nodes:
			if current in item.next:
				result.append(_locations[item.key].duplicate(true))
	return result

func return_target() -> Dictionary:
	# 仅有一个出口时用于跨层、回城快捷按钮；分叉由玩家点选。
	var choices := return_targets()
	return choices[0] if choices.size() == 1 else {}

func step_return(expected_key: String) -> bool:
	var before := log_state()
	var result := _step_return(expected_key)
	Log.context["run_id"] = run_id
	Log.event("exploration", "step_return", {"input": {"expected_key": expected_key}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _step_return(expected_key: String) -> bool:
	var target: Dictionary = {}
	for choice in return_targets():
		if choice.key == expected_key: target = choice
	if target.is_empty(): return false
	_advance_step()
	if target.id == "city":
		phase = "returned"
		_summary = {"run_id": run_id, "deepest_floor": deepest_floor, "cleared_count": battles_won, "character": character.duplicate(true)}
		message = "已安全回城。本趟探索结束。"
		return true
	floor_number = target.floor
	nodes = _floors[floor_number]
	message = "返程中：选择向上的连线，注意怪物剩余刷新步数。"
	_arrive(node(target.id))
	return true

func return_summary() -> Dictionary:
	return _summary.duplicate(true)

func enter_city() -> bool:
	var before := log_state()
	var result := _enter_city()
	Log.context["run_id"] = run_id
	Log.event("exploration", "enter_city", {"input": {}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _enter_city() -> bool:
	if phase != "returned": return false
	phase = "city"
	message = "已回到城市。战利品随身保留，可休整、补给或打造铁剑。"
	return true

func city_service(action: String) -> bool:
	var before := log_state()
	var result := _city_service(action)
	Log.context["run_id"] = run_id
	Log.event("exploration", "city_service", {"input": {"action": action}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _city_service(action: String) -> bool:
	if phase != "city": return false
	match action:
		"rest":
			if character.hp >= character.max_hp: return false
			character.hp = character.max_hp
			message = "旅店休整：生命已恢复。Demo 阶段免费。"
		"potion":
			if character.gold < 3: return false
			character.gold -= 3
			character.potions += 1
			message = "花费 3 金币，购入 1 瓶治疗药水。"
		"forge":
			if character.gold < 6 or character.scrap < 3 or character.weapon == "iron_sword": return false
			character.gold -= 6
			character.scrap -= 3
			character.weapon = "iron_sword"
			message = "花费 6 金币、3 铁片，打造并装备铁剑。剑击与强攻伤害 +2。"
		_: return false
	return true

func depart_city(next_seed: int) -> bool:
	var before := log_state()
	var result := _depart_city(next_seed)
	Log.context["run_id"] = run_id
	Log.event("exploration", "depart_city", {"input": {"next_seed": next_seed}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _depart_city(next_seed: int) -> bool:
	if phase != "city" or character.hp <= 0: return false
	var prepared := character.duplicate(true)
	setup(next_seed, total_floors)
	character = prepared
	message = "带着装备、金币、铁片与补给，从第一层开始新的远征。"
	return true

func save_data() -> Dictionary:
	# 地图与城市使用同一角色快照，旧记录读取不会向外部余额重复发奖。
	if phase not in ["descending", "returning", "city"] or not pending.is_empty() or failed or character.hp <= 0: return {}
	return {"seed": seed_value, "run_id": run_id, "total_floors": total_floors,
		"floor_number": floor_number, "deepest_floor": deepest_floor, "phase": phase,
		"current": current, "completed": completed, "steps_taken": steps_taken,
		"battles_won": battles_won, "character": character.duplicate(true),
		"floors": _floors.duplicate(true), "route": route.duplicate(), "return_route": return_route.duplicate()}

static func from_save(data: Variant) -> RefCounted:
	if not data is Dictionary: return null
	var shape := {"seed": TYPE_INT, "run_id": TYPE_STRING, "total_floors": TYPE_INT,
		"floor_number": TYPE_INT, "deepest_floor": TYPE_INT, "phase": TYPE_STRING,
		"current": TYPE_STRING, "completed": TYPE_BOOL, "steps_taken": TYPE_INT,
		"battles_won": TYPE_INT, "character": TYPE_DICTIONARY, "floors": TYPE_DICTIONARY,
		"route": TYPE_ARRAY, "return_route": TYPE_ARRAY}
	for key in shape:
		if not data.has(key) or typeof(data[key]) != shape[key]: return null
	if data.run_id.is_empty() or data.total_floors < 1 or data.total_floors > 1000: return null
	if data.floor_number < 1 or data.floor_number > data.deepest_floor or data.deepest_floor > data.total_floors: return null
	if data.phase not in ["descending", "returning", "city"] or data.steps_taken < 0 or data.battles_won < 0: return null
	data = data.duplicate(true)
	# 原地图记录没有经济字段，读取时补零余额和原木剑，保留原文件。
	for key in ["gold", "scrap", "weapon", "captain_defeated"]:
		if not data.character.has(key): data.character[key] = CharacterLibrary.resolve()[key]
	var hero := CharacterLibrary.resolve()
	for key in hero:
		if not data.character.has(key) or typeof(data.character[key]) != typeof(hero[key]): return null
	if data.character.id != "lorn" or data.character.max_hp <= 0 or data.character.hp <= 0 or data.character.hp > data.character.max_hp: return null
	if data.character.potions < 0 or data.character.fire_potions < 0: return null
	if data.character.gold < 0 or data.character.scrap < 0 or data.character.weapon not in ["training_sword", "iron_sword"]: return null
	if data.phase == "city" and (data.current != "entry" or data.floor_number != 1): return null
	if data.floors.size() != data.deepest_floor: return null
	var restored = load("res://Scripts/Exploration/floor_run.gd").new()
	restored.setup(data.seed, data.total_floors, data.run_id)
	# 用本内容版本生成拓扑校验存档，再覆盖运行时字段；不重新抽取已存刷新阈值。
	for level in range(1, data.deepest_floor + 1):
		restored.floor_number = level
		restored.generate_floor()
		if not data.floors.has(level) or not data.floors[level] is Array: return null
		var saved_nodes: Array = data.floors[level]
		if saved_nodes.size() != restored.nodes.size(): return null
		for index in range(saved_nodes.size()):
			var saved: Variant = saved_nodes[index]
			var expected: Dictionary = restored.nodes[index]
			if not saved is Dictionary: return null
			for key in expected:
				if not saved.has(key) or typeof(saved[key]) != typeof(expected[key]): return null
			for key in ["id", "key", "kind", "step", "lane", "next"]:
				if saved[key] != expected[key]: return null
			if saved.respawn_in < 0 or saved.respawn_total < saved.respawn_in or saved.clear_count < 0: return null
			if saved.kind == "battle":
				if saved.enemy_active != (saved.respawn_in == 0): return null
				if saved.cleared != (saved.clear_count > 0): return null
			if (saved.cleared or saved.reward_claimed) and not saved.visited: return null
			restored.nodes[index] = saved.duplicate(true)
	for history in [data.route, data.return_route]:
		for key in history:
			if not key is String or not restored._locations.has(key): return null
	restored.floor_number = data.floor_number
	restored.nodes = restored._floors[data.floor_number]
	if restored.node(data.current).is_empty() or not restored.node(data.current).visited: return null
	restored.current = data.current
	restored.phase = data.phase
	restored.completed = data.completed
	restored.steps_taken = data.steps_taken
	restored.battles_won = data.battles_won
	restored.character = data.character.duplicate(true)
	restored.route.assign(data.route)
	restored.return_route.assign(data.return_route)
	restored.message = "已恢复旅程。楼层、到访记录与刷新步数保持保存时的状态。"
	return restored

func log_state() -> Dictionary:
	var timers: Dictionary = {}
	for items in _floors.values():
		for item in items:
			if item.clear_count > 0: timers[item.key] = {"remaining": item.respawn_in, "active": item.enemy_active}
	return {"run_id": run_id, "seed": seed_value, "floor": floor_number, "node": current,
		"pending": pending, "phase": phase, "steps": steps_taken, "wins": battles_won,
		"hero": character.duplicate(true), "respawn": timers, "message": message}

func potion_reason() -> String:
	if phase not in ["descending", "returning", "city"] or not pending.is_empty() or failed or character.hp <= 0:
		return "请在探索地图或城市安全状态下使用。"
	if character.potions <= 0: return "治疗药水已用尽。"
	if character.hp >= character.max_hp: return "生命已满，无需使用。"
	return ""

func is_captain_node(id: String) -> bool:
	return floor_number == 3 and id == "1a"

func use_field_potion() -> bool:
	var before := log_state()
	var reason := potion_reason()
	var amount := 0
	if reason.is_empty():
		amount = mini(int(preload("res://Scripts/Battle/ability_library.gd").ENTRIES.potion.amount), character.max_hp - character.hp)
		character.potions -= 1
		character.hp += amount
		message = "使用治疗药水：恢复 %d 生命，剩余 %d 瓶。" % [amount, character.potions]
	Log.context["run_id"] = run_id
	Log.event("inventory", "field_potion", {"success": reason.is_empty(), "reason": reason, "amount": amount, "before": before, "after": log_state()}, "INFO" if reason.is_empty() else "WARN")
	return reason.is_empty()

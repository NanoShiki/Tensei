extends RefCounted

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
	return phase == "descending" and not completed and not failed and pending.is_empty() and character.hp > 0 and id in node(current).get("next", []) and not node(id).get("done", true)

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
	if not can_enter(id): return ""
	_advance_step()
	var item := node(id)
	var result := _arrive(item)
	if item.kind == "exit":
		if floor_number == total_floors:
			completed = true
			message = "已抵达最深层出口。可以选择返程路线返回城市。"
		else:
			floor_number += 1
			generate_floor()
			message = "抵达第 %d 层，生命与药水延续。" % floor_number
	return result

func finish_battle(hero: Dictionary, victory: bool) -> bool:
	if pending.is_empty(): return false
	character = hero.duplicate(true)
	if victory:
		current = pending
		node(current).done = true
		node(current).cleared = true
		var item := node(current)
		item.enemy_active = false
		item.clear_count += 1
		battles_won += 1
		var random := RandomNumberGenerator.new()
		random.seed = seed_value + floor_number * 997 + int(item.step) * 101 + int(item.lane) * 17 + int(item.clear_count) * 7919
		item.respawn_total = random.randi_range(3, 5)
		item.respawn_in = item.respawn_total
		_record_position(item.key)
		message = "战斗胜利。此处怪物将在再走 %d 步后刷新。" % item.respawn_in
	else:
		failed = true
		phase = "failed"
		message = "探索失败。返回主菜单可开始新旅程。"
	pending = ""
	return true

func can_begin_return() -> bool:
	return phase == "descending" and not failed and pending.is_empty() and character.hp > 0 and not route.is_empty()

func begin_return() -> bool:
	if not can_begin_return(): return false
	phase = "returning"
	return_route.append(node(current).key)
	message = "已开始返程。沿向上连线自由选路，每走一步推进怪物刷新。"
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

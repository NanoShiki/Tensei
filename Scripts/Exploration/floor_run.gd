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
var character: Dictionary = CharacterLibrary.resolve()
var message := "沿连线选择下一个节点。每层拥有独立路线。"

func setup(run_seed: int, count: int = 30, expedition_id: String = "") -> void:
	seed_value = run_seed
	run_id = expedition_id if not expedition_id.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()
	total_floors = maxi(1, count)
	floor_number = 1
	completed = false
	failed = false
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
	_floors[floor_number] = nodes
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
	return not completed and not failed and pending.is_empty() and character.hp > 0 and id in node(current).get("next", []) and not node(id).get("done", true)

func enter(id: String) -> String:
	if not can_enter(id): return ""
	var item := node(id)
	item.visited = true
	if item.kind == "battle":
		pending = id
		return "battle"
	item.done = true
	current = id
	route.append(item.key)
	if item.kind == "rest":
		item.reward_claimed = true
		character.hp = mini(character.max_hp, character.hp + 10)
		message = "营地休整：恢复 10 生命。"
	elif item.kind == "cache":
		item.reward_claimed = true
		character.potions += 1
		message = "找到补给：获得 1 瓶治疗药水。"
	elif item.kind == "exit":
		if floor_number == total_floors:
			completed = true
			message = "已完成本次探索的全部楼层。"
		else:
			floor_number += 1
			generate_floor()
			message = "抵达第 %d 层，生命与药水延续。" % floor_number
	return str(item.kind)

func finish_battle(hero: Dictionary, victory: bool) -> bool:
	if pending.is_empty(): return false
	character = hero.duplicate(true)
	if victory:
		current = pending
		node(current).done = true
		node(current).cleared = true
		route.append(node(current).key)
		message = "战斗胜利。选择下一段路线。"
	else:
		failed = true
		message = "探索失败。返回主菜单可开始新旅程。"
	pending = ""
	return true

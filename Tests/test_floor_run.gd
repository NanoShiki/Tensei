extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func advance_floor(run: RefCounted) -> void:
	var level: int = run.floor_number
	for step in range(5):
		if run.completed or run.floor_number != level: return
		var id: String = run.node(run.current).next[0]
		if run.enter(id) == "battle": run.finish_battle(run.character, true)

func _initialize() -> void:
	var run := Run.new()
	run.setup(123, 3, "route-test")
	check(run.route == [run.node_key(1, "entry")], "初始路线只包含首层入口")
	check(run.floor_snapshot(2).is_empty(), "未抵达的楼层不提前生成")
	var before: Array = run.floor_snapshot(1)
	check(run.enter("exit") == "" and run.enter("missing") == "", "跳节点和未知节点拒绝")
	check(run.floor_snapshot(1) == before and run.route.size() == 1, "非法进入不改变地图或路线")
	run.enter("1a")
	check(run.node("1a").visited and not run.node("1a").cleared and not run.node("1a").done, "进入战斗只登记到访，清理与完成待胜利")
	check(run.route.size() == 1 and run.pending == "1a", "待结算战斗与已通过路线分离")
	run.generate_floor()
	check(run.pending == "1a" and run.route.size() == 1, "重复生成不能解锁待结算地图")
	var hero: Dictionary = run.character.duplicate(true)
	hero.hp = 17
	hero.potions = 1
	hero.fire_potions = 0
	run.finish_battle(hero, true)
	check(run.node("1a").cleared and run.node("1a").done and not run.node("1a").reward_claimed, "战胜清理节点，当前战斗无物品奖励")
	check(run.route == [run.node_key(1, "entry"), run.node_key(1, "1a")], "胜利只追加实际通过的分支")
	check(not run.finish_battle(hero, true) and run.route.size() == 2, "重复战斗回写不能重复追加路线")
	run.enter("2b")
	check(run.node("2b").reward_claimed and not run.node("2b").cleared, "营地领取与战斗清理分别记录")
	check(run.character.hp == 27 and run.enter("2b") == "" and run.character.hp == 27, "营地只能领取一次")
	if run.enter("3a") == "battle": run.finish_battle(run.character, true)
	var carried: Dictionary = run.character.duplicate(true)
	run.enter("exit")
	check(run.floor_number == 2 and run.character == carried, "跨层保留生命和两类药水")
	var first: Array = run.floor_snapshot(1)
	check(first.size() == 8 and first[7].done, "首层出口与完整楼层保留")
	check(first[1].cleared and not first[2].visited, "历史保留清理状态与未走分支")
	check(run.route == [run.node_key(1, "entry"), run.node_key(1, "1a"), run.node_key(1, "2b"), run.node_key(1, "3a"), run.node_key(1, "exit"), run.node_key(2, "entry")], "跨层路线含上一层出口和下一层入口")
	check(first[0].key != run.node("entry").key, "不同楼层同名节点有不同标识")
	first[1].cleared = false
	first[0].next.clear()
	check(run.floor_snapshot(1)[1].cleared and run.floor_snapshot(1)[0].next.size() == 2, "历史快照嵌套修改不污染运行时")
	var active: Array = run.floor_snapshot(2)
	active[1].done = true
	check(run.can_enter("1a"), "当前层快照也不泄露可修改状态")
	var history: Array = run.floor_snapshot(1)
	advance_floor(run)
	advance_floor(run)
	check(run.completed and run.floor_number == 3 and run.route.size() == 15, "三层路线完整，终点仅记录一次")
	check(run.floor_snapshot(1) == history, "后续生成与战斗不改写首层历史")
	check(run.enter("exit") == "" and run.route.size() == 15, "终点重复进入无副作用")
	run.setup(123, 3, "route-test")
	check(not run.completed and not run.failed and run.pending.is_empty() and run.floor_snapshot(2).is_empty(), "重新出发清空旧历史与终局状态")
	check(run.floor_snapshot(1) == before and run.route.size() == 1, "同种子新旅程地图可复现且奖励重置")
	run.enter("1a")
	hero.hp = 10
	run.finish_battle(hero, false)
	check(run.failed and not run.node("1a").done and not run.node("1a").cleared, "失败不清理节点")
	check(not run.can_enter("1b") and run.route.size() == 1, "失败即终止，即使回写仍有生命也不能改道")
	run.generate_floor()
	check(run.failed and run.node("1a").visited, "重复生成不能清空失败和到访记录")
	run.setup(123)
	var other := Run.new()
	other.setup(123)
	check(not run.run_id.is_empty() and run.run_id != other.run_id, "相同种子的不同远征仍有独立标识")
	check(run.node("1a").kind == other.node("1a").kind, "远征身份不影响种子地图")
	# 多种种子贯穿实际补给节点，检查其奖励只发一次。
	var saw_cache := false
	for seed_value in range(20):
		run.setup(seed_value, 1)
		run.enter("1a")
		run.finish_battle(run.character, true)
		if run.node("2a").kind != "cache": continue
		saw_cache = true
		var stock: int = run.character.potions
		run.enter("2a")
		run.generate_floor()
		check(run.node("2a").reward_claimed and run.character.potions == stock + 1, "补给领取记录与库存一致")
		check(run.enter("2a") == "" and run.character.potions == stock + 1, "重复生成后也不能再次领取补给")
	check(saw_cache, "覆盖补给分支")
	test_return()
	print("EXPEDITION HISTORY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)

func test_return() -> void:
	var run := Run.new()
	run.setup(123, 3)
	run.enter("1a")
	check(not run.begin_return() and run.return_target().is_empty(), "战斗待结算时不能返程")
	run.finish_battle(run.character, true)
	run.enter("2b")
	advance_floor(run)
	advance_floor(run)
	advance_floor(run)
	var route: Array = run.route.duplicate()
	var inventory: Dictionary = run.character.duplicate(true)
	var histories: Array = [run.floor_snapshot(1), run.floor_snapshot(2), run.floor_snapshot(3)]
	check(run.completed and run.begin_return(), "抵达最深出口后仍可返程")
	check(not run.begin_return() and run.enter("entry") == "", "返程不能重新开始或转为下潜")
	check(not run.step_return("wrong") and run.current == "exit", "错误目标不得移动")
	for index in range(route.size() - 2, -1, -1):
		var target: Dictionary = run.return_target()
		check(target.key == route[index], "返程严格沿所选路线逆序")
		var key: String = target.key
		target.id = "tampered"
		check(run.step_return(key), "合法返程目标可移动，预览修改不污染状态")
		check(run.node(run.current).key == route[index], "跨层返回实际历史节点")
		check(not run.step_return(key), "同一目标重复提交不会多走一步")
		check(run.character == inventory, "回经战斗、营地和补给不增减资源")
	check(run.floor_number == 1 and run.current == "entry", "路线尽头为首层入口")
	check(run.return_summary().is_empty(), "抵达入口尚未结算回城")
	var city: String = run.return_target().key
	check(run.step_return(city) and run.phase == "returned", "首层入口回城成功")
	var summary: Dictionary = run.return_summary()
	var clear_count := 0
	for history in histories:
		for item in history:
			if item.cleared: clear_count += 1
	check(summary.deepest_floor == 3 and summary.cleared_count == clear_count and summary.character == inventory, "摘要深度、战斗次数及剩余资源准确")
	check(not run.step_return(city) and not run.begin_return() and not run.can_enter("1a"), "回城后不能重复结算或继续移动")
	summary.character.hp = -1
	check(run.return_summary().character.hp == inventory.hp, "摘要深拷贝隔离")
	check(run.route == route, "返程保留完整下潜历史")
	for level in range(1, 4):
		check(run.floor_snapshot(level) == histories[level - 1], "返程不清空地图或领取记录")
	run.setup(1, 3)
	check(run.phase == "descending" and run.return_summary().is_empty() and run.deepest_floor == 1, "新远征清空返程与摘要")
	check(run.begin_return() and run.step_return(run.return_target().key), "首层入口可直接回城")
	check(run.return_summary().cleared_count == 0, "零战斗摘要")
	run.setup(1, 3)
	run.enter("1a")
	run.finish_battle(run.character, false)
	check(not run.begin_return() and not run.step_return(run.run_id + "/city"), "失败不能伪装成功回城")

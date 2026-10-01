extends SceneTree

const Station = preload("res://Scripts/UI/rest_station.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-station-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("途中休整")
	await frames()
	var before: Dictionary = flow.run.character.duplicate(true)
	check(not flow.station_service("potion") and flow.run.character == before, "城市不能调用途中服务")
	flow.run.character.quests.hunt = "claimed"
	check(flow.familia_service("join"), "建立晨行编队")
	for i in range(3): check(flow.progress.award_victory("station-fixture-%d" % i, flow.run.character.player_id), "解锁游侠")
	check(flow.familia_service("enlist") and flow.familia_service("enlist_scout"), "建立三人测试队伍")
	flow.run.depart_city(7)
	for i in range(100):
		if flow.run.floor_number >= 5: break
		var result: String = flow.run.enter(flow.run.node(flow.run.current).next[0])
		if result == "battle": check(flow.settle_battle(flow.run.character, flow.party_companion(), true, flow.party_companion("scout")), "实际远征胜利")
	check(flow.run.floor_number == 5 and flow.run.current == "entry", "实际地图推进抵达第五层入口")
	flow.run.character.gold = 30
	flow.run.character.hp = 5
	flow.run.character.party_hp = 0
	flow.run.character.scout_hp = 5
	var steps: int = flow.run.steps_taken
	var timers: Dictionary = flow.run.log_state().respawn.duplicate(true)
	current_scene.show_floor_map()
	check(current_scene.map_buttons.has("station") and not current_scene.map_buttons.station.disabled, "实际入口显示休整站按钮")
	current_scene.map_buttons.station.pressed.emit()
	var station: Window
	for child in current_scene.get_children():
		if child.get_script() == Station: station = child
	check(station != null and not station.buttons.rest.disabled, "实际休整窗口开放合法服务")
	current_scene._open_station()
	var count := 0
	for child in current_scene.get_children():
		if child.get_script() == Station: count += 1
	check(count == 1, "休整站不重复堆叠")
	station.buttons.rest.pressed.emit()
	check(flow.run.character.gold == 22 and flow.run.character.hp == 17 and flow.run.character.party_hp == 0 and flow.run.character.scout_hp == 17, "付8金币，各存活成员恢复12，倒下卫士不复活")
	var stock: int = flow.run.character.potions
	station.buttons.potion.pressed.emit()
	check(flow.run.character.gold == 17 and flow.run.character.potions == stock + 1, "途中治疗按5金币扣款并发放")
	stock = flow.run.character.fire_potions
	station.buttons.fire_potion.pressed.emit()
	check(flow.run.character.gold == 10 and flow.run.character.fire_potions == stock + 1, "途中灼烧按7金币扣款并发放")
	check(flow.run.steps_taken == steps and flow.run.log_state().respawn == timers, "所有服务均不推进移动或历史刷新")
	var capture := OS.get_environment("TENSEI_STATION_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "休整站截图")
	# 开窗后共享消失，不能先恢复主角再拒绝队友。
	before = flow.run.character.duplicate(true)
	var shared_bytes := {}
	for suffix in [".0.save", ".1.save"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix):
			shared_bytes[suffix] = FileAccess.get_file_as_bytes(flow.progress.base_path + suffix)
			DirAccess.remove_absolute(flow.progress.base_path + suffix)
	station.buttons.rest.pressed.emit()
	check(flow.run.character == before and station.buttons.rest.disabled, "共享丢失时全队休整拒绝，不部分扣款或恢复")
	for suffix in shared_bytes:
		var file := FileAccess.open(flow.progress.base_path + suffix, FileAccess.WRITE)
		file.store_buffer(shared_bytes[suffix])
		file.close()
	station._refresh()
	check(not station.buttons.rest.disabled, "共享恢复后可刷新原窗口")
	station.queue_free()
	await frames()
	var record: String = flow.saves.save_record(flow.run, flow.profile, "第五层补给后")
	check(flow.load_exploration(flow.profile.id, record), "休整站安全点磁盘恢复")
	await frames()
	check(flow.run.character == before and flow.run.steps_taken == steps and flow.run.log_state().respawn == timers, "保存恢复药水、费用、各生命、步数和刷新")
	check(flow.run.enter("1a") == "battle", "离开入口进入真实战斗")
	before = flow.run.character.duplicate(true)
	check(not flow.station_service("potion") and flow.run.character == before, "战斗未结算不能远程采购")
	flow.settle_battle(flow.run.character, flow.party_companion(), true, flow.party_companion("scout"))
	current_scene.show_floor_map()
	check(current_scene.map_buttons.station.disabled, "离开入口显示休整站位置但禁用远程服务")
	flow.run.begin_return()
	flow.run.step_return(flow.run.node_key(5, "entry"))
	check(flow.run.current == "entry" and flow.run.phase == "returning", "自由返程可再次回到入口休整")
	flow.run.character.hp = 0
	flow.run.character.scout_hp = 5
	flow.run.character.gold = 8
	check(flow.station_service("rest") and flow.run.character.hp == 0 and flow.run.character.party_hp == 0 and flow.run.character.scout_hp == 17 and flow.run.character.gold == 0, "主角倒下时只恢复存活游侠且完整扣费")
	before = flow.run.character.duplicate(true)
	check(not flow.station_service("potion") and flow.run.character == before, "余额不足拒绝并保持资源")
	flow.run.character.gold = 8
	flow.run.character.scout_hp = flow.party_companion("scout").max_hp
	before = flow.run.character.duplicate(true)
	check(not flow.station_service("rest") and flow.run.character == before, "存活成员满血时不因倒下成员而收取休整费")
	check(flow.run.begin_descent(), "途中服务后随时继续深入")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("REST STATION CHECKS: ", failures, " failures")
	quit(1 if failures else 0)

extends SceneTree

const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-gm-recovery-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func frames() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	var gm = get_first_node_in_group("gm_panel")
	check(gm.rows.has("restore_party") and gm.rows.has("refill_potions"), "点击式菜单注册两条补给命令")
	check(not gm.commands.restore_party.reason.call().is_empty(), "主菜单拒绝恢复")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("GM长流程")
	await frames()
	flow.run.character.quests.hunt = "claimed"
	check(flow.familia_service("join") and flow.familia_service("enlist"), "测试夹具建立眷族")
	for i in range(3): flow.progress.award_victory("fixture-%d" % i, flow.run.character.player_id)
	check(flow.familia_service("enlist_scout"), "测试夹具建立三人编队")
	flow.run.character.hp = 10
	flow.run.character.party_hp = 0
	flow.run.character.scout_hp = 7
	current_scene.show_floor_map()
	gm.set_open(true)
	var original: Dictionary = flow.run.character.duplicate(true)
	gm.rows.restore_party.button.pressed.emit()
	var expected := original.duplicate(true)
	expected.hp = 36
	expected.scout_hp = 22
	check(flow.run.character == expected and flow.active_character == expected, "城市GM恢复存活成员、保留倒下者和其他成长，缓存同步")
	flow.run.character.potions = 20
	flow.run.character.fire_potions = 1
	gm.rows.refill_potions.button.pressed.emit()
	check(flow.run.character.potions == 20 and flow.run.character.fire_potions == 10 and flow.run.character.gold == original.gold, "补给至少10、已有更多保留且不扣金币")
	var snapshot: Dictionary = flow.run.save_data()
	gm.rows.refill_potions.button.pressed.emit()
	check(flow.run.save_data() == snapshot, "重复补给无副作用")
	current_scene.city_buttons.quests.pressed.emit()
	check(not current_scene.gm_recovery_reason("restore_party").is_empty() and not current_scene.gm_recovery("restore_party"), "窗口打开时禁用测试操作")
	for child in current_scene.get_children():
		if child is Window: child.queue_free()
	await frames()
	flow.run.character.hp = 9
	var retained := {}
	for suffix in [".0.save", ".1.save"]:
		var path: String = flow.progress.base_path + suffix
		if FileAccess.file_exists(path):
			retained[path] = FileAccess.get_file_as_bytes(path)
			DirAccess.remove_absolute(path)
	original = flow.run.character.duplicate(true)
	check(not current_scene.gm_recovery("restore_party") and flow.run.character == original, "共享档案实际缺失时原子拒绝全部恢复")
	for path in retained:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(retained[path])
		file.close()
	flow.city_service("rest")
	flow.run.depart_city(7)
	flow.run.enter("1a")
	current_scene.start_encounter()
	await create_timer(1.5).timeout
	current_scene.battle.hero.hp = 10
	current_scene.battle.ally.hp = 0
	current_scene.battle.scout.hp = 8
	current_scene.battle.action = 0
	current_scene.battle.scout_guarding = true
	current_scene.battle.hero.potions = 1
	current_scene.battle.hero.fire_potions = 0
	var battle_before: Dictionary = current_scene.battle.log_state()
	var random_state: int = current_scene.battle.rng.state
	current_scene.busy = true
	check(not current_scene.gm_recovery("restore_party") and current_scene.battle.log_state() == battle_before, "动作中拒绝恢复")
	current_scene.busy = false
	gm.rows.restore_party.button.pressed.emit()
	gm.rows.refill_potions.button.pressed.emit()
	var battle_expected := battle_before.duplicate(true)
	battle_expected.hero.hp = battle_expected.hero.max_hp
	battle_expected.scout.hp = battle_expected.scout.max_hp
	battle_expected.hero.potions = 10
	battle_expected.hero.fire_potions = 10
	check(current_scene.battle.log_state() == battle_expected and current_scene.battle.rng.state == random_state, "三人战斗只改生命和库存，保留行动、先攻、闪避和随机数")
	var capture := OS.get_environment("TENSEI_GM_RECOVERY_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		gm.scroll.scroll_vertical = 100
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	check(current_scene.gm_kill_enemy(), "测试补给后沿用正常胜利结算")
	check(flow.run.character.potions == 10 and flow.run.character.scout_hp == 22 and flow.run.character.party_hp == 0, "战斗修改随普通结算回写")
	check(not current_scene.gm_recovery("restore_party"), "已结束战斗不追加修改")
	current_scene.show_floor_map()
	gm.rows.refill_potions.button.pressed.emit()
	var record: String = flow.saves.save_record(flow.run, flow.profile, "GM修改安全点")
	check(not record.is_empty() and flow.saves.read_record(flow.profile.id, record).run.character == flow.run.character, "测试改动明确进入手动存档")
	check(not current_scene.gm_recovery("unknown"), "未知测试命令拒绝")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("GM RECOVERY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)

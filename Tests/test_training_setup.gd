extends SceneTree

const Training = preload("res://Scripts/Battle/training_library.gd")
const TrainingPanel = preload("res://Scripts/UI/training_panel.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-training-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame

func idle() -> void:
	for i in range(100):
		if not current_scene.busy: return
		await create_timer(0.1).timeout
	check(false, "演练动作在有界等待内完成")

func panel_for(scene: Node) -> Window:
	for child in scene.get_children():
		if child.get_script() == TrainingPanel: return child
	return null

func _run() -> void:
	create_timer(45).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("演练隔离检查")
	await frames()
	check(flow.progress.ensure(), "准备独立共享档案")
	var profile_id: String = flow.profile.id
	var record: String = flow.saves.save_record(flow.run, flow.profile, "演练前个人记录")
	var saved: Dictionary = flow.saves.read_record(profile_id, record).run.save_data()
	var shared: Dictionary = flow.progress.data.duplicate(true)
	var generation: int = flow.progress.inspect().generation
	check(not flow.start_training(Training.DEFAULT) and flow.run.save_data() == saved, "城市远征不能被演练接口中断")
	flow.return_to_menu()
	await frames()
	current_scene._open_character()
	current_scene._start_battle()
	await frames()
	var panel: Window = panel_for(current_scene)
	check(panel != null, "主菜单实际按钮打开演练配置")
	panel.choices.job.select(panel.values.job.find("mage"))
	panel.choices.weapon.select(panel.values.weapon.find("tempered_sword"))
	panel.choices.armor.select(panel.values.armor.find("iron_armor"))
	panel.choices.enemy.select(panel.values.enemy.find("pair"))
	panel.choices.level.value = 2
	panel.choices.party.value = 3
	panel.choices.floor.value = 4
	var config: Dictionary = panel.configuration()
	check(Training.valid(config), "真实选择器生成合法三人双敌配置")
	var capture := OS.get_environment("TENSEI_TRAINING_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-config.png")
	panel.start_button.pressed.emit()
	await frames()
	await idle()
	var screen = current_scene
	check(flow.run == null and flow.training_config == config and screen.battle.order.size() == 5, "配置启动独立三人双敌演练")
	check(screen.battle.hero.job_id == "mage" and screen.battle.hero.level == 2 and screen.battle.hero.ac == 13 and screen.battle.hero.weapon == "tempered_sword" and screen.battle.enemy.max_hp == 29 and screen.battle.enemy_b.max_hp == 25 and screen.battle.scout.level == 2, "职业、等级、护甲、武器和双方参数生效")
	var initial: Dictionary = screen.battle.log_state()
	initial.erase("battle_id")
	var rng: int = screen.battle.rng.state
	screen.battle.cursor = screen.battle.order.find("lorn")
	screen.battle.action = 1
	screen._refresh()
	var hp: int = screen.battle.enemy_b.hp
	screen._select("arcane_bolt")
	screen._target("goblin_b")
	await idle()
	check(screen.battle.enemy_b.hp < hp and screen.battle.hero.weapon == "tempered_sword", "实际法师技能点选第二敌人")
	check(screen.gm_kill_enemy(), "独立演练GM正常胜利")
	screen._restart_demo()
	await idle()
	var repeated: Dictionary = screen.battle.log_state()
	repeated.erase("battle_id")
	check(repeated == initial and screen.battle.rng.state == rng, "再试一次保持配置、种子及相同初始先攻／随机状态")
	if not capture.is_empty():
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	screen.busy = true
	check(not flow.start_training(config), "反馈动作期间禁止替换演练")
	screen._open_training()
	check(panel_for(screen) == null, "忙碌入口不打开配置窗口")
	screen.busy = false
	screen._open_training()
	panel = panel_for(screen)
	check(panel != null and panel.configuration() == config, "局内配置回填当前选择")
	var before: Dictionary = screen.battle.log_state()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	panel._unhandled_key_input(escape)
	await frames()
	check(screen.battle.log_state() == before, "取消配置保留当前战斗")
	var bad := config.duplicate(true)
	for item in [{"enemy": "unknown"}, {"level": 6}, {"party": 0}, {"seed": -1}, {"level": 2.0}]:
		bad = config.duplicate(true)
		bad.merge(item, true)
		check(not Training.valid(bad) and not flow.start_training(bad) and screen.battle.log_state() == before, "非法配置拒绝且保留战斗")
	config.enemy = "captain"
	config.party = 1
	check(flow.start_training(config), "可配置单人队长演练")
	await frames()
	await idle()
	check(current_scene.battle.enemy.captain and current_scene.battle.enemy_b.is_empty() and current_scene.battle.order.size() == 2, "队长不与第二敌人混用")
	check(flow.progress.data == shared and flow.progress.inspect().generation == generation and flow.saves.read_record(profile_id, record).run.save_data() == saved, "演练、重开、胜利与配置切换均不写个人档或共享成长")
	check(flow.load_exploration(profile_id, record), "演练结束后可恢复原角色记录")
	await frames()
	check(flow.training_config.is_empty() and flow.run.save_data() == saved, "读档清除演练配置并恢复原安全点")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("TRAINING SETUP CHECKS: ", failures, " failures")
	quit(1 if failures else 0)

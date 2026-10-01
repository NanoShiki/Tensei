extends Control

const Training = preload("res://Scripts/Battle/training_library.gd")
const BattleState = preload("res://Scripts/Battle/battle_state.gd")
const Abilities = preload("res://Scripts/Battle/ability_library.gd")
const Enemies = preload("res://Scripts/Battle/enemy_library.gd")
const Jobs = preload("res://Scripts/Character/job_library.gd")
const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
const GOLD := Color("d6b77a")
const PAPER := Color("e9e4d7")
const MUTED := Color("919e9e")
var battle: RefCounted
var canvas: Control
var selected := ""
var busy := false
var map_visible := false
var buttons: Dictionary = {}
var targets: Dictionary = {}
var end_button: Button
var result_panel: PanelContainer
var hint_label: Label
var log_label: Label
var flow: Node
var _settled := false
var map_buttons: Dictionary = {}
var expedition_button: Button
var direction_button: Button
var city_buttons: Dictionary = {}
var inventory: Window
var party_practice := false
var pause_button: Button

func _ready() -> void:
	add_to_group("gm_battle_context")
	flow = get_node_or_null("/root/GameFlow")
	canvas = Control.new()
	canvas.size = Vector2(1280, 720)
	add_child(canvas)
	resized.connect(_layout)
	_layout()
	if flow != null and flow.show_map and flow.run != null:
		show_floor_map()
	else:
		start_encounter()

func _layout() -> void:
	var ratio := minf(size.x / 1280.0, size.y / 720.0)
	canvas.scale = Vector2.ONE * ratio
	canvas.position = (size - Vector2(1280, 720) * ratio) / 2

func _clear() -> void:
	for child in canvas.get_children():
		canvas.remove_child(child)
		child.queue_free()
	buttons.clear()
	targets.clear()
	map_buttons.clear()
	city_buttons.clear()
	expedition_button = null
	direction_button = null
	pause_button = null

func _panel(rect: Rect2, color: Color = Color("182326"), border: Color = Color("3d4a48")) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	return panel

func _label(text: String, rect: Rect2, font_size: int = 18, color: Color = PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(label)
	return label

func _button(text: String, rect: Rect2, callback: Callable, accent: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 17)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("32413d") if state in ["hover", "pressed", "focus"] else Color("1d292c")
		style.border_color = GOLD if accent or state in ["hover", "focus"] else Color("45504b")
		style.set_border_width_all(2 if accent else 1)
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_disabled_color", Color("63706d"))
	button.pressed.connect(callback)
	canvas.add_child(button)
	return button

func _backdrop() -> void:
	_panel(Rect2(0, 0, 1280, 720), Color("0d171c"), Color("0d171c"))
	# 建筑由低细节几何组成，为角色留出清楚的轮廓。
	for x in [85, 375, 665, 955]:
		_panel(Rect2(x, 112, 238, 307), Color("14252c"), Color("26363a"))
		_panel(Rect2(x + 22, 135, 194, 280), Color("102027"), Color("1c3036"))
		_panel(Rect2(x - 13, 100, 30, 346), Color("243238"), Color("334248"))
	_panel(Rect2(0, 429, 1280, 88), Color("293632"), Color("47534a"))
	for i in range(12):
		var line := Line2D.new()
		line.add_point(Vector2(i * 120 - 100, 515))
		line.add_point(Vector2(640 + (i * 120 - 740) * 0.65, 430))
		line.default_color = Color("38453e")
		line.width = 1
		canvas.add_child(line)
	_panel(Rect2(0, 0, 1280, 86), Color("101b20"), Color("3e4946"))

func start_encounter() -> void:
	map_visible = false
	selected = ""
	busy = false
	_settled = false
	battle = BattleState.new()
	var character: Dictionary = CharacterLibrary.resolve()
	var floor_number := 1
	if flow != null:
		if not flow.active_character.is_empty(): character = flow.active_character
		if flow.run != null:
			character = flow.run.character
			floor_number = flow.run.floor_number
	var encounter: Dictionary = flow.run.node(flow.run.pending) if flow != null and flow.run != null else {}
	if flow != null and flow.run == null and not flow.training_config.is_empty():
		var config: Dictionary = flow.training_config
		character = Training.hero(config)
		flow.active_character = character.duplicate(true)
		var kind: String = "armored" if config.enemy == "pair" else config.enemy
		battle.setup(character, config.floor, config.seed, kind == "captain", Training.companion(config, "squire"), kind, Training.companion(config, "scout"), "goblin" if config.enemy == "pair" else "")
	else:
		battle.setup(character, floor_number, -1, flow != null and flow.run != null and flow.run.is_captain_node(flow.run.pending), BattleState.practice_companion() if party_practice else (flow.party_companion() if flow != null and flow.run != null else {}), str(encounter.get("enemy_kind", "goblin")), flow.party_companion("scout") if flow != null and flow.run != null else {}, str(encounter.get("second_enemy_kind", "")))
	if flow != null and flow.run == null and not flow.training_config.is_empty():
		preload("res://Scripts/Core/game_log.gd").event("training", "started", {"config": flow.training_config.duplicate(true), "battle": battle.log_state(), "rng": str(battle.rng.state)})
	_refresh()
	_drive_enemy()

func _refresh() -> void:
	_clear()
	_backdrop()
	var floor_number: int = flow.run.floor_number if flow != null and flow.run != null else 1
	_label("T E N S E I   /   地下城", Rect2(28, 16, 350, 28), 18, GOLD)
	_label(("演练 · 第 %02d 层参数" if flow != null and flow.run == null else "第 %02d 层   ·   苔石回廊") % (flow.training_config.floor if flow != null and not flow.training_config.is_empty() else floor_number), Rect2(28, 49, 340, 24), 14, MUTED)
	_button("指南 · F1", Rect2(340, 40, 120, 33), _open_guide)
	pause_button = _button("暂停", Rect2(470, 42, 75, 30), _open_pause)
	_label("第 %d 轮" % battle.round_number, Rect2(470, 12, 80, 24), 16, GOLD)
	var stride := 100 if battle.order.size() == 5 else (122 if battle.order.size() == 4 else 152)
	var slot_width := stride - 14
	for i in range(battle.order.size()):
		var id: String = battle.order[i]
		var name_text: String = battle.unit(id).name
		var active: bool = battle.current_id() == id
		_panel(Rect2(565 + i * stride, 16, slot_width, 53), Color("29372e") if active else Color("19262b"), GOLD if active else Color("3c4948"))
		_label(("▶ " if active else "") + name_text, Rect2(571 + i * stride, 28, slot_width - 12, 30), 13 if battle.order.size() == 5 else (16 if battle.order.size() == 4 else 18), GOLD if active else MUTED)
	_button("返回主菜单", Rect2(1090, 22, 158, 40), _return_to_menu)
	if flow == null or flow.run == null:
		_button("演练配置", Rect2(730, 90, 250, 36), _open_training)
	if not battle.scout.is_empty():
		if not battle.ally.is_empty():
			_unit("lorn", battle.hero, Rect2(30, 208, 175, 265), "res://Assets/Battle/lorn.png")
			_unit("squire", battle.ally, Rect2(225, 224, 165, 250), "res://Assets/Battle/lorn.png")
			_unit("scout", battle.scout, Rect2(420, 228, 165, 250), "res://Assets/Battle/lorn.png")
		else:
			_unit("lorn", battle.hero, Rect2(85, 197, 210, 284), "res://Assets/Battle/lorn.png")
			_unit("scout", battle.scout, Rect2(330, 212, 185, 267), "res://Assets/Battle/lorn.png")
	elif not battle.ally.is_empty():
		_unit("lorn", battle.hero, Rect2(85, 197, 210, 284), "res://Assets/Battle/lorn.png")
		_unit("squire", battle.ally, Rect2(330, 212, 185, 267), "res://Assets/Battle/lorn.png")
	else:
		_unit("lorn", battle.hero, Rect2(202, 145, 294, 340), "res://Assets/Battle/lorn.png")
	if battle.enemy_b.is_empty():
		_unit("goblin", battle.enemy, Rect2(833, 205, 222, 302), "res://Assets/Battle/goblin.png")
	else:
		_unit("goblin", battle.enemy, Rect2(830, 213, 180, 280), "res://Assets/Battle/goblin.png")
		_unit("goblin_b", battle.enemy_b, Rect2(1040, 213, 180, 280), "res://Assets/Battle/goblin.png")
	if not battle.enemy_intent().is_empty():
		_label(battle.enemy_intent(), Rect2(30, 90, 710, 36) if not battle.enemy_b.is_empty() else Rect2(500, 90, 730, 36), 18, GOLD)
	var message := "选择技能，再点击高亮目标。"
	if busy: message = "行动反馈中…"
	elif battle.is_enemy_turn(): message = str(battle.current_unit().name) + "正在行动…"
	elif not selected.is_empty():
		var entry: Dictionary = Abilities.ENTRIES[selected]
		message = "%s → 点击%s确认   ·   右键 / Esc 取消" % [entry.name, (str(battle.enemy.name) if battle.enemy_b.is_empty() else "任一存活敌人") if entry.target == "enemy" else ("存活受伤队友" if selected == "potion" else str(battle.current_unit().name))]
		if entry.target == "enemy" and not entry.has("stock") and battle.enemy_b.is_empty(): message += "   ·   命中 %d%%" % battle.hit_chance(selected)
	elif battle.action == 0: message = "本回合已行动。点击「结束回合」继续。"
	hint_label = _label(message, Rect2(30, 480, 1220, 32), 17, GOLD)
	_panel(Rect2(20, 529, 257, 170))
	var actor: Dictionary = battle.current_unit() if battle.is_player_turn() else battle.hero
	_label("装备 / " + str(actor.name), Rect2(36, 541, 230, 26), 17, GOLD)
	_label("%s · %s\n护甲 AC %d · 命中 +%d\n剑技伤害加成 +%d" % [CharacterLibrary.weapon_name(actor), CharacterLibrary.armor_name(actor), actor.ac, actor.attack, CharacterLibrary.weapon_bonus(actor)], Rect2(36, 577, 226, 70), 16)
	_label("生命 %d / %d" % [actor.hp, actor.max_hp], Rect2(36, 652, 225, 26), 18, Color("9fc0a0"))
	_panel(Rect2(291, 529, 448, 170))
	_label("技能 / " + str(Jobs.resolve(actor).name), Rect2(307, 541, 150, 24), 17, GOLD)
	_label("行动 %d · 每回合 1 次" % battle.action, Rect2(472, 541, 260, 24), 16, MUTED)
	var ids: Array = Jobs.skills(actor)
	for i in range(ids.size()): _ability_button(ids[i], Rect2(305 + i * 106, 578, 94, 96))
	_panel(Rect2(752, 529, 229, 170))
	_label("道具 / 治疗 %d · 灼烧 %d" % [battle.hero.potions, battle.hero.fire_potions], Rect2(765, 541, 210, 24), 17, GOLD)
	_ability_button("potion", Rect2(765, 578, 98, 96))
	_ability_button("fire_potion", Rect2(870, 578, 98, 96))
	_panel(Rect2(994, 529, 266, 170))
	end_button = _button("结束回合  →", Rect2(1008, 555, 237, 67), _end_turn, true)
	end_button.disabled = busy or not battle.is_player_turn()
	_label("Space 结束   ·   1–6 选择", Rect2(1008, 642, 237, 26), 15, MUTED)
	var log_text: String = "\n".join(battle.logs.slice(maxi(0, battle.logs.size() - 3)))
	log_label = _label(log_text, Rect2(620, 324, 195, 132) if not battle.scout.is_empty() else (Rect2(550, 324, 265, 132) if not battle.ally.is_empty() else Rect2(464, 324, 355, 132)), 13, MUTED)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_panel = _panel(Rect2(430, 188, 420, 255), Color("142125"), GOLD)
	result_panel.visible = battle.outcome != "ongoing"
	if result_panel.visible:
		_label(("阶段挑战完成" if battle.enemy.captain else "战斗胜利") if battle.outcome == "victory" else "战斗失败", Rect2(480, 213, 320, 50), 32, GOLD)
		_label("生命 %d · 治疗 %d · 灼烧 %d" % [battle.hero.hp, battle.hero.potions, battle.hero.fire_potions], Rect2(480, 272, 325, 30), 18)
		if flow != null and flow.run != null:
			_button("返回本层地图", Rect2(480, 326, 320, 43), show_floor_map, true)
		else:
			_button("再试一次", Rect2(480, 326, 320, 43), _restart_demo, true)
		_button("返回主菜单", Rect2(480, 382, 320, 40), _return_to_menu)

func _unit(id: String, data: Dictionary, rect: Rect2, path: String) -> void:
	var texture := TextureRect.new()
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.texture = load(path)
	texture.position = rect.position
	texture.size = rect.size
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if id in ["goblin", "goblin_b"]: texture.modulate = Color(data.get("tint", "ffffff"))
	if id == "squire": texture.modulate = Color("94c9da")
	if id == "scout": texture.modulate = Color("d9c68a")
	if data.hp <= 0: texture.modulate = Color(0.5, 0.5, 0.5, 0.45)
	canvas.add_child(texture)
	var targetable := false
	if not selected.is_empty():
		targetable = battle.can_target(selected, id)
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.flat = true
	button.disabled = not targetable or busy
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if targetable else Control.CURSOR_ARROW
	button.pressed.connect(_target.bind(id))
	if targetable and Abilities.ENTRIES[selected].target == "enemy" and not Abilities.ENTRIES[selected].has("stock"):
		button.tooltip_text = "%s · 命中 %d%%" % [data.name, battle.hit_chance(selected, id)]
	canvas.add_child(button)
	targets[id] = button
	if targetable:
		_label("▼  选择目标", Rect2(rect.position.x + 35, 91, 210, 30), 18, GOLD)
	var compact: bool = (not battle.ally.is_empty() or not battle.scout.is_empty()) and id not in ["goblin", "goblin_b"] or (not battle.enemy_b.is_empty() and id in ["goblin", "goblin_b"])
	_label(("%s\n%d / %d · AC %d" if compact else "%s   %d / %d   AC %d") % [data.name, data.hp, data.max_hp, data.ac], Rect2(rect.position.x, 134 if compact else 121, rect.size.x if compact else 290, 50 if compact else 28), 16 if compact else 17, GOLD if targetable else PAPER)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.position = Vector2(rect.position.x, 188 if compact else 151)
	bar.custom_minimum_size = Vector2(minf(216, rect.size.x), 7)
	for state in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = (Color("ba7769") if id in ["goblin", "goblin_b"] else Color("8fad82")) if state == "fill" else Color("303e3e")
		style.set_corner_radius_all(3)
		bar.add_theme_stylebox_override(state, style)
	bar.size = Vector2(minf(216, rect.size.x), 7)
	bar.max_value = data.max_hp
	bar.value = data.hp
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(bar)

func _ability_button(id: String, rect: Rect2) -> void:
	var entry: Dictionary = Abilities.ENTRIES[id]
	var button := _button("\n\n%s" % entry.name, rect, _select.bind(id), selected == id)
	var reason: String = battle.reason(id)
	button.disabled = busy or not reason.is_empty()
	button.tooltip_text = entry.hint + ("\n" + reason if not reason.is_empty() else "")
	if entry.has("die"):
		var actor: Dictionary = battle.current_unit() if battle.is_player_turn() else battle.hero
		button.tooltip_text = "1 行动 · 命中 +%d · 1d%d+%d 伤害" % [int(actor.attack) - int(entry.get("penalty", 0)), entry.die, int(entry.bonus) + (CharacterLibrary.weapon_bonus(actor) if entry.get("weapon_bonus", true) else 0)] + ("\n" + reason if not reason.is_empty() else "")
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = load("res://Assets/Battle/%s.svg" % entry.get("asset", id))
	icon.position = Vector2((rect.size.x - 40) / 2, 8)
	icon.size = Vector2(40, 40)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if button.disabled: icon.modulate = Color(0.6, 0.6, 0.6, 0.4)
	button.add_child(icon)
	buttons[id] = button

func _select(id: String) -> void:
	if get_tree().paused or busy or not battle.reason(id).is_empty(): return
	selected = "" if selected == id else id
	_refresh()

func _target(id: String) -> void:
	if get_tree().paused or busy or selected.is_empty(): return
	if battle.use_ability(selected, id):
		selected = ""
		busy = true
		_refresh()
		await _feedback()
		busy = false
		_settle()
		_refresh()

func _feedback() -> void:
	var event: Dictionary = battle.last_event
	if event.is_empty(): return
	var x: float = targets[event.target].position.x if targets.has(event.target) else 860.0
	var label := _label(str(event.text), Rect2(x, 220, 280, 55), 29, GOLD)
	var tween := create_tween()
	tween.tween_property(label, "position:y", 185.0, 0.4)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.4)
	await tween.finished

func _end_turn() -> void:
	if get_tree().paused or busy or not battle.end_turn(): return
	selected = ""
	_refresh()
	_drive_enemy()

func _drive_enemy() -> void:
	if not battle.is_enemy_turn():
		_settle()
		return
	busy = true
	_refresh()
	while battle.is_enemy_turn():
		await get_tree().create_timer(0.5, false).timeout
		battle.enemy_turn()
		_refresh()
		await _feedback()
	busy = false
	_settle()
	_refresh()

func _settle() -> void:
	if battle.outcome == "ongoing" or _settled: return
	_settled = true
	if flow != null:
		flow.active_character = battle.hero.duplicate(true)
		if flow.run != null: flow.settle_battle(battle.hero, battle.ally, battle.outcome == "victory", battle.scout)
		elif not flow.training_config.is_empty():
			preload("res://Scripts/Core/game_log.gd").event("training", "finished", {"config": flow.training_config.duplicate(true), "battle": battle.log_state(), "shared": flow.progress.data.duplicate(true)})

func gm_recovery_reason(action: String) -> String:
	if get_tree().paused: return "请先继续旅程"
	if action not in ["restore_party", "refill_potions"]: return "未知测试操作"
	if busy: return "请等待当前动作结束"
	for child in get_children():
		if child is Window and child.visible: return "请先关闭当前窗口"
	if map_visible:
		if flow == null or flow.run == null or flow.run.phase not in ["city", "descending", "returning"] or not flow.run.pending.is_empty() or not flow.run.has_living_party(): return "当前旅程无法操作"
		if action == "restore_party" and (flow.run.character.party_enlisted or flow.run.character.scout_enlisted):
			if flow.progress.data.get("player_id") != flow.run.character.player_id: return "共享档案不可用，请恢复同一玩家备份"
	elif battle == null or battle.outcome != "ongoing": return "当前战斗已结束"
	return ""

func gm_recovery(action: String) -> bool:
	if not gm_recovery_reason(action).is_empty(): return false
	if map_visible and action == "restore_party" and (flow.run.character.party_enlisted or flow.run.character.scout_enlisted) and flow.guild_level() == 0:
		preload("res://Scripts/Core/game_log.gd").event("gm", "recovery_rejected", {"action": action, "reason": "共享档案不可用，保留原状态"}, "WARN")
		return false
	var before: Dictionary = flow.run.log_state() if map_visible else battle.log_state()
	var hero: Dictionary = flow.run.character if map_visible else battle.hero
	var limits := {"lorn": hero.max_hp}
	if action == "refill_potions":
		hero.potions = maxi(10, hero.potions)
		hero.fire_potions = maxi(10, hero.fire_potions)
	elif map_visible:
		if hero.hp > 0: hero.hp = hero.max_hp
		for id in ["squire", "scout"]:
			var prefix := "party" if id == "squire" else "scout"
			if hero[prefix + "_enlisted"] and hero[prefix + "_hp"] > 0:
				limits[id] = flow.party_companion(id).max_hp
				hero[prefix + "_hp"] = limits[id]
	else:
		for member in battle.friends():
			limits[member.id] = member.max_hp
			if member.hp > 0: member.hp = member.max_hp
	var after: Dictionary = flow.run.log_state() if map_visible else battle.log_state()
	preload("res://Scripts/Core/game_log.gd").event("gm", action, {"scope": "map" if map_visible else "battle", "limits": limits, "before": before, "after": after})
	selected = ""
	if map_visible:
		flow.active_character = hero.duplicate(true)
		show_floor_map()
	else: _refresh()
	return true

func gm_kill_reason() -> String:
	if get_tree().paused: return "请先继续旅程"
	if map_visible or battle == null: return "请先进入战斗"
	if battle.outcome != "ongoing" or _settled: return "战斗已结束"
	if busy: return "等待当前动作结束"
	return ""

func gm_kill_enemy() -> bool:
	if not gm_kill_reason().is_empty(): return false
	if not battle.gm_kill_enemy(): return false
	selected = ""
	_settle()
	_refresh()
	return true

func _restart_demo() -> void:
	if flow != null: flow.active_character = CharacterLibrary.resolve()
	start_encounter()

func show_floor_map() -> void:
	map_visible = true
	selected = ""
	_clear()
	_backdrop()
	pause_button = _button("暂停 · Esc", Rect2(1070, 650, 170, 36), _open_pause)
	var run: RefCounted = flow.run
	if run.phase == "city":
		_show_city()
		return
	if run.phase == "returned":
		_show_return_summary()
		return
	_label("地 下 城   /   路 线", Rect2(32, 18, 450, 42), 25, GOLD)
	_button("指南 · F1", Rect2(330, 22, 135, 40), _open_guide)
	_label("第 %02d / %02d 层" % [run.floor_number, run.total_floors], Rect2(500, 20, 210, 40), 25)
	_button("背包 · B", Rect2(720, 22, 135, 40), _open_inventory)
	_button("放弃并回主菜单", Rect2(1060, 22, 190, 40), _return_to_menu)
	_button("保存记录", Rect2(870, 22, 175, 40), _request_save_exit)
	var returning: bool = run.phase == "returning"
	var destination: Dictionary = run.return_target()
	var return_keys: Array = []
	for choice in run.return_targets(): return_keys.append(choice.key)
	_label("向上返回 · 可随时转向深入" if returning else "继续深入 · 可随时转向返回", Rect2(40, 100, 740, 38), 21, GOLD)
	_label("已移动 %d 步 · 每步刷新倒计时 -1；切换方向与停留不计步。" % run.steps_taken, Rect2(40, 145, 810, 34), 17, MUTED)
	direction_button = _button("继续深入" if returning else "向上返回", Rect2(860, 96, 260, 40), _begin_descent if returning else _begin_return, true)
	direction_button.disabled = not (run.can_begin_descent() if returning else run.can_begin_return())
	if returning and not destination.is_empty():
		var action := "回到城市" if destination.id == "city" else "返回第 %d 层" % destination.floor
		expedition_button = _button(action, Rect2(880, 144, 350, 42), _return_step.bind(str(destination.key)), true)
	elif returning:
		_label("请选择高亮的向上节点", Rect2(880, 144, 350, 42), 20, GOLD)
	elif run.can_descend_floor():
		expedition_button = _button("进入第 %d 层" % (run.floor_number + 1), Rect2(880, 144, 350, 42), _descend_floor.bind(int(run.floor_number)), true)
	else:
		expedition_button = direction_button
	if run.floor_number == 5:
		map_buttons["station"] = _button("入口休整站", Rect2(40, 242, 180, 42), _open_station)
		map_buttons.station.disabled = run.current != "entry" or not run.pending.is_empty()
		map_buttons.station.tooltip_text = "回到第五层入口可付费休整和购买途中补给；不会推进移动和刷新。"
	for item in run.nodes:
		for next_id in item.next:
			var line := Line2D.new()
			line.add_point(_node_position(item) + Vector2(64, 34))
			line.add_point(_node_position(run.node(next_id)) + Vector2(64, 34))
			var active_edge: bool = item.id == run.current
			if returning:
				active_edge = item.key in return_keys and next_id == run.current
			line.default_color = GOLD if active_edge else Color("47544c")
			line.width = 2
			canvas.add_child(line)
	var names := {"entry": "入口", "battle": "战斗", "rest": "营地 +10 HP", "cache": "补给 +1 药水", "exit": "本层出口"}
	for item in run.nodes:
		var return_here: bool = returning and item.key in return_keys
		var enabled: bool = return_here if returning else run.can_enter(item.id)
		var revealed: bool = item.visited or enabled
		var position_text := "当前" if item.id == run.current else ("可返回" if return_here else ("可深入" if run.can_enter(item.id) else ""))
		var visit_text := "已到访" if item.visited else "未到访"
		var status: String = names[item.kind]
		if item.kind == "entry" and run.floor_number == 5: status = "入口／休整站"
		if item.kind == "battle":
			status = Enemies.encounter_name(item.enemy_kind, item.second_enemy_kind) if item.enemy_active else "刷新还需 %d 步" % item.respawn_in
		elif item.kind == "rest" and item.reward_claimed: status = "营地 · 已休整"
		elif item.kind == "cache" and item.reward_claimed: status = "补给 · 已领取"
		var title: String = (position_text + " · " if not position_text.is_empty() else "") + visit_text + "\n" + status
		if not revealed: title = "未到访\n未知"
		var callback: Callable = _choose_node.bind(str(item.id), str(item.key) if returning else "")
		var button := _button(title, Rect2(_node_position(item), Vector2(148, 68)), callback, enabled)
		button.disabled = not enabled
		if not revealed:
			button.tooltip_text = "靠近至下一步可选节点后显示详情；已到访节点保留详情。"
		if revealed and item.kind == "battle":
			button.tooltip_text = Enemies.encounter_preview(item.enemy_kind, item.second_enemy_kind, run.floor_number) + "\n每次合法移动先扣一步，再检查目的地。" + ("此处剩 1 步，进入时将遇敌。" if item.respawn_in == 1 and not item.enemy_active else "停留、预览和战斗回合不推进刷新。")
			if item.cleared:
				var progress := ColorRect.new()
				progress.position = _node_position(item) + Vector2(4, 61)
				progress.size = Vector2(140, 4)
				progress.color = Color("3d4a48")
				progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
				canvas.add_child(progress)
				var fill := ColorRect.new()
				fill.size = Vector2(140.0 * (item.respawn_total - item.respawn_in) / maxi(1, item.respawn_total), 4)
				fill.color = GOLD
				fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
				progress.add_child(fill)
		map_buttons[item.id] = button
	_panel(Rect2(24, 540, 1232, 155))
	_label("生命 %d/%d · 治疗 %d · 灼烧 %d · 金币 %d · 铁片 %d" % [run.character.hp, run.character.max_hp, run.character.potions, run.character.fire_potions, run.character.gold, run.character.scrap], Rect2(48, 563, 1100, 36), 23, GOLD)
	_label(_party_status(), Rect2(48, 597, 1100, 26), 16, MUTED)
	_label(run.objective_text(), Rect2(40, 188, 1190, 30), 17, GOLD)
	_label(run.message, Rect2(48, 627, 1150, 60), 20).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _begin_return() -> void:
	if flow.run.begin_return(): show_floor_map()

func _request_save_exit() -> void:
	if flow == null or flow.run == null or flow.run.save_data().is_empty() or get_tree().paused: return
	for child in get_children():
		if child is Window and child.visible: return
	var browser := preload("res://Scripts/UI/save_browser.gd").new()
	add_child(browser)
	browser.saved.connect(func(record_id: String):
		flow.active_record_id = record_id
		flow.active_character = flow.run.character.duplicate(true)
		preload("res://Scripts/Core/game_log.gd").context["record_id"] = record_id
		preload("res://Scripts/Core/game_log.gd").event("flow", "saved_location", {"exit": browser.exit_after_save, "record_id": record_id, "run": flow.run.log_state()})
		if browser.exit_after_save: flow.return_to_menu()
		else: show_floor_map())
	browser.open(flow.saves, flow.profile, flow.run)

func _begin_descent() -> void:
	if flow.run.begin_descent(): show_floor_map()

func _descend_floor(level: int) -> void:
	if flow.run.descend_floor(level): show_floor_map()

func _return_step(key: String, avoid: bool = false) -> void:
	if flow.run.step_return(key, avoid):
		if not flow.run.pending.is_empty(): start_encounter()
		else: show_floor_map()

func _show_return_summary() -> void:
	var summary: Dictionary = flow.run.return_summary()
	var hero: Dictionary = summary.character
	_panel(Rect2(230, 135, 820, 480))
	_label("平 安 归 来", Rect2(285, 175, 700, 55), 36, GOLD)
	_label("最深抵达  第 %d 层     /     清理战斗  %d 场" % [summary.deepest_floor, summary.cleared_count], Rect2(285, 265, 720, 45), 24)
	_label("剩余生命  %d / %d" % [hero.hp, hero.max_hp], Rect2(285, 330, 700, 38), 23)
	_label("治疗药水  %d     /     灼烧药水  %d" % [hero.potions, hero.fire_potions], Rect2(285, 385, 700, 38), 23)
	_label("随身金币 %d · 铁片 %d · 回城不重复发放战利品" % [hero.gold, hero.scrap], Rect2(285, 450, 720, 35), 18, MUTED)
	city_buttons["enter"] = _button("进入城市整备", Rect2(465, 515, 350, 48), _enter_city, true)
	_button("返回主菜单（未保存）", Rect2(465, 570, 350, 38), _return_to_menu)

func _enter_city() -> void:
	if flow.run.enter_city(): show_floor_map()

func _show_city() -> void:
	var hero: Dictionary = flow.run.character
	_label("城 市   /   整 备", Rect2(32, 18, 350, 42), 25, GOLD)
	_button("指南 · F1", Rect2(260, 22, 135, 40), _open_guide)
	city_buttons["familia"] = _button("眷族／编队", Rect2(420, 22, 135, 40), _open_familia)
	city_buttons["quests"] = _button("委托", Rect2(570, 22, 135, 40), _open_quests)
	_button("背包 · B", Rect2(720, 22, 135, 40), _open_inventory)
	_button("保存记录", Rect2(870, 22, 175, 40), _request_save_exit)
	_button("主菜单（未保存）", Rect2(1060, 22, 190, 40), _return_to_menu)
	_panel(Rect2(30, 112, 410, 402))
	_label(_party_status(), Rect2(52, 455, 370, 45), 16, MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label("%s · 等级 %d" % [str(flow.profile.get("name", "角色")).left(12), hero.level], Rect2(52, 137, 370, 40), 23, GOLD)
	city_buttons["job"] = _button("职业：%s · 查看与切换" % Jobs.resolve(hero).name, Rect2(52, 183, 365, 34), _open_jobs)
	_label("生命 %d / %d · 经验 %d\n金币 %d\n铁片 %d\n治疗药水 %d · 灼烧药水 %d\n装备：%s\n%s · 防御 AC %d" % [hero.hp, hero.max_hp, hero.experience, hero.gold, hero.scrap, hero.potions, hero.fire_potions, CharacterLibrary.weapon_name(hero), CharacterLibrary.armor_name(hero), hero.ac], Rect2(52, 226, 365, 225), 23)
	_panel(Rect2(468, 112, 780, 402))
	_label(flow.run.objective_text(), Rect2(42, 72, 1190, 32), 19, GOLD)
	_label("休整与工坊", Rect2(496, 137, 700, 40), 24, GOLD)
	city_buttons["rest"] = _button("旅店休整 · 免费恢复全部生命", Rect2(496, 192, 720, 46), _city_service.bind("rest"))
	city_buttons["rest"].disabled = hero.hp >= hero.max_hp and (not hero.party_enlisted or (not flow.party_companion().is_empty() and hero.party_hp >= flow.party_companion().max_hp)) and (not hero.scout_enlisted or (not flow.party_companion("scout").is_empty() and hero.scout_hp >= flow.party_companion("scout").max_hp))
	city_buttons["potion"] = _button("购买治疗药水 ×1 · 3 金币", Rect2(496, 250, 458, 46), _city_service.bind("potion"))
	city_buttons["trade"] = _button("批量补给／出售", Rect2(966, 250, 250, 46), _open_trade)
	city_buttons["potion"].disabled = hero.gold < 3
	city_buttons["fire_potion"] = _button("灼烧药水 ×1 · 4 金币", Rect2(496, 308, 458, 46), _city_service.bind("fire_potion"))
	city_buttons["fire_potion"].disabled = hero.gold < 4
	city_buttons["commerce"] = _button("订单／补给", Rect2(966, 308, 250, 46), _open_commerce)
	city_buttons["forge"] = _button("已持有铁剑" if hero.weapons.has("iron_sword") else "打造铁剑 · 6 金币 + 3 铁片", Rect2(496, 366, 458, 46), _city_service.bind("forge"), true)
	city_buttons["forge"].disabled = not flow.forge_reason().is_empty()
	city_buttons["equipment"] = _button("工坊／装备", Rect2(966, 366, 250, 46), _open_equipment)
	_label("铁剑：物理伤害 +2。\n" + flow.workshop_status(), Rect2(496, 427, 716, 77), 16, MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(flow.run.message, Rect2(42, 541, 1180, 60), 20).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	city_buttons["depart"] = _button("准备完毕 · 从第一层出发", Rect2(420, 620, 440, 58), _depart_city, true)

func _city_service(action: String) -> void:
	flow.city_service(action)
	show_floor_map()

func _open_equipment() -> void:
	if flow == null or flow.run == null or flow.run.phase != "city": return
	for child in get_children():
		if child is Window and child.visible: return
	var panel := preload("res://Scripts/UI/equipment_panel.gd").new()
	add_child(panel)
	panel.changed.connect(show_floor_map)
	panel.open(flow)

func _open_station() -> void:
	if flow == null or flow.run == null or flow.run.floor_number != 5 or flow.run.current != "entry" or not flow.run.pending.is_empty() or flow.run.phase not in ["descending", "returning"]: return
	for child in get_children():
		if child is Window and child.visible: return
	var station := preload("res://Scripts/UI/rest_station.gd").new()
	add_child(station)
	station.changed.connect(show_floor_map)
	station.open(flow)

func _open_commerce() -> void:
	if flow == null or flow.run == null or flow.run.phase != "city": return
	for child in get_children():
		if child is Window and child.visible: return
	var board := preload("res://Scripts/UI/commerce_board.gd").new()
	add_child(board)
	board.changed.connect(show_floor_map)
	board.open(flow)

func _open_trade() -> void:
	if not _can_open_city_board(): return
	var panel := preload("res://Scripts/UI/trade_panel.gd").new()
	add_child(panel)
	panel.changed.connect(show_floor_map)
	panel.open(flow)

func _depart_city() -> void:
	if flow.run.depart_city(randi()): show_floor_map()

func _node_position(item: Dictionary) -> Vector2:
	return Vector2(58 + int(item.step) * 244, 210 + int(item.lane) * 110)

func _enter_node(id: String, avoid: bool = false) -> void:
	var result: String = flow.run.enter(id, avoid)
	if result == "battle": start_encounter()
	else: show_floor_map()

func _return_to_menu() -> void:
	if flow != null: flow.return_to_menu()

func _open_inventory() -> void:
	if is_instance_valid(inventory) or not map_visible or flow == null or flow.run == null: return
	if flow.run.phase not in ["descending", "returning", "city"] or not flow.run.pending.is_empty(): return
	for child in get_children():
		if child is Window and child.visible: return
	inventory = preload("res://Scripts/UI/inventory_panel.gd").new()
	add_child(inventory)
	inventory.changed.connect(show_floor_map)
	inventory.open(flow.run)

func _input(event: InputEvent) -> void:
	var gm := get_tree().get_first_node_in_group("gm_panel")
	if gm != null and gm.is_open(): return
	for child in get_children():
		if child is Window and child.visible: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not map_visible and not selected.is_empty() and not busy:
			selected = ""
			_refresh()
		else: _open_pause()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_open_guide()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(inventory): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		_open_inventory()
		get_viewport().set_input_as_handled()
		return
	if map_visible or busy or battle == null: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		selected = ""
		_refresh()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			selected = ""
			_refresh()
		elif event.keycode == KEY_SPACE:
			_end_turn()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_6:
			_select((Jobs.skills(battle.current_unit()) + ["potion", "fire_potion"])[event.keycode - KEY_1])

func _choose_node(id: String, return_key: String) -> void:
	if not map_visible: return
	for child in get_children():
		if child is Window and child.visible: return
	var preview: Dictionary = flow.run.encounter_preview(id)
	if preview.is_empty():
		_move_choice(id, return_key, false)
		return
	var choice := preload("res://Scripts/UI/encounter_choice.gd").new()
	add_child(choice)
	choice.decided.connect(func(avoid: bool):
		_move_choice.call_deferred(id, return_key, avoid))
	choice.open(preview, flow.run)

func _move_choice(id: String, return_key: String, avoid: bool) -> void:
	if return_key.is_empty(): _enter_node(id, avoid)
	else: _return_step(return_key, avoid)

func _open_guide() -> void:
	if busy: return
	for child in get_children():
		if child is Window and child.visible: return
	var guide := preload("res://Scripts/UI/demo_guide.gd").new()
	add_child(guide)
	var run: RefCounted = flow.run if flow != null and flow.run != null else null
	guide.open(run, flow.guild_level() if run != null else 0)

func pause_snapshot() -> Dictionary:
	var state := {"scope": "map" if map_visible else "battle", "selected": selected, "busy": busy}
	if flow != null and flow.run != null: state["run"] = flow.run.log_state()
	if not map_visible and battle != null:
		state["battle"] = battle.log_state()
		state["rng"] = str(battle.rng.state)
	return state

func _open_pause() -> void:
	if get_tree().paused: return
	var gm := get_tree().get_first_node_in_group("gm_panel")
	if gm != null and gm.is_open(): return
	for child in get_children():
		if child is Window and child.visible: return
	var panel := preload("res://Scripts/UI/pause_menu.gd").new()
	add_child(panel)
	panel.menu_requested.connect(_return_to_menu)
	panel.open(pause_snapshot)

func _open_jobs() -> void:
	if not _can_open_city_board(): return
	var board := preload("res://Scripts/UI/job_board.gd").new()
	add_child(board)
	board.changed.connect(show_floor_map)
	board.open(flow.run)

func _open_familia() -> void:
	if not _can_open_city_board(): return
	var board := preload("res://Scripts/UI/familia_board.gd").new()
	add_child(board)
	board.changed.connect(show_floor_map)
	board.open(flow)

func _can_open_city_board() -> bool:
	if not map_visible or flow == null or flow.run == null or flow.run.phase != "city" or not flow.run.pending.is_empty(): return false
	for child in get_children():
		if child is Window and child.visible: return false
	return true

func _open_quests() -> void:
	if flow == null or flow.run == null or flow.run.phase != "city": return
	for child in get_children():
		if child is Window and child.visible: return
	var board := preload("res://Scripts/UI/quest_board.gd").new()
	add_child(board)
	board.changed.connect(show_floor_map)
	board.open(flow)

func _open_training() -> void:
	if flow == null or flow.run != null or busy or get_tree().paused: return
	var gm := get_tree().get_first_node_in_group("gm_panel")
	if gm != null and gm.is_open(): return
	for child in get_children():
		if child is Window and child.visible: return
	var panel := preload("res://Scripts/UI/training_panel.gd").new()
	add_child(panel)
	panel.open(flow)

func _toggle_practice() -> void:
	if busy or (flow != null and flow.run != null): return
	preload("res://Scripts/Core/game_log.gd").event("battle", "practice_switch", {"party": not party_practice, "previous": battle.log_state()})
	party_practice = not party_practice
	if flow != null: flow.active_character = CharacterLibrary.resolve()
	start_encounter()

func _party_status() -> String:
	var result: Array[String] = []
	for id in ["squire", "scout"]:
		var member: Dictionary = flow.party_companion(id)
		if not member.is_empty(): result.append("%s Lv%d · HP %d/%d" % [member.name, member.level, member.hp, member.max_hp])
	if not flow.run.character.familia_id.is_empty() and flow.run.character.familia_id != "dawn": return preload("res://Scripts/Character/familia_library.gd").name_for(flow.run.character.familia_id) + " · 单人探索；转回晨行后可招募远征队友"
	return "单人探索 · 在城市眷族菜单招募队友" if result.is_empty() else "  /  ".join(result)

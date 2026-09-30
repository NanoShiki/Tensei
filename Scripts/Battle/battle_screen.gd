extends Control

const BattleState = preload("res://Scripts/Battle/battle_state.gd")
const Abilities = preload("res://Scripts/Battle/ability_library.gd")
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
	battle.setup(character, floor_number, -1, flow != null and flow.run != null and flow.run.is_captain_node(flow.run.pending), BattleState.practice_companion() if party_practice else {})
	_refresh()
	_drive_enemy()

func _refresh() -> void:
	_clear()
	_backdrop()
	var floor_number: int = flow.run.floor_number if flow != null and flow.run != null else 1
	_label("T E N S E I   /   地下城", Rect2(28, 16, 350, 28), 18, GOLD)
	_label("第 %02d 层   ·   苔石回廊" % floor_number, Rect2(28, 49, 340, 24), 14, MUTED)
	_label("第 %d 轮" % battle.round_number, Rect2(470, 12, 80, 24), 16, GOLD)
	for i in range(battle.order.size()):
		var id: String = battle.order[i]
		var name_text: String = battle.unit(id).name
		var active: bool = battle.current_id() == id
		_panel(Rect2(565 + i * 152, 16, 138, 53), Color("29372e") if active else Color("19262b"), GOLD if active else Color("3c4948"))
		_label(("▶  " if active else "    ") + name_text, Rect2(577 + i * 152, 28, 120, 30), 18, GOLD if active else MUTED)
	_button("返回主菜单", Rect2(1090, 22, 158, 40), _return_to_menu)
	if flow == null or flow.run == null:
		_button("单人演练" if party_practice else "双人演练", Rect2(28, 88, 158, 36), _toggle_practice)
	if not battle.ally.is_empty():
		_unit("lorn", battle.hero, Rect2(85, 197, 210, 284), "res://Assets/Battle/lorn.png")
		_unit("squire", battle.ally, Rect2(330, 212, 185, 267), "res://Assets/Battle/lorn.png")
	else:
		_unit("lorn", battle.hero, Rect2(202, 145, 294, 340), "res://Assets/Battle/lorn.png")
	_unit("goblin", battle.enemy, Rect2(833, 205, 222, 302), "res://Assets/Battle/goblin.png")
	if battle.enemy.captain:
		_label(battle.enemy_intent(), Rect2(500, 90, 730, 36), 18, GOLD)
	var message := "选择技能，再点击高亮目标。"
	if busy or battle.current_id() == "goblin": message = str(battle.enemy.name) + "正在行动…"
	elif not selected.is_empty():
		var entry: Dictionary = Abilities.ENTRIES[selected]
		message = "%s → 点击%s确认   ·   右键 / Esc 取消" % [entry.name, str(battle.enemy.name) if entry.target == "enemy" else ("存活受伤队友" if selected == "potion" else str(battle.current_unit().name))]
		if entry.target == "enemy" and not entry.has("stock"): message += "   ·   命中 %d%%" % battle.hit_chance(selected)
	elif battle.action == 0: message = "本回合已行动。点击「结束回合」继续。"
	hint_label = _label(message, Rect2(30, 480, 1220, 32), 17, GOLD)
	_panel(Rect2(20, 529, 257, 170))
	var actor: Dictionary = battle.current_unit() if battle.is_player_turn() else battle.hero
	_label("装备 / " + str(actor.name), Rect2(36, 541, 230, 26), 17, GOLD)
	_label("%s · 布衣\n护甲 AC %d · 命中 +%d\n剑技伤害加成 +%d" % [CharacterLibrary.weapon_name(actor), actor.ac, actor.attack, CharacterLibrary.weapon_bonus(actor)], Rect2(36, 577, 226, 70), 16)
	_label("生命 %d / %d" % [actor.hp, actor.max_hp], Rect2(36, 652, 225, 26), 18, Color("9fc0a0"))
	_panel(Rect2(291, 529, 448, 170))
	_label("技能", Rect2(307, 541, 60, 24), 17, GOLD)
	_label("剩余行动  %d   ·   每回合 1 次" % battle.action, Rect2(388, 541, 355, 24), 16, MUTED)
	var ids := ["strike", "power", "guard", "surge"]
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
	log_label = _label(log_text, Rect2(550, 324, 265, 132) if not battle.ally.is_empty() else Rect2(464, 324, 355, 132), 13, MUTED)
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
	if id == "squire": texture.modulate = Color("94c9da")
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
	canvas.add_child(button)
	targets[id] = button
	if targetable:
		_label("▼  选择目标", Rect2(rect.position.x + 35, 91, 210, 30), 18, GOLD)
	var compact: bool = not battle.ally.is_empty() and id != "goblin"
	_label(("%s\n%d / %d · AC %d" if compact else "%s   %d / %d   AC %d") % [data.name, data.hp, data.max_hp, data.ac], Rect2(rect.position.x, 134 if compact else 121, rect.size.x if compact else 290, 50 if compact else 28), 16 if compact else 17, GOLD if targetable else PAPER)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.position = Vector2(rect.position.x, 188 if compact else 151)
	bar.custom_minimum_size = Vector2(minf(216, rect.size.x), 7)
	for state in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = (Color("8fad82") if id != "goblin" else Color("ba7769")) if state == "fill" else Color("303e3e")
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
		button.tooltip_text = "1 行动 · 命中 +%d · 1d%d+%d 伤害" % [int(actor.attack) - int(entry.get("penalty", 0)), entry.die, int(entry.bonus) + CharacterLibrary.weapon_bonus(actor)] + ("\n" + reason if not reason.is_empty() else "")
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = load("res://Assets/Battle/%s.svg" % id)
	icon.position = Vector2((rect.size.x - 40) / 2, 8)
	icon.size = Vector2(40, 40)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if button.disabled: icon.modulate = Color(0.6, 0.6, 0.6, 0.4)
	button.add_child(icon)
	buttons[id] = button

func _select(id: String) -> void:
	if busy or not battle.reason(id).is_empty(): return
	selected = "" if selected == id else id
	_refresh()

func _target(id: String) -> void:
	if busy or selected.is_empty(): return
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
	var x := 860 if event.target == "goblin" else (340 if event.target == "squire" else (95 if not battle.ally.is_empty() else 240))
	var label := _label(str(event.text), Rect2(x, 220, 280, 55), 29, GOLD)
	var tween := create_tween()
	tween.tween_property(label, "position:y", 185.0, 0.4)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.4)
	await tween.finished

func _end_turn() -> void:
	if busy or not battle.end_turn(): return
	selected = ""
	_refresh()
	_drive_enemy()

func _drive_enemy() -> void:
	if battle.current_id() != "goblin":
		_settle()
		return
	busy = true
	_refresh()
	await get_tree().create_timer(0.5).timeout
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
		if flow.run != null: flow.run.finish_battle(battle.hero, battle.outcome == "victory")

func gm_kill_reason() -> String:
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
	var run: RefCounted = flow.run
	if run.phase == "city":
		_show_city()
		return
	if run.phase == "returned":
		_show_return_summary()
		return
	_label("地 下 城   /   路 线", Rect2(32, 18, 450, 42), 25, GOLD)
	_label("第 %02d / %02d 层" % [run.floor_number, run.total_floors], Rect2(500, 20, 210, 40), 25)
	_button("背包 · B", Rect2(720, 22, 135, 40), _open_inventory)
	_button("放弃并回主菜单", Rect2(1060, 22, 190, 40), _return_to_menu)
	_button("保存并退出", Rect2(870, 22, 175, 40), _request_save_exit)
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
		if item.kind == "battle":
			status = ("守关队长" if run.is_captain_node(item.id) else "怪物在场") if item.enemy_active else "刷新还需 %d 步" % item.respawn_in
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
			button.tooltip_text = "每次合法移动先扣一步，再检查目的地。" + ("此处剩 1 步，进入时将遇敌。" if item.respawn_in == 1 and not item.enemy_active else "停留、预览和战斗回合不推进刷新。")
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
	_label(run.message, Rect2(48, 619, 1150, 60), 20).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _begin_return() -> void:
	if flow.run.begin_return(): show_floor_map()

func _request_save_exit() -> void:
	var browser := preload("res://Scripts/UI/save_browser.gd").new()
	add_child(browser)
	browser.saved.connect(func(record_id: String):
		flow.active_record_id = record_id
		flow.return_to_menu())
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
	_label("城 市   /   整 备", Rect2(32, 18, 480, 42), 25, GOLD)
	city_buttons["quests"] = _button("委托", Rect2(570, 22, 135, 40), _open_quests)
	_button("背包 · B", Rect2(720, 22, 135, 40), _open_inventory)
	_button("保存并退出", Rect2(870, 22, 175, 40), _request_save_exit)
	_button("主菜单（未保存）", Rect2(1060, 22, 190, 40), _return_to_menu)
	_panel(Rect2(30, 112, 410, 402))
	_label("%s · 等级 %d" % [str(flow.profile.get("name", "角色")).left(12), hero.level], Rect2(52, 137, 370, 40), 23, GOLD)
	_label("生命 %d / %d · 经验 %d\n金币 %d\n铁片 %d\n治疗药水 %d · 灼烧药水 %d\n装备：%s" % [hero.hp, hero.max_hp, hero.experience, hero.gold, hero.scrap, hero.potions, hero.fire_potions, CharacterLibrary.weapon_name(hero)], Rect2(52, 202, 365, 260), 23)
	_panel(Rect2(468, 112, 780, 402))
	_label("阶段目标：已击败守关队长 · 可继续探索" if hero.captain_defeated else "阶段目标：打造铁剑，挑战第 3 层守关队长并回城", Rect2(42, 72, 1190, 32), 19, GOLD)
	_label("休整与工坊", Rect2(496, 137, 700, 40), 24, GOLD)
	city_buttons["rest"] = _button("旅店休整 · 免费恢复全部生命", Rect2(496, 192, 720, 46), _city_service.bind("rest"))
	city_buttons["rest"].disabled = hero.hp >= hero.max_hp
	city_buttons["potion"] = _button("购买治疗药水 ×1 · 3 金币", Rect2(496, 250, 720, 46), _city_service.bind("potion"))
	city_buttons["potion"].disabled = hero.gold < 3
	city_buttons["fire_potion"] = _button("购买灼烧药水 ×1 · 4 金币（战斗／绕行）", Rect2(496, 308, 720, 46), _city_service.bind("fire_potion"))
	city_buttons["fire_potion"].disabled = hero.gold < 4
	city_buttons["forge"] = _button("铁剑已装备" if hero.weapon == "iron_sword" else "打造并装备铁剑 · 6 金币 + 3 铁片", Rect2(496, 366, 720, 46), _city_service.bind("forge"), true)
	city_buttons["forge"].disabled = hero.weapon == "iron_sword" or hero.gold < 6 or hero.scrap < 3
	_label("铁剑：剑击与强攻伤害 +2。战斗胜利获得 3 金币、1 铁片。", Rect2(496, 433, 716, 58), 17, MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(flow.run.message, Rect2(42, 541, 1180, 60), 20).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	city_buttons["depart"] = _button("准备完毕 · 从第一层出发", Rect2(420, 620, 440, 58), _depart_city, true)

func _city_service(action: String) -> void:
	if flow.run.city_service(action): show_floor_map()

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
			_select(["strike", "power", "guard", "surge", "potion", "fire_potion"][event.keycode - KEY_1])

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

func _open_quests() -> void:
	if flow == null or flow.run == null or flow.run.phase != "city": return
	for child in get_children():
		if child is Window and child.visible: return
	var board := preload("res://Scripts/UI/quest_board.gd").new()
	add_child(board)
	board.changed.connect(show_floor_map)
	board.open(flow.run)

func _toggle_practice() -> void:
	if busy or (flow != null and flow.run != null): return
	preload("res://Scripts/Core/game_log.gd").event("battle", "practice_switch", {"party": not party_practice, "previous": battle.log_state()})
	party_practice = not party_practice
	if flow != null: flow.active_character = CharacterLibrary.resolve()
	start_encounter()

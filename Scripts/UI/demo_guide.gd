extends Window

const Log = preload("res://Scripts/Core/game_log.gd")
const Quests = preload("res://Scripts/Character/quest_library.gd")
var rows: VBoxContainer
var scroll: ScrollContainer
var summary: Label
var stage_labels: Dictionary = {}

func open(expedition: RefCounted = null, guild_level: int = 0) -> void:
	title = "完整试玩指南"
	transient = true
	exclusive = true
	unresizable = true
	close_requested.connect(queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	summary = _text("从新角色到第五层：准备 → 探索 → 自由返程 → 回城成长。", box)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 16)
	scroll.add_child(rows)
	if expedition != null:
		summary.text = "%s\n当前等级 %d · 经验 %d / 85 · 第 %d 层" % [expedition.objective_text(), expedition.character.level, expedition.character.experience, expedition.floor_number]
	for item in stages(expedition, guild_level):
		stage_labels[item.id] = _text(item.title + " · " + item.status + "\n" + item.text, rows)
	_text("战斗：先选技能，再点高亮目标；空格结束回合，右键／Esc 取消选择。B 打开地图背包。\n路线：可随时切换深入／返回，沿合法分支选路；实际移动才扣刷新步数，未知节点靠近后揭示。\n保存：地图和城市手动“保存记录”，可选择保存后继续或退出，同一角色可保留多个时点。关闭游戏和回城不自动保存。读取旧个人记录恢复旧进度，共享队友成长保持最新。\n测试：右上 GM 可秒杀、恢复存活成员和补药。测试修改会进入手动存档。", rows)
	var close := Button.new()
	close.text = "关闭 · Esc / F1"
	close.custom_minimum_size.y = 38
	close.pressed.connect(queue_free)
	box.add_child(close)
	popup_centered(Vector2i(740, 470))
	close.grab_focus()
	Log.event("ui", "guide_open", {"scope": "general" if expedition == null else "journey", "level": 0 if expedition == null else expedition.character.level})

func _text(value: String, parent: Node) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	parent.add_child(label)
	return label

static func stages(expedition: RefCounted = null, guild_level: int = 0) -> Array:
	var hero: Dictionary = {} if expedition == null else expedition.character
	var entries := [
		{"id": "prepare", "title": "1. 城市准备", "text": "城市点“委托”，接取初次讨伐、工坊供货和守关队长讨伐。职业菜单可免费试选四职业。旅店免费恢复全队，准备后从第一层出发。"},
		{"id": "growth", "title": "2. 首趟收获", "text": "赢三场后选“向上返回”，沿高亮分支回到第一层入口，再进入城市。交付讨伐和三铁片，累计 25 经验到等级 3；升级保持当前生命，旅店可补满。"},
		{"id": "equipment", "title": "3. 打造与补给（可选）", "text": "铁剑需要 6 金币、3 铁片，物理伤害 +2。城市“工坊／装备”查看配方和选择持有武器；加入炉心后可用 9 金币、4 铁片制作淬火铁剑（+3），转会保留。供货也消耗铁片，可分趟收集。治疗 3 金币、灼烧 4 金币；一瓶灼烧可掩护绕行，不给战利品。"},
		{"id": "captain", "title": "4. 第三层队长", "text": "第三层 1a 是守关队长。看清蓄力／重击意图，使用闪避、恢复与技能。胜利后自由返程交付；三条入门任务合计 50 经验、等级 4。"},
		{"id": "familia", "title": "5. 眷族与成员", "text": "交付初次讨伐后，城市“眷族／编队”加入晨行、招募卫士。编队三胜升组织等级 2，可招募游侠并接取成员巡守；接取后编队五胜回城领奖。每位成员有自己的回合，只给实际参战队友共享经验。"},
		{"id": "depth", "title": "6. 第五层勘察", "text": "交付队长委托后，在城市接取勘察，再次抵达第五层。入口休整站可付费恢复存活成员（各至多12），购买较贵途中药水；服务不推进刷新，倒下成员需回城。可途中保存再继续，达成后回城交付。五条任务全部交付累计 85 经验、等级 5、生命上限 52。"},
	]
	for item in entries:
		item.status = "流程说明"
		if hero.is_empty(): continue
		match item.id:
			"prepare": item.status = "已接取" if ["hunt", "materials", "captain"].all(func(id: String): return hero.quests[id] != "available") else "城市委托中接取"
			"growth": item.status = "已交付" if hero.quests.hunt == "claimed" and hero.quests.materials == "claimed" else "讨伐：%s；供货：%s" % [Quests.progress(hero, "hunt"), Quests.progress(hero, "materials")]
			"equipment": item.status = "当前装备：" + preload("res://Scripts/Character/character_library.gd").weapon_name(hero) if hero.weapons.has("iron_sword") else "持有 %d 金币、%d 铁片" % [hero.gold, hero.scrap]
			"captain": item.status = "已交付" if hero.quests.captain == "claimed" else Quests.progress(hero, "captain")
			"familia": item.status = "未加入" if hero.familia_id.is_empty() else ("共享资格不可用" if guild_level == 0 else "组织等级 %d · 巡守 %s" % [guild_level, {"available": "未接取", "active": Quests.progress(hero, "familia_patrol"), "claimed": "已交付"}[hero.quests.familia_patrol]])
			"depth": item.status = {"available": "未接取", "active": Quests.progress(hero, "depth_five"), "claimed": "已交付"}[hero.quests.depth_five]
		if item.id == "familia" and not hero.familia_id.is_empty() and hero.familia_id != "dawn": item.status = "当前" + preload("res://Scripts/Character/familia_library.gd").name_for(hero.familia_id) + " · 晨行巡守暂停，转回后继续"
	return entries

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F1]:
		set_input_as_handled()
		queue_free()

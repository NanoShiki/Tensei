extends Window

signal changed
const Familias = preload("res://Scripts/Character/familia_library.gd")
var flow: Node
var rows: VBoxContainer
var feedback: Label
var buttons: Dictionary = {}

func open(game_flow: Node) -> void:
	flow = game_flow
	title = "眷族归属与编队"
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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size.y = 38
	close.pressed.connect(queue_free)
	box.add_child(close)
	_refresh()
	popup_centered(Vector2i(680, 470))
	close.grab_focus()

func _text(value: String) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	rows.add_child(label)

func _button(id: String, label: String, disabled: bool) -> void:
	var button := Button.new()
	button.text = label
	button.disabled = disabled
	button.custom_minimum_size.y = 40
	button.pressed.connect(_act.bind(id))
	rows.add_child(button)
	buttons[id] = button

func _refresh() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	buttons.clear()
	var hero: Dictionary = flow.run.character
	_text("当前归属：" + Familias.name_for(hero.familia_id) + "\n每个角色同时加入一个眷族；转会保留原组织成长与个人任务，旧队友留城。")
	_text("晨行眷族 · 远征与讨伐\n加入资格：交付“初次讨伐”委托。当前：" + ("已达成" if hero.quests.hunt == "claimed" else "未达成"))
	var joined: bool = hero.familia_id == "dawn"
	_button("join", "已加入晨行眷族" if joined else ("加入晨行眷族" if hero.familia_id.is_empty() else "转入晨行眷族 · 免费"), joined or hero.quests.hunt != "claimed")
	if joined:
		var available: bool = flow.progress.refresh() and flow.progress.data.get("player_id") == hero.player_id
		if available:
			var member: Dictionary = flow.progress.companion()
			_text("眷族等级 %d · 贡献 %d\n见习卫士 · 等级 %d · 共享经验 %d · 生命上限 %d\n命中 +4 · 防御 13 · 练习木剑\n每次编队胜利：眷族贡献 +1，各参战队友经验 +2。" % [flow.progress.guild_level(), flow.progress.data.familias.dawn.contribution, member.level, member.experience, member.max_hp])
			var roster := "洛恩"
			if hero.party_enlisted: roster += " + 见习卫士（生命 %d/%d）" % [hero.party_hp, member.max_hp]
			if hero.scout_enlisted: roster += " + 见习游侠（生命 %d/%d）" % [hero.scout_hp, flow.progress.companion("scout").max_hp]
			_text("当前编队：" + roster)
		else: _text("共享档案不可用，请恢复同一玩家的备份。" + flow.progress.message)
		_button("dismiss" if hero.party_enlisted else "enlist", "让卫士留在城市" if hero.party_enlisted else "招募见习卫士 · 免费", not available)
		if available:
			var scout: Dictionary = flow.progress.companion("scout")
			_text("见习游侠 · 弓箭手 · 等级 %d · 经验 %d\n生命上限 %d · 命中 +5 · 防御 12 · 敏捷 +3\n等级 2 开放瞄准射击；晨行眷族等级 2 可招募。\n当前：%s" % [scout.level, scout.experience, scout.max_hp, "已编队 · 生命 %d/%d" % [hero.scout_hp, scout.max_hp] if hero.scout_enlisted else "未编队"])
		_button("dismiss_scout" if hero.scout_enlisted else "enlist_scout", "让游侠留在城市" if hero.scout_enlisted else "招募见习游侠 · 免费 · 眷族等级 2", not available or (not hero.scout_enlisted and flow.progress.guild_level() < 2))
	_text("炉心眷族 · 锻造与工艺\n加入资格：打造并持有铁剑。当前：" + ("已达成" if Familias.qualified(hero, "ember") else "未达成") + "\n" + flow.workshop_status() + "\n会员可制作淬火铁剑；当前不提供远征队友。")
	_button("join_ember", "已加入炉心眷族" if hero.familia_id == "ember" else ("加入炉心眷族" if hero.familia_id.is_empty() else "转入炉心眷族 · 免费"), hero.familia_id == "ember" or not Familias.qualified(hero, "ember"))
	if hero.familia_id == "ember":
		var level: int = flow.guild_level()
		_text("炉心等级 %d · 贡献 %d\n晨行成员巡守暂停推进和交付，转回晨行后从原进度继续。" % [level, flow.progress.data.get("familias", {}).get("ember", {}).get("contribution", 0)] if level > 0 else "炉心共享档案不可用，请恢复同一玩家备份。")
	if not hero.player_id.is_empty():
		_button("retry", "同步待提交成长／专业贡献 · %d 条" % (hero.growth_pending.size() + hero.forge_pending.size() + hero.commerce_pending.size()), hero.growth_pending.is_empty() and hero.forge_pending.is_empty() and hero.commerce_pending.is_empty())
	_text("集市眷族 · 订单与补给\n加入资格：完成铁片供货订单。当前：" + ("已达成" if Familias.qualified(hero, "harbor") else "未达成") + "\n" + flow.commerce_status() + "\n会员可购买一次补给礼包；当前不提供远征队友。")
	_button("join_harbor", "已加入集市眷族" if hero.familia_id == "harbor" else ("加入集市眷族" if hero.familia_id.is_empty() else "转入集市眷族 · 免费"), hero.familia_id == "harbor" or not Familias.qualified(hero, "harbor"))
	if hero.familia_id == "harbor": _text("晨行巡守在集市暂停；转回晨行可继续原进度。个人武器、职业、任务与各组织成长保留。")
	feedback.text = "眷族与队友成长自动写入共享档案；角色归属、编队和当前生命需手动保存。最多三人和免费招募为 Demo 规则。"

func _act(action: String) -> void:
	if action in ["join", "join_ember", "join_harbor"] and not flow.run.character.familia_id.is_empty():
		var target: String = {"join": "dawn", "join_ember": "ember", "join_harbor": "harbor"}[action]
		if target != flow.run.character.familia_id:
			_confirm_transfer(action, target)
			return
	_apply(action)

func _confirm_transfer(action: String, target: String) -> void:
	for child in get_children():
		if child is ConfirmationDialog: return
	var confirm := ConfirmationDialog.new()
	confirm.title = "确认转会"
	confirm.ok_button_text = "确认转会"
	confirm.cancel_button_text = "取消"
	confirm.transient = true
	confirm.exclusive = true
	confirm.dialog_text = "转入%s？\n旧组织成长保留，晨行队友将留城，个人装备／任务保留。\n晨行巡守在其他眷族暂停；先同步待提交成长，主角须存活。\nDemo 免费转会，确认后请手动保存。" % Familias.name_for(target)
	confirm.confirmed.connect(func():
		_apply(action)
		confirm.queue_free())
	confirm.canceled.connect(confirm.queue_free)
	confirm.close_requested.connect(confirm.queue_free)
	add_child(confirm)
	confirm.popup_centered(Vector2i(570, 235))

func _apply(action: String) -> void:
	if flow.familia_service(action):
		_refresh()
		changed.emit()
	feedback.text = flow.familia_message

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()

extends Window

signal changed
var flow: Node
var rows: VBoxContainer
var feedback: Label
var buttons: Dictionary = {}

func open(game_flow: Node) -> void:
	flow = game_flow
	title = "晨行眷族与编队"
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
	_text("晨行眷族 · 远征与讨伐\n加入资格：交付“初次讨伐”委托。当前：" + ("已达成" if hero.quests.hunt == "claimed" else "未达成"))
	var joined: bool = hero.familia_id == "dawn"
	_button("join", "已加入晨行眷族" if joined else "加入晨行眷族", joined or hero.quests.hunt != "claimed")
	if joined:
		var available: bool = flow.progress.refresh() and flow.progress.data.get("player_id") == hero.player_id
		if available:
			var member: Dictionary = flow.progress.companion()
			_text("眷族等级 %d · 贡献 %d\n见习卫士 · 等级 %d · 共享经验 %d · 生命上限 %d\n命中 +4 · 防御 13 · 练习木剑\n每次编队参战胜利：眷族贡献 +1，卫士经验 +2。" % [flow.progress.guild_level(), flow.progress.data.familias.dawn.contribution, member.level, member.experience, member.max_hp])
			_text("当前编队：" + ("洛恩 + 见习卫士（生命 %d/%d）" % [hero.party_hp, member.max_hp] if hero.party_enlisted else "洛恩"))
		else: _text("共享档案不可用，请恢复同一玩家的备份。" + flow.progress.message)
		_button("dismiss" if hero.party_enlisted else "enlist", "让卫士留在城市" if hero.party_enlisted else "招募见习卫士 · 免费", not available)
		_button("retry", "同步待提交成长 · %d 条" % hero.growth_pending.size(), hero.growth_pending.is_empty() or not available)
	feedback.text = "眷族与卫士成长自动写入共享档案；角色归属、编队和当前生命需手动保存。双人和免费招募为 Demo 规则。"

func _act(action: String) -> void:
	if flow.familia_service(action):
		_refresh()
		changed.emit()
	feedback.text = flow.familia_message

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()

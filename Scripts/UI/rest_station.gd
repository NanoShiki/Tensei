extends Window

signal changed
var flow: Node
var details: Label
var feedback: Label
var buttons: Dictionary = {}

func open(game_flow: Node) -> void:
	flow = game_flow
	title = "第五层入口 · 休整站"
	transient = true
	exclusive = true
	unresizable = true
	close_requested.connect(queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_font_size_override("font_size", 18)
	box.add_child(details)
	for action in ["rest", "potion", "fire_potion"]:
		var button := Button.new()
		button.text = {"rest": "全体存活成员 +12 生命 · 8 金币", "potion": "治疗药水 ×1 · 5 金币（城市 3）", "fire_potion": "灼烧药水 ×1 · 7 金币（城市 4）"}[action]
		button.custom_minimum_size.y = 44
		button.pressed.connect(_service.bind(action))
		box.add_child(button)
		buttons[action] = button
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(feedback)
	var refresh := Button.new()
	refresh.text = "刷新资源与队友资格"
	refresh.custom_minimum_size.y = 32
	refresh.pressed.connect(_refresh)
	box.add_child(refresh)
	var close := Button.new()
	close.text = "关闭 · 继续深入或返回 / Esc"
	close.custom_minimum_size.y = 38
	close.pressed.connect(queue_free)
	box.add_child(close)
	_refresh()
	popup_centered(Vector2i(690, 470))
	close.grab_focus()

func _refresh() -> void:
	var hero: Dictionary = flow.run.character
	details.text = "金币 %d · 主角生命 %d/%d\n治疗 ×%d · 灼烧 ×%d\n途中服务价格高于城市；休整只治疗存活成员，至多各 12 生命，不能复活。操作不推进移动或怪物刷新，请手动保存。" % [hero.gold, hero.hp, hero.max_hp, hero.potions, hero.fire_potions]
	var members := PackedStringArray()
	if hero.party_enlisted: members.append("卫士 %d" % hero.party_hp)
	if hero.scout_enlisted: members.append("游侠 %d" % hero.scout_hp)
	if not members.is_empty(): details.text += "\n队友生命：" + " · ".join(members)
	for action in buttons:
		var reason: String = flow.station_reason(action)
		buttons[action].disabled = not reason.is_empty()
		buttons[action].tooltip_text = reason
	feedback.text = flow.station_reason("rest")

func _service(action: String) -> void:
	flow.station_service(action)
	_refresh()
	feedback.text = flow.run.message
	changed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()

extends Window

signal changed
const Quests = preload("res://Scripts/Character/quest_library.gd")
var run: RefCounted
var rows: VBoxContainer
var feedback: Label
var buttons: Dictionary = {}
var guild_level := 0
var flow: Node

func open(game_flow: Node) -> void:
	flow = game_flow
	run = flow.run
	title = "城市委托"
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
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	var refresh := Button.new()
	refresh.text = "刷新委托与共享资格"
	refresh.custom_minimum_size.y = 30
	refresh.pressed.connect(_refresh)
	box.add_child(refresh)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size.y = 38
	close.pressed.connect(queue_free)
	box.add_child(close)
	_refresh()
	popup_centered(Vector2i(680, 470))
	close.grab_focus()

func _refresh() -> void:
	guild_level = flow.guild_level()
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	buttons.clear()
	for id in Quests.DEFINITIONS:
		var entry: Dictionary = Quests.DEFINITIONS[id]
		var state: String = run.character.quests[id]
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 18)
		label.text = "%s · %s\n%s · %s\n奖励：%d 金币、%d 经验" % [entry.name, {"available": "未接取", "active": "进行中", "claimed": "已交付"}[state], entry.goal, Quests.progress(run.character, id), entry.gold, entry.xp]
		if id == "familia_patrol":
			label.text += ("\n当前眷族等级：%d" % guild_level if guild_level > 0 else ("\n未加入眷族" if run.character.familia_id.is_empty() else "\n共享资格不可用，请恢复同一玩家备份后刷新")) + " · 仅接取后的实际编队胜利计入。"
		if id == "depth_five": label.text += "\n只记录接取后的抵达楼层；返回和再次出发保留最高进度。"
		rows.add_child(label)
		var button := Button.new()
		button.custom_minimum_size.y = 38
		button.text = "接取委托" if state == "available" else ("已领取" if state == "claimed" else ("交付 3 铁片并领取奖励" if id == "materials" else "领取奖励"))
		var reason: String = Quests.reason(run.character, id, "accept" if state == "available" else "claim", guild_level)
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason
		button.pressed.connect(_act.bind(id, "accept" if state == "available" else "claim"))
		rows.add_child(button)
		buttons[id] = button
	feedback.text = "每个角色每条委托仅交付一次；接取和交付后仍需手动保存。"

func _act(id: String, action: String) -> void:
	if flow.run != run:
		feedback.text = "当前角色已变化，请重新打开委托。"
		return
	if flow.quest_service(id, action):
		_refresh()
		feedback.text = run.message
		changed.emit()
	else:
		_refresh()
		feedback.text = "当前条件不满足，资源保留。"

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()

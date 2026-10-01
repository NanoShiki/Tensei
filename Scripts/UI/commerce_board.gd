extends Window

signal changed
const Commerce = preload("res://Scripts/Character/commerce_library.gd")
var flow: Node
var rows: VBoxContainer
var feedback: Label
var buttons: Dictionary = {}

func open(game_flow: Node) -> void:
	flow = game_flow
	title = "集市订单与补给"
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
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	var refresh := Button.new()
	refresh.text = "刷新订单与共享资格"
	refresh.custom_minimum_size.y = 32
	refresh.pressed.connect(_refresh)
	box.add_child(refresh)
	var close := Button.new()
	close.text = "关闭 · Esc"
	close.custom_minimum_size.y = 38
	close.pressed.connect(queue_free)
	box.add_child(close)
	_refresh()
	popup_centered(Vector2i(710, 470))
	close.grab_focus()

func _text(value: String) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	rows.add_child(label)

func _refresh() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	buttons.clear()
	var hero: Dictionary = flow.run.character
	_text("金币 %d · 铁片 %d · 治疗 ×%d\n%s\n供货对所有归属开放；会员礼包只在当前加入集市时开放。个人订单、金币和药水需手动保存。" % [hero.gold, hero.scrap, hero.potions, flow.commerce_status()])
	for id in Commerce.ENTRIES:
		var order: Dictionary = Commerce.ENTRIES[id]
		var reason: String = flow.commerce_reason(id)
		_text(order.name + "\n" + order.description)
		var button := Button.new()
		button.text = "完成订单：" + order.name if reason.is_empty() else reason
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason
		button.custom_minimum_size.y = 40
		button.pressed.connect(_service.bind(id))
		rows.add_child(button)
		buttons[id] = button
	feedback.text = "订单以真实消耗结算，同角色同订单只增加一次共享贡献；数值与礼包为 Demo 规则。"

func _service(id: String) -> void:
	flow.commerce_service(id)
	_refresh()
	feedback.text = flow.run.message
	changed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()

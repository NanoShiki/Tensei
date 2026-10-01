extends Window

signal changed
const Trades = preload("res://Scripts/Character/trade_library.gd")
var flow: Node
var quantity: SpinBox
var status: Label
var feedback: Label
var rows: VBoxContainer
var buttons: Dictionary = {}

func open(game_flow: Node) -> void:
	flow = game_flow
	title = "批量补给与材料出售"
	transient = true
	exclusive = true
	unresizable = true
	close_requested.connect(queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var line := HBoxContainer.new()
	box.add_child(line)
	var label := Label.new()
	label.text = "交易数量（每笔 1–99）"
	line.add_child(label)
	quantity = SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = 99
	quantity.step = 1
	quantity.update_on_text_changed = true
	quantity.value = 1
	quantity.custom_minimum_size = Vector2(160, 36)
	quantity.value_changed.connect(func(_value: float): _refresh())
	line.add_child(quantity)
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
	feedback.text = "出售会消耗铁片，打造和委托仍使用剩余库存。普通交易不计眷族贡献，请手动保存。"
	box.add_child(feedback)
	_button(box, "刷新持有资源", _refresh)
	var close := _button(box, "关闭 · Esc", queue_free)
	_refresh()
	popup_centered(Vector2i(650, 455))
	close.grab_focus()

func _button(box: VBoxContainer, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.pressed.connect(callback)
	box.add_child(button)
	return button

func _refresh() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	buttons.clear()
	var hero: Dictionary = flow.run.character
	status.text = "金币 %d · 铁片 %d · 治疗 ×%d · 灼烧 ×%d\n城市售价：治疗 3、灼烧 4；铁片收购 1 金币／片。" % [hero.gold, hero.scrap, hero.potions, hero.fire_potions]
	var amount := int(quantity.value)
	for id in Trades.ENTRIES:
		var trade: Dictionary = Trades.ENTRIES[id]
		var reason: String = flow.run.trade_reason(id, amount)
		var text := ("购买 %s ×%d · 支付 %d 金币" if trade.buy else "出售 %s ×%d · 获得 %d 金币") % [trade.name, amount, amount * trade.price]
		var button := _button(rows, text, _service.bind(id))
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason if not reason.is_empty() else "确认此数量与总价，完成一次交易。"
		buttons[id] = button

func _service(id: String) -> void:
	flow.trade_service(id, int(quantity.value))
	_refresh()
	feedback.text = flow.run.message
	changed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()

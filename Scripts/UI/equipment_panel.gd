extends Window

signal changed
const Weapons = preload("res://Scripts/Character/weapon_library.gd")
const Armors = preload("res://Scripts/Character/armor_library.gd")
var flow: Node
var rows: VBoxContainer
var feedback: Label
var buttons: Dictionary = {}

func open(game_flow: Node) -> void:
	flow = game_flow
	title = "炉心工坊与个人装备"
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
	refresh.text = "刷新配方与共享资格"
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

func _button(id: String, text: String, reason: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason
	button.custom_minimum_size.y = 40
	button.pressed.connect(action)
	rows.add_child(button)
	buttons[id] = button

func _refresh() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	buttons.clear()
	var hero: Dictionary = flow.run.character
	_text("%d 金币 · %d 铁片\n%s\n制作保留已有装备并自动装备成品。个人装备与配方为 Demo 参数，均需手动保存。" % [hero.gold, hero.scrap, flow.workshop_status()])
	for id in ["iron_sword", "tempered_sword"]:
		var recipe: Dictionary = Weapons.ENTRIES[id]
		var reason: String = flow.forge_reason(id)
		_text("%s · 物理伤害 +%d · %d 金币 + %d 铁片\n%s" % [recipe.name, recipe.bonus, recipe.gold, recipe.scrap, "基础配方，对所有归属开放。" if not recipe.member else "炉心会员配方：当前加入炉心并持有铁剑；转会后保留个人成品。"])
		_button("forge_" + id, "制作并装备" if reason.is_empty() else reason, reason, _craft.bind(id))
	var armor_reason: String = flow.forge_reason("iron_armor")
	_text("铁甲 · 防御 AC +1 · 6 金币 + 3 铁片\n基础配方，对所有归属开放；不改变命中、伤害、生命或职业。")
	_button("forge_iron_armor", "制作并装备铁甲" if armor_reason.is_empty() else armor_reason, armor_reason, _craft.bind("iron_armor"))
	_text("已持有装备 · 只在城市切换，不消耗资源或推进刷新")
	for id in hero.weapons:
		_button("equip_" + id, ("已装备 · " if hero.weapon == id else "装备 · ") + Weapons.ENTRIES[id].name, "已经装备" if hero.weapon == id else "", _equip.bind(id))
	_text("护甲装备 · 当前防御 AC %d，包含护甲加值 +%d" % [hero.ac, Armors.bonus(hero)])
	for id in hero.armors:
		_button("armor_" + id, ("已装备 · " if hero.armor == id else "装备 · ") + Armors.ENTRIES[id].name, "已经装备" if hero.armor == id else "", _equip_armor.bind(id))
	feedback.text = "奥术飞弹和药水不受武器加成。贡献待同步可在眷族菜单重试。"

func _craft(id: String) -> void:
	flow.city_service({"iron_sword": "forge", "tempered_sword": "forge_tempered", "iron_armor": "forge_armor"}[id])
	_refresh()
	feedback.text = flow.run.message
	changed.emit()

func _equip(id: String) -> void:
	flow.equip_weapon(id)
	_refresh()
	feedback.text = flow.run.message
	changed.emit()

func _equip_armor(id: String) -> void:
	flow.equip_armor(id)
	_refresh()
	feedback.text = flow.run.message
	changed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()

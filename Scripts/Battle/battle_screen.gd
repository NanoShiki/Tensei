extends Control

const BattleState = preload("res://Scripts/Battle/battle_state.gd")
const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
const Combatant = preload("res://Scripts/Battle/combatant.gd")
const EnemyLibrary = preload("res://Scripts/Battle/enemy_library.gd")

const INK := Color("172027")
const PAPER := Color("f4eddd")
const GOLD := Color("d8b77d")
const ALLY := Color("7ec8a3")
const ENEMY := Color("d47b7b")
const SP_COLOR := Color("d8b77d")
const MP_COLOR := Color("7aa7d4")
const BAR_BG := Color("0c1116")

var battle: RefCounted
var timeline_row: HBoxContainer
var field_row: HBoxContainer
var card_grid: GridContainer
var resource_box: VBoxContainer
var log_label: Label
var hint_label: Label
var result_panel: PanelContainer
var result_label: Label
var selected_card_id: String = ""

var _logs: PackedStringArray = PackedStringArray()
var _unit_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_start_battle()


func try_play(card_id: String, target: RefCounted = null) -> bool:
	var actor: RefCounted = battle.current_actor()
	if actor == null:
		return false
	if not battle.play_card(actor, card_id, target):
		return false
	selected_card_id = ""
	battle.advance_until_player_turn()
	return true


func _start_battle() -> void:
	battle = BattleState.new()
	var lorn: RefCounted = Combatant.from_character(_resolve_character(), 0)
	var wolf: RefCounted = Combatant.from_enemy(EnemyLibrary.resolve("cave_wolf"), 1)
	var colossus: RefCounted = Combatant.from_enemy(EnemyLibrary.resolve("stone_colossus"), 2)
	battle.setup([lorn], [wolf, colossus])
	battle.state_changed.connect(_refresh)
	battle.log_appended.connect(_append_log)
	battle.battle_finished.connect(_on_finished)
	battle.advance_until_player_turn()
	_refresh()


func _resolve_character() -> Dictionary:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null and not flow.active_character.is_empty():
		return flow.active_character.duplicate(true)
	return CharacterLibrary.resolve()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = INK
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	timeline_row = HBoxContainer.new()
	timeline_row.add_theme_constant_override("separation", 8)
	timeline_row.custom_minimum_size.y = 64
	root.add_child(timeline_row)

	field_row = HBoxContainer.new()
	field_row.add_theme_constant_override("separation", 24)
	field_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(field_row)

	hint_label = _label("", 14, Color(PAPER, 0.7))
	root.add_child(hint_label)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	bottom.custom_minimum_size.y = 236
	root.add_child(bottom)

	resource_box = VBoxContainer.new()
	resource_box.custom_minimum_size.x = 200
	resource_box.add_theme_constant_override("separation", 8)
	bottom.add_child(_framed(resource_box, Color(PAPER, 0.12)))

	card_grid = GridContainer.new()
	card_grid.columns = 4
	card_grid.add_theme_constant_override("h_separation", 8)
	card_grid.add_theme_constant_override("v_separation", 8)
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(card_grid)

	log_label = _label("", 13, Color(PAPER, 0.78))
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var log_box := VBoxContainer.new()
	log_box.custom_minimum_size.x = 248
	log_box.add_child(_label("战斗记录", 14, GOLD))
	log_box.add_child(log_label)
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(_framed(log_box, Color(PAPER, 0.12)))

	_build_result_overlay()


func _build_result_overlay() -> void:
	result_panel = PanelContainer.new()
	result_panel.visible = false
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(0, 0, 0, 0.62)
	result_panel.add_theme_stylebox_override("panel", shade)
	add_child(result_panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size.x = 360
	center.add_child(_framed(box, GOLD))
	result_label = _label("", 28, GOLD)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(result_label)
	var back := Button.new()
	back.text = "返回主菜单"
	back.pressed.connect(_return_to_menu)
	box.add_child(back)


func _framed(inner: Control, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("141b21")
	style.border_color = border
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(inner)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return panel


func _label(text: String, font_size: int, color: Color = PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _bar(value: int, maximum: int, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxi(maximum, 1)
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill
	fill_style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill_style)
	var bg := StyleBoxFlat.new()
	bg.bg_color = BAR_BG
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	return bar


func _refresh() -> void:
	_refresh_timeline()
	_refresh_field()
	_refresh_resources()
	_refresh_cards()
	var actor: RefCounted = battle.current_actor()
	if selected_card_id != "" and battle.outcome == "ongoing":
		hint_label.text = "已选择卡牌，点击敌方单位确认目标。"
	elif actor != null and actor.team == "ally":
		hint_label.text = "选择一张卡牌。普通攻击与防御不消耗体力。"
	else:
		hint_label.text = ""


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _refresh_timeline() -> void:
	_clear(timeline_row)
	var first := true
	for item in battle.preview(6):
		var actor: RefCounted = item["actor"]
		var chip := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("2a2418") if first else Color("1c262d")
		style.border_color = GOLD if first else (ALLY if actor.team == "ally" else ENEMY)
		style.set_border_width_all(2 if first else 1)
		style.set_content_margin_all(8)
		chip.add_theme_stylebox_override("panel", style)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		var title: String = str(actor.display_name)
		if first:
			title = "当前  ·  " + title
			first = false
		var name_label := _label(title, 16, PAPER if actor.team == "ally" else ENEMY)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(name_label)
		if item["is_charging"]:
			var mark := _label("蓄力", 12, GOLD)
			mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(mark)
		chip.add_child(column)
		timeline_row.add_child(chip)


func _refresh_field() -> void:
	_clear(field_row)
	_unit_buttons.clear()
	var allies := VBoxContainer.new()
	allies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	allies.alignment = BoxContainer.ALIGNMENT_CENTER
	for unit in battle.allies:
		allies.add_child(_unit_card(unit, false))
	var enemies := HBoxContainer.new()
	enemies.add_theme_constant_override("separation", 12)
	enemies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemies.alignment = BoxContainer.ALIGNMENT_CENTER
	for unit in battle.enemies:
		enemies.add_child(_unit_card(unit, true))
	field_row.add_child(allies)
	field_row.add_child(enemies)


func _unit_card(unit: RefCounted, targetable: bool) -> Control:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(220, 132)
	button.disabled = not unit.is_alive()
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a2228")
	style.border_color = ENEMY if unit.team == "enemy" else ALLY
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.border_color = GOLD
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	var disabled := style.duplicate()
	disabled.bg_color = Color("11161a")
	disabled.border_color = Color(PAPER, 0.2)
	button.add_theme_stylebox_override("disabled", disabled)
	if targetable and unit.is_alive():
		button.pressed.connect(_on_target_pressed.bind(unit))
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(center)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.custom_minimum_size.x = 180
	center.add_child(body)
	var name_color := Color(PAPER, 0.45) if not unit.is_alive() else (ENEMY if unit.team == "enemy" else PAPER)
	body.add_child(_label(unit.display_name, 20, name_color))
	body.add_child(_bar(unit.hp, unit.max_hp, ENEMY if unit.team == "enemy" else ALLY))
	body.add_child(_label("%d / %d" % [unit.hp, unit.max_hp], 14, Color(PAPER, 0.75)))
	var status := []
	if unit.guard_ratio < 1.0:
		status.append("防御")
	if not unit.pending_card.is_empty():
		status.append("蓄力")
	if not unit.is_alive():
		status.append("失去战斗力")
	body.add_child(_label("  ·  ".join(status), 13, GOLD))
	_unit_buttons[unit] = button
	return button


func _refresh_resources() -> void:
	_clear(resource_box)
	var lorn: RefCounted = battle.allies[0]
	resource_box.add_child(_label("资源", 16, GOLD))
	_add_resource_row("生命", lorn.hp, lorn.max_hp, ALLY)
	_add_resource_row("体力", lorn.sp, lorn.max_sp, SP_COLOR)
	_add_resource_row("魔力", lorn.mp, lorn.max_mp, MP_COLOR)
	if lorn.is_fatigued():
		resource_box.add_child(_label("疲劳  ·  行动变慢", 14, GOLD))


func _add_resource_row(title: String, value: int, maximum: int, fill: Color) -> void:
	resource_box.add_child(_label("%s  %d / %d" % [title, value, maximum], 14))
	resource_box.add_child(_bar(value, maximum, fill))


func _refresh_cards() -> void:
	_clear(card_grid)
	var actor: RefCounted = battle.current_actor()
	if actor == null or actor.team != "ally":
		actor = battle.allies[0]
	var ended: bool = battle.outcome != "ongoing"
	for card in battle.available_cards(actor):
		card_grid.add_child(_card_button(card, ended or actor != battle.current_actor()))


func _card_button(card: Dictionary, force_disabled: bool) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 96)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var playable: bool = card["can_play"] and not force_disabled
	button.disabled = not playable
	button.tooltip_text = str(card.get("reason", ""))
	var selected: bool = selected_card_id == str(card["card_id"])
	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(card["display_name"]))
	var cost := "体 %d" % int(card.get("sp_cost", 0))
	if int(card.get("mp_cost", 0)) > 0:
		cost += "  魔 %d" % int(card.get("mp_cost", 0))
	cost += "  时 %d" % int(card.get("time_cost", 0))
	if card.has("uses"):
		cost += "  剩 %d" % int(card.get("remaining", 0))
	lines.append(cost)
	if not card["can_play"]:
		lines.append(str(card.get("reason", "")))
	button.text = "\n".join(lines)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("3a3120") if selected else Color("24303a")
	style.border_color = GOLD if selected else Color(PAPER, 0.18)
	style.set_border_width_all(2 if selected else 1)
	style.set_content_margin_all(10)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.border_color = GOLD
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	var disabled := style.duplicate()
	disabled.bg_color = Color("12181c")
	disabled.border_color = Color(PAPER, 0.08)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_disabled_color", Color(PAPER, 0.38))
	button.add_theme_font_size_override("font_size", 14)
	if playable:
		button.pressed.connect(_on_card_pressed.bind(str(card["card_id"]), str(card["target"])))
	return button


func _on_card_pressed(card_id: String, target_kind: String) -> void:
	if target_kind == "self" or target_kind == "enemy_all":
		try_play(card_id)
		return
	selected_card_id = card_id
	_refresh()


func _on_target_pressed(target: RefCounted) -> void:
	if selected_card_id == "":
		return
	try_play(selected_card_id, target)


func _append_log(text: String) -> void:
	_logs.append(text)
	if _logs.size() > 12:
		_logs = _logs.slice(_logs.size() - 12)
	log_label.text = "\n".join(_logs)


func _on_finished(outcome: String) -> void:
	_persist_character()
	result_label.text = "胜利" if outcome == "victory" else "战败"
	result_panel.visible = true
	_refresh()


func _persist_character() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null or battle.allies.is_empty():
		return
	var lorn: RefCounted = battle.allies[0]
	flow.active_character["hp"] = lorn.hp
	flow.active_character["sp"] = lorn.sp
	flow.active_character["mp"] = lorn.mp
	flow.active_character["card_uses"] = lorn.card_uses.duplicate(true)


func _return_to_menu() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.return_to_menu()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_or_leave()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel_or_leave()
		get_viewport().set_input_as_handled()


func _cancel_or_leave() -> void:
	if selected_card_id != "":
		selected_card_id = ""
		_refresh()
		return
	_return_to_menu()

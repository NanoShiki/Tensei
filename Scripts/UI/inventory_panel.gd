extends Window

signal changed
const Characters = preload("res://Scripts/Character/character_library.gd")
const Abilities = preload("res://Scripts/Battle/ability_library.gd")
const Log = preload("res://Scripts/Core/game_log.gd")
var run: RefCounted
var details: Label
var feedback: Label
var use_button: Button

func open(expedition: RefCounted) -> void:
	run = expedition
	title = "随身背包"
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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	details = Label.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_font_size_override("font_size", 18)
	scroll.add_child(details)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	use_button = Button.new()
	use_button.custom_minimum_size.y = 42
	use_button.pressed.connect(_use)
	box.add_child(use_button)
	var close := Button.new()
	close.text = "关闭 · B / Esc"
	close.custom_minimum_size.y = 38
	close.pressed.connect(queue_free)
	box.add_child(close)
	_refresh()
	popup_centered(Vector2i(660, 470))
	close.grab_focus()
	Log.event("inventory", "open", run.log_state())

func _refresh() -> void:
	var hero: Dictionary = run.character
	details.text = "等级 %d · 经验 %d\n生命  %d / %d\n\n装备  %s（已装备）\n剑技伤害加成 +%d · 布衣\n\n金币  %d\n铁片  %d · 用于城市打造\n\n治疗药水  ×%d · 恢复 %d 生命\n灼烧药水  ×%d · 战斗中对敌造成 %d 伤害／可消耗 1 瓶掩护绕行" % [hero.level, hero.experience, hero.hp, hero.max_hp, Characters.weapon_name(hero), Characters.weapon_bonus(hero), hero.gold, hero.scrap, hero.potions, Abilities.ENTRIES.potion.amount, hero.fire_potions, Abilities.ENTRIES.fire_potion.amount]
	var reason: String = run.potion_reason()
	use_button.text = "使用治疗药水 · 恢复 %d 生命" % mini(int(Abilities.ENTRIES.potion.amount), hero.max_hp - hero.hp)
	use_button.disabled = not reason.is_empty()
	use_button.tooltip_text = reason if not reason.is_empty() else "消耗 1 瓶，不推进移动与刷新步数。"
	feedback.text = reason if not reason.is_empty() else "探索用药不计移动步数；进度仍需手动保存。"

func _use() -> void:
	if run.use_field_potion():
		_refresh()
		feedback.text = run.message
		changed.emit()
	else: _refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_B, KEY_ESCAPE]:
		set_input_as_handled()
		queue_free()

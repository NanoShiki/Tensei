extends RefCounted

signal state_changed
signal log_appended(text: String)
signal battle_finished(outcome: String)

const CardLibrary = preload("res://Scripts/Battle/card_library.gd")
const Timeline = preload("res://Scripts/Battle/timeline.gd")

var outcome: String = "ongoing"
var allies: Array = []
var enemies: Array = []

var _timeline: RefCounted
var _rng := RandomNumberGenerator.new()


func setup(next_allies: Array, next_enemies: Array) -> void:
	allies = next_allies.duplicate()
	enemies = next_enemies.duplicate()
	_timeline = Timeline.new()
	var actors: Array = []
	actors.append_array(allies)
	actors.append_array(enemies)
	_timeline.setup(actors)
	outcome = "ongoing"
	state_changed.emit()


func current_actor() -> RefCounted:
	if outcome != "ongoing":
		return null
	return _timeline.next_actor()


func available_cards(actor: RefCounted) -> Array:
	var entries: Array = []
	if actor == null:
		return entries
	for card_id in actor.card_ids:
		var card := CardLibrary.resolve(card_id)
		var entry := card.duplicate(true)
		var check := _card_playable(actor, card)
		entry["can_play"] = check["ok"]
		entry["reason"] = check["reason"]
		if card.has("uses"):
			entry["remaining"] = int(actor.card_uses.get(card_id, 0))
		entries.append(entry)
	return entries


func play_card(actor: RefCounted, card_id: String, target: RefCounted = null) -> bool:
	if outcome != "ongoing":
		return false
	if _timeline.next_actor() != actor:
		return false
	var card := CardLibrary.resolve(card_id)
	if card.is_empty():
		return false
	var check := _card_playable(actor, card)
	if not check["ok"]:
		return false
	if not _validate_target(actor, card, target):
		return false
	_begin_action(actor)
	actor.pay(card)
	_apply_card_effects(actor, card, target)
	log_appended.emit("%s 使用了 %s" % [actor.display_name, card.get("display_name", card_id)])
	_timeline.advance(actor, int(card.get("time_cost", 0)))
	_cleanup_dead_units()
	_update_outcome()
	state_changed.emit()
	return true


func advance_until_player_turn() -> void:
	while outcome == "ongoing":
		var actor: RefCounted = _timeline.next_actor()
		if actor == null:
			break
		if actor.team == "ally":
			break
		_execute_enemy_turn(actor)
	state_changed.emit()


func preview(count: int) -> Array:
	return _timeline.preview(count)


func _card_playable(actor: RefCounted, card: Dictionary) -> Dictionary:
	if actor.can_pay(card):
		return {"ok": true, "reason": ""}
	var reason := "无法使用"
	if card.has("uses") and int(actor.card_uses.get(card.get("card_id", ""), 0)) <= 0:
		reason = "次数已用尽"
	elif int(card.get("sp_cost", 0)) > actor.sp:
		reason = "体力不足"
	elif int(card.get("mp_cost", 0)) > actor.mp:
		reason = "魔力不足"
	return {"ok": false, "reason": reason}


func _begin_action(actor: RefCounted) -> void:
	actor.guard_ratio = 1.0


func _validate_target(actor: RefCounted, card: Dictionary, target: RefCounted) -> bool:
	match str(card.get("target", "")):
		"self":
			return true
		"enemy_single":
			return target != null and target.is_alive() and target.team != actor.team
		"enemy_all":
			return true
	return false


func _effect_target(actor: RefCounted, card: Dictionary, target: RefCounted) -> RefCounted:
	if str(card.get("target", "")) == "self":
		return actor if target == null else target
	return target


func _opposing_units(actor: RefCounted) -> Array:
	return enemies if actor.team == "ally" else allies


func _apply_card_effects(actor: RefCounted, card: Dictionary, target: RefCounted) -> void:
	var resolved := _effect_target(actor, card, target)
	for effect in card.get("effects", []):
		match str(effect.get("type", "")):
			"damage":
				_apply_damage(actor, card, resolved, int(effect.get("amount", 0)))
			"heal":
				if resolved != null:
					var healed: int = resolved.heal(int(effect.get("amount", 0)))
					log_appended.emit("%s 恢复了 %d 点生命" % [resolved.display_name, healed])
			"restore_sp":
				if resolved != null:
					var restored: int = resolved.restore_sp(int(effect.get("amount", 0)))
					log_appended.emit("%s 恢复了 %d 点体力" % [resolved.display_name, restored])
			"restore_mp":
				if resolved != null:
					var restored: int = resolved.restore_mp(int(effect.get("amount", 0)))
					log_appended.emit("%s 恢复了 %d 点魔力" % [resolved.display_name, restored])
			"guard":
				if resolved != null:
					resolved.guard_ratio = float(effect.get("ratio", 1.0))
			"delay":
				if resolved != null:
					resolved.next_act += float(effect.get("amount", 0))
					if not resolved.pending_card.is_empty():
						resolved.pending_card = {}
						log_appended.emit("%s 的蓄力被打断" % resolved.display_name)


func _apply_damage(actor: RefCounted, card: Dictionary, target: RefCounted, amount: int) -> void:
	match str(card.get("target", "")):
		"enemy_single":
			if target != null:
				var dealt: int = target.take_damage(amount)
				log_appended.emit("%s 受到 %d 点伤害" % [target.display_name, dealt])
		"enemy_all":
			for unit in _opposing_units(actor):
				if unit.is_alive():
					var dealt: int = unit.take_damage(amount)
					log_appended.emit("%s 受到 %d 点伤害" % [unit.display_name, dealt])


func _execute_enemy_turn(actor: RefCounted) -> void:
	_begin_action(actor)
	if not actor.pending_card.is_empty():
		var card: Dictionary = actor.pending_card.duplicate(true)
		actor.pending_card = {}
		_apply_card_effects(actor, card, null)
		log_appended.emit("%s 释放了 %s" % [actor.display_name, card.get("display_name", "")])
		_timeline.advance(actor, actor.recovery_time_cost())
	elif actor.charge_card_id != "":
		var card := CardLibrary.resolve(actor.charge_card_id)
		actor.pending_card = card.duplicate(true)
		log_appended.emit("%s 开始蓄力 %s" % [actor.display_name, card.get("display_name", "")])
		_timeline.advance(actor, int(card.get("time_cost", 0)))
	else:
		var card_id: String = actor.default_attack_card_id()
		var card := CardLibrary.resolve(card_id)
		var target := _random_alive_ally()
		if target != null:
			_apply_card_effects(actor, card, target)
			log_appended.emit("%s 使用了 %s" % [actor.display_name, card.get("display_name", card_id)])
		_timeline.advance(actor, int(card.get("time_cost", 0)))
	_cleanup_dead_units()
	_update_outcome()


func _random_alive_ally() -> RefCounted:
	var alive: Array = []
	for ally in allies:
		if ally.is_alive():
			alive.append(ally)
	if alive.is_empty():
		return null
	return alive[_rng.randi_range(0, alive.size() - 1)]


func _cleanup_dead_units() -> void:
	for unit in allies + enemies:
		if not unit.is_alive():
			_timeline.remove(unit)


func _update_outcome() -> void:
	if outcome != "ongoing":
		return
	if not _any_alive(enemies):
		outcome = "victory"
		battle_finished.emit(outcome)
		return
	if not _any_alive(allies):
		outcome = "defeat"
		battle_finished.emit(outcome)


func _any_alive(units: Array) -> bool:
	for unit in units:
		if unit.is_alive():
			return true
	return false

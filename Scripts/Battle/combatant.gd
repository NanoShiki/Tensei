extends RefCounted

const CardLibrary = preload("res://Scripts/Battle/card_library.gd")
const FALLBACK_ACTIONS := ["basic_strike", "guard"]

var id: String = ""
var display_name: String = ""
var team: String = ""
var max_hp: int = 0
var hp: int = 0
var max_sp: int = 0
var sp: int = 0
var max_mp: int = 0
var mp: int = 0
var speed: int = 100
var row: String = "front"
var card_ids: Array = []
var card_uses: Dictionary = {}
var charge_card_id: String = ""
var guard_ratio: float = 1.0
var next_act: float = 0.0
var pending_card: Dictionary = {}
var join_order: int = 0


static func from_character(definition: Dictionary, order: int = 0) -> RefCounted:
	var unit: RefCounted = load("res://Scripts/Battle/combatant.gd").new()
	unit._apply_definition(definition, "ally", order)
	unit.id = str(definition.get("character_id", definition.get("id", "")))
	return unit


static func from_enemy(definition: Dictionary, order: int = 0) -> RefCounted:
	var unit: RefCounted = load("res://Scripts/Battle/combatant.gd").new()
	unit._apply_definition(definition, "enemy", order)
	unit.id = str(definition.get("enemy_id", definition.get("id", "")))
	unit.charge_card_id = str(definition.get("charge_card_id", ""))
	return unit


func _apply_definition(definition: Dictionary, next_team: String, order: int) -> void:
	display_name = str(definition.get("display_name", ""))
	team = next_team
	max_hp = int(definition.get("max_hp", 1))
	hp = int(definition.get("hp", max_hp))
	max_sp = int(definition.get("max_sp", 0))
	sp = int(definition.get("sp", max_sp))
	max_mp = int(definition.get("max_mp", 0))
	mp = int(definition.get("mp", max_mp))
	speed = int(definition.get("speed", 100))
	row = str(definition.get("row", "front"))
	card_ids = definition.get("card_ids", []).duplicate()
	join_order = order
	_init_supply_uses()
	if definition.has("card_uses"):
		card_uses = definition["card_uses"].duplicate(true)


func _init_supply_uses() -> void:
	for card_id in card_ids:
		var card := CardLibrary.resolve(card_id)
		if card.has("uses"):
			card_uses[card_id] = int(card["uses"])


func is_alive() -> bool:
	return hp > 0


func is_fatigued() -> bool:
	return max_sp > 0 and sp < int(max_sp * 0.2)


func fatigue_multiplier() -> float:
	return 1.25 if is_fatigued() else 1.0


func can_pay(card: Dictionary) -> bool:
	var card_id := str(card.get("card_id", ""))
	if card_id in FALLBACK_ACTIONS:
		return true
	if int(card.get("sp_cost", 0)) > sp:
		return false
	if int(card.get("mp_cost", 0)) > mp:
		return false
	if card.has("uses"):
		return int(card_uses.get(card_id, 0)) > 0
	return true


func pay(card: Dictionary) -> void:
	var card_id := str(card.get("card_id", ""))
	if card_id in FALLBACK_ACTIONS:
		return
	sp -= int(card.get("sp_cost", 0))
	mp -= int(card.get("mp_cost", 0))
	if card.has("uses"):
		card_uses[card_id] = int(card_uses.get(card_id, 0)) - 1


func take_damage(amount: int) -> int:
	var final_amount := int(round(float(amount) * guard_ratio))
	hp = maxi(hp - final_amount, 0)
	return final_amount


func heal(amount: int) -> int:
	var before := hp
	hp = mini(hp + amount, max_hp)
	return hp - before


func restore_sp(amount: int) -> int:
	var before := sp
	sp = mini(sp + amount, max_sp)
	return sp - before


func restore_mp(amount: int) -> int:
	var before := mp
	mp = mini(mp + amount, max_mp)
	return mp - before


func default_attack_card_id() -> String:
	for card_id in card_ids:
		if card_id in FALLBACK_ACTIONS:
			continue
		return card_id
	return str(card_ids[0]) if not card_ids.is_empty() else "basic_strike"


func recovery_time_cost() -> int:
	var card := CardLibrary.resolve(default_attack_card_id())
	return int(card.get("time_cost", 60))

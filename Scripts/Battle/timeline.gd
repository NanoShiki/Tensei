extends RefCounted

const CardLibrary = preload("res://Scripts/Battle/card_library.gd")

var _actors: Array = []


func setup(actors: Array) -> void:
	_actors = actors.duplicate()


func next_actor() -> RefCounted:
	var best: RefCounted = null
	for actor in _actors:
		if not actor.is_alive():
			continue
		if best == null or _compare(actor, best) < 0:
			best = actor
	return best


func advance(actor: RefCounted, time_cost: int) -> void:
	if actor == null or not actor.is_alive():
		return
	actor.next_act += float(time_cost) * 100.0 / float(actor.speed) * actor.fatigue_multiplier()


func remove(actor: RefCounted) -> void:
	_actors.erase(actor)


func preview(count: int) -> Array:
	var snapshots := _build_snapshots()
	var results: Array = []
	for _i in count:
		var actor := _next_from_snapshots(snapshots)
		if actor == null:
			break
		var snap: Dictionary = snapshots[actor]
		var charging := _is_charging_action(actor, snap)
		results.append({
			"actor": actor,
			"next_act": snap["next_act"],
			"is_charging": charging,
		})
		_simulate_turn(actor, snap)
	return results


func _compare(a: RefCounted, b: RefCounted) -> int:
	return _compare_values(a.next_act, a.speed, a.join_order, b.next_act, b.speed, b.join_order)


func _compare_values(act_a: float, speed_a: int, order_a: int, act_b: float, speed_b: int, order_b: int) -> int:
	if act_a < act_b:
		return -1
	if act_a > act_b:
		return 1
	if speed_a > speed_b:
		return -1
	if speed_a < speed_b:
		return 1
	if order_a < order_b:
		return -1
	if order_a > order_b:
		return 1
	return 0


func _build_snapshots() -> Dictionary:
	var snapshots := {}
	for actor in _actors:
		if not actor.is_alive():
			continue
		snapshots[actor] = {
			"next_act": actor.next_act,
			"pending_card": actor.pending_card.duplicate(true),
			"sp": actor.sp,
			"max_sp": actor.max_sp,
		}
	return snapshots


func _next_from_snapshots(snapshots: Dictionary) -> RefCounted:
	var best: RefCounted = null
	for actor in snapshots.keys():
		var snap: Dictionary = snapshots[actor]
		if best == null or _compare_values(snap["next_act"], actor.speed, actor.join_order, snapshots[best]["next_act"], best.speed, best.join_order) < 0:
			best = actor
	return best


func _is_charging_action(actor: RefCounted, snap: Dictionary) -> bool:
	if not snap["pending_card"].is_empty():
		return true
	return actor.team == "enemy" and actor.charge_card_id != "" and snap["pending_card"].is_empty()


func _simulate_turn(actor: RefCounted, snap: Dictionary) -> void:
	var time_cost := 0
	if not snap["pending_card"].is_empty():
		time_cost = actor.recovery_time_cost()
		snap["pending_card"] = {}
	elif actor.team == "enemy" and actor.charge_card_id != "":
		var charge_card := CardLibrary.resolve(actor.charge_card_id)
		snap["pending_card"] = charge_card
		time_cost = int(charge_card.get("time_cost", 0))
	else:
		var card_id: String = "basic_strike" if actor.team == "ally" else actor.default_attack_card_id()
		var card := CardLibrary.resolve(card_id)
		time_cost = int(card.get("time_cost", 60))
	var fatigue := 1.25 if snap["max_sp"] > 0 and snap["sp"] < int(snap["max_sp"] * 0.2) else 1.0
	snap["next_act"] += float(time_cost) * 100.0 / float(actor.speed) * fatigue

"""Check retained JSONL gameplay logs. Exit 1 for errors/invariant violations.

Usage: python Tools/check_logs.py <logs directory or events-*.jsonl>
This checks recorded invariants, not every gameplay rule or visual behavior.
"""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

UNITS = {"lorn": "hero", "squire": "ally", "scout": "scout", "goblin": "enemy"}
GUARDS = {"lorn": "guarding", "squire": "ally_guarding", "scout": "scout_guarding"}


def inspect(paths):
    counts = Counter()
    sessions = defaultdict(list)
    errors = []
    for path in paths:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            try:
                row = json.loads(line)
                assert row["schema"] == 1
                assert row["level"] in ("INFO", "WARN", "ERROR")
                assert isinstance(row["sequence"], int)
                assert isinstance(row["data"], dict)
                sessions[row["session"]].append(row)
                counts[row["category"] + "." + row["event"]] += 1
            except (ValueError, KeyError, TypeError, AssertionError):
                errors.append(f"{path.name}:{number}: invalid log row")
    for session, rows in sessions.items():
        rows.sort(key=lambda r: r["sequence"])
        previous = rows[0]["sequence"] - 1
        for row in rows:
            label = f'{session} #{row["sequence"]} {row["category"]}.{row["event"]}'
            if row["sequence"] != previous + 1:
                errors.append(label + ": duplicate or missing sequence")
            previous = row["sequence"]
            if row["level"] == "ERROR":
                errors.append(label + ": " + str(row["data"].get("message", row["data"])))
            data = row["data"]
            if row["category"] == "battle" and row["event"] == "attack" and "rolls" in data:
                try:
                    rolls = data["rolls"]
                    assert all(isinstance(roll, int) and 1 <= roll <= 20 for roll in rolls), "attack dice bounds"
                    expected_mode = "advantage" if data["advantage"] and not data["guarded"] else ("disadvantage" if data["guarded"] and not data["advantage"] else "normal")
                    assert data["roll_mode"] == expected_mode, "attack advantage cancellation"
                    assert len(rolls) == (1 if expected_mode == "normal" else 2), "attack dice count"
                    assert data["roll"] == (max(rolls) if expected_mode == "advantage" else min(rolls)), "attack selected die"
                    if data["actor"] == "goblin":
                        assert data["advantage"] == (data["content_id"] == "prowler"), "enemy attack profile"
                    expected_hit = data["roll"] == 20 or (data["roll"] != 1 and data["roll"] + data["modifier"] >= data["ac"])
                    assert data["hit"] == expected_hit, "attack hit result"
                except (KeyError, TypeError, AssertionError, ValueError) as exc:
                    errors.append(label + ": " + str(exc))
            if row["category"] == "job" and row["event"] == "select":
                try:
                    before, after = data["before"], data["after"]
                    if not data["success"]:
                        assert before == after, "rejected job changed state"
                    else:
                        assert before["phase"] == "city", "job selected outside city"
                        ac, attack, dex = {"swordsman": (14, 5, 2), "mage": (12, 5, 1), "archer": (13, 6, 3), "rogue": (13, 5, 4)}[data["id"]]
                        expected = json.loads(json.dumps(before))
                        expected["hero"].update(job_id=data["id"], ac=ac, attack=attack, dex=dex)
                        expected["message"] = after["message"]
                        assert expected == after, "job selection changed unrelated progress"
                except (KeyError, TypeError, AssertionError) as exc:
                    errors.append(label + ": " + str(exc))
            if row["category"] == "familia":
                try:
                    if row["event"] == "victory_growth" and data["success"]:
                        old, new = data["before"], data["after"]
                        assert old["player_id"] == new["player_id"], "shared owner changed"
                        before, after = old["familias"]["dawn"], new["familias"]["dawn"]
                        if data["duplicate"]:
                            assert old == new and data["id"] in before["events"], "duplicate shared reward"
                        else:
                            members = data.get("members", ["squire"])
                            assert members and len(members) == len(set(members)) and all(member in ("squire", "scout") for member in members), "shared participants"
                            event = members if "scout_xp" in after else True
                            assert data["id"] not in before["events"] and after["events"].get(data["id"]) == event, "shared event ledger"
                            assert after["contribution"] == before["contribution"] + 1, "shared growth reward"
                            for member in ("squire", "scout"):
                                assert after.get(member + "_xp", 0) == before.get(member + "_xp", 0) + (2 if member in members else 0), "shared growth reward"
                            assert after["events"] == dict(before["events"], **{data["id"]: event}), "shared ledger changed history"
                    if row["event"] == "service":
                        before, after = data["before"], data["after"]
                        if not data["success"]:
                            assert before == after, "rejected familia service changed character"
                        else:
                            assert before["phase"] == "city" and before["steps"] == after["steps"] and before["respawn"] == after["respawn"], "familia service moved exploration"
                            if data["action"] == "join":
                                assert before["hero"]["familia_id"] == "" and before["hero"]["quests"]["hunt"] == "claimed", "familia qualification"
                                assert after["hero"]["familia_id"] == "dawn" and after["hero"]["player_id"] == data["shared_after"]["player_id"], "familia owner binding"
                            if data["action"] == "enlist":
                                assert after["hero"]["party_enlisted"] and after["hero"]["party_hp"] > 0, "party enlist"
                            if data["action"] == "enlist_scout":
                                assert after["hero"]["scout_enlisted"] and after["hero"]["scout_hp"] > 0 and data["shared_after"]["familias"]["dawn"]["contribution"] >= 3, "scout enlist qualification"
                            if data["action"] == "dismiss_scout":
                                assert not after["hero"]["scout_enlisted"] and after["hero"]["scout_hp"] == 0, "scout dismiss"
                            if data["action"] == "dismiss":
                                assert not after["hero"]["party_enlisted"] and after["hero"]["party_hp"] == 0, "party dismiss"
                    if row["event"] == "sync":
                        assert all(event in data["before"] for event in data["after"]), "sync invented event"
                        if data["success"]:
                            assert data["after"] == [], "successful sync still pending"
                except (KeyError, TypeError, AssertionError) as exc:
                    errors.append(label + ": " + str(exc))
            if row["category"] == "inventory" and row["event"] == "field_potion":
                try:
                    before, after = data["before"], data["after"]
                    if data["success"]:
                        assert after["hero"]["potions"] == before["hero"]["potions"] - 1, "potion stock"
                        assert after["hero"]["hp"] == min(before["hero"]["hp"] + 12, before["hero"]["max_hp"]), "field healing"
                        assert after["steps"] == before["steps"] and after["respawn"] == before["respawn"], "potion advanced exploration clock"
                    else:
                        assert before == after, "rejected potion changed state"
                except (KeyError, TypeError, AssertionError) as exc:
                    errors.append(label + ": " + str(exc))
            if row["category"] == "encounter" and row["event"] == "avoided":
                try:
                    assert data["enemy"]["enemy_active"] and data["enemy"]["visited"] and data["state"]["pending"] == "", "avoidance removed encounter"
                except (KeyError, TypeError, AssertionError) as exc:
                    errors.append(label + ": " + str(exc))
            if row["category"] == "quest":
                try:
                    before, after = data["before"], data["after"]
                    old, hero = before["hero"], after["hero"]
                    quest = data["id"]
                    if not data["success"]:
                        assert before == after, "rejected quest changed state"
                    else:
                        assert after["steps"] == before["steps"] and after["respawn"] == before["respawn"], "quest advanced exploration clock"
                        assert before["phase"] == "city", "quest outside city"
                        if row["event"] == "accept":
                            expected = json.loads(json.dumps(before))
                            assert old["quests"][quest] == "available", "quest already accepted"
                            if quest == "familia_patrol":
                                assert old["familia_id"] == "dawn" and data["guild_level"] >= 2, "member quest qualification"
                            expected["hero"]["quests"][quest] = "active"
                            expected["message"] = after.get("message")
                            assert expected == after, "accept changed resources"
                        elif row["event"] == "claim":
                            gold, xp = {"hunt": (6, 10), "materials": (8, 15), "captain": (12, 25), "familia_patrol": (10, 20)}[quest]
                            if quest == "familia_patrol":
                                assert old["familia_id"] == "dawn" and old["familia_wins"] == 5, "member quest incomplete"
                            assert old["quests"][quest] == "active" and hero["quests"][quest] == "claimed", "duplicate quest reward"
                            assert hero["gold"] == old["gold"] + gold and hero["experience"] == old["experience"] + xp, "quest reward"
                            assert hero["scrap"] == old["scrap"] - (3 if quest == "materials" else 0), "quest material cost"
                            assert hero["level"] == 1 + sum(hero["experience"] >= x for x in (10, 25, 50, 85)), "growth level"
                            assert hero["max_hp"] == 36 + 4 * (hero["level"] - 1) and hero["hp"] == old["hp"], "growth health"
                except (KeyError, TypeError, AssertionError) as exc:
                    errors.append(label + ": " + str(exc))
            if row["category"] == "battle" and "after" in data:
                try:
                    state = data["after"]
                    assert all(0 <= state[k]["hp"] <= state[k]["max_hp"] for k in ("hero", "enemy")), "battle health bounds"
                    assert state["actions"] >= 0, "negative actions"
                    for member in ("ally", "scout"):
                        if state.get(member):
                            assert 0 <= state[member]["hp"] <= state[member]["max_hp"], "ally health bounds"
                    if not data["success"]:
                        assert data["before"] == state, "rejected action changed state"
                    elif row["event"] == "use_ability":
                        old = data["before"]
                        assert old["actor"] in ("lorn", "squire", "scout") and old["actions"] > 0 and state["actions"] == old["actions"] - 1, "ability action cost"
                        ability, target = data["input"]["ability"], data["input"]["target"]
                        if ability in ("arcane_bolt", "aimed_shot", "ambush"):
                            actor = old[UNITS[old["actor"]]]
                            assert actor.get("job_id") == {"arcane_bolt": "mage", "aimed_shot": "archer", "ambush": "rogue"}[ability] and actor.get("level", 1) >= 2, "job skill qualification"
                        if ability in ("potion", "fire_potion"):
                            stock = "potions" if ability == "potion" else "fire_potions"
                            assert state["hero"][stock] == old["hero"][stock] - 1, "battle potion stock"
                            receiver = UNITS[target]
                            if ability == "potion":
                                assert old[receiver]["hp"] > 0, "healed a downed member"
                            expected_hp = min(old[receiver]["hp"] + 12, old[receiver]["max_hp"]) if ability == "potion" else max(0, old[receiver]["hp"] - 8)
                            assert state[receiver]["hp"] == expected_hp, "battle potion effect"
                        if ability == "surge":
                            actor = UNITS[old["actor"]]
                            assert state[actor]["surge"] == old[actor]["surge"] - 1 and state[actor]["hp"] == min(old[actor]["hp"] + 8, old[actor]["max_hp"]), "member surge"
                            for other in ("hero", "ally", "scout"):
                                if other != actor and old.get(other):
                                    assert state[other]["surge"] == old[other]["surge"] and state[other]["hp"] == old[other]["hp"], "surge changed another member"
                        if ability == "guard":
                            assert state[GUARDS[old["actor"]]], "member guard"
                            for member, flag in GUARDS.items():
                                if member != old["actor"]:
                                    assert state.get(flag, False) == old.get(flag, False), "guard changed another member"
                except (KeyError, TypeError, AssertionError) as exc:
                    errors.append(label + ": " + str(exc))
            if row["category"] != "exploration" or not data.get("success"):
                continue
            try:
                before, after = data["before"], data["after"]
                action = row["event"]
                hero = after["hero"]
                assert 0 <= hero["hp"] <= hero["max_hp"], "health bounds"
                assert all(hero[k] >= 0 for k in ("gold", "scrap", "potions", "fire_potions")), "negative resources"
                if action in ("enter", "step_return", "descend_floor"):
                    assert after["steps"] == before["steps"] + 1, "movement must cost one step"
                    for key, timer in before["respawn"].items():
                        new = after["respawn"][key]
                        assert new["remaining"] == max(0, timer["remaining"] - (not timer["active"])), "respawn countdown"
                if action in ("enter", "step_return") and data.get("input", {}).get("avoid"):
                    old = before["hero"]
                    assert hero["fire_potions"] == old["fire_potions"] - 1, "avoidance potion cost"
                    expected_hero = dict(old, fire_potions=old["fire_potions"] - 1)
                    assert hero == expected_hero, "avoidance changed other character progress"
                    assert after["pending"] == "" and after["wins"] == before["wins"], "avoidance counted as victory"
                    assert hero["hp"] == old["hp"] and hero["gold"] == old["gold"] and hero["scrap"] == old["scrap"], "avoidance awarded loot or damaged hero"
                    assert hero.get("captain_defeated") == old.get("captain_defeated"), "avoidance completed captain"
                if action == "finish_battle" and data["input"]["victory"]:
                    assert after["wins"] == before["wins"] + 1, "victory counted once"
                    source = data["input"]["hero"]
                    assert hero["gold"] == source["gold"] + 3 and hero["scrap"] == source["scrap"] + 1, "victory reward"
                    qualifies = data["input"].get("with_party", False) and (source.get("party_enlisted") or source.get("scout_enlisted")) and source.get("familia_id") == "dawn" and source["quests"].get("familia_patrol") == "active"
                    assert hero.get("familia_wins", 0) == min(5, source.get("familia_wins", 0) + bool(qualifies)), "member victory progress"
                if action == "city_service":
                    old = before["hero"]
                    service = data["input"]["action"]
                    if service == "rest":
                        assert hero["hp"] == hero["max_hp"] and hero["gold"] == old["gold"], "free rest"
                        if old.get("party_enlisted"):
                            assert hero["party_hp"] == data["input"]["companion_max_hp"], "party rest"
                        if old.get("scout_enlisted"):
                            assert hero["scout_hp"] == data["input"]["scout_max_hp"], "scout rest"
                    if service == "potion":
                        assert hero["gold"] == old["gold"] - 3 and hero["potions"] == old["potions"] + 1, "potion transaction"
                    if service == "fire_potion":
                        assert hero["gold"] == old["gold"] - 4 and hero["fire_potions"] == old["fire_potions"] + 1, "fire potion transaction"
                    if service == "forge":
                        assert hero["gold"] == old["gold"] - 6 and hero["scrap"] == old["scrap"] - 3 and hero["weapon"] == "iron_sword", "forge transaction"
                if action == "depart_city":
                    assert before["hero"] == hero and after["steps"] == 0 and after["run_id"] != before["run_id"], "new expedition continuity"
            except (KeyError, TypeError, AssertionError) as exc:
                errors.append(label + ": " + str(exc))
    return counts, errors, sessions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    paths = sorted(args.path.glob("events-*.jsonl")) if args.path.is_dir() else [args.path]
    if not paths:
        parser.error("No event logs found")
    counts, errors, sessions = inspect(paths)
    print(json.dumps({"events": dict(counts), "sessions": len(sessions), "errors": errors,
        "incomplete_sessions": [key for key, rows in sessions.items()
            if not any(r["category"] == "session" and r["event"] == "end" for r in rows)],
        "scope": "Retained events only; also inspect godot.log and verify UI manually."}, ensure_ascii=False, indent=2))
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())

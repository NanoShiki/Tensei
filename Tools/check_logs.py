"""Check retained JSONL gameplay logs. Exit 1 for errors/invariant violations.

Usage: python Tools/check_logs.py <logs directory or events-*.jsonl>
This checks recorded invariants, not every gameplay rule or visual behavior.
"""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path


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
                            expected["hero"]["quests"][quest] = "active"
                            expected["message"] = after.get("message")
                            assert expected == after, "accept changed resources"
                        elif row["event"] == "claim":
                            gold, xp = {"hunt": (6, 10), "materials": (8, 15), "captain": (12, 25)}[quest]
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
                    if state.get("ally"):
                        assert 0 <= state["ally"]["hp"] <= state["ally"]["max_hp"], "ally health bounds"
                    if not data["success"]:
                        assert data["before"] == state, "rejected action changed state"
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
                if action == "finish_battle" and data["input"]["victory"]:
                    assert after["wins"] == before["wins"] + 1, "victory counted once"
                    source = data["input"]["hero"]
                    assert hero["gold"] == source["gold"] + 3 and hero["scrap"] == source["scrap"] + 1, "victory reward"
                if action == "city_service":
                    old = before["hero"]
                    service = data["input"]["action"]
                    if service == "rest":
                        assert hero["hp"] == hero["max_hp"] and hero["gold"] == old["gold"], "free rest"
                    if service == "potion":
                        assert hero["gold"] == old["gold"] - 3 and hero["potions"] == old["potions"] + 1, "potion transaction"
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

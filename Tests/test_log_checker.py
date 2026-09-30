import json
from pathlib import Path
import runpy
import tempfile
import unittest

inspect = runpy.run_path(str(Path(__file__).resolve().parents[1] / "Tools/check_logs.py"))["inspect"]


class LogCheckerTests(unittest.TestCase):
    def test_field_potion_does_not_advance_clock(self):
        before = {"steps": 3, "respawn": {}, "hero": {"hp": 20, "max_hp": 36, "potions": 2}}
        after = {"steps": 3, "respawn": {}, "hero": {"hp": 32, "max_hp": 36, "potions": 1}}
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO",
               "category": "inventory", "event": "field_potion",
               "data": {"success": True, "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["steps"] = 4
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("potion advanced exploration clock", inspect([path])[1][0])

    def test_avoidance_keeps_loot_and_victory_unchanged(self):
        before = {"steps": 0, "respawn": {}, "wins": 0, "hero": {"hp": 20, "max_hp": 36,
            "gold": 0, "scrap": 0, "potions": 3, "fire_potions": 2}}
        after = json.loads(json.dumps(before))
        after.update(steps=1, pending="")
        after["hero"]["fire_potions"] = 1
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "exploration",
               "event": "enter", "data": {"input": {"avoid": True}, "success": True, "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["hero"]["gold"] = 3
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("avoidance changed other character progress", inspect([path])[1][0])

    def test_quest_rewards_cannot_repeat(self):
        before = {"steps": 0, "respawn": {}, "phase": "city", "hero": {"gold": 0, "scrap": 3,
            "hp": 30, "max_hp": 36, "level": 1, "experience": 0, "quests": {"hunt": "active"}}}
        after = json.loads(json.dumps(before))
        after["hero"].update(gold=6, experience=10, level=2, max_hp=40, quests={"hunt": "claimed"})
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "quest",
               "event": "claim", "data": {"id": "hunt", "success": True, "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            before["hero"]["quests"]["hunt"] = "claimed"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("duplicate quest reward", inspect([path])[1][0])

    def test_ally_healing_requires_an_action_and_shared_potion(self):
        before = {"actor": "lorn", "actions": 1, "hero": {"hp": 36, "max_hp": 36, "potions": 3},
            "ally": {"hp": 10, "max_hp": 28}, "enemy": {"hp": 22, "max_hp": 22}}
        after = json.loads(json.dumps(before))
        after["actions"] = 0
        after["hero"]["potions"] = 2
        after["ally"]["hp"] = 22
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "battle",
               "event": "use_ability", "data": {"input": {"ability": "potion", "target": "squire"}, "success": True, "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["actions"] = 1
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("ability action cost", inspect([path])[1][0])

    def test_detects_movement_violation_and_error(self):
        before = {"steps": 0, "respawn": {}}
        after = {"steps": 1, "hero": {"hp": 20, "max_hp": 36, "gold": 0,
                 "scrap": 0, "potions": 3, "fire_potions": 2}}
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO",
               "category": "exploration", "event": "enter",
               "data": {"success": True, "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["steps"] = 2
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("movement must cost one step", inspect([path])[1][0])
            row["level"] = "ERROR"
            path.write_text(json.dumps(row) + "\n{broken", encoding="utf-8")
            self.assertEqual(len(inspect([path])[1]), 3)

    def test_healing_cannot_revive_and_guard_cannot_affect_partner(self):
        before = {"actor": "lorn", "actions": 1, "guarding": False, "ally_guarding": False,
            "hero": {"hp": 30, "max_hp": 36, "potions": 3, "surge": 1},
            "ally": {"hp": 0, "max_hp": 28, "surge": 1}, "enemy": {"hp": 22, "max_hp": 22}}
        after = json.loads(json.dumps(before))
        after["actions"] = 0
        after["hero"]["potions"] = 2
        after["ally"]["hp"] = 12
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "battle",
               "event": "use_ability", "data": {"input": {"ability": "potion", "target": "squire"}, "success": True, "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("healed a downed member", inspect([path])[1][0])
            after = json.loads(json.dumps(before))
            after.update(actions=0, guarding=True)
            row["data"].update(input={"ability": "guard", "target": "lorn"}, after=after)
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["ally_guarding"] = True
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("guard changed another member", inspect([path])[1][0])
            after = json.loads(json.dumps(before))
            after["actions"] = 0
            after["hero"].update(hp=36, surge=0)
            row["data"].update(input={"ability": "surge", "target": "lorn"}, after=after)
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["ally"]["surge"] = 0
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("surge changed another member", inspect([path])[1][0])

    def test_shared_growth_is_idempotent(self):
        before = {"player_id": "test", "familias": {"dawn": {"contribution": 0, "squire_xp": 0, "events": {}}}}
        after = {"player_id": "test", "familias": {"dawn": {"contribution": 1, "squire_xp": 2, "events": {"clear": True}}}}
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "familia",
            "event": "victory_growth", "data": {"id": "clear", "success": True, "duplicate": False, "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            row["data"].update(before=after, duplicate=True)
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            row["data"]["after"] = json.loads(json.dumps(after))
            row["data"]["after"]["familias"]["dawn"]["squire_xp"] += 2
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("duplicate shared reward", inspect([path])[1][0])


if __name__ == "__main__":
    unittest.main()

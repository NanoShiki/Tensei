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
            self.assertIn("avoidance awarded loot", inspect([path])[1][0])

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


if __name__ == "__main__":
    unittest.main()

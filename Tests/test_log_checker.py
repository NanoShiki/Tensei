import json
from pathlib import Path
import runpy
import tempfile
import unittest

inspect = runpy.run_path(str(Path(__file__).resolve().parents[1] / "Tools/check_logs.py"))["inspect"]


class LogCheckerTests(unittest.TestCase):
    def test_station_heals_living_members_without_advancing_clock(self):
        old = {"phase": "descending", "floor": 5, "node": "entry", "pending": "", "steps": 17, "respawn": {"a": 2}, "message": "old",
            "hero": {"hp": 5, "max_hp": 36, "party_enlisted": True, "party_hp": 0, "scout_enlisted": True, "scout_hp": 5, "gold": 8}}
        new = json.loads(json.dumps(old))
        new["hero"].update(hp=17, scout_hp=17, gold=0)
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "station", "event": "service",
            "data": {"action": "rest", "success": True, "companion_max_hp": 28, "scout_max_hp": 22, "before": old, "after": new}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            new["hero"]["party_hp"] = 12
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("station changed unrelated progress or revived member", inspect([path])[1][0])

    def test_equipment_switch_preserves_resources_and_clock(self):
        old = {"phase": "city", "pending": "", "steps": 7, "respawn": {"a": 2}, "message": "old",
            "hero": {"weapon": "iron_sword", "weapons": ["training_sword", "iron_sword"], "gold": 6}}
        new = json.loads(json.dumps(old))
        new["hero"]["weapon"] = "training_sword"
        new["message"] = "equipped"
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "inventory", "event": "equip",
            "data": {"id": "training_sword", "success": True, "before": old, "after": new}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            new["hero"]["gold"] = 0
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("equip changed unrelated progress", inspect([path])[1][0])

    def test_forge_contribution_changes_only_service_provider(self):
        old = {"player_id": "test", "familias": {"dawn": {"contribution": 3, "squire_xp": 6}, "ember": {"contribution": 0, "events": {}}}}
        new = json.loads(json.dumps(old))
        new["familias"]["ember"].update(contribution=1, events={"forge-test": True})
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "workshop", "event": "contribution",
            "data": {"id": "forge-test", "success": True, "duplicate": False, "before": old, "after": new}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            new["familias"]["dawn"]["squire_xp"] = 0
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("forge contribution changed unrelated shared growth", inspect([path])[1][0])

    def test_transfer_preserves_old_growth_and_personal_progress(self):
        shared = {"player_id": "test", "familias": {"dawn": {"contribution": 3, "squire_xp": 6, "scout_xp": 0, "events": {}}, "ember": {"contribution": 0, "events": {}}}}
        before = {"phase": "city", "steps": 0, "respawn": {}, "hero": {"familia_id": "dawn", "player_id": "test",
            "hp": 36, "weapon": "iron_sword", "gold": 9, "growth_pending": [], "quests": {"hunt": "claimed"},
            "party_enlisted": True, "party_hp": 28, "scout_enlisted": False, "scout_hp": 0}}
        after = json.loads(json.dumps(before))
        after["hero"].update(familia_id="ember", party_enlisted=False, party_hp=0)
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "familia", "event": "service",
            "data": {"action": "join_ember", "success": True, "before": before, "after": after, "shared_before": shared, "shared_after": shared}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["hero"]["gold"] = 0
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertTrue(inspect([path])[1])
            after["hero"]["gold"] = 9
            row["data"]["shared_after"] = json.loads(json.dumps(shared))
            row["data"]["shared_after"]["familias"]["dawn"]["squire_xp"] = 0
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("transfer changed shared growth", inspect([path])[1][0])

    def test_gm_recovery_cannot_revive_or_grant_actions(self):
        before = {"hero": {"hp": 10, "max_hp": 36, "potions": 1, "fire_potions": 2},
            "ally": {"hp": 0, "max_hp": 28}, "scout": {"hp": 8, "max_hp": 22}, "actions": 0}
        after = json.loads(json.dumps(before))
        after["hero"]["hp"] = 36
        after["scout"]["hp"] = 22
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "gm",
            "event": "restore_party", "data": {"scope": "battle", "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["ally"]["hp"] = 28
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertTrue(inspect([path])[1])
            after["ally"]["hp"] = 0
            after["actions"] = 1
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertTrue(inspect([path])[1])
            after = json.loads(json.dumps(before))
            after["hero"].update(potions=10, fire_potions=10)
            row.update(event="refill_potions", data={"scope": "battle", "before": before, "after": after})
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])

    def test_depth_goal_requires_actual_floor_and_city_claim(self):
        hero = {"quests": {"depth_five": "active"}, "depth_goal": 5}
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "objective",
            "event": "depth_progress", "data": {"before": 4, "after": 5, "floor": 5, "state": {"floor": 5, "hero": hero}}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            row["data"]["floor"] = 4
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertTrue(inspect([path])[1])
            before = {"phase": "city", "steps": 0, "respawn": {}, "hero": {
                "quests": {"depth_five": "active"}, "depth_goal": 4, "gold": 0, "experience": 70, "level": 4,
                "hp": 40, "max_hp": 48, "scrap": 0}}
            after = json.loads(json.dumps(before))
            after["hero"].update(quests={"depth_five": "claimed"}, gold=15, experience=85, level=5, max_hp=52)
            row.update(category="quest", event="claim", data={"id": "depth_five", "success": True, "before": before, "after": after})
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("depth quest incomplete", inspect([path])[1][0])
            before["hero"]["depth_goal"] = after["hero"]["depth_goal"] = 5
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])

    def test_growth_only_rewards_actual_members(self):
        before = {"player_id": "test", "familias": {"dawn": {"contribution": 0, "squire_xp": 0, "scout_xp": 0, "events": {}}}}
        after = {"player_id": "test", "familias": {"dawn": {"contribution": 1, "squire_xp": 0, "scout_xp": 2, "events": {"clear": ["scout"]}}}}
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "familia",
            "event": "victory_growth", "data": {"id": "clear", "members": ["scout"], "success": True, "duplicate": False, "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["familias"]["dawn"]["squire_xp"] = 2
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertTrue(inspect([path])[1])
            row["data"]["members"] = ["squire", "scout"]
            after["familias"]["dawn"]["events"]["clear"] = ["squire", "scout"]
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["familias"]["dawn"]["contribution"] = 2
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertTrue(inspect([path])[1])

    def test_third_member_guard_and_surge_are_independent(self):
        before = {"actor": "scout", "actions": 1, "guarding": False, "ally_guarding": False, "scout_guarding": False,
            "hero": {"hp": 30, "max_hp": 36, "surge": 1}, "ally": {"hp": 28, "max_hp": 28, "surge": 1},
            "scout": {"hp": 10, "max_hp": 22, "surge": 1}, "enemy": {"hp": 22, "max_hp": 22}}
        after = json.loads(json.dumps(before))
        after.update(actions=0, scout_guarding=True)
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "battle",
            "event": "use_ability", "data": {"input": {"ability": "guard", "target": "scout"}, "success": True, "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["guarding"] = True
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertTrue(inspect([path])[1])
            after = json.loads(json.dumps(before))
            after["actions"] = 0
            after["scout"].update(hp=18, surge=0)
            row["data"].update(input={"ability": "surge", "target": "scout"}, after=after)
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            after["ally"]["surge"] = 0
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertTrue(inspect([path])[1])

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

    def test_job_selection_preserves_progress_and_checks_skill_level(self):
        before = {"phase": "city", "steps": 0, "respawn": {}, "message": "ready", "hero": {
            "job_id": "swordsman", "ac": 14, "attack": 5, "dex": 2, "gold": 9, "hp": 30,
            "familia_id": "dawn", "party_hp": 10, "growth_pending": ["queued"]}}
        after = json.loads(json.dumps(before))
        after["hero"].update(job_id="mage", ac=12, attack=5, dex=1)
        after["message"] = "changed"
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "job",
            "event": "select", "data": {"id": "mage", "success": True, "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])

            after["hero"]["growth_pending"] = []
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("job selection changed unrelated progress", inspect([path])[1][0])
            before = {"actor": "lorn", "actions": 1, "hero": {"job_id": "mage", "level": 1, "hp": 36, "max_hp": 36},
                "enemy": {"hp": 22, "max_hp": 22}}
            after = json.loads(json.dumps(before))
            after["actions"] = 0
            after["enemy"]["hp"] = 12
            row.update(category="battle", event="use_ability", data={"input": {"ability": "arcane_bolt", "target": "goblin"}, "success": True, "before": before, "after": after})
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("job skill qualification", inspect([path])[1][0])
            before["hero"]["level"] = after["hero"]["level"] = 2
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])

    def test_enemy_advantage_cancelled_by_guard(self):
        data = {"rolls": [4, 17], "roll": 17, "roll_mode": "advantage", "advantage": True,
            "guarded": False, "actor": "goblin", "content_id": "prowler", "modifier": 4, "ac": 14, "hit": True}
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "battle", "event": "attack", "data": data}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            data["roll"] = 4
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("attack selected die", inspect([path])[1][0])
            data.update(rolls=[4], roll_mode="normal", guarded=True, hit=False)
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            data["roll_mode"] = "advantage"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("attack advantage cancellation", inspect([path])[1][0])

    def test_member_quest_requires_guild_level_and_real_party_victory(self):
        before = {"phase": "city", "steps": 0, "respawn": {}, "message": "ready", "hero": {
            "familia_id": "dawn", "familia_wins": 0, "quests": {"familia_patrol": "available"}}}
        after = json.loads(json.dumps(before))
        after["hero"]["quests"]["familia_patrol"] = "active"
        after["message"] = "accepted"
        row = {"schema": 1, "session": "test", "sequence": 1, "level": "INFO", "category": "quest", "event": "accept",
            "data": {"id": "familia_patrol", "guild_level": 1, "success": True, "before": before, "after": after}}
        with tempfile.TemporaryDirectory(prefix="tensei-checker-") as directory:
            path = Path(directory) / "events-test.jsonl"
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("member quest qualification", inspect([path])[1][0])
            row["data"]["guild_level"] = 2
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            source = {"familia_id": "dawn", "familia_wins": 0, "party_enlisted": True, "quests": {"familia_patrol": "active"},
                "hp": 36, "max_hp": 36, "gold": 0, "scrap": 0, "potions": 3, "fire_potions": 2}
            hero = dict(source, gold=3, scrap=1, familia_wins=1)
            row.update(category="exploration", event="finish_battle", data={"success": True, "input": {"hero": source, "victory": True, "with_party": True},
                "before": {"wins": 0}, "after": {"wins": 1, "hero": hero}})
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertEqual(inspect([path])[1], [])
            row["data"]["input"]["with_party"] = False
            path.write_text(json.dumps(row), encoding="utf-8")
            self.assertIn("member victory progress", inspect([path])[1][0])


if __name__ == "__main__":
    unittest.main()

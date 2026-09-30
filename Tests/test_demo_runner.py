from pathlib import Path
import runpy
import unittest

classify = runpy.run_path(str(Path(__file__).resolve().parents[1] / "Tools/run_demo_checks.py"))["classify"]


class DemoRunnerTests(unittest.TestCase):
    def test_requires_success_marker_and_no_engine_error(self):
        self.assertEqual(classify(0, "CITY LOOP CHECKS: 0 failures"), "")
        self.assertEqual(classify(0, "PASS: menu"), "")
        self.assertEqual(classify(0, "CITY LOOP CHECKS:  0  failures"), "")
        self.assertTrue(classify(0, "Godot started"))
        self.assertTrue(classify(0, "SCRIPT ERROR: invalid call\nCITY LOOP CHECKS: 0 failures"))
        self.assertTrue(classify(1, "CITY LOOP CHECKS: 0 failures"))

    def test_import_needs_exit_and_engine_checks_without_assertion_marker(self):
        self.assertEqual(classify(0, "import complete", False), "")
        self.assertTrue(classify(0, "ERROR: parse failed", False))


if __name__ == "__main__":
    unittest.main()

"""Run isolated Godot Demo checks and retain output, engine and event logs.

Usage: python Tools/run_demo_checks.py --godot <console executable>
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
LOG_SCENARIOS = {"test_city_loop", "test_inventory", "test_stage_boss", "test_quests_growth", "test_depth_goal", "test_gm_recovery", "test_encounter_choice", "test_party_combat", "test_party_expedition", "test_three_party", "test_jobs", "test_enemy_variety", "test_familia_quests", "test_familia_transfer", "test_forge_growth", "test_member_workshop"}
LOG_SCENARIOS.add("test_rest_station")
LOG_SCENARIOS.add("test_commerce_orders")
LOG_SCENARIOS.add("test_enemy_parties")
LOG_SCENARIOS.add("test_pause_menu")
LOG_SCENARIOS.add("test_bulk_trading")
LOG_SCENARIOS.add("test_armor_equipment")
LOG_SCENARIOS.add("test_training_setup")
LOG_SCENARIOS.add("test_save_and_continue")


def classify(returncode, output, require_completion=True):
    if returncode != 0:
        return f"process exit {returncode}"
    if re.search(r"(?m)^\s*(?:SCRIPT ERROR|ERROR):", output):
        return "engine or script error"
    if require_completion and not re.search(r"(?m)(?:CHECKS:\s+0\s+failures|^PASS:)", output):
        return "missing completion marker"
    return ""


def execute(command, directory, env, timeout, require_completion=True):
    directory.mkdir(parents=True, exist_ok=False)
    start = time.monotonic()
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=timeout)
        output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
        reason = classify(result.returncode, output, require_completion)
        code = result.returncode
    except subprocess.TimeoutExpired as exc:
        output = ((exc.stdout or b"") + (exc.stderr or b"")).decode("utf-8", errors="replace")
        reason, code = "timeout", None
    (directory / "console.txt").write_text(output, encoding="utf-8")
    return {"passed": not reason, "reason": reason, "exit_code": code,
            "seconds": round(time.monotonic() - start, 3), "artifacts": str(directory)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", shutil.which("godot")))
    parser.add_argument("--tests", nargs="+", help="test script stems; default all test_*.gd")
    parser.add_argument("--import-timeout", type=int, default=180, help="seconds for asset import")
    parser.add_argument("--timeout", type=int, default=60, help="seconds per process")
    args = parser.parse_args()
    if not args.godot or not Path(args.godot).is_file():
        parser.error("Set --godot to the matching Godot console executable or set GODOT_BIN")
    args.godot = str(Path(args.godot).resolve())
    if args.timeout < 1 or args.import_timeout < 1:
        parser.error("timeout must be positive")
    tests = sorted((ROOT / "Tests").glob("test_*.gd"))
    if args.tests:
        known = {p.stem: p for p in tests}
        if any(name not in known for name in args.tests):
            parser.error("Unknown test name; use script stems from Tests/")
        tests = [known[name] for name in dict.fromkeys(args.tests)]
    artifacts = Path(tempfile.mkdtemp(prefix="tensei-demo-checks-"))
    env = os.environ.copy()
    # Ambient capture/restart flags can change a test's scenario or block a headless run.
    for key in list(env):
        if key.startswith("TENSEI_"):
            del env[key]
    env["TENSEI_LOG_DIR"] = str(artifacts / "import-events")
    report = {"artifacts": str(artifacts), "tests": {}, "restart": {}, "scope": "Assertions and engine errors for every test; log invariants for listed normal scenarios. User saves are not test inputs."}
    report["import"] = execute([args.godot, "--headless", "--path", str(ROOT), "--log-file",
        str(artifacts / "import" / "engine.log"), "--editor", "--import", "--quit"], artifacts / "import", env, args.import_timeout, False)
    if report["import"]["passed"]:
        from check_logs import inspect
        for test in tests:
            directory = artifacts / test.stem
            env["TENSEI_LOG_DIR"] = str(directory / "events")
            result = execute([args.godot, "--headless", "--path", str(ROOT), "--log-file",
                str(directory / "engine.log"), "--script", str(test)], directory, env, args.timeout)
            result["log_rules_checked"] = test.stem in LOG_SCENARIOS
            if result["log_rules_checked"]:
                paths = sorted((directory / "events").glob("events-*.jsonl"))
                _, errors, sessions = inspect(paths)
                if not paths:
                    errors.append("missing business logs")
                if any(not any(row["category"] == "session" and row["event"] == "end" for row in rows) for rows in sessions.values()):
                    errors.append("missing session end")
                result["log_errors"] = errors
                result["passed"] = result["passed"] and not errors
                if errors: result["reason"] = result["reason"] or "business log invariants"
            report["tests"][test.stem] = result
            print(("PASS " if result["passed"] else "FAIL ") + test.stem, flush=True)
        for stem, prefix in (("test_expedition_save", "SAVE"), ("test_save_library", "LIBRARY"), ("test_player_progress", "FAMILIA")):
            if stem not in report["tests"]:
                continue
            restart_env = env.copy()
            tag = {"SAVE": "test-save-", "LIBRARY": "test-library-", "FAMILIA": "test-familia-"}[prefix]
            restart_env[f"TENSEI_{prefix}_TEST_PATH"] = "user://" + tag + uuid.uuid4().hex
            for phase in ("write", "read"):
                key = stem + "-" + phase
                directory = artifacts / key
                restart_env[f"TENSEI_{prefix}_TEST_PHASE"] = phase
                restart_env["TENSEI_LOG_DIR"] = str(directory / "events")
                result = execute([args.godot, "--headless", "--path", str(ROOT), "--log-file",
                    str(directory / "engine.log"), "--script", str(ROOT / "Tests" / (stem + ".gd"))], directory, restart_env, args.timeout)
                report["restart"][key] = result
                print(("PASS " if result["passed"] else "FAIL ") + key, flush=True)
                if not result["passed"]: break
        report["python"] = execute([sys.executable, "-m", "unittest", "discover", "-s", "Tests", "-p", "test_*.py"], artifacts / "python", env, args.timeout, False)
    passed = report["import"]["passed"] and report.get("python", {}).get("passed", False) and all(t["passed"] for t in report["tests"].values()) and all(t["passed"] for t in report["restart"].values())
    report["passed"] = passed
    (artifacts / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Artifacts: " + str(artifacts))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

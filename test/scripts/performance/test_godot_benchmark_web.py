"""Data-adapter checks with synthetic fixtures, never performance evidence."""

import copy
import json
from pathlib import Path
import shutil
import unittest
from uuid import uuid4

from prepare_godot_benchmark_web import CASES, convert_run, read_runs


def fixture():
    trials = []
    for case in CASES:
        for run in range(1, 4):
            trials.append({"case": case, "run": run, "data": {
                "engine": {"version": "v4.7.1.stable.official", "version_hash": "a" * 40},
                "system": {"os": "Windows", "cpu_name": "fixture", "cpu_count": 8,
                           "gpu": "fixture", "cpu_architecture": "x86_64"},
                "comparison": {"headless": False, "case": case, "frames_captured": 100,
                               "elapsed_ms": 5000, "renderer": "forward_plus"},
                "benchmarks": [{"results": {"time": float(run), "render_cpu": run / 10}}],
            }})
    return {"headless": False, "renderer": "forward_plus", "runs": 3, "trials": trials,
            "source_commit": "b" * 40, "source_dirty": True, "native_dll_sha256": "c" * 64,
            "upstream_commit": "d" * 40}


class WebAdapterTests(unittest.TestCase):
    def test_real_units_categories_and_distinct_run_time(self):
        converted = convert_run("20260906-020556-fixture", fixture())
        self.assertEqual(len(converted["benchmarks"]), 6)
        self.assertEqual(converted["local"]["started_at"], "2026-09-06T02:05:56")
        self.assertEqual({row["category"] for row in converted["benchmarks"]}, {
            "Animation > Tween", "Animation > Native Easing Curve", "Animation > Legacy Easing Curve"})
        for row in converted["benchmarks"]:
            self.assertEqual(row["results"], {"local_editor": {"time": 2.0, "render_cpu": 0.2}})

    def test_incomplete_and_duplicate_trials_fail(self):
        data = fixture()
        data["trials"].pop()
        with self.assertRaises(ValueError):
            convert_run("20260906-020556-fixture", data)
        data = fixture()
        data["trials"][1]["run"] = 1
        with self.assertRaises(ValueError):
            convert_run("20260906-020556-fixture", data)

    def test_invalid_measurements_fail(self):
        for value in (None, 0, -1, float("nan"), float("inf"), True):
            data = fixture()
            data["trials"][0]["data"]["benchmarks"][0]["results"]["time"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                convert_run("20260906-020556-fixture", data)

    def test_mixed_capture_metadata_fails(self):
        data = fixture()
        data["trials"][1]["data"]["system"]["gpu"] = "different"
        with self.assertRaises(ValueError):
            convert_run("20260906-020556-fixture", data)

    def test_headless_and_other_hardware_are_excluded(self):
        # A repository-local temporary directory avoids modifying user data.
        root = Path(__file__).resolve().parents[3] / "test/_temp"
        root.mkdir(exist_ok=True)
        base = (root / ("benchmark-web-fixture-" + uuid4().hex)).resolve()
        self.assertEqual(base.parent, root.resolve())
        base.mkdir()
        self.addCleanup(shutil.rmtree, base)
        for index in range(3):
            data = copy.deepcopy(fixture())
            if index == 0:
                data["trials"][0]["data"]["system"]["gpu"] = "other GPU"
            data["headless"] = index == 2
            folder = base / f"20260906-02000{index}-fixture"
            folder.mkdir()
            (folder / "summary.json").write_text(json.dumps(data), encoding="utf-8")
        selected, skipped = read_runs(base, "forward_plus")
        self.assertEqual([run_id for run_id, _ in selected], ["20260906-020001-fixture"])
        self.assertEqual(len(skipped), 2)


if __name__ == "__main__":
    unittest.main()

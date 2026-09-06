"""Adapt recorded Easing Curve runs to the pinned Godot benchmark web interface."""

import argparse
from datetime import datetime
import json
import math
from pathlib import Path
import shutil
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
UPSTREAM = Path(__file__).parent / "godot_tween_upstream" / "web"
OVERRIDES = Path(__file__).parent / "godot_benchmark_web"
CASES = [f"{backend}_{workload}" for backend in ("tween", "native", "legacy")
         for workload in ("properties", "methods")]
GRAPHS = [
    {"id": "animation-tween", "title": "Tween", "benchmark-path-prefix": "Animation/Tween"},
    {"id": "animation-native-easing-curve", "title": "Native Easing Curve",
     "benchmark-path-prefix": "Animation/Native Easing Curve"},
    {"id": "animation-legacy-easing-curve", "title": "Legacy Easing Curve",
     "benchmark-path-prefix": "Animation/Legacy Easing Curve"},
    {"id": "animation-easing-comparison", "title": "Tween, Native & Legacy",
     "benchmark-path-prefix": "Animation"},
]


def hardware_key(summary):
    system = summary["trials"][0]["data"]["system"]
    return (system["os"], system["cpu_name"], system["cpu_count"], system["gpu"],
            system.get("cpu_architecture", system.get("architecture")),
            summary["renderer"], summary["upstream_commit"])


def read_runs(results, renderer):
    candidates = []
    skipped = []
    for path in sorted(results.glob("*/summary.json")):
        summary = json.loads(path.read_text(encoding="utf-8-sig"))
        if summary["headless"] or summary["renderer"] != renderer:
            skipped.append(path.parent.name)
            continue
        if not summary.get("trials"):
            raise ValueError(f"No trials: {path}")
        candidates.append((path.parent.name, summary))
    if not candidates:
        raise ValueError(f"No completed rendered {renderer} reports in {results}")
    reference = hardware_key(candidates[-1][1])
    selected = []
    for run_id, summary in candidates:
        if hardware_key(summary) == reference:
            selected.append((run_id, summary))
        else:
            skipped.append(run_id)
    return selected, skipped


def positive_number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"Non-numeric benchmark measurement: {value!r}")
    if not math.isfinite(value) or value <= 0:
        raise ValueError(f"Non-positive or non-finite measurement: {value!r}")
    return value


def convert_run(run_id, summary):
    started = datetime.strptime(run_id[:15], "%Y%m%d-%H%M%S")
    first = summary["trials"][0]["data"]
    engine = first["engine"]
    if "version_hash" not in engine:  # First local report used Engine.get_version_info().
        engine = {"version": "v" + engine["string"], "version_hash": engine["hash"]}
    benchmarks = []
    if len(summary["trials"]) != len(CASES) * summary["runs"]:
        raise ValueError(f"Incomplete six-case report: {run_id}")
    for case in CASES:
        trials = [trial for trial in summary["trials"] if trial["case"] == case]
        if sorted(trial["run"] for trial in trials) != list(range(1, summary["runs"] + 1)):
            raise ValueError(f"Missing or duplicate trial for {run_id}/{case}")
        for trial in trials:
            data = trial["data"]
            capture = data["comparison"]
            if (capture["headless"] or capture["case"] != case
                    or capture["frames_captured"] <= 0 or capture["elapsed_ms"] < 5000
                    or capture["renderer"] != summary["renderer"]
                    or data["system"] != first["system"] or data["engine"] != first["engine"]):
                raise ValueError(f"Inconsistent or incomplete capture: {run_id}/{case}")
        metrics = {metric: statistics.median(
            positive_number(trial["data"]["benchmarks"][0]["results"][metric])
            for trial in trials) for metric in ("time", "render_cpu")}
        backend, workload = case.split("_")
        category = "Tween" if backend == "tween" else backend.title() + " Easing Curve"
        name = "Tween 100 Properties" if workload == "properties" else "Animate 1000 Tween Methods"
        benchmarks.append({"category": "Animation > " + category, "name": name,
                           "results": {"local_editor": metrics}})
    return {
        "engine": engine, "system": first["system"], "benchmarks": benchmarks,
        "local": {"run_id": run_id, "started_at": started.isoformat(),
                  "source_commit": summary["source_commit"], "source_dirty": summary["source_dirty"],
                  "renderer": summary["renderer"], "trials_per_case": summary["runs"],
                  "native_dll_sha256": summary["native_dll_sha256"],
                  "upstream_commit": summary["upstream_commit"]},
    }


def adapt_chart_script(path):
    """Small explicit patches for local, sometimes single-run history; keep upstream plots."""
    source = path.read_text(encoding="utf-8")
    patches = [
        ("Date.parse(benchmark.date)", "Date.parse(benchmark.local.started_at)", 1),
        ("values.sort();", "values.sort((a, b) => a - b);", 1),
        (".reduce((a, b) => a + b)", ".reduce((a, b) => a + b, 0)", 2),
        ("/ comparedTo.length", "/ Math.max(1, comparedTo.length)", 1),
        ("const trend = avgLast - avgComparedTo;",
         "const trend = comparedTo.length ? avgLast - avgComparedTo : 0;", 1),
        ("mode: 'lines',", "mode: 'lines+markers',", 2),
        ("type: 'date',", "type: 'date',\n\t\t\trange: [Math.min(...xAxis) - Math.max(60000, (Math.max(...xAxis) - Math.min(...xAxis)) * 0.05), Math.max(...xAxis) + Math.max(60000, (Math.max(...xAxis) - Math.min(...xAxis)) * 0.05)],", 1),
    ]
    for old, new, expected in patches:
        if source.count(old) != expected:
            raise ValueError(f"Pinned upstream chart changed; review adapter for {old!r}")
        source = source.replace(old, new)
    path.write_text(source, encoding="utf-8")


def prepare(results, output, renderer):
    runs, skipped = read_runs(results, renderer)
    converted = [(run_id, convert_run(run_id, summary)) for run_id, summary in runs]
    if output.exists():
        raise ValueError(f"Output already exists; choose a new directory: {output}")
    shutil.copytree(UPSTREAM, output, ignore=shutil.ignore_patterns(".github", "godot-empty-project"))
    shutil.copytree(OVERRIDES / "layouts", output / "layouts", dirs_exist_ok=True)
    config = output / "hugo.toml"
    config.write_text(config.read_text(encoding="utf-8").replace(
        "['taxonomy', 'term', 'sitemap', 'RSS']", "['taxonomy', 'term', 'sitemap', 'RSS', 'section']"), encoding="utf-8")
    (output / "src-data/graphs.json").write_text(json.dumps(GRAPHS, indent=2), encoding="utf-8")
    for run_id, data in converted:
        date = data["local"]["started_at"][:10]
        name = f"{date}_{run_id}.json"
        (output / "src-data/benchmarks" / name).write_text(json.dumps(data, indent=2), encoding="utf-8")
    adapt_chart_script(output / "static/graphs.js")
    subprocess.run([sys.executable, "generate-content.py"], cwd=output, check=True)
    # The original graph page keeps its filter and Plotly controls; add accurate local context.
    graph_page = output / "layouts/graph/single.html"
    graph_page.write_text(graph_page.read_text(encoding="utf-8").replace(
        "</h1>", '</h1>\n{{ partial "local-notice.html" . }}'), encoding="utf-8")
    manifest = {"included": [run_id for run_id, _ in runs], "excluded": skipped,
                "renderer": renderer, "reason": "Only rendered runs matching the newest run's hardware and upstream workload are combined."}
    (output / "static/import-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Prepared {len(runs)} recorded runs; excluded {len(skipped)}: {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", type=Path, default=ROOT / "_exports/_benchmarks/godot-tween")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--renderer", choices=("forward_plus", "mobile", "gl_compatibility"), default="forward_plus")
    args = parser.parse_args()
    prepare(args.results.resolve(), args.output.resolve(), args.renderer)


if __name__ == "__main__":
    main()

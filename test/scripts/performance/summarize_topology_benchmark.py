"""Summarize test-only topology output; preserves raw samples for independent review."""
import argparse
import json
import math
from collections import defaultdict
from pathlib import Path
from statistics import median


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]


def read_samples(paths):
    samples = []
    for path in paths:
        for line in Path(path).read_text(encoding="utf-8-sig", errors="replace").splitlines():
            if line.startswith(("TOPOLOGY_SAMPLE|", "TOPOLOGY_MODEL|", "TOPOLOGY_CHILD_MOVEMENT|")):
                kind, payload = line.split("|", 1)
                samples.append({"kind": kind, **json.loads(payload)})
    return samples


def summarize(samples):
    groups = defaultdict(list)
    for sample in samples:
        groups[(sample["kind"], sample["backend"], sample["count"], sample["workload"])].append(sample)
    rows = []
    for (kind, backend, count, workload), group in sorted(groups.items()):
        row = {"kind": kind, "backend": backend, "count": count, "workload": workload, "samples": len(group)}
        for metric in ("request_usec", "ui_usec", "to_frame_usec", "usec", "post_completion_to_frame_usec", "constructed", "retained", "parses"):
            values = [sample[metric] for sample in group if metric in sample]
            if values:
                row[metric] = {"median": median(values), "p95": percentile(values, 0.95)}
        rows.append(row)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    samples = read_samples(args.logs)
    args.output.write_text(json.dumps({"samples": samples, "summary": summarize(samples)}, indent=2) + "\n", encoding="utf-8")
    print("backend | start | operation | request median/p95 ms | UI median/p95 ms | frame median/p95 ms | panels")
    for row in summarize(samples):
        if row["kind"] != "TOPOLOGY_SAMPLE":
            continue
        timings = []
        for metric in ("request_usec", "ui_usec", "to_frame_usec"):
            value = row[metric]
            timings.append(f"{value['median'] / 1000:.2f}/{value['p95'] / 1000:.2f}")
        print(f"{row['backend']} | {row['count']} | {row['workload']} | " + " | ".join(timings) + f" | {row['constructed']['median']}")


if __name__ == "__main__":
    main()

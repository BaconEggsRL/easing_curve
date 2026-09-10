# Inspector topology performance — PERF-POINTS-01 through 05

> Implementation/investigation record. Dated counts and failures below are
> historical; [v1.2.1 certification](../../v1.2.1_CODE_TRACKER.md) records current results.

## Decision and measured cause

Native topology now reconciles existing point panels by resource identity. Middle
Add creates one panel; middle Remove and interior swap create none. Endpoint
shape changes replace only affected panels. Reverse rebuilds stored-side bindings;
Invert refreshes values. Snapshot replacement reuses only exact identity matches.

The baseline gate was satisfied before Native integration: at 65 starting points,
Native Add spent a median 300.16 ms in row reconstruction versus 0.662 ms in the
separately measured backend mutation. The graph and Inspector context survived,
but all 65 point panels were replaced. At 257 points the same construction path
took 1,170.92 ms. Model evaluation was not the dominant measured cost.

Legacy retains its current lifecycle. Real-Inspector measurements show one parse
per completed topology operation, despite both resource property-list notification
and explicit Undo publication. No redundant second parse was demonstrated, and no
surviving Legacy presentation offered a narrow incremental integration point.
There are no Legacy snapshot, serialization, factory, or publication changes.

## Call paths and ownership

```text
Native graph Add / Inspector Add / detached Points Add
  -> editor transaction -> Native backend topology snapshot
  -> points_changed + Resource.changed
  -> identity/Reverse detection -> deferred presentation generation check
  -> identity maps -> remove/create/move panels -> metadata/selection refresh
  -> container layout -> subsequent frame_post_draw

Legacy graph Add / Inspector Add / Remove
  -> Inspector snapshot mutation -> set_point_snapshot
  -> count change reconstructs point resources
  -> property_list_changed + points_changed + changed
  -> Inspector reparse -> new context, graph, toolbar, Points root, rows

Legacy swap / committed X order
  -> swap/sort or committed point order -> property-list notification
  -> same reparse lifecycle
```

The list remains the owner of each panel. Panel metadata stores identity, endpoint
shape, the drag handle, property headers, and idempotent callback cleanup. Surviving
panels keep their connections. Removing a panel disconnects external signals before
freeing it, including a panel never attached to a tree. Existing root-exit ownership
and coordinate-overlay cleanup remain in place.

Native ordinary Add/Remove/Reorder Undo and Redo retain surviving point resources
in the graph-owned and detached-Points history paths. Focused tests verify this
contract instead of assuming it. A replacement editor snapshot receives fresh
panels for fresh identities; matching geometry is never treated as identity.

## Index-capture audit

| Construction/routing site | Resolution |
| --- | --- |
| Native remove buttons | Bind point resource; detached removal resolves index after finishing the previous edit |
| Previous/Next buttons | Bind point resource; resolve current storage/display neighbor at invocation |
| Move request across edit completion | Preserve source/target resources, then resolve indices after completion |
| Vector inputs, mode options, locks, Force Linear, resets | Existing point/property binding; current backend lookup at action time |
| Context menus, clipboard, Copy Property Path | Existing point identity binding; clipboard controller resolves current index |
| Property header and label tooltips | Refresh from one storage-index map; no per-row backend scans |
| Header selection metadata | Resource ID and stored property name; reattach selected header after replacement |
| Graph selection | Update logical identity on selection events; re-resolve its index after topology |
| DragHandle.index / payload | Compatibility cache only; source panel determines current drag index |
| Deferred drag source/target | Retain point resources; resolve current panels once at execution, cancel if absent |
| Endpoint omission / reverse-side binding | Shape metadata; selective endpoint replacement and full Reverse fallback |
| Legacy construction indices | Existing full-build consumer retained; no speculative Legacy extraction |

Reconciliation builds the storage-index and existing-panel maps once, then visits
desired display order once. It performs no repeated linear lookup or child scan in
the per-panel loop. Native display order currently equals storage order with Reverse
applied; transform regression tests verify the resulting stored-side bindings.

## Benchmark method

`test/scripts/performance/easing_curve_topology_benchmark.gd` uses real
`EditorInspector` instances and test-only subclasses of the existing plugin/context.
No construction counters, timers, or measurement signals ship in the addon.
Counts **9, 65, 129, 257 are starting counts**: Add at 129 measures 129 -> 130.
Undo Add at 129 starts with 129 points and restores 128.

Each workload uses two warmups and seven measured trials. Fixture construction,
history preparation and teardown are outside the operation interval. Samples report
request CPU, UI construction/reconciliation CPU, row instance retention, parse count,
and request-to-rendered-frame time. Separate uninspected fixtures measure backend
mutation CPU; this is not subtracted from the inspected request measurement.

A sample registers its generation boundary before the request, waits for completed
parse/reconciliation and matching final model/panel identity order, and only then
awaits a subsequent `RenderingServer.frame_post_draw`. This is a rendered-frame
proxy, not physical monitor presentation. Post-completion-to-frame time includes
layout, scheduling and rendering; it is not presented as isolated layout CPU.

Environment: Godot 4.7.1 stable official `a13da4feb`, Windows Compatibility/OpenGL,
AMD Ryzen 9 7950X, NVIDIA GeForce RTX 4070 Ti, 820 x 900 Inspector window, VSync off.
The repository launcher isolates user data and all direct launches supply local
logs under `test/_temp/`. Unrelated development plugins/autoloads are excluded.

The first baseline run's build-specific construction counters were read too late;
those zero counters are not valid construction measurements. Operation construction
counts and timings are valid. The corrected harness measures build counters before
Inspector creation. Legacy spacer metadata diagnostics in that initial harness were
also corrected with an explicit `has_meta` guard. Initial interrupted Legacy results
are not used as a complete comparison dataset.

## Native topology results

Median milliseconds, starting counts. These are the first complete before/after
Native operation datasets; raw distributions and subsequent validation runs are
retained with the report.

| Starting points | Backend Add CPU baseline | Add UI before | Add UI after | Add to frame before | Add to frame after | Panels before -> after |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 9 | 0.079 | 47.45 | 4.70 | 58.20 | 12.19 | 10 -> 1 |
| 65 | 0.662 | 300.16 | 6.87 | 355.72 | 27.11 | 66 -> 1 |
| 129 | 1.542 | 581.19 | 8.72 | 691.29 | 42.12 | 130 -> 1 |
| 257 | 4.001 | 1,170.92 | 14.82 | 1,393.11 | 83.91 | 258 -> 1 |

| Starting points | Remove UI before -> after | Remove to frame before -> after | Swap UI before -> after | Swap to frame before -> after |
| ---: | ---: | ---: | ---: | ---: |
| 9 | 36.63 -> 1.80 | 44.45 -> 5.83 | 40.65 -> 0.45 | 49.69 -> 4.96 |
| 65 | 288.08 -> 3.89 | 341.03 -> 19.47 | 291.18 -> 2.52 | 342.38 -> 15.93 |
| 129 | 582.05 -> 6.55 | 689.41 -> 36.54 | 585.87 -> 5.21 | 687.06 -> 30.86 |
| 257 | 1,173.47 -> 12.28 | 1,396.46 -> 73.44 | 1,158.87 -> 10.82 | 1,361.38 -> 61.89 |

Normalized Add reconciliation CPU growth is approximately **1.27x for 65 -> 129**
and **1.70x for 129 -> 257**, versus baseline **1.94x / 2.01x**. After UI CPU per
starting point is 0.106 / 0.068 / 0.058 ms at 65 / 129 / 257. Construction is
constant; metadata refresh and Control/layout work still scale with count.

The initial 9-point graph-Add after-run has a 442.63 ms frame p95 outlier despite
a 12.19 ms median. It is retained rather than hidden; repeated Add trials and a
cost-hooks-disabled run are used to distinguish startup/scheduling noise from
reconciliation cost. Seven-sample p95 is the maximum sample, not a robust tail estimate.

A focused seven-trial 9-point Add repeat measured 9.58 ms median / 31.32 ms p95,
with 3.92 / 4.19 ms reconciliation CPU and exactly one new panel. A separate
9-point reorder repeat also had a large frame outlier (1,021 ms). These short
small-count runs expose unresolved host scheduling/startup noise; they do not
establish reliable tail latency. Larger-count repeats reproduced the scaling win.

## Complexity and remaining limits

- Middle Add constructs exactly one panel; middle Remove and interior reorder
  construct zero. Shape-changing endpoint operations replace only affected panels.
- Maps, identity signatures, tooltips, selection and display refresh remain O(N).
- Snapshots, model signal synchronization and graph updates remain O(N); ordering
  includes sorting. Native duplicate validation still contains an O(N²) check.
- Godot child movement may be linear per move. Large permutations can exceed the
  linear matching pass even though they create no interior panels.
- Initial Inspector construction, Reverse fallback and full identity replacement
  remain O(N). Legacy topology remains O(N) UI construction.
- 257-point Native topology is far more responsive, but approximately 84 ms to a
  rendered frame is not a 60 Hz frame budget. Layout/rendering is still material.
  This change does not claim constant total latency or eliminate every visible pause.

Virtualization, lazy rows, very-large-curve model optimization, Reverse-side rebinding
and broad Legacy lifecycle/serialization changes remain deferred.

## Reproduction

Use isolated copies for before/after runs. Do not run GPU benchmarks concurrently.
PowerShell must pass the Godot user-argument separator through the array explicitly:

```powershell
& test/runners/run_godot.ps1 -GodotArgs @(
  '--editor', '--path', 'test/_temp/points-after',
  '--script', 'res://test/scripts/performance/easing_curve_topology_benchmark.gd',
  '--log-file', 'test/_temp/topology.log', '--', '--native-only'
)
```

Optional test arguments: `--legacy-only`, `--large-only`, `--add-only`,
`--build-only`, `--count=257`, `--workload=undo_add`, `--cost-hooks-off`.
The last option disables cost counters/timing accumulation while preserving the
generation/frame correctness observer. Summary generation uses only Python's
standard library:

```text
python test/scripts/performance/summarize_topology_benchmark.py LOG --output RESULTS.json
```

## Additional timing distributions

All cells below are **median / p95 milliseconds**. Seven-trial p95 is the maximum.

| Starting points | Workload | Frame before | Frame after | After UI CPU |
| ---: | --- | ---: | ---: | ---: |
| 9 | build | 51.41 / 53.90 | 53.37 / 89.35 | 38.65 / 41.59 |
| 9 | list_add | 55.46 / 57.14 | 10.24 / 12.37 | 4.38 / 5.04 |
| 9 | undo_add | 45.80 / 47.26 | 5.71 / 6.17 | 1.60 / 1.65 |
| 9 | redo_add | 52.90 / 54.09 | 10.35 / 11.25 | 4.03 / 4.30 |
| 9 | takeover | 47.75 / 49.36 | 8.85 / 9.26 | 4.45 / 4.62 |
| 65 | build | 322.05 / 327.54 | 328.16 / 331.92 | 238.67 / 240.92 |
| 65 | list_add | 352.95 / 357.81 | 24.01 / 25.72 | 6.08 / 6.50 |
| 65 | undo_add | 342.34 / 352.34 | 20.58 / 21.91 | 3.63 / 3.75 |
| 65 | redo_add | 355.71 / 360.29 | 27.24 / 29.60 | 5.75 / 6.21 |
| 65 | takeover | 344.12 / 357.34 | 21.54 / 21.63 | 6.74 / 6.94 |
| 129 | build | 630.57 / 637.35 | 615.58 / 620.52 | 448.74 / 453.83 |
| 129 | list_add | 700.65 / 721.97 | 44.33 / 48.02 | 9.14 / 9.40 |
| 129 | undo_add | 693.70 / 731.47 | 40.99 / 44.53 | 6.38 / 6.77 |
| 129 | redo_add | 706.25 / 756.05 | 51.55 / 55.52 | 8.92 / 10.38 |
| 129 | takeover | 684.88 / 689.28 | 36.66 / 36.97 | 9.38 / 9.61 |
| 257 | build | 1329.25 / 1335.57 | 1279.87 / 1287.11 | 925.43 / 933.72 |
| 257 | list_add | 1420.62 / 1448.94 | 83.65 / 92.96 | 14.95 / 15.30 |
| 257 | undo_add | 1368.09 / 1373.14 | 85.56 / 95.47 | 11.68 / 12.89 |
| 257 | redo_add | 1411.96 / 1442.36 | 102.47 / 110.50 | 14.77 / 15.38 |
| 257 | takeover | 1408.42 / 1429.24 | 69.38 / 70.47 | 15.04 / 15.26 |

After Native graph Add attribution:

| Starting points | Request CPU | Reconciliation CPU | UI CPU per point | Completion to subsequent frame |
| ---: | ---: | ---: | ---: | ---: |
| 9 | 0.75 / 0.91 | 4.70 / 5.73 | 0.5226 / 0.6370 | 5.87 / 436.72 |
| 65 | 2.47 / 3.43 | 6.87 / 7.68 | 0.1056 / 0.1181 | 16.92 / 19.77 |
| 129 | 4.74 / 4.94 | 8.72 / 8.95 | 0.0676 / 0.0693 | 28.67 / 29.22 |
| 257 | 11.87 / 12.13 | 14.82 / 15.48 | 0.0577 / 0.0602 | 57.27 / 63.32 |

Growth ratios for 65 -> 129 and 129 -> 257, respectively:

| Contribution | Median growth | p95 growth |
| --- | --- | --- |
| Reconciliation | 1.27x / 1.70x | 1.17x / 1.73x |
| Request | 1.92x / 2.50x | 1.44x / 2.46x |
| Completion to frame | 1.69x / 2.00x | 1.48x / 2.17x |
| Isolated backend Add | 2.38x / 2.60x | 2.33x / 2.60x |

Cost-hook cross-check: Native graph Add to frame (counters disabled):

| Starting points | Instrumented | Cost hooks disabled |
| ---: | ---: | ---: |
| 9 | 12.19 / 442.63 | 9.55 / 237.37 |
| 65 | 27.11 / 30.21 | 24.40 / 25.42 |
| 129 | 42.12 / 42.52 | 42.67 / 43.57 |
| 257 | 83.91 / 89.74 | 81.49 / 88.93 |

The large small-count outlier recurs with counters disabled. Its precise scheduling
cause is not established. At 65/129/257, the independent run reproduces the
improvement. Disabled-counter zeros in raw records mean **unmeasured**, not zero
construction or UI cost. The generation/order observer remains enabled.

## Legacy reference results

Legacy production topology is unchanged. These are reference measurements, not a
claimed before/after optimization. Some 65/129-point reference samples overlapped
headless correctness execution; do not use their small timing differences as gains.
The final 257-point Undo/Redo/takeover groups were rerun serially. Every operation
below performed one actual Inspector reparse and retained zero row instances.

| Starting points | Graph Add | Inspector Add | Remove | Swap | Undo Add | Redo Add |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 9 | 106.48 / 108.85 | 107.58 / 108.15 | 90.41 / 91.19 | 102.44 / 107.35 | 91.38 / 92.79 | 109.42 / 118.38 |
| 65 | 657.73 / 670.85 | 644.62 / 654.98 | 630.92 / 640.28 | 622.85 / 627.23 | 639.23 / 655.16 | 660.03 / 667.81 |
| 129 | 1277.33 / 1289.41 | 1274.59 / 1299.30 | 1240.91 / 1290.02 | 1212.89 / 1223.03 | 1241.51 / 1258.38 | 1263.36 / 1284.19 |
| 257 | 2525.34 / 2614.19 | 2601.43 / 2626.19 | 2581.23 / 2604.51 | 2492.23 / 2653.19 | 2591.84 / 2996.81 | 2570.43 / 2615.91 |

## Evidence and scope

- [Raw topology samples](inspector_topology_samples.jsonl)
- [Environment, source hashes and median/p95 summaries](inspector_topology_summary.json)
- [Focused reconciliation regression](../../../scripts/unit/native_point_reconciliation_test.gd)
- [Benchmark harness](../../../scripts/performance/easing_curve_topology_benchmark.gd)

Baseline addon source is revision `adb3188`; the worktree moved to `c7fa408` during
validation due to an independent preset/scene change. That commit does not change
the measured addon implementation. The summary records before/after context SHA256.
The serialization test fixture paths were updated to follow the independently moved
fixtures; no fixture values or serialization behavior were changed.

The original baseline did not record completion-to-frame separately. Its full
request-to-frame and UI CPU remain usable; corrected initial-build and follow-up
samples use the complete timing schema. Final-state row absence counts indicate
removed panels, not an engine-wide destructor or allocator profiler. Initial-build
`retained`, `parses` and replacement flags describe the post-build operation boundary;
use `constructed` and build timings for initial construction.


## Ordinary dragging and crossing

The existing direct-construction benchmark now covers both backends and all four
counts. It preserves 8 warmup motions, 7 trials of 40 vertical motions and 64
horizontal crossing motions. Native horizontal commit waits for its expected
reconciliation generation/order, then a subsequent frame. These direct fixtures
are attribution measurements; Legacy direct commits do not reproduce real-Inspector
reparses and must not be used as Legacy end-to-end topology latency.

All entries are **before median / p95 -> after median / p95 milliseconds**.

| Backend | Starting points | Vertical motion CPU | Horizontal motion CPU | Horizontal commit to draw/frame |
| --- | ---: | ---: | ---: | ---: |
| legacy | 9 | 0.27 / 0.29 -> 0.29 / 0.33 | 0.28 / 0.29 -> 0.28 / 0.30 | 0.70 / 0.75 -> 0.68 / 0.71 |
| legacy | 65 | 0.26 / 0.66 -> 0.23 / 0.49 | 0.49 / 0.63 -> 0.46 / 0.54 | 3.23 / 3.57 -> 3.25 / 3.82 |
| legacy | 129 | 0.48 / 0.99 -> 0.50 / 0.97 | 0.78 / 0.99 -> 0.78 / 0.92 | 6.76 / 6.92 -> 6.63 / 6.95 |
| legacy | 257 | 0.73 / 1.49 -> 0.77 / 1.50 | 1.24 / 1.55 -> 1.25 / 1.57 | 12.69 / 13.61 -> 12.53 / 12.85 |
| native | 9 | 0.10 / 0.11 -> 0.10 / 0.11 | 0.10 / 0.15 -> 0.10 / 0.11 | 48.86 / 54.18 -> 5.49 / 6.45 |
| native | 65 | 0.10 / 0.14 -> 0.11 / 0.16 | 0.14 / 0.20 -> 0.12 / 0.16 | 341.84 / 350.63 -> 27.29 / 30.54 |
| native | 129 | 0.13 / 0.20 -> 0.14 / 0.23 | 0.16 / 0.27 -> 0.15 / 0.24 | 673.39 / 685.07 -> 48.86 / 54.61 |
| native | 257 | 0.21 / 0.31 -> 0.19 / 0.31 | 0.23 / 0.31 -> 0.23 / 0.33 | 1364.01 / 1388.27 -> 97.86 / 102.30 |

[Raw drag/build samples](inspector_drag_samples.jsonl) and
[all drag/build distributions](inspector_drag_summary.json) include draw CPU,
motion-to-draw, commit CPU, commit-to-draw/frame, and direct initial construction.
Motion-to-draw measures graph rendering, not Inspector reconciliation. Native
commit-to-frame uses the stricter completion boundary; Legacy retains the original
direct-fixture draw metric. Do not compare those different fixture lifecycles as
a backend speed contest.

No material ordinary-motion regression was identified: measured Native motion CPU
remains about 0.10–0.23 ms at the medians. Small absolute differences and noisy p95s
are retained in the evidence rather than rounded into an unsupported speed claim.

## Engine child movement and validation

The repeat reorder run separately times one adjacent `move_child` on the existing
Native list, after the topology sample, then restores its position outside the
measurement. This isolates the engine API's synchronous cost, excluding matching,
model changes and layout. It is a microbenchmark, not a decomposition of every
possible permutation. Its raw records use `TOPOLOGY_CHILD_MOVEMENT`.

| Starting points | Adjacent move CPU median / p95 (microseconds) |
| ---: | ---: |
| 9 | 9 / 25 |
| 65 | 16 / 19 |
| 129 | 18 / 21 |
| 257 | 22 / 24 |

These small values approach timer/scheduling noise; ratios would be misleading.
Many moves in a large permutation can still accumulate appreciable cost.

Rendered Godot 4.7.1 checks passed:

- 11,712 Native reconciliation checks, including identity/construction assertions
  at every starting count, ordinary history identity, replacement snapshots,
  endpoint shapes, passive selection, active edits, Reverse during an active edit,
  callback disposal, second drag routing and a simulated header click after reuse.
- 6,762 Native Points transform checks.
- 34 real-Inspector ownership checks, including mixed backend presentations.
- The generated mixed-Inspector capture was visually inspected for layout and
  selection presentation.

The final registered **full correctness runner passed all 31 suites** after the
active-edit Reverse correction. The final reconciliation suite reports 11,712
checks in both headless editor-host and rendered runs. Relevant suites include
serialization/transition contracts, point locks and aliases, clipboard/property
paths, graph/list Add selection, reorder, Undo/Redo, gestures, ownership, and drag
coordinates. `git diff --check` and Python summary-script compilation also passed.

The Native contract accepts both zero and one point. Tests first assert acceptance,
then exercise Add/Remove recovery; no runtime contract was changed to enable them.
Legacy snapshot reconstruction and dynamic-property tests remain in the runner.

Rendered hosts also emitted Godot editor initialization diagnostics about the root
certificate store/current window and exit RID/ObjectDB cleanup, as the baseline
hosts did. Test PASS counts are not a claim of an empty engine log. No new diagnostic
allowlist was added. No physical mouse automation, allocator profiling, or physical
monitor-presentation measurement was performed.

All cost instrumentation is test-only. Production generation fields exist for stale
presentation cancellation, with no timers or counters. Legacy serialization,
notification publication and presentation ownership are unchanged; the shared list
drag correction is consumed by Native and also restores Legacy's original filters.

Re-run the registered full correctness suite with:

```powershell
& test/runners/run_all_tests.ps1 --run
```

## Plan closeout

| Item | Outcome |
| --- | --- |
| PERF-POINTS-01 | Baseline isolated mutation vs real-Inspector UI establishes construction as the dominant Native Add cost; Legacy scope resolved conservatively |
| PERF-POINTS-02 | Native identity maps, endpoint signatures, metadata refresh, callback cleanup, deferred identity routing and mouse restoration implemented and tested |
| PERF-POINTS-03 | Exactly 1 / 0 / 0 new panels for middle Add / Remove / interior reorder at 9/65/129/257; ordinary Undo identity and exact replacement behavior verified; timing improvement reproduced |
| PERF-POINTS-04 | No Legacy topology/publication refactor: one observed reparse per operation, no proven redundant request or surviving incremental caller |
| PERF-POINTS-05 | Full correctness and rendered checks pass; before/after construction, timing and ordinary-edit evidence retained; remaining latency and measurement limits stated above |

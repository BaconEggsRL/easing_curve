# Native runtime sampling parity

## Root cause and sampling paths

Native is a GDExtension `Resource` with a `TypedArray<NativeEasingCurvePoint>`
and a C++ vector of eight-coordinate cubic segments. It has no backing Godot
`Curve`, `Curve.sample()`, `sample_baked()`, normalized baked offsets, or baked
sampling cache. Callable baking is a separate explicit conversion into points.

Legacy `sample()` clamps X to [0, 1], then `_sample_raw()` evaluates its function
or point geometry. For strictly increasing point X values separated by more
than `SEGMENT_X_EPSILON`, packed segment arrays support cached/binary lookup.
Otherwise `_sample_bezier_points_with_t()` visits adjacent authored points in
order. Nonvertical segments use `bezier_solver.gd`: effective control X values
are clamped to endpoint bounds and crossed controls share their midpoint. Eight
Newton iterations use a bracket and fall back to 32 bisections, with an X solve
tolerance of `1e-8`. Reversed intervals are supported. Near-zero widths retain
the solver's existing midpoint convention.

Native `sample()` clamps X, applies reverse, selects compiled geometry for Custom
or modified Bézier presets (analytic evaluation otherwise), and applies invert.
Point assignment, topology restoration and nested point changes rebuild the
compiled cache and reset locality state. Conversion copies point/control data
and modes into Native resources; it was not the source of this loss.

Previously `compile_segments()` stable-sorted by X, then merged points within
`1e-6`, retaining the last point. This replaced the incoming endpoint in both
reported examples, creating a different cubic before any lookup or inversion
ran. Sorting also changed manually authored reversed/overlapping topology.
The old smoke test explicitly expected sorting and last-duplicate-wins behavior;
those two assertions conflicted with the graph and Legacy and are now corrected.

The shared editor's `get_display_points()` keeps the stored topology (reversing
display order for Native reverse). `_draw_bezier_curve()` draws every adjacent
pair, rendering vertical segments as lines and others as adaptive cubic paths.
It reads point controls directly, not Native's lossy compiled cache. Interactive
point reordering is an editor mutation, separate from runtime compilation.
This is why graph appearance was correct while runtime values were wrong.

## Measured reproduction (Godot 4.7.1, Windows)

Both fixtures use actual point resources with controls at their endpoints.

| Fixture | X | Legacy / expected | Native before | Native after |
| --- | ---: | ---: | ---: | ---: |
| (0,0), (.5,0), (.5,1), (1,1) | .1 | 0 | .2 | 0 |
| same | .25 | 0 | .5 | 0 |
| same | .5 | 0 | 1 | 0 |
| same | .5001 | 1 | 1 | 1 |
| (0,0), (.5,1), (.5,0), (1,1) | .1 | .2 | 0 | .2 |
| same | .25 | .5 | 0 | .5 |
| same | .5 | 1 | 0 | 1 |
| same | .5001 | .0002 | .0002 | .0002 |

The focused test prints all ten requested sample positions and uses `2e-6`
parity tolerance, matching the existing Native custom-curve tests.

## Exact boundary convention

Legacy chooses the **first matching adjacent segment in authored order**:

1. A segment with absolute X width <= `1e-6` returns its ending Y when
   `abs(sample_x - start_x) <= 1e-6`, otherwise it is skipped.
2. A wider segment accepts its inclusive endpoint interval and solves X to t.
3. No matching segment, or fewer than two points, returns zero.

Thus an incoming segment wins at X=.5 in both examples: zero for the step,
one for the reset. Immediately before the boundary the incoming segment still
wins. Immediately after it, the vertical segment returns its ending Y inside
the tolerance band; beyond that band the outgoing segment supplies the value.
A leading or isolated vertical segment returns its ending Y at the boundary.
With three duplicate points, the first vertical segment reached wins, not the
last point in the duplicate group. Query order does not change these rules.

## Fix and costs

`native/src/native_easing_curve.cpp` now retains each adjacent authored segment.
`native_easing_curve.h` adds one cached flag identifying strictly increasing
topology. Such curves keep the locality cache and `lower_bound` on segment ends;
the cache cannot claim a later segment's left boundary. Duplicate, near-duplicate
or reversed topology scans the already compiled vector in authored order and
handles vertical intervals before invoking the solver. There are no per-sample
allocations, resource accesses, sorting, synchronization or editor dependencies.
Compilation no longer sorts or builds a second deduplicated vector.

The existing C++ Newton/bisection evaluator is retained, with decreasing-X and
near-zero-width behavior aligned with Legacy. Effective controls also preserve
Legacy/graph Vector2 precision for a crossed-control midpoint. Authored resources,
public methods, serialized fields, Legacy implementation and graph code are
unchanged. The existing Native custom sampler was repaired; no Godot `Curve`
sampler was introduced or replaced.

Graph and runtime retain separate GDScript/C++ implementations of the same
evaluation rules. Sharing executable code would require a new native graph API
or GDScript calls in runtime; that is unnecessary for this fix. Regression tests
call the existing graph control/position methods and compare their cubic points
with Native runtime samples to guard this seam directly.

## Coverage and validation

`test/scripts/unit/native_sampling_parity_test.gd` covers both reported fixtures,
ordinary linear/Bézier curves, all five handle modes, force-linear controls,
crossed/out-of-range controls, leading/trailing/isolated/triple duplicates,
near-duplicate and decreasing X, endpoint fallback, cache query order, conversion,
mutation between fast and ordered lookup, runtime copies and reverse/invert.
Each parity case sweeps 10,001 X positions in ascending, descending and interleaved
order plus explicit positions around the `1e-6` boundary. Graph checks evaluate
interior cubic positions through the actual editor methods.

The focused suite is registered in `test/runners/run_all_tests.ps1`.
`native_v2_smoke_test.gd` now asserts authored-order/Legacy semantics in the two
old conflicting expectations. The focused suite passed 678 checks on Windows
Godot 4.7.1 with the rebuilt release DLL.

The full runner completed **32 passing suites out of 33**. The remaining suite,
`editor_undo_redo_test.gd`, failed only its two CSS dropdown-label assertions.
Those labels were already modified in the working tree before this task. Running
that suite in the isolated host with the original pre-fix DLL reproduced the
same two failures out of 640 checks. Those unrelated edits were preserved.
The passing suites include Native smoke (1,789), public API/format (143), runtime
updates (1,411), serialization (919), Native point transforms (6,756), and Native
reconciliation (11,712). Existing headless skips for clipboard/visible layout
remain; allowed engine shutdown/certificate diagnostics are recorded by the runner.

Logs under `test/_temp/`:

- `native-sampling-before-console.txt`: original-DLL characterization.
- `native-sampling-final.txt`: final focused pass, no script errors.
- `native-sampling-full-suite.txt`: full runner and individual results.
- `native-sampling-baseline-undo.txt`: original-DLL reproduction of label failures.
- `native-sampling-build.txt`: successful Windows release build.

### Performance measurements

The custom-curve subset of `native_v2_vs_tween_benchmark.gd` was run against the
original and rebuilt DLLs: nine timing trials per case, 50,000 samples per trial,
precomputed offsets, medians reported in microseconds. Temporary scripts and raw
trials are retained as `sampling-benchmark*` under `test/_temp/`. These are local
measurements, not a cross-platform performance guarantee or a full benchmark run.

| Points / order | Before (us) | After (us) | Change |
| --- | ---: | ---: | ---: |
| 2 sequential | 1621 | 1655 | +2.1% |
| 2 reverse | 1607 | 1675 | +4.2% |
| 2 random | 1952 | 2008 | +2.9% |
| 9 sequential | 1504 | 1552 | +3.2% |
| 9 reverse | 1496 | 1555 | +3.9% |
| 9 random | 2049 | 2123 | +3.6% |
| 65 sequential | 1602 | 1643 | +2.6% |
| 65 reverse | 1593 | 1638 | +2.8% |
| 65 random | 2703 | 2774 | +2.6% |

Ordinary sampling measured a 2.1–4.2% increase, about 0.7–1.5 ns/sample including
the GDScript call overhead; Native remained approximately 42–135 times faster
than Legacy in these cases. Additional duplicate-heavy fixtures (each adjacent
pair sharing X, with distinct Y) measured the ordered path:

| Points / order | Native (us) | Legacy (us) |
| --- | ---: | ---: |
| 9 sequential | 2670 | 223166 |
| 9 reverse | 2715 | 226858 |
| 9 random | 3831 | 232076 |
| 65 sequential | 4061 | 657191 |
| 65 reverse | 4025 | 641112 |
| 65 random | 4999 | 645882 |

At 65 points this is about 81–100 ns per Native sample, with the expected O(n)
ordered-search cost. Native remained approximately 61–162 times faster than
Legacy across these duplicate-heavy cases. Memory-allocation behavior was
verified by inspecting the hot C++ path, not with a heap profiler.

## Limits

Ordered lookup is O(n) for ambiguous topology, matching Legacy's first-hit
semantics; strictly increasing lookup remains cached/O(log n). Multiple Y values
on a vertical or overlapping graph necessarily require a branch convention;
this change preserves Legacy's convention, including its existing tolerances.
Null/nonfinite point data is outside these supported-geometry parity fixtures.
No manual visible-editor inspection or Web runtime validation is claimed.

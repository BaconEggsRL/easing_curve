# Native Easing Curve

`NativeEasingCurve` and `NativeEasingCurvePoint` are independent GDExtension
resources. They coexist with the GDScript `EasingCurve` and
`EasingCurvePoint` APIs; neither runtime solver delegates to the other.

Both API families are supported in v1.2.0. The GDScript API remains the
compatibility and fallback implementation and is not deprecated. Any future
deprecation proposal remains conditional on broader Native platform coverage,
a stable release cycle, proven migration and rollback, and explicit approval.

See [PLAN.md](PLAN.md) for milestone status, the manual smoke-test checklist,
and the prioritized next implementation tranche.

## Build contract

The `godot-cpp` submodule is pinned to `godot-4.4.1-stable`. The v1.2.0 minimum
is **Godot 4.4.1** for both API families. The extension manifest declares `4.4.1`,
matching godot-cpp's runtime version check. Godot 4.4.0 is outside the v1.2.0
support contract; the current Native DLL cannot load on it.
Build the supported
Windows release library and both non-threaded Web variants from the repository
root:

```powershell
./native/build_native.ps1 -Platform windows -Target template_release
./native/build_native.ps1 -Platform web -Target all
```

Web builds require Emscripten 3.1.62. The build script resolves an activated
`EMSDK` toolchain when `emcc` is not already on `PATH`. The Web artifacts are
explicitly non-threaded, and the export preset must have Extension Support
enabled and thread support disabled. Both debug and release manifest entries
were restored after isolated browser runtime validation.

A legacy-only Web project can export without Native, but a scene or resource
containing serialized Native types cannot fall back: the matching extension
must load before Godot can deserialize `NativeEasingCurve` or
`NativeEasingCurvePoint`.

Until the Windows debug artifact passes local security validation, editor
sessions use the verified release DLL through the generic `windows.x86_64`
manifest entry. Release exports use the explicit release entry. This keeps the
project and fallback test scene loadable without claiming debug/hot-reload
support.

The Windows ABI fixture validates one 4.4.1-built DLL against Godot
4.4.1, 4.5.1, 4.6.1 and 4.7.1:

```powershell
./test/runners/run_native_compatibility_test.ps1
```

The legacy fallback fixture copies the complete GDScript addon into a project
with no GDExtension manifest or binary:

```powershell
./test/runners/run_legacy_without_native_test.ps1
```

## Resource contract

Native production resources use `format_version = 3`. Godot omits stored
properties equal to their class defaults, so an absent marker means the current
v3 default. Version 3 adds an explicit modified-preset marker. Version 2 remains
loadable and samples with its original rule: standard transitions stay analytic
while Custom retains its authored points. Malformed (`<= 0`), experimental v1,
and future (`> 3`) resources fail closed and return `NAN`. Clean presets omit
redundant canonical point geometry when saved; modified presets retain their
point states and marker. Call `get_format_status()` or `is_format_supported()`
before migration tooling uses the resource.

The bidirectional converter uses the validated dictionary schema in
`curve_conversion_result.gd`. Every converted field is classified as
`exact`, `approximated`, `baked`, or `unsupported`; the schema carries the
source/target backend IDs, optional output resource, warnings, and errors.
Inspector conversion always creates a new unsaved resource. A live legacy
Custom Callable is refused unless the user explicitly chooses the bake action;
the Native result contains sampled points and never retains the Callable.

Standard transition IDs `0`–`11` intentionally match Godot Tween. Native-only
IDs are frozen independently:

| ID | Transition |
| ---: | --- |
| 100 | Custom Bézier |
| 101 | Constant |
| 102 | Jitter |
| 103 | Irregular |
| 104 | Step |
| 105 | Power |
| 106 | Physics Spring |
| 107 | CSS Linear |
| 108 | CSS Cubic Bézier |

All transition IDs above are implemented. Jitter and Irregular persist their
generated point arrays, so sampling is deterministic until **Generate** is used
again. CSS Linear parses stop lists into a compiled piecewise-linear
representation, and CSS Cubic Bézier parses and solves its four controls in
Native code. Arbitrary Callables can be explicitly baked into piecewise-linear
Native Bézier points; Native sampling never retains or invokes the Callable.
Invalid transition IDs are rejected rather than silently sampling as linear.

`points` returns an isolated typed-array container. Point resources remain
shared for authored editing, and nested changes invalidate compiled segments.
`create_runtime_copy()` deep-copies every point and all runtime parameters.
Native points persist handle mode, control locks, and force-linear state, and
`apply_state()` restores a point snapshot atomically for future Undo/Redo use.

## Validation and benchmarks

Run the Native correctness suite and the expanded runtime benchmark:

```powershell
./test/runners/run_godot.ps1 --headless --path . --script test/scripts/unit/native_v2_smoke_test.gd
./test/runners/run_godot.ps1 --headless --path . --script test/scripts/unit/native_public_contract_test.gd
./test/runners/run_native_runtime_benchmark.ps1
./test/runners/run_curve_editor_backend_benchmark.ps1
./test/runners/run_point_scaling_benchmark.ps1
./test/runners/run_native_point_scaling_benchmark.ps1
./test/runners/run_native_release_export_test.ps1
./native/validate_native_manifest.ps1 -Platform all
./test/runners/run_native_web_export_test.ps1 -SkipBuild
```

The Native smoke suite currently contains 1,789 checks. The runtime benchmark runs
in an isolated project containing only this addon and
the benchmark script. It reports median, median absolute deviation, and raw values
for all 12 standard transitions in all four ease modes; 2-, 9-, and 65-point
custom curves in sequential, reverse, and random sampling order; mutation; and
deep runtime duplication. By default it evaluates the median of three release-
library runs. The editor-backend benchmark compares adapter and direct costs for
preview sampling, 65-point reads, snapshots, mutation-plus-recompile, and
transaction-shaped gestures, then reports curve-change signals and 65-point
add/remove/reorder/snapshot topology workloads for each backend. The interaction
scaling benchmark drives the shared Legacy and Native editors at 9 through 129
points. The separate runtime-scaling characterization measures 65 through 1,025
points and is intentionally outside the retained historical baseline.
Tween is used only as a benchmark and numerical oracle. No Native sampling path
calls Tween, GDScript, or a Callable.

### Runtime performance evidence

The historical absolute baseline remains deliberately unpromoted. The retained
release-library results below are supplemented by the current three-run extended-
Bounce comparison; the current run did not evaluate or replace the absolute file.

| Workload | Iterations | Native | Comparator | Native advantage |
|---|---:|---:|---:|---:|
| 48 standard Transition/Ease cases | 200,000 | 5.183–8.957 ms | Tween: 9.330–31.636 ms | 1.8–4.0× |
| Deterministic functions | 50,000 | 1.248–2.279 ms | Legacy: 86.340–153.226 ms | 62.7–104.2× |
| Extended Bounce (6 bounces, 42.5 decay) | 50,000 | 1.741 ms | Legacy: 135.744 ms | 78.0× |
| Custom curves, 2/9/65 points | 50,000 | 1.543–2.776 ms | Legacy: 83.491–246.812 ms | 42.3–134.2× |
| 65-point random sampling | 50,000 | 2.776 ms | Legacy: 246.812 ms | 88.9× |
| 65-point mutation and sampling | 4,000 | 30.032 ms | Legacy: 325.832 ms | 10.8× |
| 65-point deep copies | 500 | 113.880 ms | Legacy: 11,345.662 ms | 99.6× |

All 64 current relative comparisons pass. Eight of the 27 retained Native-only
absolute cases exceed their old timing plus the noise allowance, so the
historical file remains unchanged pending a quiet reference-host run.

### Large-curve characterization

The generalized shared-editor benchmark measures one-event point crossings;
times below are update-to-draw p99 in milliseconds. Four-event bursts remain in
the raw benchmark output as diagnostics.

| Points | Legacy p99 | Native p99 |
|---:|---:|---:|
| 9 | 1.092 | 0.985 |
| 13 | 1.255 | 1.206 |
| 17 | 1.789 | 1.244 |
| 25 | 1.845 | 1.716 |
| 33 | 2.057 | 2.113 |
| 49 | 3.079 | 2.977 |
| 65 | 3.679 | 3.654 |
| 97 | 5.591 | 5.661 |
| 129 | 8.421 | 7.468 |

Neither backend crosses 16.667 ms through 129 points in this level-2 shared-
editor harness, and Native passes the 9–33 point p99/noise gates. An older
Legacy-only end-to-end editor run measured 15.562 ms p99 at 49 points and
20.845 ms at 65 points; its dock/render scope differs, so it remains useful
historical context rather than a direct comparison with this harness.

The new runtime-scaling characterization shows Native random sampling retaining
about 219,000–297,000 samples per 16.667 ms across 65–1,025 points. At 65 points
it estimates about 297,000 Native samples versus 3,120 Legacy samples per frame.
These values are linear estimates from 50,000-sample batches, not measured frame
thresholds.

## Shared editor status

The production Inspector and Curve Editor choose either the legacy or Native
backend through the shared adapter boundary. Native custom curves and the ten
Bézier-backed presets support graph and point-list creation, deletion, crossing,
reordering, point/handle dragging, handle modes, force-linear state, locks, and
preset reset. Graph and list drags compile local previews but defer public and
live-debug publication until release. Discrete edits, Undo, and Redo add one
resource-owned Undo/Redo operation carrying a resource-free snapshot; this gives
Godot's live debugger a method call it can replay in the running game and gives
the owning scene the correct dirty history. Point-list reorder now matches legacy
by exchanging the points' x positions and translating both handles. Point identity
and selection survive reorder and Undo/Redo, and detached points are disconnected.
Native point-property cells retain the compact list layout while supporting the
same selection highlight, context menu, keyboard shortcuts, serialized system
clipboard, and cross-copy behavior as Legacy. Deferred value-edit completion is
resolved by curve and point identity rather than retaining row controls, so an
Inspector rebuild, topology action, or resource switch cannot replay a stale UI
callback or merge unrelated Undo transactions.
Ease and Trans remain ungrouped above the custom **Curve Editor** foldout.
The structural Native property-list groups are **Transition Parameters** and
**Global Transform**, with the conditional **Points** section inserted between
them at the serialized `points` field only for point-graph transitions. The
Jitter and Irregular keep **Generate** at the bottom of **Curve Editor**. Point
graphs show **New point handles** and **Add Point** as the first row inside the
**Points** section, immediately above the editable point array. Both controls
shrink together in narrow Inspectors and stop expanding at their text-fitting
widths in wide Inspectors. Conversion actions are the last item inside Godot's
built-in **Resource** section, after **Name**.
Native numeric
parameter sliders use the same deferred transaction boundary,
including the Constant and Back parameters that regenerate Bézier preset geometry:
motion previews locally, then publishes one Inspector/live-scene update on release.
Directly entered values still publish immediately.
Clean presets continue on the analytic sampler; only Custom and modified preset
geometry use compiled segments. Pending additions and point-list drags render
directly from backend point state, stale pending/detached previews are discarded,
Autofit includes visible handles, transition parameters are shown only for their
owning preset, and point-list controls rebuild only when point identity/order changes.
The editor-only **New point handles** selector beside **Add Point** chooses Free,
Linear, Balanced, Mirrored, or Linked for both graph-click and list additions in
both backends. Open inspectors share the preference. It does not modify existing
points, curve resources, Undo history, live publication, or runtime sampling.

## Manual smoke-test status — 2026-09-04

| Area | Result | Follow-up |
|---|---|---|
| Standard transition parity | Pass with observation | Circ, Cubic, Elastic, Expo, Quart, and Quint showed slight start jitter relative to Tween. Legacy showed the same behavior, so this is recorded as a harness/timing investigation rather than a Native release blocker. |
| Deterministic modes and transforms | Pass | No follow-up from this run. |
| Custom editing and ownership | Pass for reported workflows; new selector restart check pending | The reported graph/list selection, live restart, preset/function preview, topology, and stale-point issues are resolved. Automated coverage includes deferred drags, endpoint takeover, detached-point disconnection, identity-preserving Undo/Redo, one publication per commit, all five new-point handle defaults, compact Native property selection/copy/paste, cross-backend clipboard values, and stale-row lifecycle cancellation. |
| Preset editing and persistence | Pass for reported workflows; full restart persistence check pending | Constant, Linear, Sine, Quad, Cubic, Quart, Quint, Expo, Circ, and Back use canonical legacy geometry, retain Transition/Ease identity while edited, show modified/reset state, save overrides, and normalize clean saves. |
| Save, reload, and coexistence | Automated pass | Modified Native presets and Custom curves round-trip; clean presets omit redundant geometry; both public APIs continue to work independently. |
| Native resource preview/icon | Pass | Generated Native Inspector previews and the `Curve.svg` FileSystem class icon both passed manual verification. |
| Match Tween timing probe | Deferred | The probe remains available for a later jitter investigation. |
| Web export with Native resource | Prior automated pass; local rerun limited | Both local exports succeeded, but Chrome could not start in the current sandbox because crashpad access was denied. The latest hosted attempt hit a Windows setup-Godot CRC infrastructure failure before checkout. The repository-side extensionless-link fix now copies the resolved executable to a validated `.exe` path and still needs a hosted run. |

The original Web failure was caused by the absent wasm32 library. The validated
manifest now loads the matching non-threaded extension; no legacy substitution
is used for serialized Native resources.

## Remaining release certification

- Run the corrected Windows behavioral and Web browser-runtime jobs in GitHub
  Actions and retain the exact artifacts.
- Retain the passing automated exact-ZIP Windows dual-API and plugin-lifecycle
  evidence; test both Web export variants and the real-manifest legacy fallback.
- Manually verify visible Inspector ordering, conversion confirmation,
  saved/reloaded converted resources, lifecycle behavior, and the new-point
  preference across an editor restart.
- Record a quiet-host performance baseline. The current relative performance
  gates pass, but the historical absolute baseline is intentionally unpromoted.
- Add remaining Native platforms and complete at least one stable release cycle
  before considering any legacy deprecation proposal.

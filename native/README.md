# Native Easing Curve

`NativeEasingCurve` and `NativeEasingCurvePoint` are independent GDExtension
resources. They coexist with the GDScript `EasingCurve` and
`EasingCurvePoint` APIs; neither runtime solver delegates to the other.

The GDScript API remains the stable compatibility and fallback implementation.
It is not deprecated. A future deprecation label is conditional on full Native
runtime, editor, serialization, platform, test, and release qualification, and
would begin a compatibility period rather than remove the legacy classes.

See [PLAN.md](PLAN.md) for milestone status, the manual smoke-test checklist,
and the prioritized next implementation tranche.

## Build contract

The `godot-cpp` submodule is pinned to `godot-4.4.1-stable`. The extension
manifest accepts Godot 4.4 and later compatible engines. Build both debug and
release variants from the repository root:

```powershell
./native/build_native.ps1 -Platform windows -Target all
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

The Windows ABI fixture validates one 4.4-built DLL against Godot 4.4–4.7:

```powershell
./test/runners/run_native_compatibility_test.ps1
```

The legacy fallback fixture copies the complete GDScript addon into a project
with no GDExtension manifest or binary:

```powershell
./test/runners/run_legacy_without_native_test.ps1
```

## Resource contract

Native production resources use `format_version = 2`. Godot omits stored
properties equal to their class defaults, so an absent marker means the current
v2 default. Explicit malformed (`<= 0`), older (`1`), and future (`> 2`)
versions are retained through load, save, and runtime duplication so tools can
diagnose them. Only current-v2 resources can sample; unsupported versions return
`NAN` instead of being silently interpreted with the current solver. Call
`get_format_status()` or `is_format_supported()` before migration tooling uses
the resource. The experimental v1 Native format was never released and is not
automatically migrated.

Future bidirectional converters share the validated dictionary schema in
`curve_conversion_result.gd`. Every converted field must be classified as
`exact`, `approximated`, `baked`, or `unsupported`; the schema carries the
source/target backend IDs, optional output resource, warnings, and errors.

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

Constant, Step, Power, Physics Spring, parameterized Back/Elastic/Spring, and
reverse/invert are currently native. Arbitrary Callables can be explicitly
baked into piecewise-linear Native Bézier points; sampling never retains or
invokes the Callable. Jitter, Irregular, extended Bounce, and
the CSS modes remain reserved until their compiled representations land.
Unsupported reserved IDs are rejected rather than silently sampling as linear.

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
./test/runners/run_native_release_export_test.ps1
./native/validate_native_manifest.ps1 -Platform all
./test/runners/run_native_web_export_test.ps1 -SkipBuild
```

The runtime benchmark reports median, median absolute deviation, and raw values
for all 12 standard transitions in all four ease modes; 2-, 9-, and 65-point
custom curves in sequential, reverse, and random sampling order; mutation; and
deep runtime duplication. The editor-backend benchmark compares adapter and
direct costs for preview sampling, 65-point reads, snapshots, and
mutation-plus-recompile.
Tween is used only as a benchmark and numerical oracle. No Native sampling path
calls Tween, GDScript, or a Callable.

## Shared editor status

The production Inspector and Curve Editor now choose either the legacy or Native
backend through the shared adapter boundary. The first Native slice renders
standard and custom curves, supports point selection, exposes force-linear and
lock options, generates previews, and records toolbar changes atomically for
Undo/Redo. Native graph geometry remains read-only until the next gesture and
topology tranche; legacy editing behavior is unchanged.

## Manual smoke-test status — 2026-09-03

| Area | Result | Follow-up |
|---|---|---|
| Standard transition parity | Pass with observation | Circ, Cubic, Elastic, Expo, Quart, and Quint showed slight start jitter relative to Tween. Legacy showed the same behavior, so this is recorded as a harness/timing investigation rather than a Native release blocker. |
| Deterministic modes and transforms | Pass | No follow-up from this run. |
| Custom editing and ownership | Partial | Handle modes and ordinary point operations worked. Force-linear and point-lock controls are not exposed by the current test/editor UI. |
| Save, reload, and coexistence | Partial | Observed state round-tripped, but force-linear and locks require editor integration before manual verification is complete. |
| Web export with Native resource | Automated pass; manual rerun pending | Isolated debug and release exports loaded, sampled, and deep-copied built-in and custom Native resources in headless Chrome. Rerun the user-facing test scene before final release qualification. |

The original Web failure was caused by the absent wasm32 library. The validated
manifest now loads the matching non-threaded extension; no legacy substitution
is used for serialized Native resources.

## Remaining release work

- Run the Web build/preflight and browser-runtime jobs in GitHub Actions and
  retain their artifacts.
- Finish generated, CSS, and extended Bounce representations.
- Complete the remaining Native point-state edge cases and curve-level snapshots.
- Finish write-side graph gestures and point-list integration through the shared editor backend.
- Add optional, non-destructive bidirectional conversion.
- Build the exact dual-API release archive.
- Add remaining platforms before any legacy deprecation proposal.

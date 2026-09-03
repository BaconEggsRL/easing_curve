# Native Easing Curve

`NativeEasingCurve` and `NativeEasingCurvePoint` are independent GDExtension
resources. They coexist with the GDScript `EasingCurve` and
`EasingCurvePoint` APIs; neither runtime solver delegates to the other.

The GDScript API remains the stable compatibility and fallback implementation.
It is not deprecated. A future deprecation label is conditional on full Native
runtime, editor, serialization, platform, test, and release qualification, and
would begin a compatibility period rather than remove the legacy classes.

## Build contract

The `godot-cpp` submodule is pinned to `godot-4.4.1-stable`. The extension
manifest accepts Godot 4.4 and later compatible engines. Build both debug and
release variants from the repository root:

```powershell
./native/build_native.ps1 -Platform windows -Target all
./native/build_native.ps1 -Platform web -Target all
```

Web builds require Emscripten on `PATH`. The Web preset is non-threaded and has
Extension Support enabled.

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
v2 default; explicit non-default values are retained for migration testing.
The experimental v1 Native format was never released and is not automatically
migrated.

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
./test/runners/run_native_runtime_benchmark.ps1
./test/runners/run_native_release_export_test.ps1
```

The benchmark reports median, median absolute deviation, and raw values for all
12 standard transitions; 2-, 9-, and 65-point custom curves in sequential,
reverse, and random sampling order; mutation; and deep runtime duplication.
Tween is used only as a benchmark and numerical oracle. No Native sampling path
calls Tween, GDScript, or a Callable.

## Remaining release work

- Finish generated, CSS, and extended Bounce representations.
- Complete the remaining Native point-state edge cases and curve-level snapshots.
- Retarget the existing editor to the backend foundation and add Native Inspector/graph support.
- Add optional, non-destructive bidirectional conversion.
- Validate Web runtime/export and build the exact dual-API release archive.
- Add remaining platforms before any legacy deprecation proposal.

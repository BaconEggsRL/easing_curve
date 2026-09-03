# Native v2 spike

This directory contains the GDExtension spike source. It intentionally
registers `NativeEasingCurve` and `NativeEasingCurvePoint` so it can be loaded
beside the existing GDScript implementation without changing serialized v1
resources.

Build a Windows debug library from this directory:

```powershell
scons platform=windows target=template_debug arch=x86_64
```

The build uses the `native/godot-cpp` submodule and writes the shared library
to `addons/easing_curve/bin/`. Build products are ignored for the spike; a
release pipeline can produce and package platform binaries after the design is
validated. The build profile generates only `Resource` and the binding classes
required by godot-cpp instead of compiling the entire engine API.

Build the Windows release library with:

```powershell
scons platform=windows target=template_release arch=x86_64
```

`points` returns an isolated typed array so external in-place array mutation
cannot bypass cache invalidation. Assign a changed array back to `points`, or
use `add_point()` / `remove_point()`. Editing a point Resource in place remains
supported and recompiles the affected curve through its `changed` signal. The
curve emits both `points_changed` and `Resource.changed` for topology and nested
point edits.

Authored curves follow Godot's normal subresource model: assigning a points
array copies the array container while retaining the point Resource references.
Use `create_runtime_copy()` when playback needs an isolated snapshot; it clones
every point Resource and preserves the curve parameters and format version.

`NativeEasingCurve.FORMAT_VERSION` is the current resource contract version.
The storage-only `format_version` property preserves explicit version values
through save/load. Godot omits properties equal to their class defaults, so an
absent marker is the implicit v1 format.

The native transition and ease IDs intentionally match Godot's
`Tween.TransitionType` and `Tween.EaseType` values. `TRANS_CUSTOM` uses the
separate stable value `100`. Invalid enum assignments and non-finite numeric
inputs are rejected. Custom points are sampled in ascending x order; when
multiple points share an x coordinate, the last point in the assigned array
wins.

This freezes a different numeric layout from the pre-contract spike. Native
resources saved with the experimental transition values `2` through `4` must
be recreated or explicitly reassigned; those values are ambiguous and cannot
be migrated safely.

Run the smoke test from the project root after building:

```powershell
$env:EASING_CURVE_GODOT_PATH --headless --path . --log-file test/_temp/native_v2_smoke.log --script test/scripts/unit/native_v2_smoke_test.gd
```

Build the release DLL, export an isolated Windows project, and execute it to
load both a built-in transition and a custom Bézier Native resource:

```powershell
./test/runners/run_native_release_export_test.ps1
```

## Current result

Godot 4.7.1 on Windows, 200,000 samples per trial, median of nine alternating
trials:

| Case | Native | Comparison | Result |
| --- | ---: | ---: | ---: |
| Linear Out | 5.110 ms | Tween 9.659 ms | 1.89x faster |
| Sine Out | 5.440 ms | Tween 18.311 ms | 3.37x faster |
| Quint Out | 5.165 ms | Tween 10.998 ms | 2.13x faster |
| Quart Out | 5.143 ms | Tween 10.952 ms | 2.13x faster |
| Quad Out | 5.148 ms | Tween 9.826 ms | 1.91x faster |
| Expo Out | 6.869 ms | Tween 23.805 ms | 3.47x faster |
| Elastic Out | 8.167 ms | Tween 29.026 ms | 3.55x faster |
| Cubic Out | 5.106 ms | Tween 9.708 ms | 1.90x faster |
| Circ Out | 5.137 ms | Tween 10.163 ms | 1.98x faster |
| Bounce Out | 5.182 ms | Tween 9.661 ms | 1.86x faster |
| Back Out | 5.077 ms | Tween 9.713 ms | 1.91x faster |
| Spring Out | 7.411 ms | Tween 30.764 ms | 4.15x faster |
| Custom Bézier | 9.645 ms | GDScript 316.670 ms | 32.83x faster |

Run `test/scripts/performance/native_v2_vs_tween_benchmark.gd` to reproduce
the comparison. Tween is used only as the benchmark and equivalence oracle;
the native implementation owns its equations and Bézier solver.

## Deliberate spike limits

- Windows x86_64 binaries only in the current extension manifest.
- Point data includes position and two control handles, without v1's editor
  lock and handle-mode policies.
- The standard Tween transition set and all four ease modes are implemented;
  extended legacy functions and arbitrary Callable mode are not yet native.
- No legacy resource migration or graph editor yet.

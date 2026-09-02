# Native v2 spike

This directory contains the source-only GDExtension spike. It intentionally
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

`points` returns an isolated typed array so external in-place array mutation
cannot bypass cache invalidation. Assign a changed array back to `points`, or
use `add_point()` / `remove_point()`. Editing a point Resource in place remains
supported and recompiles the affected curve through its `changed` signal.

Run the smoke test from the project root after building:

```powershell
$env:EASING_CURVE_GODOT_PATH --headless --path . --log-file test/_temp/native_v2_smoke.log --script test/scripts/unit/native_v2_smoke_test.gd
```

## Initial result

Godot 4.7.1 on Windows, 200,000 samples per trial, median of nine alternating
trials:

| Case | Native | Comparison | Result |
| --- | ---: | ---: | ---: |
| Cubic Out | 4.886 ms | Tween 12.950 ms | 2.65x faster |
| Sine Out | 5.156 ms | Tween 21.974 ms | 4.26x faster |
| Elastic Out | 8.022 ms | Tween 32.397 ms | 4.04x faster |
| Custom Bézier | 9.497 ms | GDScript 319.684 ms | 33.66x faster |

Run `test/scripts/performance/native_v2_vs_tween_benchmark.gd` to reproduce
the comparison. Tween is used only as the benchmark and equivalence oracle;
the native implementation owns its equations and Bézier solver.

## Deliberate spike limits

- Windows x86_64 binaries only in the current extension manifest.
- Point data includes position and two control handles, without v1's editor
  lock and handle-mode policies.
- No legacy resource migration, graph editor, or arbitrary Callable mode yet.

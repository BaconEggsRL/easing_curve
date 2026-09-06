# Godot Tween / Native / Legacy benchmark comparison

Run the two upstream animation workloads with Godot Tween, NativeEasingCurve and
Legacy EasingCurve on the same machine. The baseline executes an unmodified copy
of [Godot's Tween benchmark](https://github.com/godotengine/godot-benchmarks/blob/ef3a94f131552c9c5aa040c985185de705068eda/benchmarks/animation/tween.gd),
pinned at `ef3a94f131552c9c5aa040c985185de705068eda`. This is a local comparison
using the workloads behind the [Animation / Tween graph](https://benchmarks.godotengine.org/graph/animation-tween/),
not a reproduction of that server's hardware or historical engine builds.

## Run

Use PowerShell 7 on Windows x86_64, Godot 4.7.1 and the addon's built Windows
Native DLL. No network access or upstream checkout is needed. From the repository
root:

```powershell
# Default: validate first, then three rendered trials for each of six cases.
./test/runners/run_godot_tween_comparison.ps1

# Fast deterministic checks; does not produce performance measurements.
./test/runners/run_godot_tween_comparison.ps1 -ValidateOnly

# More repetitions, or an explicit engine / renderer.
./test/runners/run_godot_tween_comparison.ps1 -RunCount 5
./test/runners/run_godot_tween_comparison.ps1 -GodotPath 'C:/path/to/Godot_console.exe' -Renderer gl_compatibility

# Optional CPU-only run: render CPU is unavailable and omitted.
./test/runners/run_godot_tween_comparison.ps1 -Headless -RunCount 3
```

The engine defaults to `EASING_CURVE_GODOT_PATH`, then the existing launcher's
local fallback. Renderer defaults to `forward_plus`; `mobile` and
`gl_compatibility` are also accepted. Run counts must be odd. The timeout is per
process (90 seconds by default), configurable with `-TimeoutSeconds`.

The default run takes at least 90 seconds of measurements plus startup/import
time. Close other games and heavy applications and use the same power settings,
engine build, renderer and display conditions for repeated comparisons. Keep
the rendered benchmark windows visible and avoid resizing or minimizing them.

The runner creates an isolated project under `test/_temp/godot-tween/<run-id>`;
it copies the current addon, without enabling its EditorPlugin. Import caches,
AppData and explicit Godot log paths stay in that temporary project. It does not
edit the development scene or the root project's `.godot/` files. Both source
directories have `.gdignore` files: these scripts are imported only in the
isolated host, where the original upstream resource paths resolve.

## Workloads

| Workload | Tween baseline | Native and Legacy variants |
| --- | --- | --- |
| 100 properties | One Tween; 100 parallel Sprite2D `position` tweeners | Same arrangement; `set_custom_interpolator(curve.sample)` |
| 1000 methods | 1000 Tweens; each calls one Sprite2D's `rotate()` | Same arrangement; a shared form of GDScript callback samples the curve and passes the increment to `rotate()` |

All six cases use the upstream icon, seed `0x60d07`, random starting positions,
1920×1080 logical viewport, five-second duration and disabled VSync. Property
targets are the viewport center. Method angles progress from 0 to 0.01 radians
**per invocation**: `rotate()` adds each angle rather than assigning rotation.
Curve variants retain one shared curve resource per workload, explicitly set to
Linear/Ease In. Upstream's default Linear transition is also identity easing.
Separate random curves or nonlinear presets would change this benchmark.

The baseline's construction order and Tween scheduling are unchanged. Native
and Legacy property variants add the resource and custom interpolator; method
variants add the same callback adapter because MethodTweener has no equivalent
custom-interpolator setter. Curve construction, Callable creation and adapter
setup are included in the respective setup times.

## Measurements and reports

Each case runs in a fresh Godot process. Case order rotates between trials. The
small local runner follows the pinned upstream manager's measurement boundaries:

- **`time` / setup ms:** elapsed time around the workload factory call; excludes
  engine startup, script loading and adding the returned node to the tree.
- **`render_cpu` / render CPU ms:** after three warmup frames, collect frames for
  five seconds; average viewport measured render CPU plus frame setup CPU time.
  These are the two metrics enabled by the upstream Tween suite.
- **`idle_max_ms` (supplemental):** highest `Performance.TIME_PROCESS` value
  observed, converted to milliseconds. Godot updates this monitor once a second
  with the previous interval's average. It includes general engine processing
  and can retain startup work after the short warmup; it is not a direct measure
  of curve sampling or one frame's maximum. Upstream Tween does not publish it.

The timing loop uses these upstream equations but does not run upstream's menu,
autoload or complete benchmark manager. The full upstream project also has
other configuration (including a default 3D environment) that this Sprite2D
host does not copy. Absolute dashboard comparisons require matching hardware,
engine build and harness conditions; use the local Tween rows as the baseline.

Results persist in `_exports/_benchmarks/godot-tween/<run-id>/`:

- `summary.md`: readable median setup/render timings and ratios to local Tween.
- `summary.csv`: median metrics, setup min/max and ratios for all six cases.
- `summary.json`: summary plus every raw trial, source commit/dirty status,
  upstream revision and copied Native DLL SHA-256.
- `run-<n>-<case>.json`: engine version/hash, CPU/GPU, renderer, logical viewport,
  physical window size, frame count, elapsed time and the benchmark's
  `category` / `name` / `results` record with upstream metric names and ms units.
- Import, semantic-validation and per-case console/engine logs.

Ratios are variant median divided by the matching Tween median; below 1 is
lower cost. These are observations, not pass/fail thresholds. Render CPU mainly
measures drawing work, so nearly identical render timings do not establish
equal easing performance. Use multiple runs and inspect variation before
interpreting small differences. Method results include GDScript adapter and
Callable dispatch overhead. The existing
[`native_v2_vs_tween_benchmark.gd`](../scripts/performance/native_v2_vs_tween_benchmark.gd)
separately measures direct sampling across transitions, custom curves and
mutations; its units/workload should not be compared to the Tween dashboard.

`-Headless` reports omit render CPU and render ratios. A headless result is not a
rendered dashboard result. Temporary hosts are retained for diagnosis; benchmark
reports are outside `test/_temp` so normal test-temp cleanup does not remove
them. Failed runs also retain partial reports and their temporary-host logs.

## Automated checks and scope

Before any measurement, the runner validates all six workloads with deterministic
Tween stepping. It checks sprite count, valid Tween count, identical texture,
seeded starting positions and every sprite's position or cumulative rotation at
five elapsed-time checkpoints, including completion. Position tolerance is
0.002 pixels; rotation tolerance is 0.000001 radians.

Missing Native support, invalid motion, parse/runtime diagnostics, timeout,
missing completion marker, incomplete capture, an incorrect logical viewport,
unexpected renderer/display mode or absent rendered timing fails the run.
The existing Windows root-certificate-store diagnostic is the only ignored
environment error; its original text stays in the logs. Native is required,
including for `-ValidateOnly`; there is no silent Legacy-only fallback.

These are separate performance checks, not part of the 23-suite correctness
manifest or a release-readiness gate. They do not validate inspector behavior,
nonlinear easing parity, Web performance or a published package. The semantic
checks are automated; visual smoothness and representative application behavior
remain separate observations.

Pinned source paths, hashes and MIT attribution are in
[`PROVENANCE.md`](../scripts/performance/godot_tween_upstream/PROVENANCE.md).

## Development verification — 2026-09-06

Tested `cfd08d6261bdf4ca2056b5e978e04ffabae8cb7c` plus these uncommitted benchmark
additions, using Godot `4.7.1.stable.official.a13da4feb` on Windows x86_64,
Ryzen 9 7950X and RTX 4070 Ti:

- Deterministic validation passed for all six workloads.
- Forward+ passed 18 measurements (three per case), with a checked 1920×1080
  logical viewport. Report: `_exports/_benchmarks/godot-tween/20260906-020556-aa85f82f/summary.md`.
- Headless passed six measurements (one per case), with render metrics omitted.
  Report: `_exports/_benchmarks/godot-tween/20260906-020855-5573bef2/summary.md`.
- A separately imported host containing Legacy but no Native extension exited 1
  with `Tween comparison requires the Native extension`, as intended.
- PowerShell parsing, new documentation links, provenance hashes and owned-file
  whitespace checks passed. The Windows certificate-store diagnostic described
  above occurred and was retained in logs.

The reports are local ignored artifacts. Mobile/Compatibility renderer runs,
other engine versions and visual playback were not validated in this record.

# Development testing

## Clear selection before transition changes (2026-09-10)

Both Inspector transition handlers now finish any pending point edit and clear
graph/control selection, the Points property highlight and Legacy's persisted
selection before changing the preset. This uses the existing selection/toolbar
updates synchronously; no delay or forced redraw was added. Undo/Redo restores
the curve while leaving selection cleared. Ease, reset and same-transition
handling are unchanged.

The gesture suite reproduces Linear plus two added points to Cubic through the
actual dropdown callbacks. It checks selection and control visibility at the
first resource-change notification, subsequent frames, Undo/Redo and Legacy
rebuilds. A pending edit remains a separate Undo action. The initial regression
produced 20 failures before the production fix; the expanded headless suite
passes 1,077 checks. All 34 correctness suites and exact-archive lifecycle/API
validation passed. After refining the capture fixture, the rendered suite passed
1,083 checks and the final headless focused run passed 1,077 checks.

Rendered Legacy/Native captures show selected-point controls absent in the first
updated frame. First and third updated-frame PNGs are byte-identical. Input is
synthetic through the real Inspector callbacks with actual Editor rendering.
The first capture attempt waited indefinitely for an idle Editor to redraw;
the fixture now reads completed frames in an isolated window. No production
rendering workaround or diagnostic allowlist change was needed. Existing
standalone rendered teardown diagnostics remain in the logs.

Evidence: `_exports/_validation/transition-selection-20260910/`. Full-suite and
archive checks used isolated working-tree snapshots; separate demo-scene edits
were preserved. The final capture-only adjustments were checked in the focused
headless and rendered runs; production code was unchanged after the full run.

## Legacy right-drag deletion regression (2026-09-10)

Deleting a Legacy point publishes a property-list refresh and rebuilds its
Inspector graph. Presentation-owned graphs previously skipped delete-gesture
storage/restoration, so the replacement graph lost the held RMB gesture after
one deletion. Native does not take this rebuild path and was already working.

Legacy contexts now share the existing delete-gesture state through their
Inspector plugin, scoped by resource. Replacement graphs restore it only while
RMB is held. Native's presentation-local behavior and standalone graph fallback
are unchanged. No state is serialized into curve resources.

The gesture-characterization suite now deletes three points through actual
Inspector callbacks, rebuilding the Legacy context between deletions. It also
checks Native deletion, release/hover behavior, isolation across Inspectors and
resources, and one Undo/Redo action per deletion. Before the fix the new case
caused nine failures, all in the Legacy path; its Native case passed. The final
gesture suite passed 963 checks, and all 34 correctness suites passed on Godot
4.7.1 with the pinned editor. Exact-archive install, dual-API behavior and plugin
lifecycle checks also passed. Logs are retained under
`_exports/_validation/legacy-rmb-20260910/`. Input is synthetic with actual
held-button state and Inspector callbacks; physical mouse interaction was not
verified. The standalone RMB test alone cannot catch this regression because it
keeps the same graph instance for the whole gesture.
The concurrent demo-scene edit was preserved; it appeared after the test/ZIP
snapshots and is not covered by these results.

## Inspector minimum width

See [Inspector minimum-width validation](INSPECTOR_MINIMUM_WIDTH.md) for the
measured hidden EditorProperty chrome allowance, horizontal-only compensation,
native height parity, and creation/rebuild checks at actual Editor scales.

## Responsive graph layout

See [graph layout validation](GRAPH_LAYOUT.md) for canonical sizing, grouped
control rows, gesture ownership tests, full-editor captures and the
pre-existing CSS-label failures in the full correctness gate.

## Fixed graph grid and reference box

See [the grid validation report](FIXED_GRAPH_GRID.md) for the shared rendering
behavior, 1,016 focused checks, 32-suite correctness results, visual comparison,
and remaining differences from the supplied references.

## DRAG-COORDS-01 — shared drag-coordinate overlay

Implemented in `EasingCurveEditor` only, using its existing drag indices and
pending-add resource. The four private helpers separate resolved coordinates,
formatting, bounded placement and direct drawing. The instance-local suppression
flag controls presentation only; it does not finish or cancel transactions.

Grid-snapping follow-up: an input-transparent foreground Control draws the
readout above graph geometry, with a theme outline (contrasting fallback when
transparent). The snap toolbar follows the bundled Godot Curve editor: toggle,
one 2–100 subdivision count for both axes (default 10), and temporary Ctrl/Cmd
snapping. Only points and pending additions snap; Bézier handles remain free.
Snapping occurs in visible graph space before existing constraints. Major grid
lines retain Godot's sparse layout even at 100 subdivisions. Preferences use
per-resource editor metadata and restore when the graph is rebuilt.

Snapping regression coverage checks both backends, Reverse/Invert combinations,
counts 2/10/100, new-point placement, free handles, Shift precedence, temporary
snapping, preference restoration and one Undo action. The focused suite passes
763 headless checks and 775 rendered checks. Evidence: `test/_temp/snapping.txt`,
`test/_temp/snapping-rendered.txt`, `test/_temp/snapping-full-correctness.txt`,
and `drag-coordinates-snapping.png` alongside the rendered fixture captures.

Follow-up: graph transforms and Autofit share a font-sized top inset, allowing
the readout to stay above top-edge points. Points-list slider drags now feed the
same readout via weak presentation references to the input and point; they never
set graph drag indices. Release, typing, field hide/exit and Points teardown clear
those references. A new graph gesture cannot inherit a dismissed list readout.

Native Linear control fields now route through Position for both mutation and
transaction completion, matching Legacy point movement and ordering. They display
Position, use its X limits, and honor stored control/position locks. This also
works when only the Points surface survives. The fix is in Inspector callbacks;
Native resource setters, serialization and binaries are unchanged. Field range
refreshes block signals to avoid turning UI synchronization into another edit.

Native Balanced/Mirrored graph drags now use the same handle-pair calculation as
Legacy, with the graph's current X/Y display scale. Balanced preserves the
opposite handle's screen-space radius; Mirrored preserves equal opposing screen
vectors. The Native backend retains the prepared scale per presentation and
publishes the resulting handle pair in one existing Native state update. This
does not add editor-scale data to resources or change Native runtime setters.
Rotation coverage compares both backends through multiple angles, wide/tall
graphs and unequal X/Y zoom. Against the previous Native backend, 40 assertions
fail; the corrected backend passes all 603 focused checks (615 rendered).

Native Position inputs now constrain both X and Y to `[0, 1]`, including Linear
control aliases. The central Native Inspector edit path also clamps Position so
non-widget edits cannot bypass the bounds. Free handle coordinates remain
unrestricted by these point limits. Ownership/list coverage passes 567 checks,
including limits, direct callback edits and Undo. Evidence is recorded in
`test/_temp/balanced-parity-before.txt`, `test/_temp/balanced-parity.txt`,
`test/_temp/position-limits.txt`, `test/_temp/balanced-rendered.txt`, and
`test/_temp/balanced-full-correctness-final.txt`.

Coordinate sources: `position`, `left_control_point`, `right_control_point`, and
the pending point's `position` are absolute curve-space values. Pending-add press
and motion already convert input into that space. Native applies Reverse/Invert
once on the way to display coordinates; Legacy's backend conversion is identity
(its resource transforms already update geometry). No C++ or resource API changes.

`easing_curve_editor_drag_coordinates_test.gd` is an Editor-host suite registered
in `run_all_tests.ps1`. It covers both backends and all Reverse/Invert combinations,
point/handle/pending gestures, constraints and modes, interruption cleanup,
formatting, pan/zoom, bounds, notification/snapshot/history invariants and
instance isolation. The ownership suite additionally checks a live readout while
the Points root exits, then dismissal on graph release. Native Autofit must settle
before asserting visible presentation.

Validation on Godot `4.7.1.stable.official.a13da4feb`, 2026-09-08:

| Check | Result |
| --- | --- |
| Fresh pre-edit baseline | All 24 suites passed |
| Focused drag-coordinate suite, headless | 763 checks passed |
| Gesture characterization | 214 checks passed |
| Position-X drag | 72 checks passed |
| Editor vertical slice | 1,053 checks passed |
| Inspector ownership | 567 checks passed |
| Rendered drag-coordinate suite | 775 checks passed |
| Final correctness runner | All 25 suites passed |

Rendered execution uses actual graph drawing in an Editor host, synthetic viewport
press/release (including release outside the graph), and light/dark theme fixtures
at 1.0 and 1.5 scale. Normal dark and enlarged light captures were visually
inspected for both backends. Focus-loss coverage sends Godot notifications; this
does not claim physical OS input, actual monitor DPI changes or a global Editor
theme-switch test. Existing standalone-host `current_window`, certificate-store
and exit-allocation diagnostics remain in the rendered logs. No diagnostic
allowlist was broadened.

Local evidence is under `test/_temp/drag-project/test/_temp/` (focused/rendered
logs and PNGs), `test/_temp/drag-*.txt` (individual regressions), and
`test/_temp/drag-full-correctness.txt` (full runner). Direct launches used the
repository launcher, `EASING_CURVE_GODOT_PATH`, and repository-local log files.
The initial isolated import used a direct launch and emitted user-directory
permission diagnostics; subsequent checks used the launcher's isolated data path.

Follow-up logs: `test/_temp/drag-list-ownership.txt`,
`test/_temp/drag-list-gesture.txt`, `test/_temp/drag-list-rendered-final.txt`, and
`test/_temp/drag-list-full-correctness-final.txt`. The first follow-up full run
caught an Autofit mismatch after introducing the inset; centering now uses the
shared graph rectangle and a world-space delta to avoid pixel roundoff. The
rendered fixture also captures `drag-coordinates-top-inset.png` at the graph top.

## Release procedure

`release.ps1 --version 1.2.0 --mode Validate` promotes `plugin.cfg` and builds
and tests the archive; it is not a dry run. Commit documentation and script
changes before `--mode Prepare`, which accepts only plugin.cfg modifications.
Publish requires a clean release branch, the exact release version/commit and
an unused tag, checked before building and again before publication.

Packaging copies the root README/LICENSE into archive staging without rewriting
the tracked addon copies. For publication, use Native binaries downloaded from
the successful CI run for the release commit and compare their SHA-256 hashes
with that run's certified package. Publish rebuilds and validates the final ZIP.
CI also runs `run_native_release_export_test.ps1 -SkipBuild` using its Windows
artifact; omit `-SkipBuild` locally to rebuild through the pinned Native builder.

The v1.2.0 manual parity checklist is user-reported completed. Its tested commit
and archive hash were not supplied; this is distinct from automated certification
of the final release package.

## Performance comparisons

The [Godot Tween comparison](GODOT_TWEEN_BENCHMARK.md) runs the upstream
100-property and 1000-method workloads with Tween, Native and Legacy curves.
Run `./test/runners/run_godot_tween_comparison.ps1` for three rendered trials per
case, or add `-ValidateOnly` for deterministic workload checks. JSON, CSV and
Markdown reports include a local Tween baseline and pinned upstream provenance.
These six performance cases are separate from the correctness manifest.

Run `./test/runners/run_godot_benchmark_web.ps1 -Serve` to view saved results in
Godot's existing Hugo/Plotly benchmark interface, with Native, Legacy, Tween and
combined graphs. Python 3 and Hugo are required; see the
[web interface instructions](GODOT_TWEEN_BENCHMARK.md#view-results-with-godots-existing-web-interface).

## Inspector ownership

The [ownership follow-up](INSPECTOR_OWNERSHIP.md) records the graph/Points lifetime
fixes, the indexed regression suite, rendered input coverage and baseline
diagnostic comparison. Run `./test/runners/run_all_tests.ps1 --run` for all registered
correctness suites.

## v1.2.0 parity coverage audit

Audit baseline: `v1.1.0..ea7e2c6`, plus the release-preparation test/documentation
changes in this working tree. Coverage means assertions that execute, not merely
a named test function or a historical PASS. Manual sign-off is maintained in
[the paired smoke checklist](SMOKE_TEST.md).

| Behavior | Executed automated coverage | Remaining boundary |
| --- | --- | --- |
| Built-in and extended sampling | `tween_equivalence_test.gd`, `native_v2_smoke_test.gd`: Tween comparisons, configured extended modes, custom Bézier and transforms | Numeric fixtures/tolerances, not every possible parameter combination or visual playback |
| CSS and generated curves | `css_linear_test.gd`, Native smoke: valid CSS samples, persisted generated data, generated/CSS round trips | Native CSS parity uses representative strings; broader malformed-input differential coverage remains a follow-up |
| Backend topology and identity | `curve_editor_backend_contract_test.gd`: add/remove/reorder, exact point resources, invalid snapshots, plain UndoRedo transition restoration | Runtime-mode suite does not exercise the Editor history manager |
| Inspector lifetime and real history | `curve_editor_vertical_slice_test.gd`: actual Native transition dropdown, EditorUndoRedoManager, freed/replaced controls, another inspected resource, repeated Undo/Redo, external `.tres` and exported embedded `.tscn` save/reload | Physical shortcuts, real scene-tab history routing, Inspector selection navigation and remote running-game integration still require P05/P08 |
| Shared transition controls | Vertical slice: table-driven Quad, CSS Linear/Cubic Bezier, Custom, Linear, Back and Power; selected IDs, Ease/reset, Points mode, parameter metadata, modified/reset preset | Metadata/mode assertions are not screenshots; full catalog/layout/focus sweep is P01/P02 |
| Point gestures and properties | Vertical slice plus gesture, position-X, reorder, add/delete, control-editability and selection suites: simulated input, constraints, identity, reset, accepted edit/publication behavior | OS input delivery, actual hit targets, drop indicators, focus and scroll usability require P03 |
| Clipboard and conversion | Vertical slice: typed paste/invalid data, conversion report and deferred confirmation contracts; Native smoke/public contract: bidirectional conversion, ownership, Callable baking | OS clipboard branch requires display support; visible menus, confirmation/cancellation focus and source/copy navigation require P06 |
| Serialization and runtime updates | `serialization_transition_contract_test.gd`, `native_public_contract_test.gd`, Native smoke, `runtime_curve_updates_test.gd`: public surface, format versions, representative round trips and notifications | Not every API × parameter × container × history combination; real editor-to-game synchronization remains manual |
| Layout, view, preview | Vertical slice, `editor_undo_redo_test.gd`, preview and transform suites: structure, zoom routing, preview geometry and cached state | Headless FoldableContainer/responsive fixtures skipped; visible sizing, theme/DPI, folding and thumbnails require P01/P07 |
| Distribution and compatibility | Separate runners below; CI builds Windows/Web, runs Windows suites, Web runtime and package validation | Separate checks are not included in the 23-suite command; actual candidate install, disable/re-enable and browser presentation require P08/P09 |

### Gaps closed for this candidate

- Mixed-resource toolbar regression: both exported resource controls stay alive,
  both creation orders and every Ease selection are exercised with the real
  history manager. Ease reset/Trans changes must target only their own resource,
  even after a Native parse clears the inspector's current Legacy reference.
- Moved the real Editor undo-manager lifecycle regression out of the runtime-only
  backend suite into the registered Editor-host vertical slice. Previously the
  `Engine.is_editor_hint()` branch never ran in the default manifest.
- Extended the regression to dropdown signals, reopened UI selection, external
  and embedded persistence, and isolation from a subsequently inspected resource.
- Added shared transition-control assertions, including CSS Ease disabling and
  restoring Ease when returning to/resetting Quad.
- The vertical slice now fails explicitly without an Editor host or Native class.
  OS clipboard unavailability emits a SKIP marker; typed paste checks still run.

### Conditional coverage and prioritized follow-ups

1. **P1, manual now:** actual scene-tab/global-history keyboard routing, live
   editor-to-running-game transition updates, OS clipboard exchange and dialogs.
   The new regression uses real history but constructed inspector controls; it
   does not claim end-to-end physical UI coverage. Future automated UI work should
   test those routes rather than add more plain UndoRedo-only tests.
2. **P1, automatable follow-up:** extend real Editor-manager lifecycle coverage to
   parameters, generation, transforms and multiple actions across multiple scene
   histories. Ease isolation now has real-manager mixed-resource coverage; other
   existing fixtures cover portions with plain UndoRedo
   or direct mutation; that is not equivalent to the complete editor lifecycle.
3. **P2, automatable follow-up:** expand Native/Legacy malformed CSS differential
   cases, parameter boundary combinations and conversion round trips. Preserve
   current numerical tolerances; share generated points when comparing RNG modes.
4. **P2, manual now:** layout/theme/DPI, physical input, accessibility/focus,
   folding and repeated plugin lifecycle. `editor_undo_redo_test.gd` explicitly
   skips its FoldableContainer/responsive fixtures under headless Godot 4.7.
5. **Release evidence:** minimum plugin-loading compatibility, Native ABI and full
   workflow compatibility are different claims. The ABI runner defaults to
   4.4.1/4.5.1/4.6.1/4.7.1. The v1.2.0 supported minimum is 4.4.1 for both APIs;
   historical 4.4.0 Legacy results do not expand that release contract.

### Separate non-publishing release gates

Run from the repository root. `EASING_CURVE_GODOT_PATH` selects the primary engine;
the ABI runner uses its explicit version list. Direct Godot invocations must
include an absolute repository-local `--log-file` under `test/_temp`.

```powershell
./test/runners/run_all_tests.ps1 --run
./test/runners/release_workflow_contract_test.ps1
./test/runners/run_native_compatibility_test.ps1
./test/runners/run_legacy_without_native_test.ps1
./test/runners/run_native_release_export_test.ps1
./test/runners/run_native_web_export_test.ps1 -SkipBuild
./build_asset_store.ps1
./test/runners/run_release_archive_test.ps1
```

The Windows export runner builds the release DLL and needs SCons/toolchain and
installed Godot Windows export templates. Web `-SkipBuild` validates existing
debug/release WASM binaries and needs Web templates, Python and a supported
Chromium browser; omit that flag to build WASM with the configured toolchain.
Archive validation tests the exact allowlisted ZIP, not merely the checkout.
The release workflow contract mocks publishing operations; it does not publish.

Record exit codes, exact engine versions, skips, artifact hash and source state
before successful-run cleanup. Failed prerequisites are unverified, not passes.
Never promote a working-tree result to committed/archive release readiness.

### v1.2.0 execution record — 2026-09-06

Source: `ea7e2c6` plus the uncommitted parity test/documentation changes. Version
remains `1.2.0-dev`; nothing was committed, tagged or published by this work.

- Initial full runs: 22/23 suites passed; the new fixture emitted unnamed
  root-node and assertion-message formatting diagnostics despite passing its
  assertions. Fixed the fixture's root name and Array-to-string formatting;
  no product-code change or diagnostic suppression was required.
- Regression proof: in an isolated host, replacing only the editor script with
  its pre-`ea7e2c6` version caused 12/619 vertical-slice checks to fail, including
  resource restoration, reopened selection and persisted undo state.
- Focused restored-code run: **619/619** vertical-slice checks passed in the
  Editor host, including all new lifecycle/control-state checks.
- Release-workflow helper contract and Legacy-without-Native runner: **PASS**.
- Native ABI: **PASS** on stable Godot **4.4.1, 4.5.1, 4.6.1 and 4.7.1**. This is
  ABI evidence, not a new full-workflow or minimum-4.4.0 claim.
- Windows release DLL rebuild and exported built-in/custom Native resources:
  **PASS** on Godot 4.7.1.
- Non-threaded Web debug and release exports: **PASS** in the automated browser
  runner using existing WASM binaries (`-SkipBuild`). Initial sandboxed Chromium
  startup failed with Windows IPC access denied; the approved elevated retry
  passed both runtime fixtures. This is not manual browser presentation sign-off.
- Exact allowlisted `easing_curve_v1.2.0-dev.zip`: **PASS** for hashes, both APIs'
  load/sample/save/reload and plugin lifecycle. SHA-256:
  `BB879A9878627E1573D638B532B98B07531264C24EAC022AE0ECBEAAE4EA9891`.
- Full-suite closeout: **23/23 suites PASS**, runner exit **0**, **23 PASS markers**,
  **0 SCRIPT ERROR markers**, no timeouts or unexpected diagnostics. Existing
  narrowly classified engine teardown/root-certificate diagnostics remain allowed.
  Skips: OS clipboard exchange in vertical-slice/Points-list tests and visible
  FoldableContainer/responsive layout fixtures. These remain manual requirements.
- Results and the archive hash were recorded before the required successful-run
  cleanup; transient logs/isolated fixtures are removed by `--cleanup`.
- Manual P01–P09: **not performed; all sign-off boxes remain unchecked**.

### Mixed Native / Legacy toolbar follow-up — 2026-09-06

Source: `a0c1f3a` plus this inspector fix and regression. Keeping both exported
resource toolbars alive reproduced cross-resource Ease changes and the exact nil
`curve_mode` error before the fix (54/771 vertical-slice assertions failed).
Callbacks now capture the owning control/editor and Legacy resource explicitly.

After the fix: **771/771** focused Editor-host checks and **23/23** full suites
passed, runner exit **0**, with no script errors or unexpected diagnostics.
Both creation orders, every Ease mode, reset, transition changes and Undo/Redo
are covered. Clipboard/layout skips remain as above. Results recorded before
successful-run cleanup. The earlier export/archive evidence predates this addon
change; rebuild/revalidate the candidate package before release. Visible manual
sign-off remains outstanding.

---

### Minimum version and Windows CI launcher follow-up — 2026-09-06

Source: `0d7b544520693e4688302ae8cb6a5f4f32317b4f` plus the uncommitted
minimum-version documentation/manifest and CI launcher changes. The minimum is
now Godot **4.4.1** for both APIs; this does not extend platform support.

The GUI-only Godot executable used by CI reproduced the missing global script
class cache failure locally before the fix. Piping the launch output makes
PowerShell wait for process completion before inspecting its exit code or
cleaning up. With that fix, the same GUI-only 4.7.1 executable passed **23/23**
suites, exit **0**. A separate delayed-exit fixture verified captured stdout and
propagation of exit **7**. Existing clipboard/layout skips still apply.

The Native compatibility runner passed on **4.4.1, 4.5.1, 4.6.1 and 4.7.1**;
Windows/Web manifest validation and the release-workflow contract also passed.
Logs were preserved under `_exports/_validation/ci-gui-*.log` and
`_exports/_validation/minimum-441-*.log` before successful-run cleanup.
The hosted workflow rerun, rebuilt candidate exports/archive and visible manual
sign-off remain outstanding. No release or merge was performed.

## GitHub build failures and release gates

Current scope: tests, bug fixes and release gates only. Feature work is frozen.

On 2026-09-10, Native builds
[34490073007](https://github.com/BaconEggsRL/easing_curve/actions/runs/34490073007)
and [34490624449](https://github.com/BaconEggsRL/easing_curve/actions/runs/34490624449)
failed in `windows-tests`: 33 of 34 suites passed, but the Undo/Redo suite
expected enum-derived `Css Cubic Bezier` / `Css Linear` labels. The Inspector
intentionally displays `cubic-bezier()` / `linear()`. The fix records those
literal expectations in the test and reports expected/actual labels on failure.
The native compilation jobs succeeded; downstream export/package jobs were
blocked by the correctness gate.

For future failures:

1. Inspect the first failing job with `gh run view <run-id> --log-failed`.
   Read the failing assertion and suite summary before changing build tooling.
   A workflow named **Native builds** can fail after compilation succeeds.
2. Trace the tested behavior and its callers. Intentional UI-label changes
   require updating independent test expectations; do not call the production
   formatter to generate expected values or remove the assertion.
3. Reproduce with the CI editor/runtime versions and the isolated full runner.
   A focused PASS is insufficient while another registered suite still fails.
4. Require zero process exit, a PASS marker and no unexpected diagnostics.
   Preserve failed logs; do not broaden diagnostic allowlists or retry a
   deterministic failure into a pass. Exit `-1073741819` (`0xC0000005`) is a
   native crash even when the log looks clean. The separately qualified fix
   for the Godot editor shutdown crash is documented in
   [tooling/godot](../../tooling/godot/README.md).

For a fresh local PowerShell 7 session, select the official runtime through
`EASING_CURVE_GODOT_PATH` (or `-GodotPath`) and install/configure the pinned editor:

```powershell
.\tooling\godot\install_editor.ps1
$pin = Get-Content .\tooling\godot\editor-pin.json -Raw | ConvertFrom-Json
$env:EASING_CURVE_EDITOR_GODOT_PATH = (Resolve-Path .\test\_temp\pinned-editor\godot-editor.exe).Path
$env:EASING_CURVE_EDITOR_GODOT_SHA256 = $pin.editor_sha256
.\test\runners\run_all_tests.ps1 --run
```

The installer writes `GITHUB_ENV` in Actions; locally the environment variables
must be set in the invoking session. Editor exports use the official template
version in `editor-pin.json`, not the patched editor's custom version string.

After correctness passes, run the existing Windows release export, Web
debug/release browser runtime and exact archive gates from
[native-build.yml](../../.github/workflows/native-build.yml). `-SkipBuild`
requires existing binaries; release certification requires artifacts from the
successful CI run for the exact release commit. Local working-tree results
do not certify a committed release or the hosted workflow. Preserve summaries
outside `test/_temp` before cleanup; cleanup also removes the downloaded editor,
so run it only after all dependent gates finish and failed evidence is retained.

Local validation on 2026-09-10, working tree based on `c1deb9102ed5710759bb5a092aab957e0fc41b47`:

- Before the fix: 33/34 suites passed; the same two label assertions failed.
- After the fix: 34/34 suites passed, including 640 Undo/Redo checks.
- All five process, runner-hardening, tooling, archive-diagnostics and release
  workflow contract scripts passed. Windows/Web manifest checks passed.
- Windows release export and Web debug/release browser runtime passed using
  existing local binaries (`-SkipBuild`) and official 4.7.1 templates.
- The working-tree ZIP passed hash/content checks, both APIs and clean-project
  enable/disable/re-enable checks. SHA256:
  `F5677E7486CDFBB5C04D78A06A02B15994888890FB475A3CEAC9C92033CFC1B3`.

Logs: `_exports/_validation/ci-fix-20260910/`. The baseline failure and older
unarchived diagnostics remain under `test/_temp`; global cleanup was not run.
Visible-only layout fixtures remain skipped in the headless suite. These are
local results, not a new CI certification, Native rebuild or published release.
A concurrent edit to `addons/easing_curve/_test_scene/test.tscn` appeared after
the isolated test project and ZIP were created. It was preserved and is not
covered by these results; validate that scene before certifying a later archive.

## Automated suites

`test/runners/run_all_tests.ps1` is the sole source of truth for the explicit
automated-suite manifest. List the current entrypoints with:

```powershell
.\test\runners\run_all_tests.ps1 --list
```

Scripts and `.uid` sidecars live under `test/scripts/unit/`; shared harnesses
live under `test/scripts/support/`. The manifest's `Editor` flag selects the
host mode. Do not infer a suite or its mode from its filename, or copy the
manifest into documentation where it can become stale.

Run an Editor-dependent test with:

```text
./test/runners/run_godot.ps1 --editor --headless --path . --script res://test/scripts/unit/<test_name>.gd
```

Plain `--headless` execution may not instantiate `EditorInspectorPlugin` and can
misleadingly report zero checks. It is not a valid result for these tests.

## Complete automated suite

Run every headless and Editor-host suite independently with:

```powershell
.\test\runners\run_all_tests.ps1 --run
```

Use PowerShell 7. The runner selects the official runtime from `-GodotPath`,
`EASING_CURVE_GODOT_PATH`, or `godot` on PATH, in that order. Editor invocations
use the checksum-verified editor configured by the tooling manifest; see the
setup below. Before running the suites, it creates
a generated project under `test/_temp/runner` containing only the Easing Curve
addon, test scripts, and test presets. The generated project enables only the
Easing Curve plugin, so root-project development plugins and autoloads cannot
affect product-test startup. An Editor import pass initializes its script-class
cache, then the runner starts each suite with `--headless` and adds `--editor`
for suites marked as requiring an Editor/Inspector host.

After the final full suite and any dependent export/archive gates pass, preserve
the validation summaries outside `test/_temp`, then run:

```powershell
.\test\runners\run_all_tests.ps1 --cleanup
```

This is the final cleanup step, not a test. It removes everything in
`test/_temp`, including the pinned editor and other runs' artifacts, while
preserving `test/_temp/.gdignore` and the directory itself. Do not run it while
another test is active or unarchived failure evidence is still needed.
Do not run cleanup after a failure, crash, timeout,
missing PASS marker, script error, or any other unexpected result; retain those
artifacts for debugging. If tests are rerun while investigating a problem, run
cleanup only after the final full suite passes.

The PowerShell runner creates a separate process and isolated `APPDATA` and
`LOCALAPPDATA` directories for every suite, and writes each child log under
`test/_temp/runner`. A suite fails if it times out, exits unsuccessfully, lacks
a PASS marker, or logs a script error. Each suite has a 60-second timeout; the
runner terminates timed-out process trees and continues with the remaining
suites. The generated project and logs are preserved after a failure and
removed after a successful run. Update checks are suppressed for headless
Editor-host tests, while the Easing Curve plugin and Inspector remain enabled
for those tests. Godot 4.7.1's exact Windows root-certificate-store diagnostic
is classified separately because it also occurs in the isolated product-only
host; other unexpected diagnostics still fail the suite.

`test/runners/run_godot.ps1` applies the same executable selection for standalone
invocations and supplies a repository-local log when one is not given.

Under Godot 4.7 `--editor --headless`, `editor_undo_redo_test.gd` skips its
`FoldableContainer` fixture because it crashes in that environment and its
responsive-layout fixtures because they require a visible Editor layout. Verify
those fixtures in a visible Editor session instead.

## Release workflow contract

Run the non-publishing PowerShell contract check with:

```powershell
.\test\runners\release_workflow_contract_test.ps1
```

This check parses `release.ps1`, verifies that Publish and Republish delegate
their shared high-risk steps to the expected helpers, and exercises validation,
annotated-tag, release-note lifecycle, and version helpers with mocked Git
responses. It does not invoke real `git push`, tag mutation, or `gh` commands.

## Test-asset ownership

Only scripts under `test/scripts/unit/` in the runner's explicit manifest are
release-gating correctness suites. The following assets are
intentionally documented by their observed repository role; none is registered
by `test/runners/run_all_tests.ps1`.

### Shared automated-test harness and fixtures

- `editor_host_test_harness.gd` is preloaded by Editor-host suites to
  require an Editor/Inspector host and create their Inspector contexts.
- `presets/legacy_pre_flat_triangle.tres` and
  `presets/legacy_flat_without_force_linear.tres` are serialization fixtures
  loaded by `serialization_transition_contract_test.gd`.
- `runners/run_godot.ps1` is the shared launcher used by the complete-suite
  runner; it is not a suite entrypoint.

### Manual regression fixture

- `test_foldable_container.tscn` is a native `FoldableContainer` scene for
  visible-Editor layout/focus checking. It is not safe to validate under
  `--editor --headless`; use the visible-Editor checklist in
  `docs/_test_plans/_archive/v1.0.5/easing_curve_editor_visible_regression_checklist.md`.

### Exploratory/development utilities

- `export_array_resource.gd`, `export_array_test.gd`, and
  `export_array_test.tscn` are an Inspector/exported-array experiment with a
  reloadable scene.
- `elastic_func.gd` and `elastic_func.tscn` are an interactive elastic-easing
  preview.
- `rand_test.gd` and `rand_test.tscn` print deterministic global and local RNG
  sequences.
- `test_force_linear.gd` and `test_force_linear.tscn` are a manually launched
  Force Linear persistence/snapshot experiment; its snapshot branch is
  currently disabled in the script. `presets/test_force_linear_persistence.tres`
  is its associated saved-resource fixture.

### Historical or uncertain assets

- `foo.gd` is an unreferenced tool `Resource` experiment for propagating
  `EasingCurvePoint` changes. Its current consumer and retention purpose are
  unclassified.
- `anim_test.tscn` loads `presets/_TestAnimation.res` into an `AnimationPlayer`,
  but neither asset is referenced by a registered suite. Their intended manual
  regression or development purpose is uncertain.
- The `.uid` files beside test scripts are Godot script identifiers, not
  independent test entrypoints.

# Feature development

---

## Add a new EasingCurvePoint property

There are two categories of point properties:

* **Ordinary properties** use the generic descriptor-backed storage, Inspector, and
  snapshot lifecycle.
* **Semantic / geometry-affecting properties** use explicit snapshot and behavior
  handling where generic restoration is not sufficient.

Every point-property definition must explicitly declare its snapshot lifecycle:

```gdscript
"snapshot_lifecycle": POINT_SNAPSHOT_LIFECYCLE_ORDINARY,
```

or:

```gdscript
"snapshot_lifecycle": POINT_SNAPSHOT_LIFECYCLE_SEMANTIC,
```

Do not omit `snapshot_lifecycle`. Making the lifecycle explicit prevents a missing
field from silently determining how a property is handled.

### Descriptor key order

Keep descriptor keys in this relative order:

```text
name
type
default
inspector_label
inspector_visible
resettable
copy_paste_enabled
editor_kind
snapshot_key
snapshot_lifecycle
```

Keys that do not apply may be omitted, but preserve the relative order of the
remaining keys.

For example:

```gdscript
{
	"name": &"example_value",
	"type": TYPE_VECTOR2,
	"default": Vector2.ZERO,
	"inspector_label": "Example Value",
	"inspector_visible": true,
	"resettable": true,
	"copy_paste_enabled": true,
	"editor_kind": POINT_EDITOR_KIND_VECTOR2,
	"snapshot_key": &"example_values",
	"snapshot_lifecycle": POINT_SNAPSHOT_LIFECYCLE_ORDINARY,
},
```

### Ordinary property

Use this path for a bool, a non-geometry enum, a Vector2 used only as data, or
another option with no graph, transform, or point-geometry semantics.

> **Important:** None of the existing built-in point properties currently uses the
> ordinary snapshot lifecycle. Position, control points, Handle Mode, locks, and
> Force Linear all have special semantic handling and are explicitly marked
> `POINT_SNAPSHOT_LIFECYCLE_SEMANTIC`.
>
> A new ordinary property must explicitly use:
>
> ```gdscript
> "snapshot_lifecycle": POINT_SNAPSHOT_LIFECYCLE_ORDINARY,
> ```
>
> This enables the generic ordinary snapshot capture, comparison, restoration,
> Inspector mutation, and point-order reversal path.

1. **Add domain state to `EasingCurvePoint`**

   Add normal state/getter/setter behavior to `scripts/runtime/point.gd`.

   The setter must store the new value before emitting `changed`.

   For example:

   ```gdscript
   var _example_value := Vector2.ZERO

   var example_value: Vector2:
   	get:
   		return _example_value
   	set(value):
   		if _example_value == value:
   			return
   		_example_value = value
   		emit_changed()
   ```

   Point Resources must not own Inspector Controls.

2. **Add one `EasingCurve.POINT_PROPERTY_DEFINITIONS` entry**

   For example:

   ```gdscript
   {
   	"name": &"example_value",
   	"type": TYPE_VECTOR2,
   	"default": Vector2.ZERO,
   	"inspector_label": "Example Value",
   	"inspector_visible": true,
   	"resettable": true,
   	"copy_paste_enabled": true,
   	"editor_kind": POINT_EDITOR_KIND_VECTOR2,
   	"snapshot_key": &"example_values",
   	"snapshot_lifecycle": POINT_SNAPSHOT_LIFECYCLE_ORDINARY,
   },
   ```

   The relevant fields are:

   * `name` — point property name.
   * `type` — Variant/storage type.
   * `default` — serialized/reset default.
   * `inspector_label` — displayed Points-list label.
   * `inspector_visible` — whether it participates in normal Points-list rows.
   * `resettable` — whether the normal reset infrastructure applies.
   * `copy_paste_enabled` — whether normal property copy/paste applies.
   * `editor_kind` — editor control category.
   * `snapshot_key` — typed point-snapshot array key.
   * `snapshot_lifecycle` — explicitly selects ordinary or semantic snapshot
     handling.

3. **Add Inspector presentation placement**

   If visible, add the property to `POINT_INSPECTOR_PROPERTY_ORDER`.

   Presentation order is intentionally separate from serialized descriptor order.

4. **Reuse an existing editor kind when possible**

   A Vector2 property should reuse `POINT_EDITOR_KIND_VECTOR2`.

   If a new UI category is needed, such as a bool checkbox, add one reusable
   editor-kind builder for that category rather than a property-specific normal-row
   implementation.

   `editor_kind` describes only the input widget. It does not imply:

   * point geometry;
   * lock support;
   * Force Linear support;
   * left/right control semantics;
   * graph interaction.

5. **Use the existing Inspector transaction path**

   Ordinary properties use the generic snapshot mutation path through
   `EasingCurve.set_point_snapshot_property_value()`.

   Do not add a separate property-specific Undo/Redo mechanism.

   With `POINT_SNAPSHOT_LIFECYCLE_ORDINARY`, the generic typed snapshot lifecycle
   handles:

   * snapshot capture;
   * snapshot comparison;
   * snapshot restoration;
   * point-order reversal;
   * ordinary Inspector mutation.

   Ordinary properties are not automatically transformed by invert.

   Reversing point order reverses the property's snapshot value order so values
   remain associated with the corresponding points; it does not transform the
   property values themselves.

6. **Add tests**

   Cover as applicable:

   * descriptor metadata;
   * storage save/load round-trip;
   * reset;
   * copy/paste;
   * snapshot capture/restore;
   * Undo/Redo;
   * reorder/reverse value alignment;
   * visible Editor behavior.

#### Ordinary property checklist

* [ ] Add point state/getter/setter
* [ ] Setter stores the supplied value before `emit_changed()`
* [ ] Add one `POINT_PROPERTY_DEFINITIONS` entry
* [ ] Add a unique `snapshot_key`
* [ ] Set `snapshot_lifecycle` to `POINT_SNAPSHOT_LIFECYCLE_ORDINARY`
* [ ] Add intentional presentation placement if visible
* [ ] Reuse or add one editor kind
* [ ] Add focused tests
* [ ] Run the complete automated suite
* [ ] Smoke-test visible Editor changes

### Semantic / geometry-affecting property

Use `POINT_SNAPSHOT_LIFECYCLE_SEMANTIC` when a property's snapshot behavior cannot
be handled correctly by the generic ordinary lifecycle.

For example, `handle_mode` is not an ordinary enum. It changes control geometry and
interacts with locks and Force Linear, so its descriptor explicitly uses:

```gdscript
"snapshot_lifecycle": POINT_SNAPSHOT_LIFECYCLE_SEMANTIC,
```

Position, left/right control points, locks, and Force Linear are also semantic
properties because their snapshot restoration or transform behavior has additional
meaning beyond storing and restoring a value.

A semantic property may additionally need:

* `EasingCurvePoint` state-transition or geometry logic;
* Inspector semantic mutation handling;
* reset consequences;
* graph rendering or interaction behavior;
* snapshot capture/restoration handling;
* snapshot restore ordering;
* reverse/invert policy;
* lock or Force Linear interactions;
* selection/reorder considerations;
* Undo/Redo characterization.

Semantic properties should remain explicit where those branches represent real
behavior.

The goal is to eliminate duplicated generic bookkeeping, not to hide geometry or
state-transition semantics inside descriptor metadata.

#### Semantic property checklist

* [ ] Add point state/getter/setter
* [ ] Add the property descriptor
* [ ] Set `snapshot_lifecycle` to `POINT_SNAPSHOT_LIFECYCLE_SEMANTIC`
* [ ] Add Inspector metadata/presentation where applicable
* [ ] Define geometry/state semantics
* [ ] Define snapshot capture/restoration behavior where generic handling is insufficient
* [ ] Define snapshot restoration ordering
* [ ] Define reverse/invert behavior
* [ ] Define graph/editor behavior
* [ ] Cover lock/Force Linear interactions where relevant
* [ ] Add Undo/Redo and characterization tests
* [ ] Run visible Editor validation

---

## Add a new function transition

For a normal parameterized function transition:

1. **Add the transition**

   * `scripts/runtime/easing_curve.gd`
   * Add `TRANS.<NEW_MODE>` to `EasingCurve.TRANS`.

2. **Add one transition definition**

   * `scripts/runtime/easing_curve.gd` → `TRANSITION_DEFINITIONS`
   * Include `mode`, `supports_ease`, `class`, `extended`, and ordered
     `parameters`. Add `generated: true` and `editor_properties` only when needed.

   ```gdscript
   TRANS.WOBBLE: {
	"mode": CurveMode.FUNCTION,
	"supports_ease": true,
	"class": EASING_LIBRARY.Wobble,
	"extended": true,
	"parameters": [&"wobble_frequency", &"wobble_strength"],
   },
   ```

3. **Add exported parameters**

   * `scripts/runtime/easing_curve.gd`
   * Add `@export` properties with ranges/defaults.
   * Setters must call `_notify_parameter_changed()`.
   * Exported defaults are automatically used by the Inspector reset infrastructure.

4. **Add easing equations**

   * Easing-equation script loaded by `easing_curve.gd`
   * Add `easeInEx()`, `easeOutEx()`, `easeInOutEx()`, and `easeOutInEx()` as needed.
   * Arguments after `t, b, c, d` must match the registry parameter order.

5. **Add Inspector presentation**

   * Add the transition to the desired `TRANSITION_PRESENTATION` group and order.
   * That table owns category/order/presentation only; Ease support comes from
     `TRANSITION_DEFINITIONS`.

6. **Add or update tests**

Everything else is automatic for normal numeric parameters: function-mode detection,
Inspector visibility, deferred editing, `sample()` arguments, defaults/reset handling,
snapshots, Undo/Redo, Callable mapping, and runtime updates.

### Special cases

* **Extra Inspector controls:** add `editor_properties` to the transition
  definition.
* **Generated internal data:** add `generated: true` to the transition definition;
  if it adds new generated state, update `_get_generated_function_snapshot()` and
  its restore/parsing helper.

A normal new function should **not** require changes to `_update_preset()`,
`_init_function()`, `sample()`, `_validate_property()`, `get_function_snapshot()`,
`set_function_snapshot()`, `DeferredParameterEditorProperty`, or
`easing_curve_editor_undo.gd`.

## SMOOTHSTEP-01 validation (2026-09-08)

Completed before CURVE-ICONS-01. Godot 4.7.1: baseline 25 suites; final 26 suites
passed, including 40,475 Smoothstep checks. Tests cover dense analytic/geometry
references, Godot Curve, transforms, bounds, symmetry, slopes, conversion,
serialization, snapshot Undo/Redo and modified/reset behavior. The vertical-slice
suite also exercises Smoothstep through the actual Native Inspector history.
All requested Windows/Web debug/release Native builds passed. Windows release,
Web debug/release browser exports and Legacy-only validation passed.
Logs: `test/_temp/smoothstep-baseline.txt`, `smoothstep-validated.txt`,
`smoothstep-build.txt`, `smoothstep-windows.txt`, `smoothstep-web-final.txt`, and
`smoothstep-legacy-final.txt`. Web browser validation required execution outside
the sandbox after sandboxed browser startup/connection failed. No diagnostic
allowlist changed. Earlier runs exposed stale catalog assertions and a test-only
UndoRedo leak; these were corrected before the final validation.

## CURVE-ICONS-01 validation (2026-09-08)

Implemented after SMOOTHSTEP-01 passed its full gate. The shared icon catalog is
keyed by transition/ease names; Native IDs resolve through the existing converter
mapping. Built-in Editor theme icons are preferred for Constant, Linear,
Smoothstep and all ease modes. The remaining mini-curves and standalone fallbacks
are original SVG artwork exported through Inkscape 1.4.4. All 22 transitions and
four ease modes have static assets. No Godot SVG artwork was copied.

Custom theme variants are cached by name, scale and light/dark appearance.
Inspector labels retain their icons when modified/reset; the demo uses static
fallbacks without calling EditorInterface. No resource is sampled or mutated to
render an icon. The demo's Tween catalog remains unchanged.

Validation: all 27 correctness suites passed; focused icon coverage passed 478
checks; Legacy-only validation passed after integration. Actual Editor popups for
both backends and dark/light, 1.0/1.5 scale artwork fixtures were rendered and
visually inspected. Light styling and enlarged scale were fixture overrides,
not a physical monitor DPI change or a full Editor restart at another scale.
Logs: `test/_temp/curve-icons-full.txt`, `curve-icons-focused.txt`,
`curve-icons-legacy.txt`, `curve-icons-rendered.txt`, `curve-icons-inkscape.txt`.
PNG evidence: `test/_temp/drag-project/test/_temp/curve-icons-*.png`.
The final two SVG refinements were reimported and checked with the focused suite
and rendered fixtures. Full-suite source code was unchanged by those refinements.

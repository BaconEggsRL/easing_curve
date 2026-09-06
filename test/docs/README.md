# Development testing

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
These six performance cases are separate from the 23-suite correctness manifest.

Run `./test/runners/run_godot_benchmark_web.ps1 -Serve` to view saved results in
Godot's existing Hugo/Plotly benchmark interface, with Native, Legacy, Tween and
combined graphs. Python 3 and Hugo are required; see the
[web interface instructions](GODOT_TWEEN_BENCHMARK.md#view-results-with-godots-existing-web-interface).

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

## Automated suites

`test/runners/run_all_tests.ps1` is the sole source of truth for the explicit
automated-suite manifest. It currently registers 23 suites: 12 headless and
11 Editor-host. Their entrypoint scripts and `.uid` sidecars live under
`test/scripts/`. Do not infer an automated suite or its mode from its filename.

### Headless suites

- `css_linear_test.gd`
- `curve_editor_backend_contract_test.gd`
- `easing_curve_editor_rmb_delete_test.gd`
- `easing_curve_manual_reorder_test.gd`
- `easing_curve_transform_test.gd`
- `easing_curve_v105_regression_test.gd`
- `native_v2_smoke_test.gd`
- `native_public_contract_test.gd`
- `runtime_curve_updates_test.gd`
- `serialization_transition_contract_test.gd`
- `test_scene_curve_backend_test.gd`
- `tween_equivalence_test.gd`

### Editor-host suites

The following suites require an Editor-host launch:

- `easing_curve_control_editability_test.gd`
- `easing_curve_preview_generator_test.gd`
- `easing_curve_editor_position_x_drag_test.gd`
- `easing_curve_linear_control_alias_test.gd`
- `easing_curve_points_list_add_editor_test.gd`
- `easing_curve_points_list_reorder_editor_test.gd`
- `easing_curve_point_state_characterization_test.gd`
- `easing_curve_selection_refresh_characterization_test.gd`
- `easing_curve_editor_gesture_characterization_test.gd`
- `curve_editor_vertical_slice_test.gd`
- `editor_undo_redo_test.gd`

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

The PowerShell runner uses `EASING_CURVE_GODOT_PATH` when set and otherwise uses
its configured Godot 4.7 console fallback. Before running the suites, it creates
a generated project under `test/_temp/runner` containing only the Easing Curve
addon, test scripts, and test presets. The generated project enables only the
Easing Curve plugin, so root-project development plugins and autoloads cannot
affect product-test startup. An Editor import pass initializes its script-class
 cache, then the runner starts the 12 compatible suites with `--headless` and adds
`--editor` only for the 11 suites that require an Editor/Inspector host.

Only after that command exits successfully with every suite passing, immediately
run:

```powershell
.\test\runners\run_all_tests.ps1 --cleanup
```

This is the required final validation step. It removes the runner's temporary
logs and artifacts from `test/_temp` while preserving `test/_temp/.gdignore`
and the directory itself. Do not run cleanup after a failure, crash, timeout,
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

`test/runners/run_godot.ps1` retains its existing behavior for standalone or
full-suite invocations, including selecting the configured Godot 4.7.1
console executable and supplying a repository-local log when one is not given.

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

Only the 23 scripts under `test/scripts/unit/` in the explicit runner manifest
above are release-gating automated suites. The following assets are
intentionally documented by their observed repository role; none is registered
by `test/runners/run_all_tests.ps1`.

### Shared automated-test harness and fixtures

- `editor_host_test_harness.gd` is preloaded by the 11 Editor-host suites to
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

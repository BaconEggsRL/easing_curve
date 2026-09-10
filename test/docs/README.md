# Development testing

Current release: **v1.2.2**. See the [release tracker](v1.2.1_CODE_TRACKER.md)
for the tested source, binaries, exact archive, results, and outstanding gates.
The [changelog](CHANGELOG.md) supplies release notes. The
[paired smoke checklist](SMOKE_TEST.md) covers visible/manual behavior.

## Engine setup

Run commands from the repository root in PowerShell 7. Select the official
Godot runtime with `EASING_CURVE_GODOT_PATH` or `-GodotPath`. Project development
targets 4.7; release validation uses official 4.7.1 runtime/export templates and
the checksum-pinned editor described in [tooling](../../tooling/godot/README.md).

```powershell
./tooling/godot/install_editor.ps1
$pin = Get-Content ./tooling/godot/editor-pin.json -Raw | ConvertFrom-Json
$env:EASING_CURVE_EDITOR_GODOT_PATH = (Resolve-Path ./.cache/godot/pinned-editor/godot-editor.exe).Path
$env:EASING_CURVE_EDITOR_GODOT_SHA256 = $pin.editor_sha256
```

The pinned editor is for editor invocations. Runtime and export templates retain
their official identity. Direct Godot launches must use an absolute repository-
local `--log-file` under `test/_temp/`; the shared launcher supplies one if omitted.
Use isolated projects so imports cannot rewrite development fixtures or involve
unrelated addons. Never manually edit `.godot/` files.

## Correctness and runner contracts

`test/runners/run_all_tests.ps1` is the single suite/host-mode manifest:

```powershell
./test/runners/run_all_tests.ps1 --list
./test/runners/run_all_tests.ps1 --run
./test/runners/godot_process_contract_test.ps1
./test/runners/runner_hardening_test.ps1
./tooling/godot/tooling_contract_test.ps1
./test/runners/release_archive_diagnostics_test.ps1
./test/runners/release_workflow_contract_test.ps1
```

The complete runner copies the addon, scripts, and fixtures into a unique
`test/_temp/runner/isolated-project-*` host. Every suite must finish within its
timeout, exit zero, emit PASS, and have no script error or unexpected diagnostic.
Known certificate-store and editor teardown diagnostics are narrowly recorded
by the runner. Never widen allowlists or retry a deterministic failure into PASS.
Inspect signed native exit status even when assertions printed PASS.

Headless skips include rendering, responsive native controls, and OS clipboard
exchange. A successful headless run does not sign off those behaviors.
The release contract script mocks Git/GitHub mutations and does not publish.

## Build, compatibility, export, and package gates

```powershell
./native/build_native.ps1 -Platform windows -Target template_release
./native/build_native.ps1 -Platform web -Target all
./native/validate_native_manifest.ps1 -Platform all
./test/runners/run_native_compatibility_test.ps1
./test/runners/run_legacy_without_native_test.ps1
./test/runners/run_native_release_export_test.ps1 -SkipBuild
./test/runners/run_native_web_export_test.ps1 -SkipBuild
./build_asset_store.ps1
./test/runners/run_release_archive_test.ps1
```

The ABI runner defaults to locally installed 4.4.1/4.5.1/4.6.1/4.7.1 executables;
use `-GodotPaths` for other locations. ABI sampling does not establish Inspector
compatibility: validate the extracted package with the minimum 4.4.1 editor too.
Windows/Web exports require official templates. Web additionally requires
Emscripten 3.1.62 for building, Python, and a Chromium browser for runtime checks.
`-SkipBuild` is appropriate only after the candidate binaries have been built.
Record provenance; local build success does not certify a hosted CI artifact.

Packaging uses `release/addon_files.txt`, copies the root README/LICENSE into
staging, and records metadata and binary hashes. Keep the tracked addon README
and LICENSE synchronized as well. Source archives omit ignored Native binaries;
the packaged ZIP is the complete dual-API download.

## Rendered and manual checks

```powershell
./test/runners/run_curve_editor_layout_validation.ps1
./test/runners/run_curve_editor_layout_validation.ps1 -Suite easing_curve_editor_gesture_characterization_test
./test/runners/run_curve_editor_layout_validation.ps1 -Suite easing_curve_editor_drag_coordinates_test
```

These reuse existing suites in isolated full-editor hosts and remove passing
hosts. To inspect captures, pass `-EvidenceDirectory _exports/_validation/layout`
to save only the requested logs/captures outside temp before host cleanup. They exercise rendered controls and synthetic viewport
input, not physical mouse/keyboard routing, monitor DPI changes, global theme
switches, or an editor-to-running-game session. Finish the paired checklist for
those cases, conversion dialogs, clipboard, and restart persistence. Record any
unavailable operation as unverified rather than checking its box.

## Release procedure and evidence

`./release.ps1 --version 1.2.2 --mode Validate` changes the plugin version,
builds the ZIP, and runs clean-install/archive tests. It is not a dry run.
It does not commit, tag, push, or publish. Prepare commits the version change;
Publish/Republish mutate remote releases and require separate authorization.

Save command output and summaries under `_exports/_validation/v1.2.2/` before
cleanup. Record source commit/dirty state, executable identities, build commands,
binary/archive SHA-256, exits, diagnostics, and skips in the tracker. Passing tests remove their temporary data; redirect console output or explicitly
export needed evidence outside temp. Preserve failed runs only while they need
investigation, then remove them after resolution. `test/_temp` is not a tool cache
or an evidence archive. The pinned editor lives in `.cache/godot/pinned-editor`.
Do not run `--cleanup` while any gate is active or failed evidence is needed. Never equate working-tree results
with committed-source, exact-archive, or hosted CI certification.

## Test assets and supporting documentation

- Registered correctness suites live in `test/scripts/unit/`; host helpers live
  in `test/scripts/support/`. Old version names describe retained regressions.
- Export/ABI/fallback entrypoints live in `test/scripts/integration/` and are
  driven by the separate runners above.
- Serialization fixtures live in `test/presets/native/contracts/`, including
  `legacy_pre_flat_triangle.tres`, `legacy_flat_without_force_linear.tres`, and
  `test_force_linear_persistence.tres`.
- `test/user/anim_test.tscn` references `test/presets/anim/test.res`.
  `test/user/` contains exploratory scenes/scripts, not correctness gates;
  preserve them unless a concrete consumer defect warrants a change.
- Performance runners and their Python/web adapters are optional diagnostics;
  see [benchmark instructions](_archive/v1.2.1/GODOT_TWEEN_BENCHMARK.md). Retained numbers are
  historical observations, not candidate guarantees. Do not promote baselines
  during release documentation cleanup.
- [Graph layout](_archive/v1.2.1/GRAPH_LAYOUT.md), [grid](_archive/v1.2.1/FIXED_GRAPH_GRID.md),
  [minimum width](_archive/v1.2.1/INSPECTOR_MINIMUM_WIDTH.md), [ownership](_archive/v1.2.1/INSPECTOR_OWNERSHIP.md),
  [sampling parity](_archive/v1.2.1/native_sampling_parity.md), and
  [topology performance](_archive/v1.2.1/inspector_topology_performance.md) describe behavior and
  historical investigations. The tracker supersedes their dated results.
- [Historical development records](_archive/v1.2.1/development_history.md)
  preserve the previous testing guide. Older release archives remain historical.
- [Workflow requirements](_CODE_WORKFLOW_REQUIREMENTS.md) define the single
  release tracker convention. No separate plan/report pair is needed.

# Feature development

The recipes below describe the Legacy GDScript implementation; paths beginning
with `scripts/` are relative to `addons/easing_curve/`. They are contributor
guidance, not additional v1.2.1 scope. For a shared transition, separately update
the Native enum/implementation, backend mapping, converter, icons, demo catalog,
and parity/serialization/export tests. Append IDs; do not renumber saved values.

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

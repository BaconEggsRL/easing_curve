# Development testing

---

## Automated suites

`test/runners/run_all_tests.ps1` is the sole source of truth for the explicit
automated-suite manifest. It currently registers 18 suites: eight headless and
ten Editor-host. Their entrypoint scripts and `.uid` sidecars live under
`test/scripts/`. Do not infer an automated suite or its mode from its filename.

### Headless suites

- `css_linear_test.gd`
- `easing_curve_editor_rmb_delete_test.gd`
- `easing_curve_manual_reorder_test.gd`
- `easing_curve_transform_test.gd`
- `easing_curve_v105_regression_test.gd`
- `runtime_curve_updates_test.gd`
- `serialization_transition_contract_test.gd`
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
- `editor_undo_redo_test.gd`

Run an Editor-dependent test with:

```text
./test/runners/run_godot.ps1 --editor --headless --path . --script res://test/scripts/<test_name>.gd
```

Plain `--headless` execution may not instantiate `EditorInspectorPlugin` and can
misleadingly report zero checks. It is not a valid result for these tests.

## Complete automated suite

Run every headless and Editor-host suite independently with:

```powershell
.\test\runners\run_all_tests.ps1 --run
```

The PowerShell runner uses `EASING_CURVE_GODOT_PATH` when set and otherwise uses
its configured Godot 4.7 console fallback. It starts the 8 compatible suites
with `--headless`, and adds `--editor` only for the 10 suites that require an
Editor/Inspector host.

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

The PowerShell runner creates a separate process and isolated `APPDATA`
directory for every suite, and writes each child log
under `test/_temp/runner`. A suite fails if it times out, exits unsuccessfully,
lacks a PASS marker, or logs a script error. Each suite has a 60-second timeout;
the runner terminates timed-out process trees and continues with the remaining
suites. Update checks are suppressed for headless Editor-host tests, while the
Easing Curve plugin and Inspector remain enabled for those tests.

`test/runners/run_godot.ps1` retains its existing behavior for standalone or
full-suite invocations, including selecting the configured Godot 4.7.1
console executable and supplying a repository-local log when one is not given.

Under Godot 4.7 `--editor --headless`, `editor_undo_redo_test.gd` skips its
`FoldableContainer` fixture because it crashes in that environment and its
responsive-layout fixtures because they require a visible Editor layout. Verify
those fixtures in a visible Editor session instead.

## Test-asset ownership

Only the 18 scripts under `test/scripts/` in the explicit runner manifest
above are release-gating automated suites. The following assets are
intentionally documented by their observed repository role; none is registered
by `test/runners/run_all_tests.ps1`.

### Shared automated-test harness and fixtures

- `editor_host_test_harness.gd` is preloaded by the ten Editor-host suites to
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

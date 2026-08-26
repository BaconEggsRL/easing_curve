# Development testing
---

## Editor-host tests

The following tests require an Editor-host launch:

- `easing_curve_control_editability_test.gd`
- `easing_curve_editor_position_x_drag_test.gd`
- `easing_curve_linear_control_alias_test.gd`
- `easing_curve_points_list_reorder_editor_test.gd`
- `editor_undo_redo_test.gd`

Run an Editor-dependent test with:

```text
./test/scripts/run_godot.ps1 --editor --headless --path . --script res://test/<test_name>.gd
```

Plain `--headless` execution may not instantiate `EditorInspectorPlugin` and can
misleadingly report zero checks. It is not a valid result for these tests.

## Complete automated suite

Run every headless and Editor-host suite independently with:

```powershell
./test/scripts/run_all_tests.ps1
```

`test/scripts/run_godot.ps1` launches the configured Godot 4.7.1 console executable
with Windows native application-error dialogs suppressed for that test process
tree only. All automated Godot tests must use this wrapper; do not invoke Godot
directly for routine test validation. The wrapper supplies a unique,
sandbox-writable `--log-file` under `.godot/test_logs` unless the caller has
already supplied `--log-file`. Do not request privileged execution solely
because `user://logs` is inaccessible; only escalate if the wrapper encounters
a different sandbox restriction. It preserves Godot stdout, stderr, and exact
exit codes; a non-zero Godot exit remains a test failure. Direct Godot
execution remains valid for manual debugging. The runner returns a non-zero
exit code if any suite times out, exits unsuccessfully, lacks a PASS marker, or
logs a script error.

Under Godot 4.7 `--editor --headless`, `editor_undo_redo_test.gd` skips its
`FoldableContainer` fixture because it crashes in that environment and its
responsive-layout fixtures because they require a visible Editor layout. Verify
those fixtures in a visible Editor session instead.


# Feature development

---


## Add a new EasingCurvePoint property

There are two categories of point properties.

### Ordinary property

Use this path for a bool, a non-geometry enum, or another option with no graph,
transform, or point-geometry semantics.

1. Add normal state/getter/setter behavior to `EasingCurvePoint`. Point Resources
   must not own Inspector Controls.
2. Add one `EasingCurve.POINT_PROPERTY_DEFINITIONS` entry with `name`, `type`,
   `default`, `inspector_visible`, `resettable`, `copy_paste_enabled`,
   `inspector_label`, `editor_kind`, and `snapshot_key` as applicable. Mark an
   ordinary snapshot participant with
   `snapshot_lifecycle: EasingCurve.POINT_SNAPSHOT_LIFECYCLE_ORDINARY`.
3. If visible, add it to `POINT_INSPECTOR_PROPERTY_ORDER`. Presentation order is
   intentionally separate from serialized descriptor order.
4. Reuse an existing editor kind when possible. A new UI category needs one
   editor-kind builder, not a property-specific normal-row implementation.
5. Use the existing Inspector transaction path. Ordinary values use
   `EasingCurve.set_point_snapshot_property_value()` and the descriptor-backed
   typed snapshot lifecycle; do not create another Undo/Redo mechanism.
6. Add descriptor, storage round-trip, snapshot capture/restore, Undo/Redo, and
   visible-editor tests as applicable.

Ordinary property checklist:

- [ ] Add point state/setter
- [ ] Add one descriptor entry
- [ ] Mark ordinary snapshot lifecycle when appropriate
- [ ] Add intentional presentation placement if visible
- [ ] Reuse or add one editor kind
- [ ] Add focused tests, run the aggregate, and smoke-test UI changes

### Semantic / geometry-affecting property

`handle_mode` is not an ordinary enum: it changes control geometry and interacts
with locks and Force Linear. A property with comparable semantics may also need
explicit `EasingCurvePoint` transitions, Inspector mutation handling, reset
consequences, graph behavior, snapshot restore ordering, reverse/invert policy,
selection/reorder considerations, and Undo/Redo characterization.

These explicit branches are intentional. Do not hide real geometry semantics in
descriptor metadata.

Semantic property checklist:

- [ ] Complete ordinary-property steps where applicable
- [ ] Define geometry/state semantics and restore ordering
- [ ] Define reverse/invert and graph/editor behavior
- [ ] Cover lock/Force Linear interactions where relevant
- [ ] Add Undo/Redo and characterization tests
- [ ] Run visible Editor validation


---


## Add a new function transition

For a normal parameterized function transition:

1. **Add the transition**

   * `scripts/easing_curve.gd`
   * Add `TRANS.<NEW_MODE>` to `EasingCurve.TRANS`.

2. **Register the function**

   * `scripts/easing_curve.gd` → `FUNCTION_CLASSES`
   * Map the transition to its easing class and set `extended` for `*Ex` functions.

   ```gdscript
   TRANS.WOBBLE: {
   	"class": EASING_LIBRARY.Wobble,
   	"extended": true,
   },
   ```

3. **Add exported parameters**

   * `scripts/easing_curve.gd`
   * Add `@export` properties with ranges/defaults.
   * Setters must call `_notify_parameter_changed()`.
   * Exported defaults are automatically used by the Inspector reset infrastructure.

4. **Register parameters**

   * `scripts/easing_curve.gd` → `FUNCTION_PARAMETERS`
   * Order must match the easing-function arguments.

   ```gdscript
   TRANS.WOBBLE: [&"wobble_frequency", &"wobble_strength"],
   ```

5. **Add easing equations**

   * Easing-equation script loaded by `easing_curve.gd`
   * Add `easeInEx()`, `easeOutEx()`, `easeInOutEx()`, and `easeOutInEx()` as needed.
   * Arguments after `t, b, c, d` must match `FUNCTION_PARAMETERS` order.

Everything else is automatic for normal numeric parameters: function-mode detection, Inspector visibility, deferred editing, `sample()` arguments, defaults/reset handling, snapshots, Undo/Redo, Callable mapping, and runtime updates.

### Special cases

* **No normal Ease support:** update 'TRANSITION_PRESENTATION::supports_ease' field in `easing_curve_editor_inspector_plugin.gd`.
* **Extra Inspector controls:** register them in `FUNCTION_EDITOR_PROPERTIES`.
* **Generated internal data:** add the transition to `GENERATED_FUNCTION_TRANSITIONS`; if it adds new generated state, update `_get_generated_function_snapshot()` and its restore/parsing helper.

A normal new function should **not** require changes to `_update_preset()`, `_init_function()`, `sample()`, `_validate_property()`, `get_function_snapshot()`, `set_function_snapshot()`, `DeferredParameterEditorProperty`, or `easing_curve_editor_undo.gd`.

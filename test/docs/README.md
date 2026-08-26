# Development testing

## Editor-host tests

The following tests require an Editor-host launch:

- `easing_curve_control_editability_test.gd`
- `easing_curve_editor_position_x_drag_test.gd`
- `easing_curve_linear_control_alias_test.gd`
- `easing_curve_points_list_reorder_editor_test.gd`
- `editor_undo_redo_test.gd`

Run an Editor-dependent test with:

```text
./test/run_godot.ps1 --editor --headless --path . --script res://test/<test_name>.gd
```

Plain `--headless` execution may not instantiate `EditorInspectorPlugin` and can
misleadingly report zero checks. It is not a valid result for these tests.

## Complete automated suite

Run every headless and Editor-host suite independently with:

```powershell
./test/run_all_tests.ps1
```

`test/run_godot.ps1` launches the configured Godot 4.7.1 console executable
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


## Adding a New Function Transition

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

* **No normal Ease support:** update `_transition_supports_ease()` in `easing_curve_editor_inspector_plugin.gd`.
* **Extra Inspector controls:** register them in `FUNCTION_EDITOR_PROPERTIES`.
* **Generated internal data:** add the transition to `GENERATED_FUNCTION_TRANSITIONS`; if it adds new generated state, update `_get_generated_function_snapshot()` and its restore/parsing helper.

A normal new function should **not** require changes to `_update_preset()`, `_init_function()`, `sample()`, `_validate_property()`, `get_function_snapshot()`, `set_function_snapshot()`, `DeferredParameterEditorProperty`, or `easing_curve_editor_undo.gd`.

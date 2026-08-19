### Adding a New Function Transition

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

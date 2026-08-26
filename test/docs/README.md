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

There are two categories of point properties:

- **Ordinary properties** use the generic descriptor-backed storage, Inspector, and
  snapshot lifecycle.
- **Semantic / geometry-affecting properties** require explicit behavior in addition
  to the generic infrastructure.

### Ordinary property

Use this path for a bool, a non-geometry enum, a Vector2 used only as data, or
another option with no graph, transform, or point-geometry semantics.

> **Important:** None of the existing built-in point properties currently uses the
> ordinary snapshot lifecycle. Position, control points, Handle Mode, locks, and
> Force Linear all have special semantic handling.
>
> A new ordinary property must explicitly opt in with:
>
> ```gdscript
> "snapshot_lifecycle": POINT_SNAPSHOT_LIFECYCLE_ORDINARY,
> ```
>
> Omitting this field means the property will **not** use the generic ordinary
> snapshot capture, comparison, restoration, mutation, and point-order reversal
> path.

1. **Add domain state to `EasingCurvePoint`**

   Add normal state/getter/setter behavior to `scripts/point.gd`.

   The setter must actually store the new value before emitting `changed`.

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
   	"inspector_visible": true,
   	"resettable": true,
   	"copy_paste_enabled": true,
   	"inspector_label": "Example Value",
   	"editor_kind": POINT_EDITOR_KIND_VECTOR2,
   	"snapshot_key": &"example_values",
   	"snapshot_lifecycle": POINT_SNAPSHOT_LIFECYCLE_ORDINARY,
   },
   ```

   The relevant fields are:

   * `name` — point property name.
   * `type` — Variant/storage type.
   * `default` — serialized/reset default.
   * `inspector_visible` — whether it participates in normal Points-list rows.
   * `resettable` — whether the normal reset infrastructure applies.
   * `copy_paste_enabled` — whether normal property copy/paste applies.
   * `inspector_label` — displayed Points-list label.
   * `editor_kind` — editor control category.
   * `snapshot_key` — typed point-snapshot array key.
   * `snapshot_lifecycle` — set to `POINT_SNAPSHOT_LIFECYCLE_ORDINARY`
     for ordinary properties.

3. **Add Inspector presentation placement**

   If visible, add the property to `POINT_INSPECTOR_PROPERTY_ORDER`.

   Presentation order is intentionally separate from serialized descriptor order.

4. **Reuse an existing editor kind when possible**

   A Vector2 property should reuse `POINT_EDITOR_KIND_VECTOR2`.

   If a new UI category is needed, such as a bool checkbox, add one reusable
   editor-kind builder for that category rather than a property-specific row
   implementation.

   Editor kind describes only the input widget. It does not imply geometry, lock,
   Force Linear, or graph semantics.

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

   Ordinary properties are not automatically transformed by invert, and point-order
   reversal changes only value ordering, not the values themselves.

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
* [ ] Add `snapshot_lifecycle: POINT_SNAPSHOT_LIFECYCLE_ORDINARY`
* [ ] Add intentional presentation placement if visible
* [ ] Reuse or add one editor kind
* [ ] Add focused tests
* [ ] Run the complete automated suite
* [ ] Smoke-test visible Editor changes

### Semantic / geometry-affecting property

`handle_mode` is not an ordinary enum. It changes control geometry and interacts
with locks and Force Linear, so it intentionally uses explicit semantic code rather
than `POINT_SNAPSHOT_LIFECYCLE_ORDINARY`.

A property with comparable semantics may additionally need:

* `EasingCurvePoint` state-transition or geometry logic;
* Inspector semantic mutation handling;
* reset consequences;
* graph rendering or interaction behavior;
* snapshot restore ordering;
* reverse/invert policy;
* lock or Force Linear interactions;
* selection/reorder considerations;
* Undo/Redo characterization.

These explicit branches are intentional. The goal is to eliminate duplicated generic
bookkeeping, not to hide real geometry semantics inside descriptor metadata.

#### Semantic property checklist

* [ ] Complete ordinary-property metadata/UI steps where applicable
* [ ] Do **not** mark the property ordinary if generic restoration is insufficient
* [ ] Define geometry/state semantics
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

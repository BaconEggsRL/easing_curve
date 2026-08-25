# Easing Curve Refactor Plan

## Audit status

- Audit date: 2026-08-25.
- Baseline branch: `dev`, tracking `origin/dev`.
- Baseline commit: `5ece891` (`Update easing_curve_editor_undo.gd`).
- Baseline before this document: clean worktree; no staged or unstaged changes.
- Project engine: Godot 4.7 project configuration; baseline tests used Godot 4.7.1 stable.
- Plugin version: `1.0.6-dev`.
- Document scope: Milestone 1 only. No production code or tests were changed.

This document is the contract for later behavior-preserving refactor runs. A
future run must implement only the named milestone or sub-milestone, preserve
the compatibility boundaries below, and stop after its validation is complete.

## Executive summary

The plugin is feature-rich, well covered in several difficult runtime and
editor areas, and already uses a centralized editor snapshot for Undo/Redo.
Its most important technical debt is not simply that some files are large.
The highest-risk maintenance costs are:

1. Point handle/lock/Force Linear transition rules exist in both
   `EasingCurvePoint` and Inspector snapshot-mutation code.
2. Editor selection is represented by graph index, Inspector index, point
   resource identity, property name, live header control, and one-shot refresh
   flags whose writes are spread through several workflows.
3. Inspector edit transactions combine gesture boundaries, snapshot mutation,
   deferred notification, ordering preview, Undo/Redo, Inspector refresh, and
   selection restoration.
4. Adding a transition or parameter requires coordinated edits across enums,
   metadata tables, exports, initialization, argument construction, preset
   generation, Inspector presentation, defaults, snapshots, and tests.
5. Two automated test runners currently make the baseline less trustworthy:
   one reports a partial pass after script errors, and one never exits after a
   successful run.

The highest-value low-risk cleanup is the removal of reference-proven dead
Inspector fields/constants/debug helpers and obsolete commented-out code, plus
the elimination of identical notification branches. That cleanup must follow
test-runner repair so every later milestone starts from a trustworthy baseline.

No evidence supports a large rewrite. The existing snapshot architecture,
primitive point storage, endpoint ordering policy, Bézier solver policy, and
Godot-specific Inspector workarounds should remain intact.

# Architecture summary

## Repository and packaging map

| Area | Primary locations | Current responsibility |
| --- | --- | --- |
| Runtime resource | `addons/easing_curve/scripts/easing_curve.gd` | Curve data, exported transition parameters, preset generation, primitive point storage, snapshots, change notification, function/Bézier sampling, transforms, endpoint ordering |
| Point resource | `addons/easing_curve/scripts/point.gd` | Position, controls, locks, handle modes, Force Linear/control-state invariants, display-space handle relationships |
| Easing functions | `addons/easing_curve/scripts/easing.gd` | Analytic easing implementations, CSS parsing/sampling, generated irregular sampling |
| Graph editor | `addons/easing_curve/scripts/easing_curve_editor.gd` | Input gestures, graph drawing, pending add, drag/delete, ordering preview, point toolbar, pan/zoom, graph selection |
| Inspector | `addons/easing_curve/easing_curve_editor_inspector_plugin.gd` | Custom property parsing, Points list, foldables, property controls, selection, reset controls, graph integration, snapshot mutations, Undo/Redo initiation |
| Undo/Redo | `addons/easing_curve/scripts/easing_curve_editor_undo.gd` | Complete editor-state capture, action commit, Inspector/live-debug notification, optional editor-selection restoration |
| Plugin lifecycle | `addons/easing_curve/easing_curve_editor_plugin.gd` | Inspector registration, save handling, update checker, editor settings/menu lifecycle |
| Data/examples | `addons/easing_curve/presets/`, `addons/easing_curve/test_scene/` | Shipped preset and documented runtime example |
| Tests | `test/` and `test/docs/` | Headless runtime/graph tests, editor-host Inspector tests, manual release checklist |
| Packaging | `build_asset_store.ps1`, `.gitattributes` | Copies only `addons/easing_curve`, verifies archive root/path shape, synchronizes root README/license into addon |

The development project also contains `addons/godot_ai`, an autoload, and local
test/support material. The Asset Store build script copies only
`addons/easing_curve`, and `.gitattributes` excludes `addons/godot_ai`; no
required Easing Curve resource path found by this audit points into that
development-only addon.

## Runtime/resource model

`EasingCurve` is a `@tool Resource` and the runtime authority for curve output.
It selects between:

- Bézier mode, where editable `EasingCurvePoint` resources are sampled; and
- Function mode, where a callable from `EasingCurveEasing` receives the active
  transition parameters or generated/CSS data.

`EasingCurve.points` exposes the runtime point array, but point persistence is
implemented with dynamic primitive properties. `_get_property_list()` publishes
`_point_count` and `_point_<index>/<property>` storage fields. This avoids
depending on nested `Array[Resource]` propagation and permits resource-free
snapshots for editor/live-debug synchronization.

`EasingCurvePoint` owns geometry invariants. Handle-mode changes can collapse,
align, mirror, or link controls; locks and Force Linear can override direct
editing; point movement translates unlocked controls. Balanced handles can be
computed in display space so non-uniform graph scaling does not distort the
visual relationship.

## Point edit flow

```text
Graph gesture or Points-list input
-> EasingCurveEditor emits a point request
-> InspectorPlugin._apply_point_property_change()
-> capture complete editor state (before)
-> mutate a primitive point snapshot
-> EasingCurve.set_point_snapshot(changing = true/false)
-> update point geometry immediately
-> defer or publish points_changed / Resource.changed / property-list refresh
-> settle endpoint takeover or stable X ordering
-> capture complete editor state (after)
-> EasingCurveEditorUndo.commit_applied_action()
-> Undo/Redo writes _editor_state_snapshot
-> Inspector refreshes and selection is re-resolved
```

Continuous point/handle edits deliberately use `changing = true` so graph
geometry previews immediately while runtime restart/change signals are delayed
until the gesture boundary. Position-X editing also maintains a separate graph
order preview so the Points list is not rebuilt during a slider drag.

## Transition flow

```text
Inspector transition/ease selection
-> complete before-state capture
-> EasingCurve.trans_type/ease_type setter
-> _update_curve_mode()
-> _update_preset() or _init_function()
-> Bézier point construction or callable selection
-> parameter/default/generated-data handling
-> changed/property-list notification
-> Inspector visibility/reset state refresh
-> sample() uses baked Bézier geometry or function arguments
-> complete after-state committed to Undo/Redo
```

Bézier global transforms are baked into point snapshots. Function transforms
are applied at sample time. Applying function transforms to Bézier samples as
well would transform them twice and is forbidden.

## Selection flow

Graph selection is stored as `EasingCurveEditor.selected_index` and mirrored in
the static `_selected_index_by_curve` map so a recreated graph editor can recover
selection for the same live resource. Inspector point-property selection uses:

- `_selected_point_index` for the current list position;
- `_selected_point_resource_id` to follow the logical point after reordering;
- `_selected_point_property_name` for the selected property;
- `_selected_point_property_header` for the currently instantiated highlight;
- `_preserve_point_selection_on_refresh` to survive the next Inspector reparse.

`_capture_point_selection_state()` prefers a valid Inspector selection and
falls back to graph selection. `_restore_point_selection_state()` resolves the
resource identity against the current point order, updates Inspector state, and
mirrors the result to the graph. Selection is not part of the serialized curve
or `EDITOR_STATE_SNAPSHOT_PROPERTY`; topology actions pass selection snapshots
to the Undo helper separately.

## Undo/Redo and notification flow

`EasingCurveEditorUndo.capture_state()` returns the curve's resource-free
complete editor snapshot. `commit_applied_action()` writes that snapshot through
the synthetic `_editor_state_snapshot` property for both do and undo. With a
real `EditorUndoRedoManager`, it also invokes the parent Inspector's private
`_edit_request_change` path and emits `property_edited` so live debugging sees
the same complete state on initial edit, Undo, and Redo.

The curve coordinates notification suppression with:

- `_suppress_point_notifications` during exact snapshot restoration;
- `_point_snapshot_change_pending` and
  `_point_snapshot_property_list_pending` during draft point edits;
- `_parameter_edit_depth`, `_parameter_update_depth`, and
  `_parameter_update_change_pending` during parameter drags/generated data;
- `_applying_function_snapshot` and `_applying_editor_state_snapshot` during
  exact restoration.

These flags form an implicit state machine. Their current signal counts are
part of behavior, not an implementation detail.

## Plugin integration and lifecycle

The `EditorPlugin` registers one Inspector plugin in `_enter_tree()` and removes
it in `_exit_tree()`. It connects/disconnects resource-save and editor-settings
signals, owns an update-checker child, and removes its menu items on exit. On
saving a non-custom Bézier preset, it changes the transition to `CUSTOM` so a
later load does not regenerate preset geometry over user edits.

The update checker is editor-only, uses namespaced editor settings, and may
perform a GitHub release request when enabled. It is packaged with the addon but
does not affect runtime sampling.

# Compatibility constraints

## Public classes, enums, signals, and callable surface

The following are compatibility boundaries even when repository-wide search
finds no internal caller:

- `class_name EasingCurve`, `EasingCurvePoint`, `EasingCurveEditor`,
  `EasingCurveEditorUndo`, and `EasingCurveEasing`.
- `EasingCurve.points_changed(points)` and `range_changed`.
- `EasingCurvePoint.lock_changed(property_name, locked)`.
- Public methods and constants on those classes, including unreferenced utility
  methods such as `auto_smooth_handles()`, `generate_from_function()`,
  `derivative()`, and `printpoints()`.
- The numeric enum values below.

`EasingCurve.CurveMode`: `BEZIER = 0`, `FUNCTION = 1`.

`EasingCurve.EASE`: `IN = 0`, `OUT = 1`, `IN_OUT = 2`, `OUT_IN = 3`.

`EasingCurve.TRANS`:

| Value | Transition | Value | Transition |
| ---: | --- | ---: | --- |
| 0 | `CUSTOM` | 11 | `EXPO` |
| 1 | `CONSTANT` | 12 | `CIRC` |
| 2 | `LINEAR` | 13 | `BACK` |
| 3 | `JITTER` | 14 | `ELASTIC` |
| 4 | `IRREGULAR` | 15 | `BOUNCE` |
| 5 | `STEP` | 16 | `SPRING` |
| 6 | `POWER` | 17 | `PHYSICS_SPRING` |
| 7 | `QUAD` | 18 | `CSS_LINEAR` |
| 8 | `CUBIC` | 19 | `SINE` |
| 9 | `QUART` | 20 | `CSS_CUBIC_BEZIER` |
| 10 | `QUINT` |  |  |

`EasingCurvePoint.HandleMode`: `FREE = 0`, `LINEAR = 1`, `BALANCED = 2`,
`MIRRORED = 3`, `LINKED = 4`.

`EasingCurvePoint.ControlState`: `FREE = 0`, `LINEAR = 1`, `LOCKED = 2`.

New enum entries must append without renumbering existing serialized values.

## Exported properties and defaults

Do not rename, retype, remove, regroup in storage, or change these defaults:

| Property | Default |
| --- | --- |
| `ease_type` | `EASE.IN` |
| `trans_type` | `TRANS.LINEAR` |
| `constant_value` | `0.5` |
| `overshoot` | `1.70158` |
| `num_points` | `3` |
| `randomness` | `3.5` |
| `steps` | `4` |
| `from_start` | `false` |
| `y_offset` | `0.0` |
| `power` | `2.0` |
| `amplitude` | `1.0` |
| `period` | `0.3` |
| `num_bounces` | `3` |
| `bounce_damping` | `75.0` |
| `frequency` | `2.5` |
| `decay` | `2.2` |
| `stiffness` | `100.0` |
| `damping` | `10.0` |
| `mass` | `1.0` |
| `velocity` | `0.0` |
| `css_linear` | `"linear(0, 1)"` |
| `css_cubic_bezier` | `"cubic-bezier(0.25, 0.1, 0.25, 1)"` |
| `reverse`, `invert` | `false` |

Point exports and defaults are `position = Vector2.ZERO`, both controls at the
point position after initialization, `handle_mode = FREE`, both Force Linear
flags `false`, and all three lock entries `false`.

## Serialized resource format

The current point storage schema is:

```text
_point_count
_point_<index>/position
_point_<index>/left_control_point
_point_<index>/right_control_point
_point_<index>/locked
_point_<index>/handle_mode
_point_<index>/left_force_linear
_point_<index>/right_force_linear
```

The order and names in `POINT_PROPERTIES`, default handling for absent newer
fields, generated irregular arrays, CSS parsed-data fields, and custom resource
metadata are compatibility-sensitive. `points` remains editor-visible but is
not the current storage representation.

## Snapshot contracts

Point snapshot keys:

```text
positions
left_control_points
right_control_points
handle_modes
locks
left_force_linear
right_force_linear
changing                 # optional transaction flag
```

Function snapshot keys include every entry derived from
`FUNCTION_PARAMETERS`, plus `generated_points_x`, `generated_points_y`, and the
optional `force_notify` control flag.

Complete editor snapshot keys:

```text
ease_type
trans_type
curve_mode
from_start
reverse
invert
bezier_parameter_snapshot
point_snapshot
function_snapshot
```

The three snapshot properties are editor bridges and must not become serialized
resource fields or contain `Resource` objects.

## Sampling and topology behavior

The following results are frozen unless a separately approved behavior change
is made:

- `sample()` clamps input to `[0, 1]`.
- Fewer than two Bézier points use the `0.0` fallback.
- Missing endpoint ranges use the same fallback and the graph displays it.
- Interior equal-X points remain present and stable; only occupied `x = 0` or
  `x = 1` uses active-point endpoint takeover.
- Point ordering uses the current epsilon bucket and stable original index.
- Near-zero-width segments deterministically select the later point at that X.
- Effective segment controls clamp/collapse X for evaluation without mutating
  stored handles.
- Multiple X roots use the first monotonic interval; Newton and binary search
  are fallbacks with their current tolerances/iteration counts.
- Preset geometry coefficients and Tween-equivalence error limits are fixed.
- Bézier reverse/invert transforms geometry; function reverse/invert transforms
  sampling.

## Editor behavior

Preserve gesture boundaries, one-action Undo behavior, notification counts,
selection restoration, point identity across reordering, pending-add/RMB
interlocks, endpoint preview semantics, X-slot swap semantics for manual list
reordering, property copy/paste paths, reset-button focus/layout, fold state,
pan/zoom focus behavior, and live-runtime synchronization.

## Supported Godot range and portability

The README advertises Godot 4.4.0 as the verified loading minimum and Godot
4.7.1 for the full workflow. Preserve the compatibility guards:

- runtime discovery of `FoldableContainer` with a fallback section;
- `has_method("set_deferred_drag_mode_enabled")` before the Godot 4.7 API;
- portable `res://addons/easing_curve/...` paths;
- self-contained archive contents under `addons/easing_curve/`.

# Test baseline

## Commands and environment

The baseline used:

```text
C:\Godot\4.7\engine\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe
```

Runtime/graph tests used:

```text
godot --headless --path . --script res://test/<test>.gd
```

Inspector-dependent tests used:

```text
godot --editor --headless --path . --script res://test/<test>.gd
```

## Self-contained headless results

| Test | Result |
| --- | --- |
| `css_linear_test.gd` | PASS — 86 checks |
| `easing_curve_editor_rmb_delete_test.gd` | PASS — 20 checks |
| `easing_curve_manual_reorder_test.gd` | PASS — 75 checks |
| `easing_curve_transform_test.gd` | PASS — 498 checks; exits with code 0 |
| `easing_curve_v105_regression_test.gd` | PASS — 1,056 checks |
| `runtime_curve_updates_test.gd` | PASS — 1,039 checks |
| `tween_equivalence_test.gd` | PASS — 36 Bézier approximation and 48 analytic reference checks |

## Editor-host results

| Test | Result |
| --- | --- |
| `easing_curve_control_editability_test.gd` | PASS — 15 checks |
| `easing_curve_editor_position_x_drag_test.gd` | PASS — 60 checks |
| `easing_curve_linear_control_alias_test.gd` | PASS — 72 checks |
| `easing_curve_points_list_add_editor_test.gd` | PASS — 80 checks |
| `easing_curve_points_list_reorder_editor_test.gd` | PASS — 45 checks; all four fixtures complete and the suite exits with code 0 |
| `editor_undo_redo_test.gd` | PASS — 505 checks; native layout fixtures skipped as documented |

Under `--editor --headless`, successful suites also reported aborted filesystem
scan and leaked RID/ObjectDB diagnostics during immediate shutdown. The observed
assertions exited with code 0, but those diagnostics are recorded separately and
must not be silently treated as either confirmed addon leaks or irrelevant
noise. A visible-editor lifecycle run is required to classify them.

## Manual baseline

`test/docs/easing_curve_v1.0.5_manual_test_plan.md` is comprehensive, but no
manual editor, save/restart, clean-project, plugin enable/disable, or packaged
archive run was performed in this Milestone 1 audit. Those checks remain
unverified.

# Technical-debt findings

## TEST-01 — Points-list reorder suite is a false-positive baseline

- **Location:** `test/easing_curve_points_list_reorder_editor_test.gd` lines
  119, 129, 164, and 169; Inspector `_create_handle_mode_property()`.
- **Category:** Missing Test Coverage / Test Harness Reliability.
- **Evidence:** Four fixtures call `_create_handle_mode_property(point, index)`;
  production requires `(point, index, property_grid)`. Godot reports script
  errors, the affected fixtures do not run, and the suite still prints PASS for
  the 13 earlier checks before hanging.
- **Why it matters:** Handle-mode reset, property-cell selection, layout, and
  copy/paste appear covered but currently are not. Later refactors could regress
  them without a failing baseline.
- **Proposed action:** Build a `GridContainer`, pass it to the helper, retrieve
  the two generated cells from that grid, and make any script error or incomplete
  fixture fail the suite. Ensure the success path exits.
- **Risk:** Low.
- **Priority:** P0 — correctness/reliability risk.
- **Required validation:** Run the suite under `--editor --headless`; require all
  four fixtures, no script errors, a complete check count, and exit code 0. Run
  the property-cell selection/copy/paste checks in a visible editor as well.

## TEST-02 — Global-transform runner does not terminate on success

- **Location:** `test/easing_curve_transform_test.gd::_init()`.
- **Category:** Test Harness Reliability / Complex Control Flow.
- **Evidence:** `quit(_failures)` is inside the failure-only `else` branch. A
  successful run prints 498 PASS checks and remains alive.
- **Why it matters:** A normal all-tests command cannot complete and may hide
  later results or be mistaken for a regression.
- **Proposed action:** Call `quit(_failures)` once after the PASS/FAIL branch.
- **Risk:** Low.
- **Priority:** P1 — high-value technical debt.
- **Required validation:** Run the test alone and in the full headless sequence;
  require the same 498 checks and exit code 0 without external termination.

## TEST-03 — Visible layout/focus and editor lifecycle remain uncharacterized

- **Location:** `test/editor_undo_redo_test.gd`, `test/docs/README.md`, manual
  release plan, Inspector `PointsFoldableSection` and responsive controls.
- **Category:** Missing Test Coverage.
- **Evidence:** Godot 4.7 headless deliberately skips `FoldableContainer` and
  responsive-layout fixtures. Headless shutdown produces scan/RID/ObjectDB
  diagnostics. The manual plan covers the missing behavior but was not executed.
- **Why it matters:** Inspector organization, focus changes, or control
  extraction can reintroduce scroll jumps, wrapping, unstable widths, or cleanup
  problems that headless assertions cannot observe.
- **Proposed action:** Add a repeatable visible-editor checklist/fixture for
  fold focus, follow-focus scroll position, narrow/wide layout, repeated
  enable/disable, and clean shutdown. Classify headless diagnostics by comparing
  a minimal editor-host fixture and a normal visible close.
- **Risk:** Medium.
- **Priority:** P1 — high-value technical debt.
- **Required validation:** Visible Godot 4.7.1 pass plus the advertised Godot
  4.4 minimum where practical; no persistent errors after normal editor close.

## SERIAL-01 — Legacy serialization coverage does not include a committed pre-flat fixture

- **Location:** `EasingCurve._get_property_list()`, `_get()`, `_set()`,
  `set_point_snapshot()`; `test/runtime_curve_updates_test.gd`; committed
  `.tres` fixtures.
- **Category:** Missing Test Coverage / Serialization Compatibility.
- **Evidence:** Current committed presets use `_point_count` and flat
  `_point_<index>/...` fields. The legacy test loads `triangle_linear.tres`, but
  that file has already been rewritten to the current format. No committed
  fixture contains the earlier `Array[Resource]` representation or a snapshot
  missing newer Force Linear arrays.
- **Why it matters:** Apparently local property-list or snapshot cleanup could
  break old resources without the present suite detecting it.
- **Proposed action:** Commit immutable fixtures produced by supported older
  releases, including pre-flat points and absent newer keys. Assert load output,
  signals, sampling, and current-format save/reload without modifying the source
  fixtures in place.
- **Risk:** Medium.
- **Priority:** P1 — high-value technical debt.
- **Required validation:** Load fixtures with cache ignored, compare complete
  point/function state and representative samples, save to temporary paths,
  reload, and compare again.

## INSPECTOR-01 — Inspector plugin has divergent responsibilities

- **Location:** Entire `easing_curve_editor_inspector_plugin.gd` (about 3,275
  lines), especially nested editor properties/containers and top-level parse,
  selection, UI construction, mutation, and transaction functions.
- **Category:** Large Class / Divergent Change / Organization.
- **Evidence:** One script owns property parsing, clipboard/path menus, deferred
  parameter editors, generate controls, drag/drop, foldables, Points-list layout,
  graph setup, selection, point-state snapshot rules, Undo/Redo, and preset UI.
- **Why it matters:** Unrelated changes share a large review surface and natural
  responsibility boundaries are obscured. Size alone is not the problem; mixed
  reasons to change are.
- **Proposed action:** First group related functions and split local
  multi-responsibility methods without moving files. Reassess extraction only
  after selection and transaction dependencies are simpler.
- **Risk:** Medium.
- **Priority:** P1 — high-value technical debt.
- **Required validation:** All editor-host suites; visible Points/Curve Editor
  layout, fold, focus, selection, reset, drag/drop, and copy/paste checklist.

## INSPECTOR-02 — `_create_vector2_property()` mixes several cohesive UI builders

- **Location:** Inspector `_create_vector2_property()` (roughly lines
  1897–2208).
- **Category:** Long Method / UI Construction / Coupling.
- **Evidence:** The method builds the selectable/reset header, value panel,
  Force Linear slot, lock button, X and Y spin sliders, editability rules,
  selection hooks, drag/focus hooks, and point-to-input bindings.
- **Why it matters:** Layout changes risk edit semantics, and behavioral changes
  risk responsive layout because both are interleaved.
- **Proposed action:** Extract small local builders for the value panel, handle
  state button, lock button, and axis input wiring. Keep orchestration and all
  callbacks in the Inspector; do not introduce a generic form framework.
- **Risk:** Medium.
- **Priority:** P1 — high-value technical debt.
- **Required validation:** Control editability, Linear alias, Points-list layout,
  property selection/copy/paste, locks, Force Linear, reset focus, and manual
  narrow/wide Inspector checks.

## POINT-STATE-01 — Point transition semantics are duplicated in editor snapshots

- **Location:** `EasingCurvePoint.set_handle_mode()`,
  `get_handles_for_mode_change()`, `_set_control_force_linear()`,
  `set_force_linear_state()`; Inspector `_set_snapshot_handle_mode()`,
  `_set_snapshot_control_state()`, and corresponding branches of
  `_apply_point_property_change()`.
- **Category:** Duplication / Shotgun Surgery / Coupling.
- **Evidence:** Both layers encode how Linked synchronizes sides, how Linear
  collapses geometry, how Force Linear and Lock win over one another, and which
  default handle is restored when a state is cleared.
- **Why it matters:** A new handle mode or state-rule change can update direct
  point behavior but not Undo/Redo/Inspector snapshot behavior, or vice versa.
- **Proposed action:** After a full state-transition matrix is characterized,
  centralize derivation of the next point-state values in one pure helper path.
  The Inspector should still apply a primitive snapshot so transaction and live
  update semantics remain unchanged.
- **Risk:** High.
- **Priority:** P1 — high-value technical debt.
- **Required validation:** Every HandleMode-to-HandleMode transition, both
  sides, Linked symmetry, Lock/Force Linear precedence, toolbar/property reset,
  exact geometry, signal counts, save/load, and repeated Undo/Redo.

## SELECTION-01 — Selection has multiple cooperating authorities

- **Location:** Inspector selection fields and `_parse_begin()`,
  `_capture_point_selection_state()`, `_restore_point_selection_state()`,
  `_select_reordered_point()`, `_select_point_property()`,
  `_reorder_position_edited_point()`; graph `selected_index` and
  `_selected_index_by_curve`.
- **Category:** State Ownership / Complex Control Flow / Coupling.
- **Evidence:** Index, resource ID, property name, live header Control, graph
  index, static per-resource cache, and one-shot preserve flag are written in
  multiple point-add/reorder/edit/reset paths. Undo topology state is passed
  separately from curve snapshots.
- **Why it matters:** A refresh or topology change can retain the right index but
  wrong logical point, retain a point but lose its selected property, or restore
  graph and list to different selections.
- **Proposed action:** Keep selection editor-only, but route all Inspector
  selection writes through a small set of helpers: resolve logical point,
  assign/clear selection, attach the current header, capture, and restore. Treat
  the resource identity plus property name as durable refresh state and the
  header Control/index as derived state. Continue mirroring the graph explicitly.
- **Risk:** High.
- **Priority:** P1 — high-value technical debt.
- **Required validation:** No selection, graph-only selection, every point
  property, refresh, reorder, endpoint takeover, add/remove before/at/after the
  selected point, nested Undo/Redo, and resource switch/reselect.

## UNDO-01 — Transaction lifecycle is repeated around a shared commit helper

- **Location:** `DeferredParameterEditorProperty`,
  `GenerateFunctionEditorProperty`, Inspector `_apply_point_property_change()`,
  `_commit_point_edit()`, `_move_point()`, `_add_point()`, `_remove_point()`,
  `_emit_curve_property()`, and reset callbacks.
- **Category:** Duplication / Complex Control Flow.
- **Evidence:** Many paths repeat capture-before, begin edit, mutate, capture
  after, finish/cancel, commit, select/refresh. Drag transactions are legitimately
  different from immediate actions, but immediate action boilerplate is also
  repeated.
- **Why it matters:** New actions can omit final notification flush, source
  property, selection restoration, or no-op cancellation.
- **Proposed action:** Preserve explicit drag boundaries. Add only narrow local
  wrappers for common immediate snapshot actions and common commit arguments;
  do not hide mutation order or build a generic transaction framework.
- **Risk:** High.
- **Priority:** P1 — high-value technical debt.
- **Required validation:** One history entry per gesture, no entry for no-op or
  canceled edits, exact signal counts, live-debug refresh, selection restoration,
  and repeated Undo/Redo for every action family.

## TRANSITION-01 — Transition registration is distributed across parallel structures

- **Location:** `EasingCurve.TRANS`, `FUNCTION_TRANSITIONS`,
  `FUNCTION_CLASSES`, `BEZIER_PARAMETERS`, `FUNCTION_PARAMETERS`,
  `NON_DEFERRED_FUNCTION_PARAMETERS`, `GENERATED_FUNCTION_TRANSITIONS`,
  `FUNCTION_EDITOR_PROPERTIES`, exports/setters, `_get_function_arguments()`,
  `_init_function()`, `_update_preset()`; Inspector `TRANSITION_GROUPS` and
  `_transition_supports_ease()`.
- **Category:** Shotgun Surgery / Parallel Data / Change Preventer.
- **Evidence:** Adding a transition or parameter requires coordinated changes in
  several tables and functions. Inspector grouping and ease support are separate
  complete/partial transition lists. Tests already protect some specific IDs and
  contracts, confirming these locations must remain synchronized.
- **Why it matters:** A missed site can yield an invisible parameter, invalid
  callable arguments, wrong mode/ease availability, incomplete snapshot, or
  incompatible enum value.
- **Proposed action:** Keep exported properties, enum IDs, public constants, and
  preset numeric code unchanged. First add a catalog contract test. Then
  consolidate only Inspector presentation metadata (group/order/ease support)
  into one authoritative editor table and derive both dropdown and ease support
  from it. Do not add a generalized transition framework merely to combine
  runtime tables that are public compatibility boundaries.
- **Risk:** Medium.
- **Priority:** P1 — high-value technical debt.
- **Required validation:** Every enum appears exactly once in the dropdown with
  the same ID/order/group; correct mode, callable, argument order, property
  visibility/default/reset, generated-data persistence, ease support, finite
  sampling, save/load, and Undo/Redo.

## RUNTIME-01 — Snapshot restoration duplicates exact point-restore sequencing

- **Location:** `EasingCurve.set_point_snapshot()` topology-preserving and
  topology-changing branches.
- **Category:** Duplication / Complex Control Flow / Serialization.
- **Evidence:** Both branches disable Force Linear, temporarily set Free, restore
  position/controls, restore handle mode, restore Force Linear without geometry,
  and normalize locks. The only fundamental difference is preserving existing
  point resource identity versus constructing new points.
- **Why it matters:** A new stored point field or invariant can be restored in
  one branch but omitted from the other. The sequence itself is delicate.
- **Proposed action:** Extract one local helper that applies parsed snapshot
  values to a supplied point. Keep separate identity/topology branches and the
  existing notification suppression around them.
- **Risk:** High.
- **Priority:** P1 — high-value technical debt.
- **Required validation:** Same-size snapshots preserve object identity;
  topology snapshots replace/create the correct objects; old/missing keys,
  every handle state, locks, transforms, signals, and save/load remain exact.

## EDITOR-01 — `_gui_input()` is a monolithic ordering-sensitive gesture state machine

- **Location:** `EasingCurveEditor._gui_input()` (roughly lines 135–456) and RMB
  state helpers.
- **Category:** Long Method / Complex Control Flow.
- **Evidence:** One method handles RMB release precedence, panning, function-mode
  guards, delete sweep, pending-add motion/cancel/commit, point/control drag,
  hover/cursors, wheel zoom, selection, and gesture completion.
- **Why it matters:** Branch order is behavioral. A locally reasonable early
  return can leave delete or drag state active and reintroduce already-fixed
  regressions.
- **Proposed action:** After gesture characterization, split into ordered private
  handlers for button-release cleanup, motion, wheel, LMB, and RMB. Keep the
  top-level dispatch order visible and documented.
- **Risk:** High.
- **Priority:** P1 — high-value technical debt.
- **Required validation:** Full RMB suite, pending add, point/control drag,
  endpoint preview, zoom-during-drag, panning, locks, function-mode input, and
  one-action commit boundaries.

## BOUNDARY-01 — Runtime resources carry editor-control/view concerns

- **Location:** `EasingCurvePoint._input_controls` and input update methods;
  `EasingCurve._last_slider_value`, `_last_zoom`, `_last_pan`, and curve-editor
  callbacks; graph direct access to `_curve._last_slider_value`.
- **Category:** Coupling / Runtime-Editor Boundary / State Ownership.
- **Evidence:** Point resources store weak references to Inspector controls in a
  static dictionary and set their read-only/value state. The curve resource
  stores non-serialized graph view state and callback entrypoints.
- **Why it matters:** Runtime data objects know editor widget APIs, and static
  instance-ID maps have lifecycle/ownership that is difficult to see.
- **Proposed action:** Review after higher-value editor cleanup. Prefer moving
  control binding/synchronization to editor code while preserving point public
  APIs and behavior. Move view state only if doing so simplifies ownership
  without losing per-resource refresh persistence.
- **Risk:** High.
- **Priority:** P2 — worthwhile cleanup.
- **Required validation:** Numeric inputs refresh without recursive edits,
  read-only state follows modes/locks after Undo/Redo, per-resource pan/zoom and
  selection survive Inspector refresh, and runtime use has no editor dependency.

## CLEANUP-01 — Several private Inspector symbols are reference-proven dead

- **Location:** Inspector `BTN_NORMAL`, field `trans_option` (shadowed by a local),
  `points_editor_property` and its never-reached preferred branch,
  `print_properties()`, unused `anchor_icon`, unused default parameters/locals in
  point Vector2 handlers.
- **Category:** Dead Code / Redundant Locals / Naming.
- **Evidence:** Repository-wide reference search finds declarations only, a
  commented debug call, or values passed only to parameters that are themselves
  unused. `curve_editor_property` is the actual Undo source.
- **Why it matters:** Dead state suggests authorities that do not exist and adds
  noise to the largest hotspot.
- **Proposed action:** Remove only the verified private symbols, update affected
  callback signatures/binds, and rerun reference searches. Do not remove public
  classes, signals, constants, or methods based solely on internal references.
- **Risk:** Low.
- **Priority:** P2 — worthwhile cleanup.
- **Required validation:** GDScript parse, Inspector creation, all editor-host
  tests, source-property Undo refresh, and zero remaining references.

## CLEANUP-02 — Obsolete commented implementations obscure useful rationale

- **Location:** Old Irregular implementation in `easing.gd`; commented debug
  calls in Inspector/editor/drag handle; commented `_init`, swap, auto-range,
  and auto-smoothing fragments.
- **Category:** Dead/Stale Code / Organization.
- **Evidence:** Multi-line inactive implementations and print calls remain next
  to current code. Separately, comments explaining effective controls, endpoint
  behavior, preset approximation, focus, and deferred commits remain current and
  valuable.
- **Why it matters:** Future cleanup cannot easily distinguish abandoned code
  from regression rationale.
- **Proposed action:** Delete inactive implementation/debug blocks. Preserve or
  improve comments that explain current behavior or Godot engine constraints.
- **Risk:** Low.
- **Priority:** P2 — worthwhile cleanup.
- **Required validation:** Parse/tests plus review that every removed line was
  inactive and every retained rationale still matches code.

## PRESET-01 — Parameter setters contain identical notification branches

- **Location:** `constant_value` and `overshoot` setters in `easing_curve.gd`.
- **Category:** Redundant Control Flow.
- **Evidence:** Each records `revision_before` and then calls
  `_notify_parameter_changed()` in both the `if` and `else` branches.
- **Why it matters:** The branch implies a behavioral distinction that does not
  exist and distracts from the real snapshot/notification sequence.
- **Proposed action:** Remove the unused revision comparison and retain one
  unconditional `_notify_parameter_changed()` at the same point.
- **Risk:** Low.
- **Priority:** P2 — worthwhile cleanup.
- **Required validation:** Back/Constant parameter drag, preset modified/reset,
  signal counts, runtime update, and Undo/Redo tests.

## PACKAGE-01 — Working tree is packaged correctly by inspection, but the archive is unverified

- **Location:** `build_asset_store.ps1`, `.gitattributes`, addon scenes/resources.
- **Category:** Packaging / Missing Validation.
- **Evidence:** The script copies only `addons/easing_curve`, checks archive paths,
  and synchronizes README/license. Resource paths found by audit are addon-local.
  The script and resulting archive were not run because Milestone 1 permits only
  `REFACTOR_PLAN.md` as a repository change and the build synchronizes files.
- **Why it matters:** UID/import portability, clean enable/disable, update-checker
  behavior, and exact archive contents cannot be proven from source inspection.
- **Proposed action:** Reserve archive build and clean-project installation for
  the final milestone, using the actual intended release archive.
- **Risk:** Medium.
- **Priority:** P2 — worthwhile cleanup/validation.
- **Required validation:** Archive inventory, README/license equality, no
  development addon/files, clean project import, plugin enable/edit/save/run,
  restart, disable, and minimum-version smoke test.

# Missing characterization tests

Milestone 2 must add or repair coverage before medium/high-risk production
refactors. Existing tests should be extended rather than replaced.

## Test-runner trust

- Repair TEST-01 and TEST-02 first.
- Make each suite fail on script errors, incomplete fixtures, or unexpected
  skips, and always terminate on both pass and fail.
- Provide one documented command that runs the complete headless and editor-host
  sets and reports each suite independently.

## Selection and refresh

- Property selection survives a property-list rebuild and reattaches the header.
- Resource identity re-resolves the correct point after index changes.
- Graph/list/property selection remain synchronized through add, remove, manual
  reorder, continuous Position-X reorder, endpoint takeover, Undo, and Redo.
- Removing the selected point and removing before/after it preserve the current
  semantics.
- No-selection and graph-only-selection states restore correctly.
- Switching between two curve resources does not leak selection or RMB state.

## Point state and gesture matrix

- Every source/destination HandleMode transition with asymmetric handle lengths.
- Balanced/Mirrored behavior under non-uniform display scale, resize, and zoom.
- Linked Lock/Force Linear precedence from both sides.
- Toolbar reset and Points-list reset equivalence for all modes/states.
- No-op, cancel, focus-transfer, and tree-exit commit behavior.
- Zoom while dragging a point/control and pending-add cancellation ordering.

## Serialization and compatibility

- Immutable fixtures from pre-flat storage and from versions lacking newer point
  fields/snapshot keys.
- Full numeric contracts for `TRANS`, `EASE`, `HandleMode`, and `ControlState`.
- Exported property names, types, defaults, usage flags, and visibility.
- Same-topology snapshot identity versus topology-changing recreation.
- CSS source/parsed data and generated irregular data across save/load and
  Undo/Redo.
- Representative resources saved by the advertised minimum Godot version.

## Transition/function contract

- Every transition appears exactly once in Inspector presentation metadata.
- Every transition selects the expected curve mode and ease availability.
- Every parameter has the expected default, visibility, reset behavior,
  deferred/immediate edit behavior, callable argument position, and snapshot
  participation.
- Every transition/ease combination samples finitely after switching, Undo/Redo,
  save/load, reverse, and invert.

## Plugin and packaging

- Repeated enable/disable lifecycle and signal/menu cleanup.
- Update-check disabled path without network dependence.
- Visible fold/focus/scroll/responsive layout checks.
- Clean-project installation of the exact release archive, import restart,
  example run, save/reload, and disable.

# Recommended Not To Refactor

## Primitive point storage and resource-free snapshots

The dynamic `_point_count` / `_point_<index>/...` format and the three primitive
snapshot bridges are unusual but intentional. They solve nested Resource change
propagation and live-debug/Undo transport. Do not replace them with serialized
editor-state resources, `Array[Resource]` snapshots, or a new format merely for
conventionality.

## Exact snapshot restoration order

Temporarily clearing Force Linear, switching to Free, restoring geometry, then
restoring mode/state without geometry is required for exact snapshots. A helper
may deduplicate this sequence, but its order must remain unchanged.

## Endpoint takeover, equal-X stability, and Bézier branch policy

Do not replace epsilon bucket ordering with a generic sort, deduplicate interior
equal-X points, clamp stored handles, or choose a different X root. These are
observable sampling/editor semantics with regression coverage.

## Preset coefficients and easing implementations

The easing equation file is large because it contains independent mathematical
implementations. The preset control coefficients include exact degree elevation
and optimized approximations with tested error budgets. Do not reorganize them
into a generalized math framework or “simplify” numeric constants.

## Inspector focus and compatibility workarounds

Keep `_native_section.focus_mode = Control.FOCUS_NONE`; it prevents the outer
Inspector's follow-focus behavior from scrolling an expanded section into view.
Keep the FoldableContainer fallback and Godot 4.7 method check. Keep deferred
drag commits where immediate focus/ungrab ordering can interrupt a gesture.

## RMB and position-order preview state

The per-resource RMB state survives an Inspector reconstruction while the
button remains held, and the order preview avoids rebuilding numeric controls
during continuous X editing. These mechanisms may be documented/centralized,
but should not be removed as “extra state.”

## Explicit Undo/Redo Inspector notifications

The `_edit_request_change` and `property_edited` calls use private/editor-specific
behavior to match native Inspector live-debug synchronization. Do not replace
them without an editor/live-debug characterization proving the same initial,
Undo, and Redo propagation.

## Similar but semantically different controls

Preset reset, parameter reset, point-property reset, and toolbar state reset
look similar but have different state, focus, geometry, and transaction rules.
Manual list reorder swaps X slots while automatic position editing reorders by X
and performs endpoint takeover. Do not unify these solely because their code
shapes resemble one another.

## Internally unreferenced public symbols

`range_changed`, `lock_changed`, `FUNCTION_TRANSITIONS`, and public utility
methods may be used by external projects. Internal reference search is not proof
that they can be removed. Any public API removal requires separate approval and
a deprecation/compatibility decision outside this behavior-preserving refactor.

# Prioritized milestone plan

## Milestone 2A — Repair the automated baseline

### Goal

Make every existing automated result trustworthy and make the full sequence
terminate without manual intervention.

### Current behavior

Completed. All 13 headless and Editor-host suites pass independently with exit
code 0, a PASS marker, and no `SCRIPT ERROR:` output.

### Exact scope

`test/easing_curve_points_list_reorder_editor_test.gd`,
`test/easing_curve_transform_test.gd`, and test-run documentation/runner only.

### Proposed changes

Repair the handle-mode fixture signature/grid, make incomplete fixtures fail,
make both success paths exit, and add a single non-rewriting suite command.

### Non-goals

No production code, behavior changes, new characterization areas, or layout
redesign.

### Validation

Run every existing headless and editor-host suite under Godot 4.7.1; require no
script errors, no hangs, and unchanged passing assertion totals except the newly
restored fixture checks.

### Completion status

Completed on 2026-08-25 under Godot 4.7.1. The aggregate runner reports all 13
suites passing; the repaired Points-list suite reports 45 checks and the
transform suite reports 498 checks. Known `--editor --headless` shutdown
diagnostics remain recorded separately above.

### Risk

Low.

### Dependencies

Milestone 1 only.

### Expected payoff

Every subsequent refactor starts from a reliable, automatable baseline.

## Milestone 2B — Add serialization and transition contract tests

### Goal

Lock down external resource compatibility and distributed transition metadata
before runtime or catalog cleanup.

### Current behavior

Current-format round trips and broad transition sampling are tested, but old
storage fixtures, full enum IDs, and the complete metadata/default contract are
not.

### Exact scope

New immutable fixtures under `test/presets/` and focused additions to runtime
contract tests. No production changes.

### Proposed changes

Add pre-flat/missing-key fixtures; assert enum values, exported schema/defaults,
snapshot keys, mode/callable/parameter contracts, and load/save/sample behavior.

### Non-goals

No serialization migration, transition metadata refactor, new transitions, or
changed defaults.

### Validation

Run new tests plus runtime updates, v1.0.5 regression, CSS, Tween equivalence,
and transform suites.

### Risk

Low.

### Dependencies

Milestone 2A.

### Expected payoff

Later cleanup cannot silently change files, enums, defaults, or sampling paths.

### Completion record

Completed. `test/serialization_transition_contract_test.gd` adds 413 passing
contract checks, backed by immutable historical pre-flat `Array[Resource]` and
flat missing-Force-Linear fixtures under `test/presets/`. The suite locks enum
IDs; exported property metadata, defaults, storage, and editor visibility;
primitive point-storage and snapshot schemas; transition registrations,
callables, parameter order, and generated-data metadata; plus load, sample,
current-format save, and reload compatibility. The aggregate baseline now
includes this suite.

## Milestone 2C — Add editor selection, point-state, and gesture characterization

### Goal

Cover the medium/high-risk Inspector, selection, handle-state, and gesture
boundaries needed by Milestones 5–7 and 9–10.

### Current behavior

Many individual workflows are covered, but property selection across refresh,
the complete handle-state matrix, display-space handles, and visible focus/layout
remain incomplete.

### Exact scope

Editor-host tests and visible-editor checklist/fixtures only.

### Proposed changes

Add the selection/refresh, handle transition, display-scale, no-op/cancel,
resource-switch, zoom-during-drag, fold/focus, and lifecycle cases listed above.

### Non-goals

No production refactor or UX change; no attempt to force unstable native layout
fixtures through Godot 4.7 headless.

### Validation

All automated suites plus a recorded visible Godot 4.7.1 pass. Run minimum 4.4
compatibility cases where the installed engine permits.

### Risk

Medium, due to editor-host fixture stability.

### Dependencies

Milestones 2A and 2B.

### Expected payoff

High-risk editor refactors gain explicit behavioral acceptance criteria.

### Completion record

Completed. The aggregate runner now registers three focused editor-host suites:
`test/easing_curve_point_state_characterization_test.gd` (93 checks),
`test/easing_curve_selection_refresh_characterization_test.gd` (35 checks),
and `test/easing_curve_editor_gesture_characterization_test.gd` (13 checks).
They characterize the full HandleMode transition matrix, display-space handle
relationships, direct and Inspector Lock/Force Linear precedence, selection
restoration through refresh/reorder/topology/resource switching, and graph
gesture state boundaries. `test/docs/easing_curve_editor_visible_regression_checklist.md`
records the remaining visible-only fold, focus, scroll, and responsive-layout
checks, including the intentional `FOCUS_NONE` workaround. Under the Codex
sandbox, the aggregate runner cannot create Godot `user://logs` files, so its
headless suites terminate before test initialization; the first affected suite
(`css_linear_test.gd`) passes with exit code 0 under the same normal invocation
when its user directory is accessible. No production addon code was changed.

## Milestone 3 — Evidence-backed dead and stale code cleanup

### Goal

Remove proven noise without changing architecture or behavior.

### Current behavior

Private unused fields/constants/helpers, redundant callback data, inactive debug
blocks, and identical notification branches remain.

### Exact scope

The private symbols in CLEANUP-01, inactive blocks in CLEANUP-02, and redundant
branches in PRESET-01.

### Proposed changes

Delete only reference-proven private code; simplify affected binds/signatures;
retain public symbols and rationale comments; rerun searches after the diff.

### Non-goals

No class/file extraction, public API removal, naming sweep, or functional fix.

### Validation

Full automated suite, parser check, diff review proving removed code was inactive,
and key visible Inspector smoke checks.

### Risk

Low.

### Dependencies

Milestones 2A–2C.

### Expected payoff

Smaller review surfaces and fewer false architectural signals before structural
work begins.

## Milestone 4 — Local runtime snapshot duplication cleanup

### Goal

Reduce the chance that topology-preserving and topology-changing snapshot
restores diverge.

### Current behavior

Both `set_point_snapshot()` branches repeat the same delicate point-state restore
sequence while differing in resource identity behavior.

### Exact scope

`EasingCurve.set_point_snapshot()` and one new private local restore/lock helper
in `easing_curve.gd`.

### Proposed changes

Extract the exact per-point restoration sequence and lock normalization. Keep
the two topology branches, suppression flags, snapshot keys, and notify logic.

### Non-goals

No storage/snapshot schema, point-state semantics, notification redesign, or
editor change.

### Validation

Serialization contracts, runtime updates, v1.0.5 regression, transforms,
identity assertions, and exact signal-count tests.

### Risk

Medium.

### Dependencies

Milestones 2B and 3.

### Expected payoff

One restoration rule for existing and newly created point resources.

## Milestone 5 — Organize and locally split the Inspector

### Goal

Expose natural responsibility boundaries without moving classes/files or
changing behavior.

### Current behavior

Related functions are interleaved, and `_create_vector2_property()` mixes header,
layout, state buttons, inputs, and signal wiring.

### Exact scope

Function ordering and private UI-builder helpers inside
`easing_curve_editor_inspector_plugin.gd`.

### Proposed changes

Group parse/preset, foldable, Points-list, property-control, selection,
transaction, and helper sections. Split only the cohesive UI builders identified
in INSPECTOR-02; preserve node hierarchy, order, sizing, and callbacks.

### Non-goals

No file extraction, selection authority change, transaction abstraction, point
semantics, or UI redesign.

### Validation

Full editor-host suite and visible narrow/wide layout, focus, fold, reset,
copy/paste, editability, and graph/list smoke pass.

### Risk

Medium.

### Dependencies

Milestones 2C and 3.

### Expected payoff

The Inspector becomes reviewable by responsibility and later state cleanup can
target smaller functions.

## Milestone 6 — Centralize editor selection assignments

### Goal

Make one editor-only path responsible for resolving, assigning, capturing, and
restoring logical point/property selection.

### Current behavior

Selection values are correct across many tested workflows but are assigned in
several unrelated methods and represented in both Inspector and graph state.

### Exact scope

Inspector selection fields/helpers and explicit graph mirroring. No resource
serialization.

### Proposed changes

Add private helpers for logical-point resolution, durable selection assignment,
header attachment, clear, capture, and restore. Replace duplicate field writes
while preserving resource-ID semantics and one-shot refresh behavior.

### Non-goals

No serialized selection resource, new user-visible selection behavior, graph
toolbar redesign, or removal of per-resource refresh persistence.

### Validation

The complete Milestone 2C selection matrix, topology actions, repeated
Undo/Redo, property copy/paste, resource switch/reselect, and visible highlights.

### Risk

High.

### Dependencies

Milestones 2C and 5.

### Expected payoff

Future topology and transaction changes have one understandable selection
authority instead of scattered coordinated assignments.

## Milestone 7 — Simplify explicit Undo/Redo transaction boilerplate

### Goal

Reduce repeated immediate-action setup while keeping gesture transactions and
mutation order obvious.

### Current behavior

The shared Undo helper is sound, but Inspector callers repeat common source,
capture, commit, and optional selection arguments.

### Exact scope

`easing_curve_editor_undo.gd` only if a narrow compatible helper is needed, plus
Inspector immediate-action call sites. Drag editor properties remain explicit.

### Proposed changes

Introduce at most one narrow immediate-snapshot action path and one local commit
wrapper for common Inspector arguments. Retain explicit begin/finish/cancel and
deferred commits for drags.

### Non-goals

No generic transaction framework, hidden mutation callbacks for complex point
state, history merging change, private Inspector notification removal, or
selection semantic change.

### Validation

Every action family creates exactly one history item, no-ops create none, signal
counts remain exact, live-debug refresh occurs, and repeated Undo/Redo restores
curve plus selection.

### Risk

High.

### Dependencies

Milestones 2C and 6.

### Expected payoff

New actions are less likely to omit required commit/refresh arguments without
making drag behavior opaque.

## Milestone 8 — Modest transition presentation metadata consolidation

### Goal

Reduce Inspector-side shotgun surgery while respecting runtime/public metadata
compatibility.

### Current behavior

Transition dropdown grouping/order and ease-support lists are maintained
separately from one another and from runtime definitions.

### Exact scope

Inspector `TRANSITION_GROUPS`, `_transition_supports_ease()`, transition option
construction, and catalog contract tests.

### Proposed changes

Create one authoritative editor presentation table containing every transition's
group/order and ease support. Derive the dropdown and support query from it.
Keep runtime enum IDs, exported parameters, public tables, callable classes, and
preset code unchanged.

### Non-goals

No new transition, parameter, general registry/framework, exported property
generation, numeric preset rewrite, or public constant removal.

### Validation

Full transition catalog contract, dropdown layout/order, ease availability,
parameter visibility/reset, sampling, runtime switching, save/load, and
Undo/Redo.

### Risk

Medium.

### Dependencies

Milestones 2B, 3, and 5.

### Expected payoff

Adding a transition has one fewer independent complete list and missed Inspector
ease/group edits become test failures.

## Milestone 9 — Reassess Inspector responsibility extraction

### Goal

Decide from the simplified code whether moving cohesive editor helpers reduces
coupling and review cost.

### Current behavior

Nested editor-property, drag/drop, and foldable classes are cohesive in places,
but they share constants and editor assumptions with the parent script.

### Exact scope

Audit the nested `DeferredParameterEditorProperty`,
`GenerateFunctionEditorProperty`, `PointsEditorProperty`,
`PointsListContainer`, and `PointsFoldableSection` after Milestones 5–8.

### Proposed changes

Extract only a helper group that has a small explicit constructor/configuration
surface and no need to reach parent private state. If no candidate meets that
test, record a no-change decision and keep the nested classes.

### Non-goals

No “large file therefore split” change, new framework, selection/Undo redesign,
or one-class-per-file churn.

### Validation

Full editor-host and visible layout/focus/fold/clipboard suite; inspect resulting
dependencies and total diff rather than line count alone.

### Risk

Medium.

### Dependencies

Milestones 5–8.

### Expected payoff

Any file split is justified by reduced coupling; otherwise the project avoids a
large move-only diff with no maintenance benefit.

## Milestone 10 — Review runtime/editor boundary

### Goal

Reduce editor widget knowledge in runtime resources only where the ownership
improvement outweighs compatibility and complexity risk.

### Current behavior

Point resources weakly reference Inspector inputs, and the curve stores
non-serialized per-resource graph view state/callbacks.

### Exact scope

`EasingCurvePoint` input-control bridge, Inspector input synchronization,
`EasingCurve` graph view fields/callbacks, and graph setup.

### Proposed changes

First map public/external usage. Prefer editor-owned signal/binding updates for
input controls while preserving public methods. Move curve view state only if a
simple editor-only per-resource owner preserves refresh behavior and does not
add another authority. A no-change conclusion is acceptable.

### Non-goals

No removal of public methods/signals, serialized editor selection/view state,
new singleton, or architectural-purity rewrite.

### Validation

Runtime use without plugin UI, input refresh/editability, per-resource view
state across refresh, resource switching, Undo/Redo, visible editor, and clean
plugin enable/disable.

### Risk

High.

### Dependencies

Milestones 2C, 6, 7, and 9.

### Expected payoff

Clearer ownership if a simple boundary exists, with explicit permission to
leave the current bridge when moving it would increase complexity.

## Milestone 11 — Final naming, comments, and file organization

### Goal

Make the post-structural code internally consistent and preserve the rationale
needed to prevent regression cleanup.

### Current behavior

Names/comments reflect several historical designs, while useful engine and
sampling rationale is mixed with obsolete fragments.

### Exact scope

Private names, function order, rationale comments, TODO/FIXME/debug remnants,
and signal lifecycle review across modified addon files.

### Proposed changes

Normalize private naming and types, update comments to current behavior, document
remaining workarounds, remove stale remnants, and verify connect/disconnect
symmetry. Preserve public and serialized names.

### Non-goals

No behavior change, public rename, formatting-only whole-repository rewrite,
new architecture, version bump, or changelog feature entry.

### Validation

Full automated suite, parser/warning review, visible editor smoke test, public
API/storage diff review, and signal lifecycle check.

### Risk

Low to Medium.

### Dependencies

All implemented structural milestones through Milestone 10.

### Expected payoff

The final code communicates current intent and unusual behavior without stale
historical noise.

## Milestone 12 — Full regression and release-readiness comparison

### Goal

Prove the refactored addon matches the Milestone 1 baseline in source, editor,
runtime, serialization, and actual distribution form.

### Current behavior

The working-tree automated baseline is known with explicit gaps; manual and
archive validation are unverified.

### Exact scope

All automated tests, the manual release checklist, existing resources, runtime
example, plugin lifecycle, packaging script, generated archive, and clean test
projects. Documentation changes only if validation reveals drift.

### Proposed changes

Run every automated and manual check, old/current resource round trips,
enable/disable cycles, minimum-version smoke test, build the intended archive,
inspect it, and install that exact archive into a clean project. Compare results
to this baseline and resolve only refactor-caused regressions.

### Non-goals

No publishing, tagging, version bump, new feature, store submission, or unrelated
release overhaul without separate authorization.

### Validation

All suites pass without false-positive errors/hangs; manual checklist passes;
resources and samples match; editor is clean after restart/disable; archive is
self-contained and clean-project validated.

### Risk

Medium.

### Dependencies

All selected Milestones 2–11.

### Expected payoff

Evidence that the refactor preserved behavior in the exact form users install.

# Dependency ordering

```text
Milestone 1 audit
-> 2A reliable runners
-> 2B serialization/transition contracts
-> 2C editor/selection/gesture characterization
-> 3 dead/stale cleanup

2B + 3 -> 4 runtime snapshot local cleanup
2C + 3 -> 5 Inspector organization
2C + 5 -> 6 selection authority
2C + 6 -> 7 Undo/Redo caller cleanup
2B + 3 + 5 -> 8 transition presentation metadata
5 + 6 + 7 + 8 -> 9 extraction decision gate
2C + 6 + 7 + 9 -> 10 runtime/editor boundary review
completed structural milestones -> 11 naming/comments
all selected milestones -> 12 full regression/release validation
```

Milestones 4 and 8 may proceed independently after their stated dependencies.
Milestone 9 may legitimately conclude with no production changes. Milestone 10
may also retain current ownership if no simpler compatibility-preserving design
is demonstrated.

# Risk assessment

| Area | Risk | Primary failure mode | Required protection |
| --- | --- | --- | --- |
| Test harness repair | Low | False pass/hang remains | Explicit check counts, script-error detection, exit codes |
| Dead/stale cleanup | Low | Mistaking public/dormant rationale for dead code | Reference proof, public API review, full suite |
| Serialization/snapshots | High | Old resource fails or exact state changes | Immutable old fixtures, schema/default contracts, identity and signal assertions |
| Point handle/state logic | High | Geometry or Lock/Force precedence changes | Full transition matrix, save/load, repeated Undo/Redo |
| Selection/topology | High | Wrong logical point/property after refresh/Undo | Resource-identity matrix across all topology actions |
| Undo/Redo transactions | High | Extra/missing history item, signal, refresh, or selection | Action-count and notification-count assertions plus live editor |
| Graph gesture splitting | High | Stale drag/delete/add state due branch ordering | Complete gesture suite and manual interaction pass |
| Transition metadata | Medium | Missing dropdown/parameter/callable site | Enumerated catalog/default/argument/sample contract |
| Inspector UI organization | Medium | Layout/focus/editability drift | Editor-host plus visible responsive/focus checks |
| Runtime/editor boundary | High | Lost input/view refresh or API break | External surface review, runtime and editor lifecycle tests |
| File extraction | Medium | More coupling/import churn without clarity | Dependency gate and no-change option |
| Packaging | Medium | Development dependency or UID/import failure | Exact archive inspection and clean-project install |

# Milestone 1 completion statement

This audit intentionally made no production-code or test changes. The only
planned repository change for Milestone 1 is this `REFACTOR_PLAN.md` document.
No public API, enum, exported property, default, signal, snapshot schema,
serialized resource format, sample result, editor UX, selection behavior, or
Undo/Redo behavior was modified.

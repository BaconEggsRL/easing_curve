---
document: AXIS_DRAG_01_CODE_PLAN.md
project: Easing Curve
release: 1.0.8-dev
feature_id: AXIS-DRAG-01
feature: Shift axis-constrained graph dragging
plan_type: feature
status: design_complete_execution_not_started
created: 2026-08-27
requirements: test/docs/_test_plans/CODE_PLAN_REQUIREMENTS.md
companion_report: test/docs/_test_plans/AXIS_DRAG_01_CODE_REPORT.md
---

# AXIS-DRAG-01 Code Plan — Shift Axis-Constrained Graph Dragging

## 1. Release goals

This feature plan is a focused companion to `v1.0.8_CODE_PLAN.md`. It does not
replace the v1.0.8 release plan. It isolates the implementation and validation
work for one user-confirmed release goal.

### User-confirmed feature goal

Add **Shift-constrained dragging** to the Easing Curve graph for:

- graph points;
- left Bézier control handles;
- right Bézier control handles.

The desired interaction is:

1. Start an ordinary LMB drag on an existing point or handle.
2. Press and hold **Shift after the drag is active**.
3. Constrain the dragged target to the dominant X or Y axis.
4. Release Shift to return immediately to ordinary 2D dragging.
5. Release LMB through the existing edit/Undo completion path.

The behavior should intentionally resemble Godot's 2D editor where that model
maps cleanly to Easing Curve.

### Explicit non-goals for AXIS-DRAG-01

Do not include any of the following in this feature unless a demonstrated
blocker creates a separate approval decision:

- multi-point selection or box selection;
- pre-held Shift as an axis-constrain gesture;
- Alt-based axis controls;
- X/Y keyboard axis overrides;
- axis arrows, gizmos, or visual constraint guides;
- a generalized graph gesture framework;
- `EDITOR-01`, `EDITOR-02`, `EDITOR-03`, or `UNDO-01` refactors;
- snapshot-format, serialized-format, public-API, notification-policy, or Undo
  framework changes.

The feature plan is frozen once execution starts. Per
`CODE_REPORT_REQUIREMENTS.md`, execution details and progress belong in
`AXIS_DRAG_01_CODE_REPORT.md`, not in this plan.

---

## 2. Baseline audit

### 2.1 Repository state

The feature baseline was refreshed immediately before this plan was generated.

| Item | Feature baseline |
| --- | --- |
| Branch | `dev` tracking `origin/dev` |
| Commit | `e694fb8aec392a572791204f5e3a0ecc39ff950e` |
| Plugin version | `1.0.8-dev` |
| Worktree before creating this feature plan/report | Clean |
| Project feature version | Godot `4.7` |
| Test engine | Godot `4.7.1.stable.official.a13da4feb` |
| Completed v1.0.8 prerequisites | `TEST-01`, `TEST-02`, `CLEANUP-01`, `METADATA-01` |
| Axis feature production work | Not started |

The completed maintenance slices above are treated as closed prerequisites. They
must not be reopened as part of AXIS-DRAG-01 without a demonstrated regression.

### 2.2 Automated test baseline audit

The current registered suite was rerun through the repository's authoritative
launcher:

```powershell
./test/scripts/run_all_tests.ps1
```

Result: **PASS — all 17 registered suites passed**. The runner exited `0`; every
suite exited `0`, emitted a PASS marker, did not time out, and did not contain a
`SCRIPT ERROR` according to `run_all_tests.ps1`.

#### 2.2.1 Test results

| Suite | Mode | Baseline result |
| --- | --- | --- |
| `css_linear_test.gd` | headless | PASS — 86 checks |
| `easing_curve_editor_rmb_delete_test.gd` | headless | PASS — 20 checks |
| `easing_curve_manual_reorder_test.gd` | headless | PASS — 75 checks |
| `easing_curve_transform_test.gd` | headless | PASS — 498 checks |
| `easing_curve_v105_regression_test.gd` | headless | PASS — 1,056 checks |
| `runtime_curve_updates_test.gd` | headless | PASS — 1,072 checks |
| `serialization_transition_contract_test.gd` | headless | PASS — 769 checks |
| `tween_equivalence_test.gd` | headless | PASS — 36 Bézier + 48 analytic checks |
| `easing_curve_control_editability_test.gd` | editor-host | PASS — 21 checks |
| `easing_curve_editor_position_x_drag_test.gd` | editor-host | PASS — 69 checks |
| `easing_curve_linear_control_alias_test.gd` | editor-host | PASS — 72 checks |
| `easing_curve_points_list_add_editor_test.gd` | editor-host | PASS — 84 checks |
| `easing_curve_points_list_reorder_editor_test.gd` | editor-host | PASS — 73 checks |
| `easing_curve_point_state_characterization_test.gd` | editor-host | PASS — 106 checks |
| `easing_curve_selection_refresh_characterization_test.gd` | editor-host | PASS — 70 checks |
| `easing_curve_editor_gesture_characterization_test.gd` | editor-host | PASS — 45 checks |
| `editor_undo_redo_test.gd` | editor-host | PASS — 627 checks |

Fresh-run anomaly observed in the already-open editor:

`Cannot change to 'res://test/_serialization_transition_contract/' folder.`

This is the already-documented temporary-`res://` serialization fixture/editor
scan race. The serialization suite and complete runner still passed. No new
blocking diagnostic was found.

Other previously documented headless/editor-host environment diagnostics remain
baseline noise unless their behavior changes.

#### 2.2.2 Test coverage assessment

The existing suite gives **strong regression coverage for the behavior around
this feature**, but **does not yet cover Shift-modified graph motion**.

| Area | Existing coverage | AXIS-DRAG-01 assessment |
| --- | --- | --- |
| Basic graph point/control drag transaction | `easing_curve_editor_gesture_characterization_test.gd` | Strong baseline; extend here |
| Pending add, RMB cancel/delete, MMB pan, wheel zoom | gesture + RMB suites | Strong preservation coverage |
| Point Position-X crossing/order/endpoint takeover | `easing_curve_editor_position_x_drag_test.gd` | Strong; add constrained cases only where useful |
| Control locks / Force Linear | control editability + point state | Strong downstream behavior coverage |
| Linear control alias behavior | `easing_curve_linear_control_alias_test.gd` | Strong downstream coverage |
| Free/Balanced/Mirrored/Linked point semantics | point state characterization | Strong downstream coverage |
| Selection/resource identity across refresh | selection/refresh suite | Strong preservation coverage |
| Undo/Redo transaction behavior | `editor_undo_redo_test.gd` | Strong preservation coverage |
| `shift_pressed` graph mouse events | None | **Coverage gap** |
| Shift pressed after drag start | None | **Coverage gap** |
| Pre-held Shift reservation | None | **Coverage gap** |
| View-space vs world-space dominant-axis choice | None | **Coverage gap** |
| Godot-style non-latched X/Y switching | None | **Coverage gap** |
| Shift release returning to free drag | None | **Coverage gap** |

The preferred strategy is to expand the existing graph gesture
characterization rather than add a new test framework or automatic suite.

### 2.3 Preservation / compatibility constraints

AXIS-DRAG-01 must preserve all current v1.0.8 compatibility constraints, with
special emphasis on the graph editing boundary.

Must preserve:

- all existing serialized `EasingCurve` and `EasingCurvePoint` formats;
- all public classes, methods, properties, signals, constants, and callable
  signatures;
- point Resource identity and stable point order semantics;
- equal-X ordering and endpoint takeover behavior;
- point/control locks and Force Linear behavior;
- Free, Linear, Balanced, Mirrored, and Linked Handle Mode semantics;
- opposite-handle geometry consequences owned by existing point/snapshot paths;
- existing point clamp behavior;
- Inspector snapshot mutation and notification ordering;
- one existing edit transaction / Undo action per completed drag;
- no Undo action for no-op drags;
- selection/resource restoration through Undo/Redo;
- existing public `point_property_change_requested` behavior unless separately
  characterized and approved;
- graph pan, zoom, hover, add, cancel, delete, and function-mode input;
- per-resource graph view-state persistence;
- the explicit 17-suite runner and Editor-host/headless assignments.

The axis feature must not use a new serialized or Resource-owned setting. Any
new state should be private, graph-local, and gesture-lifetime-only.

### 2.4 Code smells audit & methodology

The feature review uses the Refactoring.Guru smell catalog as required by
`CODE_PLAN_REQUIREMENTS.md`, but does not repeat maintenance work already closed
by the v1.0.8 audit.

Methodology for this focused refresh:

- re-read the comprehensive v1.0.8 smell audit and completion report;
- re-inspected the current `EasingCurveEditor` input/drag path after completed
  CLEANUP-01 and METADATA-01 work;
- re-assessed existing gesture, Position-X, control, point-state, selection, and
  Undo coverage against the requested feature;
- checked Godot 4.7's public ClassDB surface for reusable editor constraint APIs;
- reviewed Godot's 2D editor C++ interaction model for Shift-constrained motion;
- classified possible refactors as prerequisites, feature-local improvements,
  deferred debt, or false prerequisites.

No new maintenance prerequisite was found.

#### 2.4.1 Code smells findings

| ID | Priority | Finding | AXIS-DRAG-01 decision |
| --- | --- | --- | --- |
| `AXIS-TEST-01` | High | Modifier-specific graph characterization is missing | Address first inside feature execution |
| `AXIS-STATE-01` | Medium | New gesture-origin state can drift if initialized/reset inconsistently across drag entry/exit paths | Use one narrow private capture/reset boundary if needed; no gesture framework |
| `EDITOR-02` | Medium | Point dragging redundantly requests handle translation already owned downstream | **Defer**; do not combine with feature |
| `EDITOR-03` | Low for this feature | `_draw()` contains several rendering responsibilities | No action because no visual constraint guide is planned |
| `EDITOR-01` | Low for this feature | Inspector point-property coordinator remains multi-responsibility | Defer; not on the coordinate-input boundary |
| `UNDO-01` | Low for this feature | Undo registration has backend duplication | Defer; feature should reuse current transaction path unchanged |

##### AXIS-TEST-01 — Missing modifier-specific gesture characterization

- **Location:** `test/easing_curve_editor_gesture_characterization_test.gd`.
- **Smell/category:** Test Gap / Missing Characterization Around Change Boundary.
- **Evidence:** The suite exercises point/control drag, transaction boundaries,
  pending add, pan, and zoom, but its mouse-event helpers do not currently set
  Shift and no assertion covers modifier state.
- **Why it matters:** The feature changes only graph input interpretation. Tests
  should lock the input contract before expanding the production path.
- **Action:** Extend the existing event helpers and graph characterization. Do
  not introduce a new test framework or inferred runner registration.

##### AXIS-STATE-01 — Gesture-origin state must have one lifecycle

- **Location:** `EasingCurveEditor._handle_left_pressed()`,
  `_handle_drag_motion()`, `_handle_left_released()`, and drag invalidation in
  `_on_curve_changed()`.
- **Smell/category:** Temporal Coupling / Potential Duplicated State Setup.
- **Evidence:** A point/control drag is selected in more than one branch of
  `_handle_left_pressed()`. AXIS-DRAG-01 requires a stable original mouse/view
  position, original dragged-target world position, and knowledge of whether
  Shift was pre-held.
- **Why it matters:** Missing one drag entry/reset branch could make axis behavior
  depend on how the same target was selected.
- **Action:** Prefer one narrowly scoped private initialization/reset boundary for
  the new feature state if that makes the lifecycle explicit. Do not refactor
  general graph dragging or selection.

##### EDITOR-02 — Redundant point-handle translation requests

This remains valid debt, but AXIS-DRAG-01 must leave it unchanged. The axis
projection should feed the existing point target; the existing downstream point
and handle request sequence remains the compatibility baseline.

##### EDITOR-03 — Graph draw extraction

No visual axis guide is planned, so there is no feature justification for draw
refactoring. Leave `_draw()` unchanged.

##### EDITOR-01 and UNDO-01

Neither lies on the required coordinate-input boundary. Reuse the existing
Inspector and Undo transaction behavior unchanged.

#### 2.4.2 Recommended implementation order

1. Add modifier-capable graph event characterization without changing production
   behavior.
2. Add the smallest private drag-origin/Shift-eligibility state needed by the
   existing graph editor.
3. Implement Shift projection for point dragging.
4. Apply the same projection model to left/right handle targets.
5. Characterize view-space dominance, point clamp/order, Handle Modes, locks,
   and Force Linear without moving those responsibilities into the graph.
6. Verify Undo/request and unaffected-input compatibility.
7. Perform focused integration and visible-editor drag-feel smoke.
8. Close with `git diff --check`, all 17 registered suites, final scope review,
   report update, and a bounded feature commit.

No cleanup/refactor task is required before Step 1.

---

## 3. New features

### 3.1 AXIS-DRAG-01 — Shift axis-constrained graph dragging

#### 3.1.1 Current related architecture assessment

The current graph input architecture is already sufficient:

```text
_gui_input()
    -> mouse button prepass / pan handling
    -> _handle_mouse_motion()
        -> _handle_drag_motion()
    -> _handle_mouse_button()
        -> _handle_left_pressed()
        -> _handle_left_released()
```

For an active point/control drag, `_handle_drag_motion()` currently:

1. resolves the active point;
2. converts event view position to a world target with `get_world_pos()`;
3. checks target locks;
4. requests left/right control or point-position mutation;
5. for a point move, clamps position and computes the existing translation
   delta used by the current control requests;
6. emits/redraws through existing paths.

The constraint belongs locally between world-target calculation and the existing
mutation/clamp path.

No reusable Godot editor API is exposed for this calculation. Godot 4.7's
`CanvasItemEditor` implementation is internal; scripting exposes modifier state
through `InputEventMouseMotion.is_shift_pressed()`, but does not expose the
editor's `_gui_input_move()` or a public axis-constrain helper.

Reference behavior is implemented in Godot 4.7's
`editor/scene/canvas_item_editor_plugin.cpp`.

#### 3.1.2 Feature design decisions settled before implementation

The following decisions are **settled for the first implementation**.

##### Modifier

Use **Shift**.

Do not use Alt. Alt has other transformation/selection meanings in Godot and
would imply gizmo behavior that is not needed here.

##### Shift timing / future selection reservation

Axis constraint is eligible only when Shift is engaged **after an existing
point/control LMB drag has started**.

If Shift is already held on the initial LMB press:

- the initial Shift hold must not activate axis constraint;
- the drag remains the existing ordinary drag for that Shift hold;
- once Shift is released, a later Shift press during the same active drag may
  engage axis constraint normally.

This deliberately leaves pre-held `Shift + LMB drag` available for a future
multi-point/additive/box-selection design.

##### Axis choice

Follow Godot's simple dominant-axis model:

```text
abs(view_delta.x) > abs(view_delta.y)
    -> constrain X
else
    -> constrain Y
```

The equality case therefore resolves to **Y**, matching the strict `>` branch.

Determine dominance from **total view-space / graph-pixel displacement from the
original drag mouse position**, not from latest-frame delta and not from
normalized Easing Curve world-space delta.

This view-space rule is important because the graph is rectangular and its
world X/Y axes do not have equal pixel scale.

##### Constraint target

Keep the ordinary current mouse-to-world target, then project only its
non-dominant coordinate back to the **original dragged target world position**:

```text
dominant X -> target.y = original_target.y
dominant Y -> target.x = original_target.x
```

For points, project before the existing clamp and point-delta calculation.
For handles, project only the requested left/right handle target.

##### Latching / threshold / modifier transitions

Match Godot's first-pass behavior:

- no additional axis-selection threshold;
- no axis latch;
- dominant axis may change as total displacement crosses the 45-degree boundary;
- pressing Shift may immediately project the target onto the chosen axis;
- releasing Shift immediately restores ordinary unconstrained drag targeting,
  including the corresponding visible projection if the cursor is off-axis.

If manual testing shows unacceptable flicker or transition feel, a latch or
continuity/rebase model requires a separate reviewed follow-up. Do not silently
add one during implementation.

##### Visuals and other controls

Do not add:

- axis arrows;
- axis guide lines;
- a gizmo;
- X/Y keyboard selection;
- a new InputMap action.

Use the Shift modifier state already present on mouse events.

#### 3.1.3 Recommendations and rough execution plan

The expected implementation should be small and graph-local.

Primary production file:

- `addons/easing_curve/scripts/easing_curve_editor.gd`.

Primary characterization file:

- `test/easing_curve_editor_gesture_characterization_test.gd`.

Potential additional focused characterization only where it naturally belongs:

- `test/easing_curve_editor_position_x_drag_test.gd` for constrained point
  ordering/endpoint takeover;
- existing control/point/Undo suites should preferably remain unchanged and be
  used as regression gates unless a real feature-specific assertion belongs
  there.

Recommended implementation shape:

1. Extend test mouse-event construction so Shift state can be expressed.
2. Preserve current unconstrained/pre-held-Shift behavior before production
   changes.
3. Introduce only gesture-lifetime private state needed to remember:
   - original drag mouse/view position;
   - original dragged point/handle world position;
   - pre-held Shift eligibility state.
4. Initialize/reset that state through one narrow lifecycle boundary if needed.
5. In `_handle_drag_motion()`, derive the ordinary world target first.
6. When Shift is eligible and active, choose the dominant axis from original-to-
   current view displacement and project the world target.
7. Continue through existing point/control lock, clamp, Handle Mode, request,
   ordering, notification, and Undo behavior.
8. Validate the expanded interaction matrix before full-suite closeout.

Do not include exact code diffs in this code plan. Exact proposed diffs for each
execution step must be presented through the companion code report approval
flow before that step is implemented.

#### 3.1.4 Execution constraints from code smells audit

- `AXIS-TEST-01` must be addressed as the first execution slice.
- `AXIS-STATE-01` may justify one small private state lifecycle helper, but not a
  generalized drag state object/framework.
- `EDITOR-02` must remain separate even though point drag currently repeats
  handle-translation requests.
- `EDITOR-03` remains untouched because no visual guide is planned.
- `EDITOR-01` and `UNDO-01` remain deferred.
- Do not move Handle Mode, Force Linear, lock, order, endpoint, snapshot,
  notification, or Undo semantics into `EasingCurveEditor`.

#### 3.1.5 Validation & test requirements

##### Required automated characterization

Cover at minimum:

- unchanged unconstrained point drag;
- unchanged unconstrained left/right handle drag;
- horizontal constrained point drag after Shift is pressed during the drag;
- vertical constrained point drag after Shift is pressed during the drag;
- horizontal/vertical constrained left handle drag;
- horizontal/vertical constrained right handle drag;
- pre-held Shift does not activate axis constraint during its initial hold;
- release of a pre-held Shift followed by a new Shift press can engage
  constraint in the same drag;
- Shift release returns to ordinary unconstrained drag targeting;
- total view-space displacement selects the axis;
- a case where world-space comparison would select the wrong visual axis;
- X-dominant and Y-dominant behavior on both sides of the equality boundary;
- exact/effectively exact equality resolves consistently with the selected
  implementation rule;
- correctness under graph pan;
- correctness under graph zoom;
- wheel zoom during an active drag remains supported;
- point X endpoint/Y range clamping;
- horizontal constraint preserves point crossing/order preview/endpoint takeover;
- vertical constraint does not create an X order change;
- locked point position remains immovable;
- locked left/right controls remain immovable;
- Force Linear behavior remains owned downstream;
- Free, Linear fallback, Balanced, Mirrored, and Linked behavior remains correct;
- one Undo action per completed drag;
- no Undo action for no-op drag;
- Undo/Redo restores selection and Resource identity;
- pending add behavior remains unchanged;
- RMB cancel/delete remains unchanged;
- MMB pan remains unchanged;
- hover remains unchanged;
- function-mode graph input remains unchanged.

##### Focused suite gate during development

At minimum run, as applicable:

- `easing_curve_editor_gesture_characterization_test.gd`;
- `easing_curve_editor_position_x_drag_test.gd`;
- `easing_curve_control_editability_test.gd`;
- `easing_curve_linear_control_alias_test.gd`;
- `easing_curve_point_state_characterization_test.gd`;
- `easing_curve_selection_refresh_characterization_test.gd`;
- `editor_undo_redo_test.gd`.

Use `easing_curve_editor_rmb_delete_test.gd` when delete/cancel interaction is
specifically touched or characterized.

##### Visible-editor smoke gate

Manually verify:

1. Free point drag still feels unchanged.
2. Press Shift after starting a horizontal-biased point drag: Y remains at the
   original point value.
3. Press Shift after starting a vertical-biased point drag: X remains at the
   original point value.
4. Cross the visual diagonal while Shift remains held and confirm Godot-style
   non-latched axis switching.
5. Release Shift and confirm free drag resumes immediately.
6. Start with Shift already held and confirm the initial hold does not constrain.
7. Release and re-press Shift in that same drag and confirm constraint can engage.
8. Repeat for left and right handles.
9. Repeat representative drags under zoom and pan.
10. Smoke Free, Balanced, Mirrored, Linked, Force Linear, and locked controls.
11. Smoke horizontal point crossing/endpoint takeover and vertical no-reorder.
12. Verify Undo/Redo returns exact geometry/selection.
13. Verify RMB delete/cancel, pending add, MMB pan, and wheel zoom remain normal.

##### Feature release gate

Before AXIS-DRAG-01 is marked complete:

- all focused automated tests pass;
- visible-editor smoke passes or records an explicitly approved issue;
- `git diff --check` passes;
- all 17 registered suites pass with the standard runner;
- final diff/status contains only approved feature/test/report changes;
- no serialized/public API/version changes were introduced;
- `AXIS_DRAG_01_CODE_REPORT.md` contains the completed execution record;
- feature implementation is committed in one bounded closeout commit or a
  clearly documented bounded commit sequence approved during execution.

---

## 4. Summary & closing remarks

AXIS-DRAG-01 is ready for execution planning with no prerequisite cleanup.

The implementation should remain a small extension of the existing graph input
path rather than a new interaction framework. Shift is intentionally used only
when engaged after an existing point/control drag begins. Dominant direction is
selected from total **view-space** displacement, while the resulting constraint
is applied to the ordinary **world-space** drag target. Existing point/control,
Inspector, order, notification, and Undo systems remain authoritative.

The current automated baseline is green at 17/17. The main missing coverage is
modifier-specific graph characterization, which should be added first.

Execution must proceed through the companion report one approved step at a time.
No AXIS-DRAG-01 production implementation has been performed by creation of this
plan.

---
document: AXIS_DRAG_01_CODE_REPORT.md
project: Easing Curve
release: 1.0.8-dev
feature_id: AXIS-DRAG-01
feature: Shift axis-constrained graph dragging
report_type: execution-progress
status: in_progress
created: 2026-08-27
last_updated: 2026-08-27
authoritative_plan: test/docs/_test_plans/AXIS_DRAG_01_CODE_PLAN.md
requirements: test/docs/_test_plans/CODE_REPORT_REQUIREMENTS.md
---

# AXIS-DRAG-01 Code Report — Shift Axis-Constrained Graph Dragging

## 1. Purpose

This report is the execution companion to:

`test/docs/_test_plans/AXIS_DRAG_01_CODE_PLAN.md`

It exists to record the detailed execution plan, approval gates, progress,
validation results, implementation notes, diagnostics, and final closeout for
AXIS-DRAG-01.

Per `CODE_REPORT_REQUIREMENTS.md`:

- the feature code plan is not to be modified during execution;
- this report is the mutable implementation log;
- no execution step may begin without user approval;
- when a step is presented for execution, the exact proposed code diff and
  targeted validation for that step must be shown before implementation;
- generating this report does **not** authorize production changes.

AXIS-DRAG-01 Steps 1-4 are complete. Step 4 added test-only characterization proving the Shift-projected graph target remains subordinate to existing Handle Mode, lock, and Force Linear semantics.

---

## 2. Current feature status

| Field | Value |
| --- | --- |
| Feature ID | `AXIS-DRAG-01` |
| Feature | Shift axis-constrained graph dragging |
| Release | `1.0.8-dev` |
| Plan | `test/docs/_test_plans/AXIS_DRAG_01_CODE_PLAN.md` |
| Execution status | IN PROGRESS |
| Current step | Awaiting approval for Step 5 of 8 |
| Production code changed for feature | Yes — `easing_curve_editor.gd` point/handle axis-constraint path |
| Feature tests changed | Yes — graph gesture characterization |
| Baseline branch | `dev` |
| Baseline commit | `e694fb8aec392a572791204f5e3a0ecc39ff950e` |
| Baseline automated result | 17/17 PASS on Godot 4.7.1 |
| Known blocking regression | None |
| Known non-blocking diagnostic | Serialization temporary `res://` folder/editor scan race |

---

## 3. Plan execution summary

The following IDs are present in the feature code plan. Only `AXIS-DRAG-01` is
an active feature execution item; the others are feature-local findings or
existing deferred maintenance constraints.

| Plan ID | Status | Execution relationship |
| --- | --- | --- |
| `AXIS-TEST-01` | IN PROGRESS | Step 1 added modifier-capable baseline characterization; active-constraint coverage continues in later steps |
| `AXIS-STATE-01` | COMPLETE | Step 2 added one narrow private gesture-origin/Shift-eligibility lifecycle |
| `AXIS-DRAG-01` | IN PROGRESS | Steps 1-4 complete; awaiting approval for Step 5 |
| `EDITOR-02` | DEFERRED | Must not be folded into feature |
| `EDITOR-03` | NOT REQUIRED | No visual constraint guide planned |
| `EDITOR-01` | DEFERRED | Not on the graph coordinate-input boundary |
| `UNDO-01` | DEFERRED | Existing Undo path must be reused unchanged |

Completed v1.0.8 prerequisites `TEST-01`, `TEST-02`, `CLEANUP-01`, and
`METADATA-01` are external to this feature plan and are treated as closed.

---

# 4. AXIS-DRAG-01 formal execution plan

## Execution rules

Each step below is an approval gate.

Before executing a step, present to the user:

1. the exact files expected to change;
2. the exact proposed code diff for that step;
3. the targeted automated/manual validation to be run;
4. any new scope discovered since the previous step.

Do not implement the step until the user approves it.

Do not automatically advance to the next step after completing a step. Update
this report with the result, then present the next step for approval.

The full 17-suite runner is reserved for closeout unless a step creates a reason
to run it earlier. Use focused suites during development.

---

## AXIS-DRAG-01 Step 1 of 8 — Establish modifier-capable graph characterization

**Status:** COMPLETE

### Objective

Prepare the existing graph gesture test to express Shift-modified mouse input
and lock the current non-feature behavior before changing production code.

### Expected files

Primary expected change:

- `test/easing_curve_editor_gesture_characterization_test.gd`.

No production file should change in this step.

### High-level work

- Extend the existing mouse button/motion test helpers so Shift state can be
  represented without changing existing call sites unnecessarily.
- Add/strengthen characterization proving ordinary unconstrained point and
  left/right handle drags remain unchanged.
- Characterize that Shift currently has no special effect before feature
  implementation, especially the **pre-held Shift** case that must remain
  unconstrained after the feature is introduced.
- Preserve existing pending-add, transaction, zoom, and pan characterization.
- Do not add desired active-Shift assertions that would intentionally leave the
  registered suite failing before production support exists.

### Targeted validation

- Fresh Editor-host run of
  `easing_curve_editor_gesture_characterization_test.gd`.
- `git diff --check`.
- Confirm only the graph gesture test changed.

### Execution result

Completed on 2026-08-27.

Changed only:

- `test/easing_curve_editor_gesture_characterization_test.gd`.

Implemented:

- optional `shift_pressed` support in the existing mouse button/motion test helpers while preserving existing call sites;
- explicit ordinary left-handle and right-handle unconstrained drag baselines;
- pre-held Shift characterization proving that its initial hold still starts and performs an ordinary unconstrained point drag and cleans up normally.

The suite increased from **45 to 52 checks**. No desired mid-drag Shift-axis assertions were added yet, so Step 1 does not require unfinished production behavior.

Validation:

- fresh Godot 4.7.1 Editor-host run through `test/scripts/run_godot.ps1`;
- process exit code `0`;
- `PASS: 52 graph gesture characterization checks`;
- no `SCRIPT ERROR` or `ERROR:` in the final test log;
- `git diff --check` passed;
- Step 1 implementation scope contained no production code.

Diagnostic encountered:

- during the multi-patch edit, the first patch temporarily registered `_test_modifier_capable_drag_baseline()` in `_run()` before its function body existed, producing an expected transient editor parse diagnostic; after the planned function body was added the script parsed cleanly and the fresh Editor-host process passed 52 checks. This was a patch-order/tooling artifact, not a final source defect.

Next approval gate: **AXIS-DRAG-01 Step 2 of 8 — Implement Shift eligibility and constrained point dragging**.

---

## AXIS-DRAG-01 Step 2 of 8 — Implement Shift eligibility and constrained point dragging

**Status:** COMPLETE

### Objective

Implement the smallest graph-local production state/lifecycle required for
Shift-constrained **point** dragging and validate the core modifier contract.

### Expected files

Expected production change:

- `addons/easing_curve/scripts/easing_curve_editor.gd`.

Expected characterization change:

- `test/easing_curve_editor_gesture_characterization_test.gd`.

### High-level work

- Capture stable gesture origin information when an actual point/handle drag
  begins:
  - original mouse/view position;
  - original dragged target world position;
  - whether Shift was already held on initial LMB press.
- Keep this new state private and gesture-lifetime-only.
- Ensure pre-held Shift remains ineligible until it is released; a later Shift
  press during the same drag may then engage constraint.
- For point dragging only in this step:
  - derive the ordinary world target first;
  - choose dominant X/Y from total original-to-current **view-space** movement;
  - project the non-dominant world coordinate to the original point coordinate;
  - continue through the existing clamp, delta, request, notification, order,
    and transaction path.
- Match Godot's non-latched/no-extra-threshold behavior.
- Equality should follow the agreed strict-comparison rule and resolve to Y.
- Reset feature state on ordinary drag completion and existing drag invalidation
  paths.

### Required behavior covered in this step

- mid-drag Shift horizontal point constraint;
- mid-drag Shift vertical point constraint;
- pre-held Shift remains unconstrained during its initial hold;
- releasing pre-held Shift then pressing Shift again can engage constraint;
- releasing active Shift returns immediately to free dragging;
- dominant axis can change as total displacement crosses the diagonal;
- no new Undo boundary or point request contract.

### Targeted validation

- graph gesture characterization;
- Position-X drag suite if point-order behavior is touched by the exact diff;
- `git diff --check`.

Do not run the full suite unless a broader regression appears.

### Execution result

Completed on 2026-08-27.

Changed implementation files:

- `addons/easing_curve/scripts/easing_curve_editor.gd`;
- `test/easing_curve_editor_gesture_characterization_test.gd`.

Production implementation:

- added three private gesture-lifetime fields for original view position, original dragged-target world position, and pre-held Shift blocking;
- added `_begin_axis_drag()` to capture the stable drag origin when an existing point/handle drag starts;
- added `_clear_axis_drag()` and reset the new state through the existing LMB-release and drag-invalidation paths;
- added `_apply_point_axis_constraint()` for point targets only;
- pre-held Shift remains ignored until a motion arrives with Shift released, after which a later Shift press in the same drag may constrain;
- eligible Shift compares total view-space displacement from the original mouse press with strict `abs(x) > abs(y)` dominance;
- X-dominant movement restores the original point Y, otherwise the original point X is restored;
- projection occurs before the existing point clamp and existing point/control delta request sequence;
- no axis latch, extra threshold, continuity rebase, visual cue, Handle Mode logic, Inspector logic, Undo change, or `EDITOR-02` cleanup was introduced.

The existing legacy `initial_grab_*` declarations were not repurposed because they are not part of the current drag path; the feature state uses narrowly named private fields instead.

Characterization added seven checks covering:

- mid-drag horizontal point constraint;
- mid-drag vertical point constraint;
- non-latched axis switching while Shift remains held;
- Shift release immediately returning to free dragging;
- constrained-drag cleanup on LMB release;
- pre-held Shift remaining unconstrained through its initial hold/release;
- a later Shift re-press in the same drag becoming eligible.

The graph gesture suite increased from **52 to 59 checks**.

Validation:

- fresh Godot 4.7.1 Editor-host graph gesture run: `PASS: 59 graph gesture characterization checks`, exit `0`, no `SCRIPT ERROR` or `ERROR:`;
- fresh Position-X drag regression run: `PASS: 69 EasingCurveEditor Position X drag checks`, exit `0`, no `SCRIPT ERROR` or `ERROR:`;
- `git diff --check` passed;
- no full 17-suite run was performed because Step 2 remained within its focused validation scope.

Diagnostics encountered:

- each live save of `easing_curve_editor.gd` produced the previously observed Godot hot-reload error code `43`; fresh Editor-host compilation and both focused suites passed, so this remains classified as a live-editor hot-reload artifact;
- while applying the test edit, `_run()` briefly referenced `_test_point_axis_constraint_behavior()` before its function body was patched in, producing a transient parse diagnostic; the final test file parsed cleanly and passed 59 checks.

Step 2 intentionally does **not** constrain Bézier handles yet; that is the next approved slice.

Next approval gate: **AXIS-DRAG-01 Step 3 of 8 — Apply the same constraint model to Bézier handles**.

---

## AXIS-DRAG-01 Step 3 of 8 — Apply the same constraint model to Bézier handles

**Status:** COMPLETE

### Objective

Extend the already-reviewed point constraint model to left and right control
handles without moving Handle Mode semantics into the graph editor.

### Expected files

Expected production/test scope:

- `addons/easing_curve/scripts/easing_curve_editor.gd`;
- `test/easing_curve_editor_gesture_characterization_test.gd`.

### High-level work

- Reuse the same drag-origin and Shift-eligibility lifecycle established in
  Step 2.
- For a left/right handle drag, project only the requested control target.
- Do not introduce control clamping, opposite-handle math, Force Linear logic,
  or Handle Mode geometry into `EasingCurveEditor`.
- Preserve first/last handle availability and existing lock checks.
- Add horizontal/vertical characterization for both left and right handles.
- Cover Shift press/release timing on at least one control target in addition to
  the point coverage from Step 2.

### Targeted validation

- graph gesture characterization;
- `easing_curve_control_editability_test.gd`;
- `easing_curve_linear_control_alias_test.gd`;
- `git diff --check`.

### Execution result

Completed on 2026-08-27.

Production change remained confined to `addons/easing_curve/scripts/easing_curve_editor.gd`:

- renamed the Step 2 point-specific projection helper to the generic `_apply_axis_drag_constraint()`;
- applied that helper once to the ordinary world target after existing lock checks and before the existing left/right/point dispatch;
- reused the existing Step 2 drag-origin and pre-held-Shift eligibility state for handles;
- left left/right property requests, control availability, locks, Handle Modes, Force Linear, Inspector mutation, notifications, and Undo transaction behavior unchanged.

Characterization change remained in `test/easing_curve_editor_gesture_characterization_test.gd` and added five checks:

- left-handle horizontal constraint;
- left-handle vertical constraint;
- left-handle Shift release returning immediately to ordinary unconstrained movement;
- right-handle horizontal constraint;
- right-handle vertical constraint.

The graph gesture suite increased from **59 to 64 checks**.

Focused validation passed in fresh Godot 4.7.1 Editor-host processes through `test/scripts/run_godot.ps1`:

- `PASS: 64 graph gesture characterization checks`;
- `PASS: 21 EasingCurve control editability checks`;
- `PASS: 72 EasingCurve Linear control alias checks`;
- all three processes exited `0`;
- no final log contained `SCRIPT ERROR` or `ERROR:`;
- `git diff --check` passed.

Diagnostic encountered:

- the live editor produced the previously observed hot-reload error code `43` while saving `easing_curve_editor.gd`; fresh Editor-host compilation and all focused suites passed, so this remains classified as a live-editor hot-reload artifact rather than a source defect.

No full 17-suite run was performed in Step 3.

Next approval gate: **AXIS-DRAG-01 Step 4 of 8 — Characterize Handle Modes, locks, and Force Linear integration**.

---

## AXIS-DRAG-01 Step 4 of 8 — Characterize Handle Modes, locks, and Force Linear integration

	**Status:** COMPLETE

	### Objective

	Prove that axis projection remains only an input-target transformation and that
	all existing point/control semantics continue to be owned downstream.

	### Expected files

	Prefer test-only changes if new feature-specific characterization is needed.
	Potential files:

	- `test/easing_curve_editor_gesture_characterization_test.gd`;
	- an existing focused control/point suite only if that suite is the clearer owner
	  of a specific invariant.

	Production changes are not expected unless this validation finds a genuine
	feature defect.

	### High-level coverage

	- locked point position;
	- locked left control;
	- locked right control;
	- Force Linear;
	- Free;
	- Linear fallback/alias behavior;
	- Balanced;
	- Mirrored;
	- Linked;
	- opposite-handle consequences remain unchanged.

	Do not change `point.gd`, snapshot mutation policy, or Inspector semantics merely
	to simplify tests.

	### Targeted validation

	- graph gesture characterization;
	- control editability;
	- Linear control alias;
	- point-state characterization;
	- `git diff --check`.

	### Execution result

	Completed on 2026-08-27 as a **test-only** integration-characterization slice.
	No production source was modified during Step 4.

	Changed for Step 4:

	- `test/easing_curve_editor_gesture_characterization_test.gd`;
	- this report for bookkeeping.

	Added 20 graph-level integration checks covering:

	- locked point position refusing to start/move under Shift motion;
	- locked left and right controls refusing to start/move;
	- Free constrained handle movement leaving the opposite handle unchanged;
	- Force Linear remaining collapsed while the point receives a constrained target;
	- Balanced constrained handle movement preserving its downstream opposite display-space direction and opposite display-space length;
	- Mirrored constrained handle movement preserving downstream display-space mirroring;
	- Linked constrained handle movement keeping both controls synchronized to the single constrained request;
	- Linear collapsed-handle hit testing continuing to fall back to the existing point-drag path, with Shift constraining that point while both controls remain collapsed.

	The graph gesture suite increased from **64 to 84 checks**.

	Validation after the final test correction:

	- `PASS: 84 graph gesture characterization checks`;
	- `PASS: 21 EasingCurve control editability checks`;
	- `PASS: 72 EasingCurve Linear control alias checks`;
	- `PASS: 106 point-state characterization checks`;
	- all four fresh Godot 4.7.1 Editor-host processes exited `0`;
	- no `SCRIPT ERROR` or `ERROR:` appeared in the passing logs;
	- `git diff --check` passed.

	One initial graph run failed 1 of 84 checks on the new Balanced opposite-direction assertion. The constrained dragged target and opposite display-space length assertions both passed. The failing predicate compared a raw display-space cross product with `is_zero_approx()`, which amplified floating-point error at editor-scale handle magnitudes. The test helper was corrected to compare normalized display-space directions instead. The rerun passed 84/84. This was a test numerical-tolerance defect, not a production Shift-drag defect; no production change was made.

	Existing `easing_curve_point_state_characterization_test.gd` remains the owner of detailed Handle Mode transition mathematics and Inspector precedence. Step 4 only characterizes the graph-input integration seam and does not duplicate those responsibilities.

	Next approval gate: **AXIS-DRAG-01 Step 5 of 8 — Validate view-space dominance, pan/zoom, clamping, and ordering**.

	---

	## AXIS-DRAG-01 Step 5 of 8 — Validate view-space dominance, pan/zoom, clamping, and ordering

**Status:** NOT STARTED

### Objective

Exercise the Easing Curve-specific geometry risks that differ from a literal
copy of Godot's canvas coordinate implementation.

### Expected files

Likely characterization scope:

- `test/easing_curve_editor_gesture_characterization_test.gd`;
- `test/easing_curve_editor_position_x_drag_test.gd` only where ordering/
  endpoint scenarios fit that suite better.

Production changes should remain confined to
`addons/easing_curve/scripts/easing_curve_editor.gd` if a defect is found.

### High-level coverage

- prove axis dominance is based on **view-space/pixel** displacement;
- include a case where normalized world-space delta would select the opposite
  axis;
- exercise both sides of the 45-degree/equality boundary;
- verify non-latched axis switching as the total displacement crosses it;
- verify behavior while zoomed;
- verify behavior while panned;
- preserve wheel zoom during active drag;
- point X endpoint clamping;
- point Y range clamping;
- horizontal constrained point crossing/order preview/endpoint takeover;
- vertical constrained movement does not change X ordering.

### Targeted validation

- graph gesture characterization;
- Position-X drag suite;
- selection/refresh characterization when zoom/pan/resource state is involved;
- `git diff --check`.

### Approval gate

Present exact proposed characterization/production diff before execution.

---

## AXIS-DRAG-01 Step 6 of 8 — Verify Undo/request boundaries and unaffected graph input

**Status:** NOT STARTED

### Objective

Prove that the feature did not alter transaction/public-request semantics or
steal input from unrelated graph gestures.

### Expected files

Prefer validation-only. Add tests only where a feature-specific contract is not
already protected.

Potential test files:

- `test/easing_curve_editor_gesture_characterization_test.gd`;
- `test/editor_undo_redo_test.gd` only if a new focused Undo assertion is needed;
- `test/easing_curve_editor_rmb_delete_test.gd` only if modifier/delete behavior
  needs direct characterization.

No Undo production refactor is authorized.

### High-level coverage

- one Undo action per completed constrained point drag;
- one Undo action per completed constrained handle drag where applicable;
- no Undo action for a no-op drag;
- Undo/Redo restores exact geometry, selection, and Resource identity;
- existing `point_property_change_requested` sequence is not intentionally
  changed;
- pending add unchanged;
- RMB cancel/delete unchanged;
- MMB pan unchanged;
- wheel zoom unchanged;
- hover unchanged;
- function-mode graph input unchanged;
- pre-held Shift remains available for future selection semantics rather than
  being globally consumed by the feature.

### Targeted validation

- graph gesture characterization;
- editor Undo/Redo suite;
- selection/refresh suite;
- RMB delete suite when applicable;
- `git diff --check`.

### Approval gate

Present any proposed test diff or corrective production diff before execution.

---

## AXIS-DRAG-01 Step 7 of 8 — Focused integration and visible-editor validation

**Status:** NOT STARTED

### Objective

Run the complete focused regression set and perform a real visible-editor
interaction smoke before the full release gate.

### Expected file changes

None expected unless validation finds a defect.

Do not make opportunistic cleanup/refactor changes in this step.

### Focused automated validation

Run at minimum:

- `easing_curve_editor_gesture_characterization_test.gd`;
- `easing_curve_editor_position_x_drag_test.gd`;
- `easing_curve_control_editability_test.gd`;
- `easing_curve_linear_control_alias_test.gd`;
- `easing_curve_point_state_characterization_test.gd`;
- `easing_curve_selection_refresh_characterization_test.gd`;
- `editor_undo_redo_test.gd`;
- RMB delete suite if it was touched/expanded.

### Visible-editor smoke

Manually verify the 13-point checklist in the code plan, including:

- free drag feel;
- horizontal/vertical point constraints;
- non-latched diagonal crossing;
- Shift release behavior;
- pre-held Shift reservation and re-press behavior;
- left/right handles;
- pan/zoom;
- Handle Modes, Force Linear, locks;
- point crossing/endpoint takeover;
- Undo/Redo;
- unrelated graph gestures.

Record any subjective drag-feel issue exactly. Do not add axis latching,
continuity rebasing, or visual guides without a new approval decision.

### Approval gate

Present the validation checklist before execution. If any code fix is required,
stop and present that diff as a bounded corrective sub-step before continuing.

---

## AXIS-DRAG-01 Step 8 of 8 — Release-gate closeout

**Status:** NOT STARTED

### Objective

Close AXIS-DRAG-01 as an independently reviewable feature slice.

### Required closeout actions

1. Run `git diff --check`.
2. Run the authoritative `test/scripts/run_all_tests.ps1` suite.
3. Require all 17 registered suites to pass with the normal exit/PASS/no-timeout/
   no-`SCRIPT ERROR` criteria.
4. Review final Git status and diff for scope.
5. Verify no serialized names/formats, enum values, public signatures, plugin
   version, snapshot policy, notification policy, or Undo framework changed.
6. Confirm `EDITOR-01`, `EDITOR-02`, `EDITOR-03`, and `UNDO-01` were not bundled.
7. Update this report with:
   - final files changed;
   - final test counts/results;
   - visible-editor result;
   - implementation decisions actually taken;
   - diagnostics encountered;
   - commit/hash information.
8. Create the bounded feature closeout commit only after the final diff has been
   reviewed and the commit scope is approved.
9. Stop. Do not begin another v1.0.8 item automatically.

### Expected final changelist

Expected production file:

- `addons/easing_curve/scripts/easing_curve_editor.gd`.

Expected test file(s):

- `test/easing_curve_editor_gesture_characterization_test.gd`;
- possibly `test/easing_curve_editor_position_x_drag_test.gd` if the approved
  execution adds ordering-specific feature coverage there.

Bookkeeping:

- `test/docs/_test_plans/AXIS_DRAG_01_CODE_REPORT.md`.

The feature code plan should remain unchanged during execution.

### Approval gate

Present final diff/test/smoke summary before committing.

---

# 5. Planning baseline and important notes

## 5.1 Fresh baseline result

Immediately before these feature documents were created:

- branch: `dev`;
- commit: `e694fb8aec392a572791204f5e3a0ecc39ff950e`;
- worktree: clean;
- plugin: `1.0.8-dev`;
- Godot: 4.7.1 stable;
- full runner: 17/17 PASS.

The graph gesture suite baseline is 45 checks and currently has no Shift-event
coverage.

## 5.2 Godot reference behavior

The desired first implementation intentionally follows Godot's 2D editor model
for active movement:

- Shift checked on mouse motion;
- dominant total displacement selects X or Y;
- no extra threshold;
- no latch;
- releasing Shift immediately returns to unconstrained movement.

Easing Curve deliberately differs only in choosing dominance in **view space**
before applying the constraint to its normalized **world-space** target.

Godot does not expose the relevant `CanvasItemEditor` movement helper through a
public scripting API, so a small local implementation is expected.

## 5.3 Pre-held Shift reservation

Pre-held Shift is intentionally not consumed as the axis-constrain gesture in
v1.0.8. The initial Shift hold remains ordinary drag behavior. The implementation
must track enough state to distinguish that initial hold from a later Shift press
within the same drag.

This is reserved design space for future additive/multi-point/box selection.
No selection feature is part of AXIS-DRAG-01.

## 5.4 Known non-blocking diagnostic

The open editor may report:

`Cannot change to 'res://test/_serialization_transition_contract/' folder.`

This is the known serialization temporary-directory/editor scan race and does
not block AXIS-DRAG-01 while the registered suite continues to pass.

---

# 6. Report update rules during execution

After each approved step, append/update this report with:

- step status (`COMPLETE`, `BLOCKED`, `PARTIAL`, etc.);
- exact files changed;
- concise implementation record;
- targeted test commands/results and check counts;
- any live-editor/manual result;
- diagnostics and whether they are feature-related;
- Git diff/status result;
- any deviation from the code plan and the approval that authorized it;
- next approval gate.

Do not erase useful failed-attempt information when it explains a later design
choice. Distinguish tooling/test-fixture artifacts from production defects.

The code plan remains the compatibility/design authority. This report becomes
the execution history.

---

# 7. Current handoff

	**AXIS-DRAG-01 Steps 1-4 are complete.**

	Current implementation/characterization state:

	- modifier-capable baseline characterization: complete;
	- Shift-constrained point dragging: implemented and focused-validated;
	- Shift-constrained left/right Bézier handle dragging: implemented and focused-validated;
	- downstream Handle Mode / lock / Force Linear integration: characterized without a Step 4 production change;
	- graph gesture suite: 84 checks passing;
	- control editability suite: 21 checks passing;
	- Linear control alias suite: 72 checks passing;
	- point-state characterization suite: 106 checks passing;
	- Position-X drag suite remains at its Step 2 validation baseline of 69 checks passing.

	The next approval gate is:

	**AXIS-DRAG-01 Step 5 of 8 — Validate view-space dominance, pan/zoom, clamping, and ordering**

	Step 5 should focus on Easing Curve-specific geometry risks: view-space axis choice, diagonal boundary behavior, pan/zoom, point clamping, and X-order/endpoint takeover interactions.

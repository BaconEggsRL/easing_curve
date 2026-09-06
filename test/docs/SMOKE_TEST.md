# v1.2.0 — Legacy / Native parity smoke test

Run this paired checklist after the gates in [Development testing](README.md).
The detailed interaction checks below remain applicable to **both** APIs; they
are not a Legacy-only sign-off. An automated PASS does not verify physical input,
OS clipboard, visible layout, or editor-to-running-game integration.

## Candidate and paired fixtures

Record version ___; commit ___; working-tree changes ___; archive SHA-256 ___;
Godot ___; OS ___; display scale ___; browser ___; tester/date ___.

Primary environment: Windows x86_64, Godot 4.7.1, release Native DLL. Install only
the candidate addon in a clean project. Enable it under Project Settings > Plugins.

Create a Node with a script exporting two Resource properties, `legacy_curve`
and `native_curve`. Assign new EasingCurve and NativeEasingCurve resources.
Save the scene with the resources embedded. Duplicate the scene, save each
resource as a separate `.tres`, and use that scene for external-resource tests.
Do not alter existing project fixtures. Test the same named modes and edits on
Legacy and Native; their integer transition IDs need not match.

For Custom geometry, create endpoints (0, 0), (1, 1) and an interior point near
(0.5, 0.4). For random curves, generate once, then convert that persisted result
to the other API. Independently generated Jitter/Irregular shapes need not match.

### Intentional differences

- Legacy remains supported; migration is optional. Native targets Windows
  x86_64 and non-threaded Web. Windows Native debug DLLs/hot reload are excluded.
- Native bakes Legacy Custom Callables to points instead of retaining a live
  Callable. Read exact/baked/approximated/unsupported conversion reports.
- Conversion creates a separate unsaved copy and must not replace its source.
- Numerical equality is assessed by automated tolerances, not visual judgment.
  Editor view state is distinct from serialized curve geometry.

## Paired release scenarios

Run each scenario on Legacy and Native. Complete the detailed sections below
when a scenario references them. For every failure, record reproduction steps,
the resource kind (embedded/external), logs and an issue link.

| ID | Scenario | Legacy pass | Native pass | Evidence / issue / blocked reason |
| --- | --- | --- | --- | --- |
| P01 | Clean install, responsive layout and folding | [ ] | [ ] | |
| P02 | Transitions, Ease and modified presets | [ ] | [ ] | |
| P03 | Point selection, topology and handles | [ ] | [ ] | |
| P04 | Parameters, CSS and generation | [ ] | [ ] | |
| P05 | Real editor history and save/reload | [ ] | [ ] | |
| P06 | OS clipboard and conversion | [ ] | [ ] | |
| P07 | View controls, transforms and thumbnails | [ ] | [ ] | |
| P08 | Running scene and Windows/Web exports | [ ] | [ ] | |
| P09 | Restart, plugin lifecycle and compatibility | [ ] | [ ] | |

### P01 — Clean install and layout

Automation covers package import and control structure. Manually complete
sections 1–3 below on both fixtures at narrow, normal and wide Inspector widths,
and at the display scales claimed in the test record. Open popups, type Vector2
values, scroll, fold/edit/unfold, and switch resources.

Expected: one coherent graph/toolbar, readable fields and reset arrows, no overlap,
duplicate foldouts, stale rows or scroll jumps. Generate/Convert remain reachable.

### P02 — Transition and Ease availability

Automation covers sampling, parameter metadata, Points mode, Ease/reset state and
Native dropdown/history restoration. Manual coverage is popup/focus/redraw.

1. Set Quad / Ease Out. Switch to CSS Linear, then CSS Cubic Bezier. Ease and its
   reset must be unavailable; only the matching CSS input should be exposed.
2. Return to Quad. Change Ease, then reset it to In. Modify a control point:
   the modified marker/preset reset appear and Ease disables. Reset the preset;
   Ease becomes available again.
3. Visit Custom, Linear, Constant, Step, Back, Power, Elastic, Bounce, Spring,
   Physics Spring, Jitter and Irregular. Inspect parameter rows and point editing.

Expected: no stale values or rows. Custom/Linear/Constant/Step/CSS do not offer
Ease; clean ease-capable presets do. Points appear only for point-graph modes.

### P03 — Selection, topology, handles and typed fields

Automation covers state, identity, ordering, locks, invalid edits and simulated
gestures. Complete sections 4–12 below physically on both APIs: add via graph/list,
select from graph/list/toolbar, cross neighbors, Shift-drag, reorder at endpoints,
delete, cycle Handle Modes, toggle Force Linear/locks, type values, accept with
Enter/focus loss, and reset before/after reordering.

Expected: graph/list/fields refer to the same logical point, constraints hold,
drop indicators remain stable, one accepted edit gives one history action, and
a no-op click gives none. Observe hit targets, focus and drag feedback directly.

### P04 — Parameters, CSS and generated state

Automation covers sampling, deferred publication and representative round trips.

1. Edit/reset Back, Elastic, Bounce, Step and spring parameters with sliders and
   typed fields. Observe preview feedback and accepted values.
2. Enter `linear(0, 0.35 20%, 0.8 65%, 1)` and
   `cubic-bezier(0.42, 0, 0.58, 1)` in the respective modes.
3. Enter malformed CSS, then restore valid text. Compare fallback/diagnostics
   with Legacy and check recovery; do not assume malformed text is valid.
4. Generate Jitter/Irregular, convert the persisted result for comparison,
   save/reopen, undo/redo generation and play the animation.

Expected: no stale graph, partial accepted text, repeated action per drag tick,
or loss of generated data. Matching persisted fixtures play alike.

### P05 — Actual history, ownership and persistence

Automation uses the real EditorUndoRedoManager after freeing/replacing controls,
with embedded/external fixtures and another inspected resource. Manually verify
the actual editor keyboard routing and saved scene state on **both** APIs:

1. Save Quad / Ease Out. Select Elastic, CSS Cubic Bezier, then Quad. After each
   edit inspect another Node/resource and return, causing an Inspector rebuild.
2. Undo once per edit, then Redo. Check Trans, Ease, geometry, parameter rows and
   Points. A console history message alone is not a pass.
3. With resource B inspected, undo the earlier change to A; inspect both. Confirm
   the intended resource/history changes and B's data is unchanged.
4. Save after Undo, reopen the scene/resource and verify values. In a fresh edit
   sequence repeat after Redo. Restart Godot and verify persisted values again.
5. Repeat with point drag, lock, reorder, parameter change and preset reset.

Expected: the actual exported resource changes, not just its visible dropdown;
no wrong-resource edits, stale callbacks, missing geometry or extra actions.

### P06 — Clipboard and conversion dialogs

Automation validates typed paste and conversion contracts. OS exchange is skipped
in headless runs without clipboard support; dialogs require visible sign-off.

1. Copy/paste Position, control points, Handle Mode and supported boolean values
   Legacy-to-Native and back. Copy a property path before/after reordering.
2. Paste incompatible text; confirm no mutation or undo action.
3. Convert both ways for a preset, edited Custom, CSS and persisted random curve.
   Read the report; cancel once, then confirm and save under a new filename.
4. Convert a Legacy Custom Callable; inspect baking/report behavior and the result.

Expected: clicked-row targeting and current property paths; usable dialog focus;
cancel leaves source untouched; confirm opens a separate editable resource;
conversion limitations are disclosed and source/copy edits remain independent.

### P07 — Graph view, transforms and previews

Automation covers transforms, preview geometry and zoom routing. Physically pan,
zoom, Autofit, navigate selection, scroll inside/outside the graph and switch
resources. Toggle Reverse, Invert and both; compare graph and playback, then
undo/redo. Check saved FileSystem thumbnails after changing curves.

Expected: correct input target, no stale previews and no geometry changes from
view-only actions. Complete the matching detailed checks below.

### P08 — Running scene and exported applications

Automation separately covers Windows/Web exported numeric fixtures. It does not
certify physical editor-to-running-game interaction or browser presentation.

1. Run a small animation with each resource. Edit point, transition and parameter
   values while running; Undo/Redo each and observe actual motion.
2. Run both APIs from the clean candidate package in a Windows export.
3. Run non-threaded Web with extension support enabled in the export configuration.
   Record browser/version and debug/release; inspect loading, motion and console.

Expected: no missing library, graph/runtime divergence or repeated errors.

### P09 — Lifecycle and bounded compatibility claims

Save/restart/reopen both types, disable/re-enable the plugin twice and close the
project. In a separate Legacy-only project without Native binaries or serialized
Native types, open/edit/play a Legacy curve.

On each claimed compatible Godot version record its exact patch number and repeat
import/enable, P02, one point edit, P05 transition history, save/restart and playback.
The README advertises 4.4.0 minimum plugin loading and full workflow on 4.7.1;
an ABI run on 4.4.1 does not prove 4.4.0 or full UI compatibility. Unsupported
environments are N/A with a reason, never PASS. No unexplained plugin errors.

## v1.2.0 sign-off

- [ ] Automated results/skips recorded in [Development testing](README.md).
- [ ] P01–P09 completed for both resource forms; failures linked in the table.
- [ ] Actual candidate archive hash and clean-install result recorded.
- [ ] No unexplained editor/runtime/browser errors.
- [ ] Compatibility claims match tested environments.
- [ ] Tester/date ___; release decision and remaining blockers ___.

Automated execution does not check these boxes.

---

# Detailed visible interaction checks (run for both APIs)

Use this checklist for release-candidate validation of the Easing Curve Godot editor plugin.

This smoke test focuses on behavior that automated headless coverage cannot fully verify, especially Inspector layout, visible interaction, focus, folding, drag/drop, and editor refresh behavior.

## Test environment

Record before starting:

- Easing Curve version:
- Git commit:
- Godot version:
- Operating system:
- Display scale / DPI:
- Test project:
- Date:
- Tester:

Recommended primary release-candidate environment:

- Godot 4.7.1
- Windows 11
- Plugin enabled from `addons/easing_curve/plugin.cfg`

For compatibility claims, repeat the **Compatibility subset** near the end on each supported Godot version being claimed.

---

## 1. Plugin load and basic Inspector

- [ ] Open the project in the normal visible Godot editor.
- [ ] Confirm the Easing Curve plugin enables without parse errors or unexpected error dialogs.
- [ ] Select or create a resource/property using `EasingCurve`.
- [ ] Confirm the custom Easing Curve Inspector appears.
- [ ] Confirm the graph is visible and correctly sized.
- [ ] Confirm Transition and Ease controls are visible and usable where applicable.
- [ ] Confirm the Points section appears for Bézier-backed transitions.
- [ ] Confirm no controls overlap, clip unexpectedly, or render behind neighboring properties.

Pass criteria:

- Plugin loads normally.
- Inspector is usable without visible corruption.
- No new editor errors appear from simply opening the resource.

---

## 2. Responsive Inspector layout

Test at several Inspector widths.

### Narrow Inspector

- [ ] Drag the Inspector panel near its practical minimum width.
- [ ] Confirm the graph shrinks cleanly without horizontal clipping.
- [ ] Confirm Transition/Ease dropdowns remain usable.
- [ ] Confirm Vector2 properties remain readable and editable.
- [ ] Confirm reset buttons remain fully visible.
- [ ] Confirm there is a small visual gap between reset buttons and the property controls to their right.
- [ ] Confirm reset buttons do not draw behind Vector2 property fields.
- [ ] Confirm spacing between the graph/drag-handle area and property controls is preserved.

### Wide Inspector

- [ ] Expand the Inspector significantly.
- [ ] Confirm the graph grows responsively.
- [ ] Confirm rows and controls do not stretch into obviously broken layouts.
- [ ] Confirm reset-button alignment remains correct.

Pass criteria:

- No clipping, overlap, disappearing buttons, or visibly broken minimum-size behavior.

---

## 3. Points foldable section

- [ ] Expand the Points section.
- [ ] Collapse the Points section.
- [ ] Expand it again.
- [ ] Confirm fold state changes cleanly.
- [ ] Confirm controls do not become detached, duplicated, or leave stale visual artifacts.
- [ ] Confirm the graph and neighboring Inspector properties reposition correctly after folding/unfolding.
- [ ] Change another property while Points is folded, then expand Points again.
- [ ] Confirm the list reflects current curve state.

Pass criteria:

- Folding is stable and does not disturb selection or layout.

---

## 4. Point selection and selection persistence

Create a curve with at least three points.

- [ ] Select the first point from the graph.
- [ ] Confirm the corresponding Points-list entry/property controls show that point.
- [ ] Select a middle point from the Points list.
- [ ] Confirm the graph selection follows it.
- [ ] Select the last point from the graph.
- [ ] Confirm Inspector controls update to the same logical point.

Now cause Inspector refreshes:

- [ ] Edit the selected point Position.
- [ ] Edit a control point.
- [ ] Change Handle Mode.
- [ ] Toggle a lock.
- [ ] Toggle Force Linear.
- [ ] Fold/unfold Points.
- [ ] Resize the Inspector.

Pass criteria:

- The same logical point remains selected unless the performed operation intentionally changes/removes it.

---

## 5. Point list Move Up / Move Down

With at least three points:

- [ ] Use Move Up on a middle point.
- [ ] Confirm it swaps with the previous list entry.
- [ ] Confirm selection follows the moved logical point.
- [ ] Use Move Down and confirm the reverse.
- [ ] From the first point, use Move Up and confirm wrap/swap behavior matches the intended current UI behavior.
- [ ] From the last point, use Move Down and confirm the corresponding wrap/swap behavior.
- [ ] Confirm the graph updates immediately after every reorder.
- [ ] Undo and redo several reorder operations.

Pass criteria:

- List order, graph order, selection, and Undo/Redo remain synchronized.

---

## 6. Points-list drag reorder

With at least three points:

- [ ] Drag a point upward in the Points list.
- [ ] Confirm the drop indicator appears above/below the intended target.
- [ ] Hover directly around row midpoints.
- [ ] Confirm the drop line does not flicker or disappear unexpectedly.
- [ ] Drag toward the last point.
- [ ] Confirm the final valid insertion line can be reached without skipping.
- [ ] Drop the point.
- [ ] Confirm the logical point moves to the expected slot.
- [ ] Confirm selection follows the moved point.
- [ ] Undo and redo the drag reorder.

Pass criteria:

- Drop indicators are stable and visually above list panels.
- Reordering uses the intended swap/order model.
- No viewport/input errors appear after dropping.

---

## 7. Graph point dragging

With a custom Bézier curve:

- [ ] Drag an interior point horizontally.
- [ ] Confirm point ordering/slot behavior updates as intended when crossing another point.
- [ ] Drag vertically.
- [ ] Confirm the graph redraws continuously.
- [ ] Confirm unlocked control handles move with the point as intended.
- [ ] Lock Position and attempt to drag the point.
- [ ] Confirm the point does not move.
- [ ] Undo and redo a point drag.

Pass criteria:

- Motion is continuous, selection remains correct, and locks are respected.

---

## 8. Control-handle hit priority

Create a point where a control handle overlaps or nearly overlaps the main point.

- [ ] Attempt to grab the overlapping location.
- [ ] Confirm the main point wins when the intended hit-priority rule says it should.
- [ ] Move the handle away and confirm the handle can then be selected/dragged normally.
- [ ] Test both left and right handles where applicable.

Pass criteria:

- Handles do not make the point position inaccessible.

---

## 9. Handle modes

For an interior point, test each mode.

### Free

- [ ] Drag left handle.
- [ ] Confirm right handle does not move.
- [ ] Drag right handle.
- [ ] Confirm left handle does not move.

### Linear

- [ ] Switch to Linear.
- [ ] Confirm handles collapse to the point as intended.
- [ ] Attempt direct handle interaction.
- [ ] Confirm interaction falls back to the point where appropriate.

### Balanced

- [ ] Switch to Balanced.
- [ ] Drag one handle.
- [ ] Confirm the opposite handle rotates with it while preserving its own distance.

### Mirrored

- [ ] Switch to Mirrored.
- [ ] Drag one handle.
- [ ] Confirm the opposite handle mirrors both direction and distance.

### Linked

- [ ] Switch to Linked.
- [ ] Confirm linked control-state behavior is shared across both handles.
- [ ] Exercise lock and Force Linear interactions on each side.

Pass criteria:

- Each mode visibly matches its intended semantics without jumps or stale controls.

---

## 10. Force Linear and locks

For left and right controls individually:

- [ ] Enable Force Linear.
- [ ] Confirm the handle collapses to the point.
- [ ] Disable Force Linear.
- [ ] Confirm the handle restores to the intended default offset.
- [ ] Lock a handle.
- [ ] Confirm an active Force Linear state is cleared/restored according to current Inspector semantics.
- [ ] Enable Force Linear while a handle is locked.
- [ ] Confirm the last-action-wins behavior is correct.
- [ ] Repeat in Linked mode.
- [ ] Use the selected-point reset action.
- [ ] Confirm Handle Mode returns to Free and control locks/Force Linear reset as intended.
- [ ] Undo/redo these changes.

Pass criteria:

- No contradictory visual state exists between lock, Force Linear, and handle mode controls.

---

## 11. Pending point addition and live preview

- [ ] Begin adding a new point on the graph.
- [ ] Confirm the pending point appears before commit.
- [ ] Drag the pending point.
- [ ] Confirm the graph previews the curve as if the point were already inserted.
- [ ] Start to the right of an existing point, then drag across to its left.
- [ ] Confirm preview ordering updates so the pending point changes its relative position correctly.
- [ ] Confirm the preview remains a valid single-valued easing curve using the current discontinuity/jump behavior.
- [ ] Commit the point.
- [ ] Confirm the real curve matches the final preview.
- [ ] Start another pending add and cancel with right click.
- [ ] Confirm no point is added.

Pass criteria:

- Pending preview, insertion ordering, cancellation, and final commit remain synchronized.

---

## 12. Right-click delete

- [ ] Right-click an interior point.
- [ ] Confirm it deletes according to current rules.
- [ ] Drag with right mouse held across removable points.
- [ ] Confirm delete-drag behavior works continuously.
- [ ] Release right mouse.
- [ ] Confirm delete-drag state ends immediately.
- [ ] Move the mouse afterward.
- [ ] Confirm no additional points delete.
- [ ] Undo and redo deletion.

Pass criteria:

- No stuck delete-drag state.

---

## 13. Pan and zoom

- [ ] Middle-mouse drag the graph.
- [ ] Confirm panning is smooth.
- [ ] Release middle mouse and confirm panning stops.
- [ ] Scroll wheel up and down over the graph.
- [ ] Confirm zoom occurs around the pointer as intended.
- [ ] Confirm hover/selection behavior still updates after pan/zoom.
- [ ] Test zoom while using a FUNCTION transition.
- [ ] Confirm wheel zoom remains available even though point editing is disabled in FUNCTION mode.

Pass criteria:

- Pan/zoom remains responsive and does not break later gestures.

---

## 14. Presets, modified indicator, and Reset

Test several built-in Bézier presets, including Back.

For each:

- [ ] Select the preset.
- [ ] Confirm no modified `*` appears initially.
- [ ] Modify a point/control.
- [ ] Confirm the preset name gains `*`.
- [ ] Confirm the Reset button appears.
- [ ] Change Ease on the modified preset.
- [ ] Confirm the modified geometry is not unexpectedly replaced unless current behavior explicitly requires it.
- [ ] Press Reset.
- [ ] Confirm canonical preset geometry is restored.
- [ ] Confirm `*` disappears.
- [ ] Confirm Reset hides again.

Back:

- [ ] Change Overshoot.
- [ ] Confirm the Back curve rebuilds immediately.
- [ ] Confirm changing only Overshoot does not incorrectly mark the canonical Back preset modified.
- [ ] Test IN, OUT, IN_OUT, and OUT_IN.

Pass criteria:

- Preset identity, modified state, Ease handling, and Reset are visually consistent.

---

## 15. Function transitions

Spot-check:

- [ ] Step
- [ ] Power
- [ ] Elastic
- [ ] Bounce
- [ ] Spring
- [ ] Physics Spring
- [ ] Jitter
- [ ] Irregular
- [ ] CSS Linear
- [ ] CSS Cubic Bezier

For each applicable transition:

- [ ] Confirm expected parameter controls appear.
- [ ] Confirm unrelated parameter controls are hidden.
- [ ] Change a parameter.
- [ ] Confirm the graph updates.
- [ ] Confirm the modified indicator/reset behavior is correct where applicable.
- [ ] Confirm Ease is enabled only for transitions that support it.

Generated transitions:

- [ ] Generate new Jitter/Irregular data.
- [ ] Confirm visible curve data changes.
- [ ] Undo/redo generation if exposed through Undo/Redo.

CSS text controls:

- [ ] Type/edit normally in the LineEdit.
- [ ] Confirm keystrokes are not intermittently lost.
- [ ] Confirm valid input updates the graph.
- [ ] Confirm invalid/incomplete input does not crash the editor.

Pass criteria:

- Parameters, visibility, Ease eligibility, and graph refresh all match the selected transition.

---

## 16. Undo / Redo smoke

Perform a mixed sequence:

1. Add point.
2. Move point.
3. Move handle.
4. Change Handle Mode.
5. Toggle lock or Force Linear.
6. Reorder point.
7. Change transition/ease or parameter where appropriate.

Then:

- [ ] Undo each step one at a time.
- [ ] Confirm curve state returns correctly.
- [ ] Confirm logical point identity/order is restored.
- [ ] Confirm selection is restored correctly.
- [ ] Confirm Inspector controls refresh correctly.
- [ ] Redo all steps.
- [ ] Confirm the same states return.

Pass criteria:

- No stale Inspector state, wrong selected point, duplicate point, or lost point identity.

---

## 17. Save / reload

- [ ] Create a nontrivial EasingCurve resource.
- [ ] Include multiple points, non-default handles, locks/Force Linear, and a non-default mode where useful.
- [ ] Save the resource.
- [ ] Close and reopen the scene/resource.
- [ ] Confirm curve geometry and Inspector state represented by serialized data are preserved.
- [ ] Restart the Godot editor.
- [ ] Reopen the resource and confirm it still loads correctly.
- [ ] Confirm there are no migration warnings/errors for a newly saved resource.

If historical fixtures/resources are available:

- [ ] Open at least one older saved EasingCurve resource.
- [ ] Confirm it loads and displays correctly.
- [ ] Save a copy and reopen it.

Pass criteria:

- No lost points, handles, modes, generated data, or transition parameters.

---

## 18. Runtime / test-scene smoke

Using the included runtime comparison/test scene:

- [ ] Run the scene.
- [ ] Confirm the curve and Tween both animate.
- [ ] Change Curve Transition at runtime.
- [ ] Confirm the curve updates/restarts correctly.
- [ ] Change Curve Ease.
- [ ] Confirm the curve visibly changes.
- [ ] Change Tween Transition/Ease.
- [ ] If “Always match tween” is enabled, confirm Curve settings follow Tween settings.
- [ ] Toggle reverse playback.
- [ ] Confirm start/end behavior is reversed.
- [ ] Use manual restart.
- [ ] Confirm the currently selected runtime Transition/Ease is preserved.
- [ ] Check Step specifically for restart behavior.
- [ ] Confirm visible start/end markers render in the intended front/behind mode if that option is present.

Pass criteria:

- No stale runtime curve after property changes and no unexpected reset to Linear/defaults.

---

## 19. Update checker visible-editor smoke

Use only if update checking is enabled for the release candidate.

- [ ] Start the editor normally.
- [ ] Confirm the checker does not create repeated dialogs.
- [ ] Confirm Enable/Disable UI reflects the current setting.
- [ ] Disable update checks and confirm menu/settings state updates.
- [ ] Re-enable and confirm an immediate check occurs if that is the intended behavior.
- [ ] Confirm ignored-version UI/state is displayed correctly.
- [ ] Confirm update dialog buttons are readable and function as intended.
- [ ] Open another editor modal/settings window and ensure the update checker does not cause a disruptive exclusive-window error in normal use.

Known low-priority issue to watch:

- A request already in flight may still finish after update checks are disabled. Record if a late dialog appears.

Pass criteria:

- No blocking editor workflow issue.

---

## 20. Error / warning check

After completing the smoke test:

- [ ] Review the Godot Output panel.
- [ ] Review the Debugger Errors tab.
- [ ] Confirm no new `SCRIPT ERROR` occurred.
- [ ] Confirm no repeated plugin errors appeared during Inspector refreshes or Undo/Redo.
- [ ] Confirm no `meta` lookup errors such as missing `point_property_label` appeared.
- [ ] Distinguish known headless-only shutdown warnings from visible-editor errors.

Pass criteria:

- No unexplained plugin errors remain.

---

# Compatibility subset

Run this shorter subset on every Godot version explicitly claimed as supported, especially Godot 4.4 and 4.6 if the README continues to claim Godot 4.4–4.7 support.

- [ ] Plugin enables without parse/load errors.
- [ ] Custom EasingCurve Inspector appears.
- [ ] Graph renders.
- [ ] Points section expands/collapses.
- [ ] Add, select, move, and delete a point.
- [ ] Drag a control handle.
- [ ] Switch Handle Mode.
- [ ] Undo and redo an edit.
- [ ] Select several transitions and Ease modes.
- [ ] Edit one function parameter.
- [ ] Save and reload an EasingCurve resource.
- [ ] Run the runtime/test scene and confirm sampling/animation works.
- [ ] Check Output/Debugger for plugin errors.

If any supported version fails this subset, do not publish the compatibility claim unchanged.

---

# Release-candidate sign-off

## Required automated baseline

- [ ] All 17 registered automated test suites pass on the release candidate.
- [ ] No suite timeout.
- [ ] `git diff --check` passes.
- [ ] Release validation passes.
- [ ] Exact Asset Store ZIP contents are inspected.

## Manual visible-editor result

- [ ] PASS
- [ ] PASS WITH KNOWN NON-BLOCKING ISSUES
- [ ] FAIL

Notes:

```text

```

Release decision:

```text
READY / NOT READY
```

Tester:

Date:

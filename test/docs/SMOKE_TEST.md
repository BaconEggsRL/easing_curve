# Easing Curve — Manual Visible Editor Smoke Test

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

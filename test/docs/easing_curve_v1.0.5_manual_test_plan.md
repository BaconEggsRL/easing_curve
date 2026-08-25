# Easing Curve Plugin --- Manual Release Test Plan

Use this manual test plan in the real Godot editor **in addition to the
automated tests/suites run by Codex**. The goal is to catch interaction,
layout, Inspector-refresh, gesture, persistence, and packaged-install
problems that automated/headless tests may not fully exercise.

## 1. Clean Install / Enable

-   Install the packaged plugin into a clean Godot project.
-   Enable it.
-   Confirm no parser errors, warnings, duplicate settings, or startup
    exceptions.
-   Create/select an `EasingCurve` resource and verify the custom
    Inspector loads correctly.
-   Disable/re-enable the plugin once and verify the Inspector still
    works.

## 2. Basic Preset Behavior

-   Cycle through all built-in transitions and Ease modes.
-   Confirm the graph updates immediately.
-   Modify a preset and verify the modified `*` state appears.
-   Reset the preset and confirm canonical geometry returns.
-   Save/reload and verify selected transition/ease and modified state
    persist correctly.

## 3. Graph Navigation

-   Pan with MMB.
-   Zoom in/out with the mouse wheel.
-   Zoom while actively dragging a point.
-   Zoom while actively dragging a handle.
-   Verify the grabbed item remains under the cursor and dragging
    continues after zoom.
-   Test narrow/wide Inspector resizing and autofit if applicable.

## 4. Add Points

-   Add a point by normal click.
-   Test pending-add:
    -   Press and hold LMB on empty graph.
    -   Move the pending point around.
    -   Cross several existing points.
    -   Confirm the graph previews the resulting topology live.
    -   Release to commit.
-   Confirm the newly added point is selected in the toolbar.
-   Pending-add then RMB cancel:
    -   Pending point disappears.
    -   Nothing is committed.
    -   Keep RMB held and move over real points---nothing should delete
        until RMB is released and pressed again.

## 5. Point Dragging / Ordering

-   Drag an existing point left/right through several neighboring points
    without releasing.
-   Confirm graph ordering updates live.
-   Drag back and forth across the same neighbor several times.
-   Release and verify final Points-list ordering matches the graph.
-   Confirm the same logical point remains selected after its index
    changes.
-   Undo once and verify original position/order returns; Redo restores
    final state.

## 6. Endpoint Takeover

-   Drag/add a point onto occupied `x=0`.
-   Confirm the active point replaces the old endpoint in preview and on
    commit.
-   Repeat at `x=1`.
-   Verify `sample(0)` / test-scene start behavior matches the new left
    endpoint.
-   Verify `sample(1)` / animation end matches the new right endpoint.
-   Drag to an endpoint, then back inward before release; the old
    endpoint should remain.
-   Undo/Redo takeover.
-   Confirm interior equal-X points are **not** deleted.

## 7. Interior Duplicate-X Behavior

-   Put two points at exactly the same interior X.
-   Confirm both remain.
-   Verify the editor displays the vertical discontinuity.
-   Drag one through the other.
-   Verify no disappearing points, hooks, or unstable sorting.

## 8. Handle Modes

Test every mode on a middle point:

-   Free
-   Linear
-   Balanced
-   Mirrored
-   Linked

Then:

-   Drag both left and right controls where applicable.
-   For Balanced, rotate handles through horizontal/diagonal/vertical
    orientations and resize/zoom the graph; apparent opposite-handle
    length should remain stable.
-   For Mirrored, verify equal/opposite behavior.
-   For Linear, verify controls remain coincident with the point.

## 9. Linear Mode Property Editing

-   In Linear mode, edit Position X/Y from the Points list.
-   Edit Left Control X/Y.
-   Edit Right Control X/Y.
-   Confirm all three represent the same location and remain coincident.
-   Drag a Linear control X field across multiple point X positions
    without releasing.
-   Confirm it behaves exactly like Position X editing and does not get
    stuck.

## 10. Force Linear / Locked

-   In Free mode, set L/R independently to Free, Linear, and Locked.
-   Verify toolbar and Points list stay synchronized.
-   Force Linear controls should behave according to the current
    non-independent-edit rule.
-   Locked controls should resist direct graph/numeric editing.
-   Undo/Redo each state change.
-   Test Linked + current supported Linear/Locked behavior.

## 11. Selected-Point Toolbar

-   Select first, middle, and last points.
-   Verify `P0`, `P1`, etc. updates correctly.
-   Verify Handle/L/R dropdown visibility for each endpoint/mode.
-   Check full text at normal Inspector width.
-   Shrink Inspector and verify ellipsis instead of wrapping.
-   Confirm Handle dropdown starts aligned with Ease/Trans dropdowns.
-   Confirm reset buttons line up vertically with Ease/Trans.
-   Confirm reset space remains reserved so dropdown widths do not jump.
-   Verify L/R labels have identical width.
-   Verify vertical row spacing matches Ease/Trans.

## 12. Toolbar / Handle Reset

-   From Free with L/R modified, Reset → Free/Free/Free.
-   From Balanced/Mirrored/Linked, Reset → Free.
-   From Linear, Reset → Free and confirm handles restore exactly as a
    manual Linear → Free transition would.
-   Test the Handle Mode reset button in the Points list.
-   Confirm it follows the same transition behavior as manually
    selecting Free.
-   Undo/Redo reset and verify geometry/state restoration.

## 13. Points-List Numeric Sliders

-   Drag Position X continuously through multiple points and back
    without releasing.
-   Confirm the slider never gets interrupted.
-   Confirm graph preview updates live.
-   Confirm the list row does not disrupt the gesture.
-   Confirm ordering settles correctly on release.
-   Confirm one Undo restores the whole drag.
-   Repeat for Position Y.
-   Repeat Linear-mode control X alias behavior.

## 14. Manual Points-List Reorder

-   Use Up/Down arrows.
-   Use drag-and-drop.
-   Confirm both use identical **X-slot swap** semantics:
    -   X swaps.
    -   Y stays with the logical point.
    -   Both controls translate horizontally with their point.
-   Repeat with Position/control locks enabled; structural reorder
    should ignore locks.
-   Confirm the moved logical point is selected at its new index.
-   Repeated arrow clicks should continue moving the same point.
-   Undo/Redo and verify geometry/order/selection.

## 15. Point Deletion

-   RMB single-click delete.
-   Hold RMB and sweep across several points.
-   Release RMB and hover another point; it must not delete.
-   Start RMB on empty space and release; no stale delete state.
-   Test deletion of the selected point and points before/after
    selection.
-   Verify toolbar selection remains valid.

## 16. Global Transforms

-   Configure several points with different Handle Modes/states.
-   Apply every global transform/reverse/invert operation.
-   Immediately open/inspect the Points list without dragging anything.
-   Verify positions, controls, modes, locks, and Force Linear state are
    already correct.
-   Undo/Redo transforms and verify the Points list refreshes
    immediately.
-   Specifically inspect Linear/Balanced/Mirrored invariants.

## 17. Pathological Bézier Shapes

-   Put Free handles far outside neighboring X intervals.
-   Create very narrow adjacent segments.
-   Move points nearly to equal X.
-   Confirm the graph remains deterministic, continuous where intended,
    and free of hooks/jitter/gaps.
-   Verify stored handles remain where authored.
-   Compare graph to runtime/test-scene output.

## 18. Missing Endpoints

-   Remove/move the first point away from `x=0`.
-   Verify the graph displays actual fallback output before the first
    point.
-   Do the same for missing `x=1`.
-   Test zero points and one point.
-   Verify graph and runtime/test scene agree.

## 19. Function-Mode Regression

-   Cycle all function-backed transitions.
-   Edit each exposed parameter.
-   Verify graph updates immediately.
-   Test Ease changes.
-   Test Reset / modified indicator.
-   Save/reload representative function curves.
-   Ensure recent Bézier/editor changes did not affect Function mode.

## 20. Persistence

Build one deliberately complex curve using several points, mixed Handle
Modes, locks/Linear states, unusual handles, and interior duplicate X.

Then:

-   Save the resource.
-   Close/reopen the project.
-   Verify geometry, ordering, modes, locks, toolbar state, and runtime
    output are unchanged.

## 21. Final Packaged Smoke Test

-   Build the Asset Store ZIP.
-   Install that ZIP into a separate clean project rather than testing
    only the development checkout.
-   Enable the plugin.
-   Create/edit/save/run one Bézier curve and one Function curve.
-   Verify version display/update checker/package structure.
-   Confirm no dependencies on development-only/test files.

## Release Sign-Off

If all automated suites pass **and** this manual pass is clean, v1.0.5
can be considered release-ready.

Highest-value manual checks:

-   Continuous slider dragging.
-   Pending-add / RMB interactions.
-   Endpoint takeover.
-   Toolbar and Points-list layout.
-   Undo/Redo across topology changes.
-   Global-transform Inspector synchronization.
-   Clean packaged-plugin smoke test.

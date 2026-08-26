# Final Manual Editor Check

## Fold / focus
- Points: first collapse does not move Inspector scroll -- PASS
- Points: repeated collapse/expand remains stable -- PASS
- Curve Editor: same checks -- PASS
- Foldable titles remain clickable -- PASS
- No unexpected focus jump -- PASS
OVERALL: PASS


## Layout
Test narrow and wide Inspector widths:
- Ease / Trans rows align -- PASS
- reset buttons do not overlap -- PASS
- point labels align -- PASS
- X/Y fields remain usable -- PASS
- lock / Force Linear controls remain usable -- PASS
- Curve Editor does not clip unexpectedly -- PASS
OVERALL: PASS
FINDINGS: Curve editor point properties row reset button width is not respected at small inspector panel widths. This is a known issue; not a bug.
This is the only way to fit all properties on one row and reach close to the minimum inspector panel width.


## Selection
- select point from graph -- PASS
- select point/property from list -- PASS
- graph/list/property selection stays synchronized -- PASS
- selection survives Inspector refresh -- PASS
- switch resources and back; selection does not leak -- PASS
OVERALL: PASS


## Point operations
- Add Point -- PASS
- trash/delete Point — no errors -- PASS
- Move Up / Move Down -- FAIL
- drag reorder -- FAIL
- Position-X reorder -- FAIL
For each:
- Undo
- Redo
- selection follows expected point
OVERALL: FAIL
FINDINGS:
Position dragging fails undo/redo preservation/restoration of selected point.
Scene Redo: Move Easing Curve Point
Scene Undo: Move Easing Curve Point
does not preserve point selection (example: Select and drag P2 before P1; P2 is now P1. Point properties updates from P2 to P1.
Undo the operation. Point properties should update back to P2; but is still P1.


## Handles
Quickly exercise:
- Free
- Linear
- Balanced
- Mirrored
- Linked
- Lock
- Force Linear
FINDINGS: Overall point dragging on curve editor & Linear seems a bit slow for some reason.
Not a blocker at the moment; but future refactors may want to look at speed improvements.
OVERALL: PASS


## Transition controls
- Constant slider feels correct at 0.001 precision
- Back overshoot works
- Ease changes work
- modified asterisk/reset behaves normally
OVERALL: PASS


FINAL TEST RESULTS:
Investigate failures in Point operations. This is a release blocker.
Note non-blocking Layout findings and Handles findings for future work.
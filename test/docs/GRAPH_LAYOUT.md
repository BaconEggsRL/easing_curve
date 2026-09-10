# Curve editor graph layout

The native and legacy Inspector presentations share `EasingCurveEditor`.
Its root remains a `Control`; an internal vertical container places the point
toolbar, Grid Snap row, clipped graph canvas and zoom row in separate regions.
Curve resources, backend interfaces, undo transactions and serialized view state
are unchanged. `setup_zoom_row()` creates the internal zoom controls idempotently;
external `set_slider_container()` bindings remain supported.

## Width-driven graph size

`PREFERRED_GRAPH_HEIGHT` is 180 logical pixels. The final usable graph width `W`
is the Inspector allocation minus four logical pixels of padding on each side.
For editor scale `S`, graph height is `clamp(180 * S, W / 2, W)`. Padding is
removed once when determining `W`, and added once around the resulting graph.

| Usable width at 100% | Graph height | Aspect |
| --- | --- | --- |
| 150 | 150 | 1:1 |
| 220 | 180 | 1.22:1 |
| 270 | 180 | 1.5:1 |
| 360 | 180 | 2:1 |
| 600 | 300 | 2:1 |

Toolbar visibility affects total editor height, never graph
dimensions at a fixed width and scale. The preferred graph height does not
publish a horizontal minimum. The existing graph minimum and Inspector
property-wrapper compensation are preserved.

## Single-row point toolbar and input

The point toolbar uses one non-wrapping row: navigation/index, Handle Mode,
applicable L/R state dropdowns, and one reserved combined reset. The row clips
at the Inspector's right edge when controls cannot shrink further; its preferred
width never becomes a graph minimum. Dropdowns retain their current tooltips.
Ease and Trans reserve the navigation-column width to align their dropdowns.

Unavailable L/R groups are hidden. Linked mode retains both applicable dropdowns,
with either editing the shared state. With no selection, the disabled arrows and
"0" stay visible, and the row reserves its full height to prevent vertical shifts.
Function mode keeps point controls and snapping hidden. Grid Snap and zoom remain
separate from the graph.

The reset submits `toolbar_options_reset`, restoring Free Handle Mode and clearing
both sides' Force Linear and handle-lock flags while preserving the position lock.
Its slot stays allocated, transparent and non-interactive when inactive. Each
edit or reset remains one Undo/Redo action. Side-specific reset intents remain
available for existing internal callers; the removed second-row reset intent is
no longer supported.

Graph drawing and transient coordinate feedback are children of the clipped
canvas. Drawing and input convert at the canvas boundary while public view/world
coordinates remain editor-local. The coordinate readout reserves no persistent
height; formatting, horizontal/vertical tracking and edge clamping are retained.

Editor Settings → Easing Curve → Curve Editor provides `Hide Position Tooltip`
and `Hide Grid Snapping Row`. Both default to off and update open Inspectors
immediately. Hiding the snapping row removes its height and separation without
changing snap enablement or subdivisions. Hiding the tooltip affects graph and
Inspector coordinate drags without changing editing behavior.

Godot mouse capture was verified with viewport-dispatched left, middle and right
button events across siblings, then with actual point, handle, pan, add and delete
gestures. An active graph gesture continues through motion/release over controls;
a fresh control-row press never starts graph editing. Empty row space is outside
the graph input boundary. No global gesture interception was added. Existing
focus-loss readout suppression and Shift-reference reset behavior is preserved.

## Auto Fit

The canonical graph rectangle drives transforms, visible sampling bounds,
coordinate placement and fitting. Auto Fit retains existing world bounds
(including handles and sampled Function overshoot), padding and discrete zoom
steps. It no longer subtracts toolbar obstructions or applies an overlay zoom
penalty or corrective pan. Initial fitting waits for a stable graph rectangle;
ordinary resizing retains the user's zoom and pan.

## Repeating validation

Run `test/runners/run_all_tests.ps1 --run` for all isolated correctness suites.
The layout contract suite covers both backends, narrow/wide allocations, aspect
breakpoints, scale/font changes, minimum widths, applicable L/R fields,
long-label clipping, Ease/Trans alignment, combined reset transactions,
no-selection spacing and graph dimensions.

Use `test/runners/run_curve_editor_layout_validation.ps1` for the same layout
suite inside a full, rendered Godot editor with real editor icons and fonts.
Its optional `-Suite` also accepts
`easing_curve_editor_gesture_characterization_test` and
`easing_curve_editor_drag_coordinates_test`. The runner copies the product and
fixtures into a unique `test/_temp/layout-editor-*` project, adapts only the
selected SceneTree suite to an EditorPlugin host and preserves logs/captures.
It honors `EASING_CURVE_GODOT_PATH` through the existing Godot launcher.

The standalone `--editor --script` host intentionally lacks an editor theme, so
its rendered captures alone cannot validate icon/text minimum widths. The full
editor runner closes that gap without altering product scenes or settings.
It disables idle rendering throttling only in the isolated test host so awaited
draw events continue firing; readout captures use a dedicated SubViewport.
Gesture captures include native/legacy Custom and Function presentations at
150, 220, 360 and 600 pixel allocations; the suite also verifies fold/reopen and
initial-fit lifecycle behavior. Readout captures exercise point, handle,
pending-add and Inspector-field feedback with zoom, pan and scale changes.

All Godot logs stay under repository-local `test/_temp/`. The main runner already
recognizes the Godot 4.7.1 certificate-store and editor shutdown leak diagnostics.
The two existing `editor_undo_redo_test.gd` CSS dropdown-label assertions were
reproduced against starting commit `23760bcbf7bfdfe43b7cca3c7177d956bb645663`;
they are unrelated to this layout change.

## Linked-state regressions

### Native Linked lock correction

Native point setters write individual sides. The backend now expands a Linked
control-state edit to both sides before committing the existing transaction.
Locked sets both handle locks; Free and Linear clear both locks and update both
Force Linear flags. This prevents a shared Locked label from masking a movable
handle. The single-row toolbar continues to use this backend behavior.

The existing dropdown regression now covers Free, Linear and Locked through
both endpoint dropdowns, with normal/reversed mapping on both backends. It checks
stored flags against drag availability, complete single-action Undo/Redo, and
viewport-dispatched attempts to drag locked Linked handles. The expanded flag
checks reproduced 36 failures before the fix; the full-editor run after the fix
passed 23,399 checks. Logs are `native-linked-lock-before-console.txt`,
`native-linked-lock-after-console.txt` and `native-linked-lock-full-console.txt`
under `test/_temp/`. Full validation passed 33 of 34 suites; only the two known
CSS-label assertions failed. The correction changes `native_curve_editor_backend.gd`,
the existing layout contract suite and this document.

Both Inspectors use the same pure Handle Mode transition when entering Linked.
The shared state resolves in priority order: Locked, Linear, then Free. Either
lock locks both sides and clears both losing Force Linear flags. If exactly one
side is locked, its existing coordinate becomes both handles' coordinate even
when the other handle is longer. With both sides locked, the existing longest
handle rule breaks the tie. With no locks, either Linear flag enables both sides.
Position locks and runtime point setters are unchanged. This covers Free with
L Locked / R Free or Linear (and the reverse), which is
a different path from editing a dropdown after the point is already Linked.
Regression coverage checks all 16 flag combinations, both endpoints and reversed
mapping, blocked viewport dragging, and one Undo restoring the original asymmetric
Free state. Returning from Linked Locked to Free retains the shared coordinate
and cannot reactivate the discarded Linear flag. Undo restores the original
asymmetric state, including that original flag. The earlier expanded suite reproduced 108 failures before its correction
and passed all 24,215 checks afterward. Full validation again passed 33 of 34
suites, with only the two known CSS-label failures. Evidence is under
`test/_temp/native-enter-linked-*-console.txt`.

### Inactive Native overrides

Native's disabled L/R fields display stored Linear/Locked values in Linear,
Balanced and Mirrored modes. Those values remain serialized but have no effect
on handle dragging until Free or Linked makes them applicable again. The Native
point setter now gates Force Linear by the active Handle Mode, matching Legacy's
existing drag behavior. It no longer collapses Mirrored/Balanced handles when a
stored Linear flag is inactive. Legacy production code is unchanged.

The Native smoke suite compares repeated mode changes and control edits against
Legacy with either side forced linear and the opposite side locked. It checks
that stored flags survive each edit. The layout suite exercises both interior
handles through viewport input, normal/reversed transforms and Undo/Redo, and
checks stored control-state values. The pre-fix Native smoke run failed 68 checks;
the rebuilt Windows release DLL passes all 2,053 smoke checks. Build and test logs
are under `test/_temp/inactive-overrides-*`. Full-editor layout/input validation
passes 24,693 checks. Reopen an existing Godot session before retesting to ensure
it loads the rebuilt Native library; only the Windows release binary was rebuilt.
Full validation passed 33 of 34 suites, with only the two known CSS-label failures.

### Linked state precedence and locked geometry

The mixed Linear/Locked case is covered through both Inspector transaction paths,
both endpoints, reverse transforms, viewport drag blocking and complete Undo/Redo.
Separate fixtures make the locked control shorter than the unlocked control and
verify that its coordinate wins. All 16 stored flag combinations are checked.
Entering Linked resolves competing overrides; passing through an inactive mode
still leaves stored overrides untouched. Returning to Free preserves the resolved
Linked geometry, while explicitly selecting the main Linear mode still collapses
both handles by design.

The expanded pre-fix run failed 200 checks. The corrected full-editor suite passes
24,873 checks; evidence is in `test/_temp/linked-precedence-*-console.txt`.
The older Legacy drag fixture permits at most 0.000001 units of float32 rounding
in restored handle coordinates. It still requires exact resource order, point
positions, modes and flags; the new Linked transition snapshots remain exact.
No Native library rebuild is needed for this Inspector-policy change.
Full validation passed 33 of 34 suites, with only the two known CSS-label failures.

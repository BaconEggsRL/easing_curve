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

Toolbar visibility and wrapping affect total editor height, never graph
dimensions at a fixed width and scale. The preferred graph height does not
publish a horizontal minimum. The existing graph minimum and Inspector
property-wrapper compensation are preserved.

## Grouped controls and input

The point toolbar uses the characterized Godot 4.7 `HFlowContainer`. Navigation,
handle mode, left label/state, right label/state and reset are separate groups;
labels remain with their fields. Current option text, theme padding and arrows
determine preferred field widths, bounded by the allocated group width.
Unavailable reset controls are hidden so they cannot create an empty flow row.
The zoom slider can shrink to 32 logical pixels before its surrounding controls.

At a fixed width, scale, selection and visibility state, the row arrangement
settles deterministically. No control region forces the Inspector wider.
Function-mode toolbar/snapping visibility retains the existing setting.

Graph drawing and transient coordinate feedback are children of the clipped
canvas. Drawing and input convert at the canvas boundary while public view/world
coordinates remain editor-local. The coordinate readout reserves no persistent
height; formatting, horizontal/vertical tracking and edge clamping are retained.

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
breakpoints, scale/font changes, minimum widths, deterministic wrapping,
readable dropdowns, transient label bounds and repeatable fitting.

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

Final validation on Godot 4.7.1: 33 of 34 headless suites passed, with only those
two baseline CSS-label failures. Full-editor runs passed 1,743 layout checks,
831 gesture checks and 1,035 readout checks. Selected-point captures confirm
readable grouped controls and strict graph boundaries at narrow/wide widths;
native and legacy coordinate feedback was also visually inspected.

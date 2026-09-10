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

## Fixed point-toolbar rows and input

A selected point has exactly two horizontal rows inside the shared vertical
point toolbar. Neither row wraps:

- Row 1: previous / index / next, Handle Mode field, reserved mode-reset slot.
- Row 2: L / left-state field, R / right-state field, reserved state-reset slot.

Shrinkable option slots report height independently of their field's preferred
text width. Dropdowns clip/ellipsize text, keep tooltips and share remaining
Row 2 space equally (allowing one pixel of rounding). Compact navigation icons
and unpadded L/R labels leave room for the native dropdown chrome even at the
established narrow Inspector allocation. The shared reset-button factory and
compact separation metric align both trailing slots with the Ease/Trans column.
Inactive reset buttons stay allocated, transparent, disabled and non-focusable.
Unavailable side fields remain visible but disabled, including missing endpoint
handles and modes that mask side overrides. No selection hides the second row;
Function-mode toolbar/snapping visibility retains the existing setting.

At a fixed width and scale, selection-state changes do not change graph size.
The two selected rows keep a constant height across Handle Modes. Repeated
resizing and long localized field labels settle without recurring minimum-size
notifications. The zoom slider remains in its separate row and can shrink to
32 logical pixels before its surrounding controls.

### Independent resets

Row 1 submits the existing `handle_mode = Free` edit. Characterization covers
both backends, all five modes and 16 combinations of stored Force Linear / Lock
flags: the existing path preserves those stored flags exactly.

Row 2 submits one `control_states_reset` intent through the existing transaction
pipeline. Legacy snapshot mutation and the Native backend clear both Force
Linear flags and both handle-lock flags, including masked overrides. Handle
Mode, position locks and handle coordinates remain unchanged. Each reset has
one Undo/Redo action; an unavailable reset creates no action. The old combined
`toolbar_options_reset` intent and callback remain compatible for existing
callers, and neither new button invokes them. Resource and backend method
signatures, serialization and curve mathematics are unchanged.

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
breakpoints, scale/font changes, minimum widths, two fixed toolbar rows,
long-label clipping, reset-column alignment, independent reset transactions,
transient label bounds and repeatable fitting.

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

## Two-row refinement measurements

Both backends produced identical measurements in the full-editor fixture.
Scale coverage combines the editor scale used by the graph/compact controls
with 16 / 24 / 32 pixel fonts; icons and styling come from the real host editor.
This is automated scale/font coverage, not three separate OS-DPI sessions.

| Scale | Editor width | Mode field | Left / right fields | Reset left edge (all rows) | Usable graph | Presentation minimum width |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| 100% | 150 | 50 | 44 / 44 | 118 | 142 × 142 | 147 |
| 150% | 225 | 92 | 75 / 76 | 193 | 213 × 213 | 168 |
| 200% | 300 | 134 | 105 / 105 | 268 | 284 × 284 | 189 |

All widths are measured pixels. Both reset columns match the Ease/Trans left
and right edges exactly; neither row wraps. Presentation minimum widths match
the pre-refinement measurements. The existing property-wrapper compensation
is unchanged. `point-toolbar-{native|legacy}-{150|220|600}.png` captures include
active reset buttons; the gesture and readout captures cover graph boundaries,
fold/reopen, scrolling, dragging and feedback.

Final validation on Godot 4.7.1 passed 33 of 34 isolated suites. The only failures
were the same two baseline CSS-label assertions noted above. Both headless and
full-editor layout runs passed 14,703 checks. Full-editor gesture validation
passed 831 checks, and coordinate-readout validation passed 1,035 checks. Narrow,
medium and wide selected-point captures were visually inspected, including
visible navigation arrows, active reset buttons and strict graph boundaries.
Both reset operations passed viewport-dispatched single-action Undo/Redo tests
for Legacy and Native, including masks imposed by unavailable Handle Modes.

Preserved evidence under `test/_temp/`:

- Full suite: `two-row-full-final-console.txt`.
- Layout and reset checks: `two-row-clean-captures-console.txt`.
- Clean active-reset captures: `layout-editor-fb4fbf38c11848dd8941c0ce92887f6a/test/_temp/`.
- Rendered gestures: `two-row-gesture-final-console.txt`.
- Rendered readouts: `two-row-readout-final-console.txt`.

The refinement began at feature-branch commit `9126c45`, which already contained
the user's no-selection indicator change to `0`; its working tree was clean.
No test-scene edits were introduced or restored. `dev` was verified unchanged
at `23760bcbf7bfdfe43b7cca3c7177d956bb645663` before and after implementation.

### Files changed by the refinement

- `addons/easing_curve/scripts/editor/easing_curve_editor.gd`
- `addons/easing_curve/scripts/editor/backend/native_curve_editor_backend.gd`
- `addons/easing_curve/scripts/editor/inspector/editor_theme_cache.gd`
- `addons/easing_curve/scripts/editor/inspector/inspector_curve_context.gd`
- `addons/easing_curve/scripts/editor/inspector/point_edit_transaction_controller.gd`
- `addons/easing_curve/scripts/runtime/easing_curve_point_snapshot_mutator.gd`
- `test/scripts/unit/easing_curve_layout_contract_test.gd`
- `test/scripts/unit/easing_curve_points_list_reorder_editor_test.gd`
- `test/runners/run_curve_editor_layout_validation.ps1`
- `test/docs/GRAPH_LAYOUT.md`

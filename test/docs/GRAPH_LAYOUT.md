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

The selected-point toolbar always has two non-wrapping rows:

- Navigation/index, Handle Mode, reserved mode-reset slot.
- L and R dropdowns on one shared row, followed by one reserved shared reset.

Linked mode keeps the separate L and R dropdowns on the same row. Both display
the backend's shared Linked state; editing either available side updates both.
At endpoints, the missing side remains visible but disabled.

Shrinkable slots report height independently of preferred text width. Dropdowns
clip/ellipsize text and retain tooltips. L/R share the available row width equally
in every mode. Labels reserve matching widths. The trailing reset slot stays aligned with
Handle Mode and Ease/Trans. Inactive resets remain allocated, transparent,
disabled and non-focusable. Unavailable side fields remain visible but disabled
in every mode. No selection hides the state row; Function-mode visibility
is unchanged.

Switching between Linked and other Handle Modes preserves the two-row height
and graph dimensions at a fixed width. Resizing, mode switching and long labels
settle without recurring minimum-size changes. Grid Snap and zoom stay separate.

### Independent edits and resets

Handle Mode reset remains `handle_mode = Free` and preserves stored Force Linear
and Lock flags. The shared state-row reset always submits `control_states_reset`:
it clears both sides' Force Linear and handle-lock flags, preserving Handle Mode,
position locks and handle coordinates. This also applies in Linked mode.
Each dropdown edit or reset remains one Undo/Redo action.

The earlier side-specific reset intents remain available to existing internal
callers, but the toolbar no longer exposes individual side reset buttons. The
old `toolbar_options_reset` intent/callback also remains compatible and is not
used by either toolbar reset. Backend/resource signatures, serialization and
curve mathematics are unchanged.

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
breakpoints, scale/font changes, minimum widths, separate L/R fields in every mode,
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

## Shared and Linked row measurements

Both backends produced identical measurements in the full-editor fixture.
Scale coverage combines the editor scale used by the graph/compact controls
with 16 / 24 / 32 pixel fonts; icons and styling come from the real host editor.
This is automated scale/font coverage, not three separate OS-DPI sessions.

| Scale | Editor width | Mode field | Left / right fields | Reset left edge (all rows) | Usable graph | Presentation minimum width |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| 100% | 150 | 50 | 44 / 44 | 118 | 142 x 142 | 147 |
| 150% | 225 | 92 | 75 / 76 | 193 | 213 x 213 | 168 |
| 200% | 300 | 134 | 105 / 105 | 268 | 284 x 284 | 189 |

All widths are measured pixels. Linked mode uses the same field allocations.
All reset columns match Ease/Trans left and right edges
exactly; no row wraps. Presentation minimum widths match
the pre-refinement measurements. The existing property-wrapper compensation
is unchanged. `point-toolbar-{native|legacy}-{separate|linked}-{150|220|600}.png` captures include
active reset buttons; the gesture and readout captures cover graph boundaries,
fold/reopen, scrolling, dragging and feedback.

Final validation on Godot 4.7.1 passed 33 of 34 isolated suites. The only failures
were the same two baseline CSS-label assertions noted above. Both headless and
full-editor layout runs passed 22,895 checks. Full-editor gesture validation
passed 831 checks, and coordinate-readout validation passed 1,035 checks. Narrow,
medium and wide selected-point captures were visually inspected, including
visible navigation arrows, active reset buttons and strict graph boundaries.
Mode and shared state resets passed viewport-dispatched single-action Undo/Redo
tests for Legacy and Native. Dropdown signal-path tests also verify one-action
Undo/Redo, shared Linked state, opposite-side preservation and reversed mapping.

Preserved evidence under `test/_temp/`:

- Full suite: `split-linked-full-console.txt`.
- Layout and reset checks: `split-linked-layout-console.txt`.
- Active-reset captures: `layout-editor-be6b9c3806c54df9acf2dc9cee997dab/test/_temp/`.
- Rendered gestures: `split-linked-gesture-console.txt`.
- Rendered readouts: `split-linked-readout-console.txt`.

This refinement began on clean `feature/curve-editor-max-graph-area` at `fda3850`.
The earlier no-selection indicator change to `0` is
preserved. No test-scene edits were made. `dev` remains
`23760bcbf7bfdfe43b7cca3c7177d956bb645663`.

### Files changed by the refinement

- `addons/easing_curve/scripts/editor/easing_curve_editor.gd`
- `test/scripts/unit/easing_curve_layout_contract_test.gd`
- `test/docs/GRAPH_LAYOUT.md`

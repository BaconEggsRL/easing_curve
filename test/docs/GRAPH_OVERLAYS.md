# Full graph overlays

## Baseline (2026-09-09)

Measured before changing production code, using the actual Legacy and Native
Inspector constructors in an isolated Godot 4.7 Editor host at scale 1.0.
`overlay_layout_baseline.json` contains every measurement, including Function
mode. Heights include the Curve Editor foldable header, but exclude Ease/Trans.

| Width | Outer section | Graph Control | Custom graph viewport | Function viewport | Top reservation (custom/function) | Zoom minimum | Parent gap |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 320 | 270 | 212 | 109 | 204 | 95 / 0 | 32 | 2 |
| 450 | 330 | 272 | 169 | 264 | 95 / 0 | 32 | 2 |
| 700 | 446 | 388 | 285 | 380 | 95 / 0 | 32 | 2 |

Both backends agree. The custom top reservation comprises 64 pixels for toolbar
heights and 31 pixels for coordinate padding. Both modes also retain 4 pixels
of graph margin on each edge. Screenshots are in `test/_temp/overlay-before/`.

Baseline full correctness: 32 of 33 suites passed. `editor_undo_redo_test.gd`
already fails two CSS dropdown label assertions ("Css Cubic Bezier" and "Css
Linear"). This layout change does not alter those labels or assertions.
Log: `test/_temp/overlay-baseline.txt`.

The extended rendered gesture suite passes 290 checks. Its measurements and
images come from real Control layout after six frames, not estimated constants.
Log: `test/_temp/overlay-baseline-gesture.txt`.

## Implemented layout

The shared `EasingCurveEditor` draws into its entire rectangle, apart from the
existing four-logical-pixel edge margin and a square height cap. The point/Grid Snap panel is anchored
flush with the top and sides. The point properties row uses the full width,
aligning its reset button with the Ease/Trans reset column. Grid Snap keeps its
eight-logical-pixel side insets through an input-transparent MarginContainer.
The shared zoom row is anchored
eight logical pixels from the bottom and sides. Passive containers, labels and
separators ignore input. Interactive descendants retain their existing behavior.

`setup_zoom_overlay()` takes no Inspector arguments. It reuses the zoom scene,
owns one row, and connects the existing slider interface once. The row's combined
minimum height plus `ZOOM_HEIGHT_ALLOWANCE` (two logical pixels, rounded using
the existing compact-spacing convention) replaces the old external row/gap in
the total height budget. Neither this allowance nor top control sizes subtract
space from the graph. External `set_slider_container()` callers remain supported;
replacing a binding disconnects the old widget's callbacks.

Godot mouse focus retains graph-originated held gestures across the overlay
controls. No global input interception or synthetic event forwarding was added.
The readout follows its original anchor in both axes, clamps below actual visible
top controls, and draws above graph content but below toolbar chrome. The fixed
grid, reference box and transforms share the expanded graph rectangle.

## Autofit and height cap follow-up

The zoom row remains an overlay. Autofit and automatic initial fitting prefer
the clear vertical space between the actual visible top controls and the zoom
row, with twelve logical pixels of preferred clearance. Hidden controls reserve
no space. Avoiding overlays may reduce zoom by at most two slider steps from
the full-canvas fit. This retains at least about 69% of that fit's linear size
instead of allowing a narrow clear strip to shrink the whole plot. Partial
overlap is allowed when that limit is reached.

Curve bounds still include handles, the reference range and sampled Function
overshoot, with the existing padding and discrete zoom levels. The preferred
center is kept between the controls unless it would push the larger fit beyond
the canvas edges. If controls fill the canvas, fitting falls back to the full
graph. This is a fitting preference, not a clipping or input boundary.

Manual pan and pointer-anchored zoom continue using the full canonical graph
rectangle. Readout placement shares the same measurement of visible top
controls but keeps its independent canvas-edge clamps.

The spacing refinement removes the top panel's eight-pixel vertical inset to
tighten the gap below the Curve Editor foldable header. It raises Autofit's
preferred control clearance from eight to twelve logical pixels at both ends,
including the numeric Grid Snap field. The readout retains its separate
eight-pixel gap. Section height, graph dimensions, soft zoom limit, passive
input routing and manual overlap behavior are unchanged.

Matched Legacy/Native captures at width 420 preserve the 420x292 editor and
zoom step 10. The toolbar moves up eight pixels; the plot moves up four, gaining
four pixels of visible clearance below the Snap field and above the zoom row
without changing plot size. Captures and measurements are in the isolated
project's `test/_temp/spacing-{before,after}*` files. Focused checks pass 994
gesture assertions headless/rendered and 955 readout assertions.
Full correctness passes 32 of 33 suites, with only the same two baseline CSS
label assertions failing (`test/_temp/spacing-full.txt`).

Full-width point-toolbar follow-up: 1,048 gesture checks pass headless/rendered,
including actual alignment with both Ease/Trans reset buttons for Legacy and
Native at widths 320/450/700. Resize/theme checks at scales 1/1.5/2 retain the
full-width point row, trailing reset alignment and the original Grid Snap and
zoom insets. The readout suite passes 955 checks. Actual Editor captures are in
the isolated project's `test/_temp/toolbar-width-after-*.png` files.
Full correctness passes 32 of 33 suites, with only the two existing CSS-label
assertions failing (`test/_temp/toolbar-width-full.txt`).

Point labels display the zero-based numeric index without a `P` prefix. Their
reserved width is measured directly from `999` in the current Label font and
refreshed with overlay layout/theme changes. This avoids stale text minimums
and reserves three digits; it does not impose a point-count limit or truncate
larger existing indices. The unselected `No Selection` label is retained.
Matched actual Editor captures measure the selected label at 28 pixels wide
instead of 44 at scale 1.0, returning 16 pixels to the dropdown row. Focused
checks pass 1,474 navigation/Shift-swap and 1,048 gesture assertions. Artifacts:
`test/_temp/overlay-project/test/_temp/point-number-{before,after}*`.
Full correctness passes 32 of 33 suites, retaining only the two baseline CSS
label assertion failures (`test/_temp/point-number-full.txt`).

The editor's established minimum-height budget is capped at its width. The
canonical graph rectangle also caps height at width if a caller supplies a tall
Control. Ordinary section heights below the cap remain unchanged; narrow or
enlarged-scale sections that previously became taller than wide now shorten.

Follow-up focused checks: 980 gesture checks headless and rendered, 1,038 grid
checks, and 955 readout checks. Tests cover both backends, Custom/Elastic modes,
oversized handles, widths 320/450/700, scales 1/1.5/2, actual control bounds,
repeated Autofit, hidden/taller controls, crowded-layout fallback, the square
cap, and unrestricted manual navigation. Logs: `test/_temp/autofit-*.txt`.
The full follow-up correctness run also passes 32 of 33 suites, with only the
same two baseline CSS-label assertions failing (`autofit-full.txt`). Actual
Editor captures at scale 1.0 (dark) and 2.0 (light) confirm clear Custom/Elastic
fits and permitted manual overlap. Images are in the isolated project's
`test/_temp/autofit-editor-*.png` files.

The soft-avoidance correction adds a flat-curve regression at width 400 and
height 280. It requires a plot at least 60% of canvas width, a maximum two-step
overlay penalty, retained control avoidance, canvas-edge containment with a
taller Snap field, and repeatable fitting. The gesture suite now has 992 checks.
The strict-clear-area assertions were replaced with canvas containment; the
readout still uses its original strict top-control clamp.

Actual Editor captures of the same flat Native curve at width 400 and scale 1.0
measure 168.55 pixels of plot width before the correction and 242.72 after it
(zoom steps 8 and 10). Both captures retain the same 307-pixel outer section,
283-pixel editor and 275-pixel graph height. Artifacts are
`test/_temp/overlay-project/test/_temp/autofit-soft-{before,after}-1.0-*`.
Headless and rendered gesture runs pass all 992 checks. Full correctness remains
32 of 33 suites passing, with only the two baseline CSS-label assertions failing.
Logs: `test/_temp/autofit-soft-{gesture,rendered,full}.txt`.

## Measured result

At scale 1.0, both backends and both curve modes preserve the old outer height
exactly in the characterization fixtures:

| Width | Outer before/after | Editor before/after | Custom viewport before/after | Function viewport before/after |
| --- | --- | --- | --- | --- |
| 320 | 270 / 270 | 212 / 246 | 109 / 238 | 204 / 238 |
| 450 | 330 / 330 | 272 / 306 | 169 / 298 | 264 / 298 |
| 700 | 446 / 446 | 388 / 422 | 285 / 414 | 380 / 414 |

Custom curves recover 129 pixels: 95 at the top and 34 from the external zoom
row/gap. Function curves recover the same 34 bottom pixels. The top reservation
is now zero in both modes; the zoom minimum remains 32. The unused parent VBox
separation still exists as a theme setting but contributes no height with one child.

## Validation

- Final full correctness run: 32 of 33 suites pass, with only the same two
  pre-existing CSS-label assertions failing. No diagnostic allowlist was changed.
  `test/_temp/overlay-final-verified.txt` records the run.
- Expanded gesture suite: 754 headless and 754 rendered checks, covering measured heights,
  idempotent setup, empty label/separator/disabled-slot and bottom-row input,
  pending addition/cancellation, modifier zoom, fresh widget clicks, and graph
  point/left-handle/right-handle/pan/pending/immediate-add/RMB-delete gestures
  crossing Grid Snap, point options, slider and Autofit before release.
  `test/_temp/overlay-gesture-final.txt` and
  `test/_temp/overlay-rendered-gesture-final.txt`. The final empty-space/Autofit
  additions passed these focused runs after the full correctness gate; production
  code was unchanged.
- Grid: 1,060 checks. Drag coordinates: 955 headless and 1,037 rendered checks.
  Rendered checks include release outside the graph; their starting point is
  intentionally exposed, because top-edge points can now lie under controls.
- Integration: 567 ownership, 6,756 Native Points transforms, 11,712 Native
  reconciliation, and 1,152 shared editor vertical-slice checks passed.
- Resize/theme fixtures cover logical widths 320/450/700 and scale values
  1.0/1.5/2.0, hidden controls, taller numeric input and toolbar-only relayout.
  Function visibility expectations in the Points reorder suite were updated
  to require an unchanged full graph rectangle.

Full Editor captures additionally used real `EditorInterface.get_editor_scale()`
values 1.0, 1.5 and 2.0, restarting an isolated Editor between scales. Actual
Editor theme/icons were used, including a Light preset at 2.0. Inspected captures
cover selected controls, fixed grid, Native readout and panned overlap. All
settings writes were confined to the temporary project's isolated appdata.

Artifacts are under `test/_temp/overlay-project/test/_temp/`:

- `overlay-layout.json`, `overlay-{legacy,native}-{custom,function}-*.png`
- `full-editor-{1.0,1.5,2.0}-*.png` and matching measurement JSON
- `full-editor-2.0-native-readout.png` and `full-editor-2.0-native-overlap.png`

The standalone rendered host emits existing window/graphics cleanup diagnostics;
full Editor captures emitted only the environment's certificate-store diagnostic.
These runs validate synthetic viewport input and real Editor scaling, not physical
mouse input or movement between monitors. The original overlay migration
preserved width-dependent sizing; the follow-up above adds the requested square
cap. Graph color choices remain unchanged.

## Repeating the checks

Run `test/runners/run_all_tests.ps1 --run` for the isolated correctness gate.
Use `test/runners/run_godot.ps1 --editor --headless --path <isolated-project>
--script res://test/scripts/unit/<suite>.gd --log-file <repository-local-log>`
for a focused suite; omit `--headless` for rendered checks. Run tests sharing
one isolated project sequentially: concurrent Windows GDExtension reload copies
can contend for the same temporary DLL.

For a visual review in the Inspector, compare at the same section height and
width, select endpoints/interior points, toggle Snap and graph background, drag
through top/bottom controls, pan the reference box under them, and exercise
Autofit, fold/reopen and resource reload on both backends. New clicks on controls
must stay with controls, while already-held graph gestures must finish on graph
release. Check the readout both on and off its top clamp.

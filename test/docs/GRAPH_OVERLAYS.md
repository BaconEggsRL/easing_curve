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
existing four-logical-pixel edge margin. The point/Grid Snap panel is anchored
eight logical pixels from the top and sides; the shared zoom row is anchored
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
mouse input or movement between monitors. Existing width-dependent height policy
and graph color choices were intentionally preserved.

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

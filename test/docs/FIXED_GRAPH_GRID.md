# Fixed graph grid and reference box

Implemented in the shared `EasingCurveEditor` for Legacy and Native Inspectors.
The supplied `ticks1.png` and `box2.png` are the visual references.

## Rendering behavior

Previously, `_draw()` generated four X intervals and two Y intervals in world
space, with every line ending at the 0..1 reference rectangle. Grid colors were
hard-coded and there were no coordinate labels.

The new graph uses the existing canonical graph rectangle, intersected with the
control bounds for drawing. Five X and three Y screen positions divide that
rectangle into four and two equal intervals. Pan and zoom leave these positions
unchanged; resizing moves them proportionally. Each label reads the coordinate
at its tick through `get_world_pos()`. There is no nice-number interval selection
or hysteresis, and the tick positions are not snapped. The background draws only
the outer plot border and short ticks; interior subdivision lines are omitted.

The 0..1 reference box remains in world space. Its corners use `get_view_pos()`;
each original edge is clipped independently. A box enclosing the whole viewport
draws no edges, rather than incorrectly outlining the viewport itself.

Draw order is plot border/ticks, reference box, coordinate labels, curve geometry,
points/handles, then the existing transient coordinate overlay. Labels are inside
the left and bottom plot edges, with no new margins or layout controls. X labels
win collisions with Y labels, and labels that do not fit are omitted. The
canonical plot rectangle, toolbar/Presets construction, pointer handling and
Autofit are unchanged.

## Formatting and styling

Labels use fixed 0.1 resolution (one decimal place) at every zoom level, with
rounded negative zero normalized to `0.0`. This intentionally replaces adaptive
precision: adjacent ticks may show the same rounded value at high zoom. Their
screen positions and underlying inverse-transform coordinates remain unchanged.

Fonts and sizes come from the Label theme. Text uses the Editor font color and
grid/box strokes use Editor `mono_color` at 10%/25% opacity, following the bundled
Godot Curve editor source in `cpp/curve_editor_plugin.cpp`. Headless/standalone
fixtures use the existing theme-cache fallback. No persistent tick/label cache,
per-tick Controls, resource mutation, or Inspector rebuilds were introduced.

## Validation

- Added `easing_curve_grid_editor_test.gd` and its UID; registered the suite in
  `test/runners/run_all_tests.ps1`.
- **1,016 focused checks passed**, including both backends, independent X/Y zoom,
  fixed anchors under navigation, inverse-transform values, rounding error,
  Reverse/Invert, resize, label containment/collisions, small controls, formatting,
  reference-box clipping, and resource/signal/Undo history invariance.
- **All 32 correctness suites passed for the initial implementation**, including gesture, drag-coordinate,
  Inspector, backend, Native-transform, Autofit characterization, serialization,
  and runtime coverage. Evidence: `test/_temp/fixed-grid-correctness.txt`.
- Rendered fixtures were visually inspected for Legacy and Native in default,
  panned, zoomed-out, anisotropically zoomed-in, resized, dragging, and enlarged
  light-theme states. Captures are under
  `test/_temp/fixed-grid-visual/test/_temp/fixed-grid-*.png`.
- The final rendered repeat passed all 1,016 checks and exited with code 0.
  Evidence: `test/_temp/fixed-grid-rendered-repeat.txt`.
- The border-only/one-decimal follow-up updates rounding regressions to the new
  0.1 display resolution. Both headless and rendered runs passed 1,028 checks
  and exited with code 0; the panned capture was visually inspected. Focused results are in
  `test/_temp/fixed-grid-border-tenths.txt`; rendered results are in
  `test/_temp/fixed-grid-border-tenths-rendered.txt`. The full correctness suite
  was not repeated for this localized rendering/formatting follow-up.

Godot was the configured official 4.7.1 executable from
`EASING_CURVE_GODOT_PATH`; launches used repository-local logs. The initial direct
project run could not load the Native DLL while the project was open, so
validation used isolated project copies. One rendered run passed its checks but
crashed during editor shutdown (`0xC0000005`); the repeat completed successfully.
Standalone editor certificate/current-window/exit-allocation diagnostics remain
in the logs. No diagnostic allowlist was changed.

## Visual comparison and limits

- The fixed quarter-width/half-height ticks and changing coordinate values match
  the requested layout. The follow-up removes inner background lines while
  retaining the outside border. The zoomed-out reference box contracts around
  the curve; partial boxes show only real domain edges.
- Unlike `ticks1.png`, X labels are above the bottom boundary, inside the existing
  plot as explicitly requested. The colliding bottom Y label is suppressed, so
  the default origin is drawn once.
- Unlike the standalone box shown in `box2.png`, the lighter plot border, ticks,
  and labels remain visible around the box as requested.
- The isolated fixtures show existing Snap/selection controls rather than the
  full Inspector/Presets presentation. Captures validate rendering and simulated
  dragging/resizing, not physical mouse input or a live Inspector resize.
- Light-theme captures exercise fallback font/grid colors at 1.5 scale. The
  existing white curve stroke is unchanged; this feature does not restyle it.

Production changes are confined to graph presentation. Runtime APIs, sampling,
Bezier math, serialization and Undo/Redo semantics were not modified. An existing
user edit in `addons/easing_curve/_test_scene/test.tscn` was preserved.

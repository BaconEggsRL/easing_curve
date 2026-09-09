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

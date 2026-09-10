# Inspector minimum-width regression

> Implementation/investigation record. Dated counts and failures below are
> historical; [v1.2.1 certification](v1.2.1_CODE_TRACKER.md) records current results.

Validated with Godot 4.7.1 on Windows. Production changes are confined to
`points_editor_property.gd`; resource and backend interfaces are unchanged.

## Characterization gate

Before changing production code, the existing vertical-slice fixture was extended
and an isolated editor plugin measured the native Inspector layout with the
actual editor theme. Both backends produced these horizontal minima at scale 1:

| Control | Before | After |
| --- | ---: | ---: |
| Ease/Trans toolbar | 138 px | 138 px |
| Complete curve presentation | 138 px | 138 px |
| PointsEditorProperty wrapper | 188 px | 139 px |
| Inspector panel, before creating a curve | 220 px | 220 px |
| Inspector panel, after creating either easing resource | 234 px | 220 px |

The native wrapper added 50 px for invisible property chrome. Temporarily placing
the unchanged presentation directly in its parent in the diagnostic host removed
exactly 50 px from the containing Inspector's minimum. This established that the
presentation itself was not the limiting descendant. The equivalent ordinary
Debug Curve did not enlarge the panel.

## Implementation

Godot 4.7.1 does not dispatch the script `_get_minimum_size()` virtual for
EditorProperty; a probe returning `(1, 1)` still reported `(50, 29)` with the
editor theme. The fix therefore uses an input-transparent internal Container.
Its horizontal minimum compensates for the difference between the native
wrapper minimum and the slot minimum, retaining the existing one-physical-pixel
content inset. Its vertical minimum remains the child's native minimum, so
EditorProperty still applies its own height floor and layout.

Compensation is measured again after theme/minimum-size changes using deferred
updates. It does not hardcode icon widths, override Inspector themes, change
resource editability, or shrink the actual toolbar controls. At identical layout
widths the old and new wrapper heights were both 331 px.

## Verification

The existing vertical-slice suite checks both backends, modified presets,
graph folding, content placement, theme/minimum-size invalidation, and height
parity with an ordinary EditorProperty. It passes 1,176 checks, including explicit
confirmation that the geometry cases transition from clean to modified presets.

An isolated full-editor host checks creation, clean/modified presets, graph
folding/reopening and Inspector reconstruction at actual Editor scales 1.0,
1.5 and 2.0. Elastic cases additionally expand the transition-parameter sections
and change amplitude. All three scale runs finish with zero failed checks.
The allowed rounding tolerance is one physical pixel.

| Editor scale | Pre-existing panel minimum | After creating Legacy or Native |
| --- | ---: | ---: |
| 1.0 | 220 px | 220 px |
| 1.5 | 330 px | 330 px |
| 2.0 | 440 px | 440 px |

The full isolated correctness runner passes 32 of 33 suites. The two existing
`Css Cubic Bezier` / `Css Linear` label assertions in `editor_undo_redo_test.gd`
remain failing. Diagnostic allowlists were not changed.

Expanding every section revealed a separate minimum in the Legacy Points list
(264 px at scale 1); this is outside the creation/graph-wrapper fix and was not
masked by lowering an ancestor's minimum. The independently edited test scene
was not changed by this work.

Local evidence: `test/_temp/width-before-output.txt`,
`width-node-before-output.txt`, `width-node-after-output.txt`,
`width-accept-1.txt`, `width-accept-1.5.txt`, `width-accept-2.0.txt`, and
`width-full-correctness.txt`. The temporary editor probe and its logs live under
`test/_temp/width-host/`. All launches used the repository runner,
`EASING_CURVE_GODOT_PATH`, and repository-local log files.

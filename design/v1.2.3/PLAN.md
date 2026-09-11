# Easing Curve v1.2.3 — Working UX Design Laboratory

## Approved purpose and refinements

Build a self-contained local HTML/CSS/JS exploration under `design/v1.2.3`. Compare practical no-code/minimal-code property animation, especially juicy UI interactions. The lab informs a separate production plan; it does not choose production architecture or release scope.

- One shared browser playback simulator for every architecture variant. Variants change authoring and routing, never duplicate animation implementations.
- Reuse existing sample data. Add the design-only exporter only because five requested presets are absent from the existing documentation data.
- Preserve Play-time versus track-start value capture.
- Keep engine lifecycle, serialization, UndoRedo and baking documented only.
- Use programming guidance selectively where it helps readability, ownership or validation, not as a blanket requirement.
- No production addon edits, migrations, commits, pushes, publishing or release integration.

## Repository and implementation structure

`index.html` supplies seven semantic sections: Overview, Inspector & tracks, Targets & values, Juicy buttons, Reverse & restore, Architecture & API, Boundaries & decisions. Shared `styles.css` uses Godot-inspired colors, compact rows, foldouts, axis colors, graphs, resource controls and accessible focus indicators.

`fixtures.js` supplies mock scene/property metadata, initial recipes and architecture descriptions. `script.js` supplies typed editing, native dialogs, scene drag/drop, independent comparison panes and one numeric/component `Playback` simulator. Authored settings, current simulated values, playback endpoints and preview snapshots are separate. No framework, CDN, package installation, network, browser persistence or server is required.

`assets/curve_samples.js` contains eight fixed tables and provenance. Existing three curves are reused verbatim; a design-only Godot export provides missing tables. One icon is copied with its MIT notice. `tests/prototype.test.cjs` is a dependency-free runnable assertion check.

## Working labs

### Inspector and tracks

Compare Simple one-track entry, expandable rows, and selected-track detail. Implement add, remove, enable, duplicate, reorder by drag and keyboard buttons, expand, target/property selection, typed endpoints, shared/per-track/default-with-override curve and timing, delay, speed, preview controls and a read-only timing strip. Retain hidden tracks when switching Simple; only its first track plays.

Phase-owned curves, duration multipliers and normalized offsets are annotated alternatives. Autoplay, loops/count, time-scale, process and pause settings are labelled engine-only mockups. No keyframe/timeline editing.

### Targets and values

Explicit fixtures: Button, visual child, Control panel, Node2D Character, Node3D object, ShaderMaterial. Pick targets by search, drag or click. Show binding root and resolved target for explicit, parent and scene-owner examples. Show material resource ownership separately from scene association.

Categorized searchable properties include components, colors, custom script values and shader values; favorites/recent choices are session-only. Manual paths are registry-validated. Editors cover float, int, Vector2, Vector3, Color and Rect2; bool remains a discrete-action question.

Current reads at capture; Value is literal; Relative adds an offset; Property reads a compatible source once. Default capture is track-start. Side A in the dynamic comparison captures at Play, side B after delay. Runtime source controls change destination without rebuilding the authored animation.

### Juicy buttons and trigger architecture

Recipes: hover scale 1.08/lift 4 px/tint/Back Out at .12 s; press scale .95/down 2 px at .06 s; Spring release at .18 s; focus scale 1.05/accent at .15 s; combined overlapping inputs. Parameters are adjustable. Mouse and keyboard work, plus explicit event buttons for focus without hardware.

Press has provisional transform priority, hover/focus emphasis follows, focus accent remains independent. Release returns to the applicable state. Superseded playback is cancelled from its visible value.

Compare A embedded triggers, B companion interaction node, C normal signals, D specialized helper. Show different controls/connection walkthrough, diagrams, benefits, costs and routing responsibility. Disconnected events visibly do nothing. All compile to the same tracks and simulator.

### Preview, reverse and baseline

Preview captures once; Replay restores snapshot before replaying; Stop holds values; Reset restores and ends preview; Reverse traverses captured progress backward. Inspector readouts distinguish authored modes, current values, captured endpoints, preview snapshot and external layout/base scale.

Compare captured return, fresh baseline return, exact reversal, explicit endpoints, paired exit, one finite ping-pong, restore-on-exit and a deliberately drifting re-read-current example. Move the layout/base scale, change source, interrupt halfway and repeat. Compare wrapper and Godot 4.7 visual offset approaches with stable browser input regions. Audition presets temporarily without changing selection.

Changing variants/scenarios restores the prior preview. Authored edits retain their changes but end an active preview first. Reset example separately clears fixture edits. Engine scene closure/deletion/plugin shutdown and editor UndoRedo are documented requirements only.

## Architecture and API documentation

Compare node + Resource tracks, one node/property, and reusable resource + host. Keep authored Resource data separate from per-playback object references, baselines and cancellation state. Data shapes are conceptual, not a serialized contract.

Compare candidate play/reverse/play_to calls and tween_property convenience placement on EasingCurve, an EasingTween static helper, a utility or external curve-taking helper. Discuss Native/Legacy parity, discoverability, ownership, Tween vs PropertyTweener returns, and the valid choice of adding no interpolation helper.

Document ease's numeric exponent, interpolate_value's initial+delta/seconds/zero-duration/extrapolation contract, custom interpolator input easing, from_current capture timing, and Tween Stop versus restoration. Preserve the addon’s existing Resource Reverse/Invert semantics.

Use EasingTween for compact dynamic gestures, code Tween for procedural composition, AnimationPlayer for authored sequences/scrubbing, AnimationTree for blending. Future baking diagrams discuss sampled keys, approximation, discontinuities, overshoot, arbitrary functions and frozen dynamic destinations. Baking buttons are disabled.

## Decision register

All recommendations are provisional, with links to the corresponding HTML section.

| Question | Candidate recommendation / alternatives | Evidence for separate production plan |
| --- | --- | --- |
| 1. Should EasingTween be a Node? | Node + data vs one node/property vs resource+host | Compare setup and scene clutter in Architecture |
| 2. Should tracks be Resources? | Reusable authored data; instance playback state separate | Validate rebinding and instance ownership in Godot later |
| 3. One track or many by default? | Simple entry, expandable rows for full gestures | Author the same hover in all layouts |
| 4. Duration ownership? | Shared + optional overrides vs per-track | Compare edits and read-only timing |
| 5. Curve ownership? | Shared + optional overrides; phase ownership alternative | Compare coordinated scale/lift/tint |
| 6. Value modes? | Implicit Current in Simple; explicit advanced modes | Delayed capture, Relative, Property and typed controls |
| 7. Trigger ownership? | Compare embedded vs companion vs signals vs helper | Same recipe in A/B/C/D |
| 8. Cleanest JuicyButton workflow? | Helper convenience vs generic flexibility | Keyboard, rapid changes, release outside |
| 9. Preview/Reset/Reverse? | Explicit snapshot and captured trajectory | Interrupt halfway and compare readouts |
| 10. Runtime baseline changes? | External baseline or independent visual offset | Reflow and runtime scale changes; expose drift |
| 11. Useful convenience APIs? | Small tween_property helper; sample may suffice | Discoverability, lifetime ownership and parity |
| 12. v1.2.3 vs later? | Proven compact UX only; baking future | Separate production scope/feasibility plan |
| 13. AnimationPlayer boundary? | Compact dynamic gestures vs authored sequences | Identify when sequencing becomes cumbersome |
| 14. Generic types/properties? | Metadata-driven controls for bounded types | Control/Node2D/3D/Rect2/int/material fixtures |

## Incremental build/review sequence

1. Shell, source evidence, status labels and decision register. Review navigation and boundaries.
2. First complete hover with target/property/typed destination/curve/duration/preview. Review fast authoring.
3. Track operations, layouts and ownership variants. Review multitrack editing.
4. Remaining typed editors, value modes, source picker and capture timing. Review dynamic destinations.
5. Button recipes and four routing architectures sharing playback. Review feel and setup effort.
6. Reverse/restore/baseline comparisons, interruptions and audition. Review captured versus fresh state.
7. API/architecture/built-in semantics/future panels. Review provisional recommendations.
8. Assertion checks, browser walkthrough, direct-file/offline, narrow layouts and scope inspection. Record evidence below.

GodotPrompter guidance informs corresponding content: godot-ui/addon-development for authoring; resource-pattern for ownership; tween-animation for interpolation/capture; animation-system for tool boundaries; godot-brainstorming for alternative structures. These are selective references, not a mandate to implement engine systems here.

## Validation record

Executed September 11, 2026:

- `node --check` passed for `script.js` and `fixtures.js`. The dependency-free `tests/prototype.test.cjs` passed: sample interpolation and preserved overshoot, unchanged reused tables, all four value modes, Play-time versus track-start capture, typed values, shared defaults/overrides, stable track IDs, independent duplication, disabled tracks, interruption, exact reversal, snapshots, fresh baselines, delay/speed/zero duration, invalid inputs, property conflicts, local assets and section links.
- The isolated Godot 4.7.1 exporter completed with eight finite sample tables; three existing tables were reused unchanged. Godot emitted environment warnings about certificate storage and unavailable user/editor settings paths; sample export itself completed successfully. Its owned temporary host and logs were removed after successful export and assertions. No production host was launched or modified.
- Localhost browser walkthrough passed: independent A/B Preview/Reset, add/duplicate/reorder, per-track curve overrides, searchable target/property selection, Vector3 control conversion, incompatible Property-source validation, and integer editing. Reordering preserves focus, including repeated keyboard activation of Move Down.
- Delayed destination comparison observed A at `(100, 35)` and B at `(-90, -25)` after changing the runtime destination during the delay. This confirms that Play-time and track-start capture produce different visible outcomes; neither source is followed continuously.
- JuicyButton walkthrough exercised hover/down/up/focus event controls, real pointer activation through the stable input region, keyboard Space activation, architecture switching, and disconnection of a signal route. Event messages reflect the chosen route and all variants use `Playback`. Focus accent remains a separate state from transform priority.
- Restore comparison observed captured return at `y=0` and fresh-baseline return at `y=24` after layout movement. A half-progress sample stayed frozen at `0.33 / 0.65 s`; Reverse returned scale from about `1.09` to `1.00` at time zero. Reset restored the preview snapshot. No browser JavaScript errors were recorded in the exercised workflows.
- Desktop review used a 1265 px content viewport with side-by-side panels. The optional `tests/layout.html` harness exercised real iframe widths of 700 and 360 px; the narrow Inspector and button sections had equal client/scroll widths (345 px at a 360 px frame), with no horizontal overflow. A 1280 px iframe at 200% CSS zoom kept controls within its content viewport. Native viewport override and browser zoom commands were ineffective in this browser tool, so this is enlarged-content review, not a claim of native browser zoom coverage.
- Repository scope inspection showed only the new `design/v1.2.3/` folder. No production paths, existing documentation, serialized resources, commits or release integration changed.

Remaining manual checks: the browser tool explicitly blocks `file://` navigation, so double-click opening is structurally supported by classic scripts and relative assets but not browser-verified here. Localhost rendering and local-link assertions passed. Native browser zoom, actual drag gestures, pointer release outside the viewport, and hardware gamepad input remain manual review items; Move Up/Down and explicit event controls cover their authoring/event alternatives. Favorites, all return policies, audition and every typed-editor permutation are implemented but were not each exercised through browser automation.

No production Godot animation, Native parity, scene-tree binding, lifecycle, restoration/UndoRedo integration, serialization or baking is simulated or claimed tested. This completed lab supplies evidence for a separate production plan; every production recommendation remains provisional.

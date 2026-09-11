# Easing Curve 1.2.3 — Motion lab

A local HTML/CSS/JS design laboratory, not a Godot addon or a production feature specification. All production recommendations are provisional and must feed a separate v1.2.3 production plan.

## Open

Double-click `index.html` or open it in a current browser. No build, install, network, Godot binary, or server is needed. Navigation and sample data use relative URLs and classic scripts.

For optional localhost review, run from the repository root:

```powershell
python -m http.server 8123 --bind 127.0.0.1 --directory design/v1.2.3
```

Open http://127.0.0.1:8123. Stop the optional server with Ctrl+C when finished. No publishing or release integration is configured.

## Review walkthrough

1. **Inspector & tracks:** compare Simple and Expandable rows. Preview both. Change one side to Selected-track detail. Add, expand, duplicate, disable, move, and delete tracks. Duplicates start disabled to prevent conflicting writes; enable after choosing a different property.
2. **Shared settings:** switch curve/time ownership among Shared, Per track, and Shared + overrides. In override mode, enable the checkbox on a track before editing its override. In per-track mode the parent control is disabled because it has no effect. The strip shows timing without timeline editing.
3. **Targets:** click Target, search, and choose a node. Alternatively expand Scene tree and drag a node onto a target row, or click it to assign to the selected track. Parent default resolves to Button; the separate scene-owner example resolves from Menu to Button/Visual. Material is a resource associated with Visual, not a Node.
4. **Properties/types:** use the picker and favorite stars; recent/favorites last only for this page session. Try position:y, Vector2 scale, Node3D position, Panel.preview_rect, Character.score, and Material shader values. Set different From/To values to see a change. Invalid manual paths and incompatible source types visibly block playback.
5. **Dynamic capture:** in Targets & values, Preview both, then immediately Change both destinations during delay. A captures at Play; B captures when the track starts. Inspect endpoint readouts after completion. Later source changes do not continuously retarget either run.
6. **Buttons:** hover, press, release outside, or tab into Try me and use Space/Enter. Explicit event buttons also demonstrate focus without a gamepad. Switch architectures A–D: routes, scene diagram, and authoring presentation change, while the recipe and simulator remain shared. Disconnect a route and fire its event to verify the binding matters.
7. **Returns:** Preview both in Reverse & restore, move both baselines +24 px, then Return both. Captured return goes to its original baseline; fresh return goes to the new external value. Reset restores the original preview snapshot. Change base scale to expose the same distinction in scale.
8. **More return variants:** choose exact reverse, explicit endpoints, paired exit (Elastic), re-read animated current (deliberate drift example), or restore on exit. For one full finite ping-pong round, Reset, select Ping-pong, then Return. Wrapper and 4.7 offset variants distinguish animated child coordinates from visual offsets added to an external baseline.
9. **Interrupt/reverse:** Preview and move Progress to 50%, then Reverse. Inspect captured endpoints and the reverse trajectory. Stop holds values; Replay restores the existing snapshot before replaying; Reset ends the preview session. Reset example separately discards authoring changes.
10. **Preset audition:** open Advanced playback and enable hover audition. Hover a preset chip, then leave it: the target restores and the chosen curve remains unchanged. Clicking a chip auditions explicitly.
11. **Accessibility:** use keyboard-accessible pickers, Move Up/Down instead of dragging, and labelled component inputs. Reduced-motion preference suppresses event-triggered animation; explicit Preview and manual progress remain available. The Manual interaction motion checkbox offers the same inspection workflow.
12. **Decisions:** review the fourteen questions and record preferred variants separately. No conclusion in the UI constitutes production approval.

## What is implemented

- Four working labs, each with independent A/B authoring and simulated target state.
- One `Playback` simulator shared across every lab and every trigger architecture.
- Fixed property metadata, typed controls, additive Relative mode, and compatible Property references.
- Separate Play-time/track-start capture; snapshot, endpoint, and external-baseline readouts.
- Numeric and component interpolation using actual EasingCurve sample tables, preserving overshoot.
- Delays, speed, cancellation, captured reversal, and one finite ping-pong demonstration.
- Browser pointer and keyboard gestures, configurable routes, and combined press/hover/focus priority.
- Architecture, ownership, API, native engine semantics, future baking, and decision documentation.

## Deliberate boundaries

This is a bounded UX simulator. It has no engine scene tree, Resource serialization, EditorUndoRedoManager, process/pause lifecycle, automatic production bindings, native extension loading, or AnimationPlayer baking. Engine-only settings update explanatory mockups but never change playback.

The fixed registry accepts only listed properties; expert paths are never evaluated as JavaScript. Bool/discrete actions and arbitrary object interpolation are excluded. Integer display rounds interpolated values. Color display clips RGB/alpha to display range while numeric sample output remains unclamped. Vector3 z is schematically represented by rotation, not a 3D engine. Rect2 is a rectangle diagram. Material glow/tint are CSS approximations, not shader execution.

The browser uses a stable input wrapper, including for the visual-only offset comparison. It does not simulate Godot hit testing, container reflow, or the complete relationship between Control and CanvasItem transforms. Wrapper coordinates and offset coordinates are explicitly separate models for comparison.

Curve tables contain 257 samples and use linear interpolation between samples. They are visual approximations, not a claim of exact solver parity. Sample time is clamped, sample output can overshoot. No curve geometry editor is recreated. Resource Reverse/Invert are never changed by playback Reverse.

Binding defaults are explicit fixture examples (parent Button, scene owner Menu). A source property resolves once at the chosen boundary. A generic helper cannot infer an external system's intended baseline from an already animated value. Re-read animated current is intentionally shown as a poor baseline policy.

Simple plays the first track only; extra tracks remain intact for the other layouts. Repeated writes to the same property, including a whole vector and one of its components, are rejected. This is a lab validation rule, not a settled production conflict policy. New interactions start from currently displayed values; changes to authored fields stop and restore a previous preview before taking effect.

## Data provenance

- `assets/curve_samples.js`: Back Out, Smoothstep, and CSS Bézier arrays reused unchanged from the repository's `docs/curve_samples.js` (popup, sliding_door, charge_meter).
- Linear, Cubic Out, Elastic Out, Spring Out, and Bounce Out were missing from that data. `tools/export_samples.gd` exists only to fill that gap using the actual portable Legacy EasingCurve, default transition parameters and Ease Out, Godot 4.7.1.
- `assets/icons/Curve.svg`: copied from `addons/easing_curve/assets/Curve.svg`; MIT notice in `assets/LICENSE.md`. No sibling JuicyButton media, audio, fonts, or code is copied.
- The static overview illustration is schematic; interactive plots use the sample tables.

## Regenerate samples (optional maintainer operation)

The normal browser experience never needs this. Use an isolated host under `test/_temp/` with a minimal Godot 4.7 project, a copy of `addons/easing_curve/scripts`, a copy of `docs/curve_samples.js` at the same relative path, and this exporter at the host root. Do not enable the production editor plugin or copy its Native binary. Import that isolated host, then run the exporter using `EASING_CURVE_GODOT_PATH`:

```powershell
& $env:EASING_CURVE_GODOT_PATH --headless --path $sampleHost --log-file "$sampleHost/import.log" --editor --import --quit
& $env:EASING_CURVE_GODOT_PATH --headless --path $sampleHost --log-file "$sampleHost/export.log" --script res://export_samples.gd
```

`$sampleHost` must be an absolute, run-owned path under the repository's `test/_temp/`. Copy the resulting `curve_samples.js` to this lab's assets only after success. Check logs, then remove only that run's temporary host. Preserve `test/_temp/.gdignore` and unrelated diagnostic data. No production resource files are rewritten.

## Validation

From the repository root:

```powershell
node --check design/v1.2.3/script.js
node --check design/v1.2.3/fixtures.js
node design/v1.2.3/tests/prototype.test.cjs
```

The dependency-free assertions cover sample provenance/overshoot, typed values, all value modes, delayed capture, overrides, identity and duplication, cancellation, reverse, restore/fresh baseline, zero duration, delays/speed, conflicting properties, and local links. The provenance comparison is skipped when this standalone folder has been copied outside the repository.

Browser validation and current results are recorded at the end of PLAN.md. Godot production playback, serialization, editor lifecycle and baking are deliberately unverified and unimplemented.

For responsive review on localhost, open [tests/layout.html](tests/layout.html). Its iframe offers 360, 700, and 1280 px widths and optional 200% CSS content zoom. This is a review aid, not a substitute for testing native browser zoom. Track controls retain keyboard focus after editing or reordering.

## Sources reviewed

- Existing EasingCurve resource and Native sampler; Inspector context/theme/backend code; popup, sliding-door and charge-meter examples; existing documentation sampler and checks.
- Sibling `C:/Godot/_dev/_plugins/juicy_button`: README, architecture notes, button event handlers, Inspector auditioning and captured starting-position behavior.
- [Godot ease()](https://docs.godotengine.org/en/stable/classes/class_@globalscope.html#class-globalscope-method-ease)
- [Godot Tween](https://docs.godotengine.org/en/stable/classes/class_tween.html)
- [Godot PropertyTweener](https://docs.godotengine.org/en/stable/classes/class_propertytweener.html)
- [Godot Control](https://docs.godotengine.org/en/stable/classes/class_control.html)
- [Shader uniform metadata](https://docs.godotengine.org/en/stable/classes/class_shader.html#class-shader-method-get-shader-uniform-list)

The host project specifies 4.7; existing release documentation supports 4.4.1+. Native and Legacy are independent supported families. Offset transforms are labelled 4.7-specific; choosing a new minimum version remains a production decision.

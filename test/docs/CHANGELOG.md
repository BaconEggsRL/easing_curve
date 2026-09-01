# Changelog

Release entries are ordered newest to oldest. Add future releases above the
current top entry.

## v1.0.9

### Added

* Added EasingCurve thumbnail previews in the Godot resource browser.
* Added selected-point navigation controls to the graph toolbar, including a centered `P#` indicator and previous/next selection with wraparound.

### Improved

* Expanded Bounce `num_bounces` from 1–10 to 1–20, enabled slider-preferred editing, and increased `bounce_damping` precision from 0.1 to 0.01.
* External EasingCurve resources now receive one initial graph Autofit when first opened while later Inspector rebuilds continue to preserve the resource's current in-session view state.
* Editor controls now reuse cached Godot editor-theme icons instead of bundling redundant copies, improving theme consistency and reducing plugin assets.
* Reorganized editor/runtime/test internals and centralized point-state transition rules while preserving public curve, point, serialization, selection, and Undo/Redo behavior.

### Performance

* Improved graph rendering with visible-range clipping and adaptive Bézier tessellation.
* Added a dirty-invalidated compiled Bézier segment cache with locality/binary lookup and compatibility fallback. Measured 150,000-sample speedups ranged from 1.39x for 2-point curves to 3.35x for 128-point curves versus the retained linear reference path.

### Fixed

* Fixed update-check notifications so `update_available` is no longer gated by debug logging.
* Hardened automated test gating so previously unclassified top-level Godot `ERROR:` or `WARNING:` diagnostics fail the affected suite instead of being silently accepted.

### Testing

* Reorganized registered automated suites under `test/scripts/` and the PowerShell runners under `test/runners/`.
* Expanded the authoritative manifest to 18 suites: 8 headless and 10 Editor-host.
* Final v1.0.9 code closeout: 18/18 suites passed; runner exit 0; 18 PASS markers; 93 explicitly classified expected diagnostics; 0 unexpected diagnostics; 0 `SCRIPT ERROR:`.

## v1.0.8

### Added

* Added Shift-constrained dragging for curve points in the graph editor.

  * Press Shift while dragging to constrain movement to the dominant horizontal or vertical axis.
  * The constrained axis can change naturally as the drag direction changes.
  * Releasing Shift immediately returns to free movement.

### Improved

* Refactored and cleaned up editor code while preserving existing curve editing, selection, Undo/Redo, handle, and point behavior.
* Improved test infrastructure and documentation, including configurable Godot executable selection.
* Expanded characterization and regression coverage for graph interactions, point state, selection, serialization, and Undo/Redo behavior.

### Fixed

* Fixed several edge cases uncovered during the v1.0.8 refactor and regression-test pass.
* Improved reliability of point dragging and editor interaction behavior without changing existing curve data or serialization semantics.


## v1.0.7

### Changed

- Centralized transition/runtime metadata and point snapshot mutation rules.
- Reorganized Inspector and graph-editor internals, including graph-input
  handling and Undo/Redo action state, while preserving point identity,
  selection, notifications, and gesture behavior.
- Extracted the Bézier numerical solver without changing curve results.
- Hardened automated test-runner and release-validation behavior.

### Testing

- Final refactor closeout passed all 17 registered automated test suites.

## v1.0.6

### Changed

- Refactored and reorganized the Easing Curve Inspector internals while
  preserving existing editor and runtime behavior.
- Centralized point selection restoration so the selected logical point remains
  synchronized between the graph, Points list, and property controls across
  Inspector refreshes and point reordering.
- Simplified editor Undo/Redo action handling and point snapshot restoration
  while preserving serialized resource compatibility and notification behavior.
- Consolidated transition presentation metadata and removed stale/internal
  duplicate code.

### Fixed

- Fixed point selection restoration after Move Up/Down, Points-list drag
  reordering, Position-X reordering, Undo, and Redo.
- Fixed an intermittent Godot Viewport error when completing native Points-list
  drag reordering by safely clearing the retiring Inspector controls from mouse
  hover state before rebuilding the list.
- Fixed Points-list delete/reorder edge cases and preserved logical point
  identity through topology changes.

### Testing

- Expanded automated coverage for serialization compatibility, transition
  contracts, point-state behavior, selection/refresh behavior, graph gestures,
  Points-list operations, and Undo/Redo.
- Added historical resource fixtures to protect compatibility with older saved
  Easing Curve resources.
- Added a PowerShell test wrapper and aggregate runner; all 17 registered test
  suites pass under the v1.0.6 release candidate.
- Completed visible-editor regression testing for fold/focus behavior, layout,
  selection, point operations, handle modes, and transition controls.

## v1.0.5

### Added

- Handle Modes for point controls: Free, Linear, Balanced, Mirrored, and Linked.
- Force Linear and Locked control states, with selected-point toolbar controls
  and reset actions.
- Expanded Points-list editing, including continuous Position X preview,
  drag-and-drop reordering, and X-slot swap semantics.
- Pending point addition with live curve preview, endpoint takeover, and
  support for interior duplicate-X points.

### Changed

- Point selection now follows the logical point after manual list reordering.
- Global transforms preserve Handle Mode state; Bézier evaluation and rendering
  handle narrow/equal-X segments and missing endpoints more reliably.
- Asset Store packaging now synchronizes the canonical root README and LICENSE
  into the addon and verifies the packaged copies.

### Fixed

- Right-click pending-add cancellation, drag-to-delete behavior, and related
  point-input edge cases.
- Inspector/toolbar refreshes after point, handle, transform, and reorder edits.

### Testing

- Added regression coverage for Handle Modes, controls, reordering, transforms,
  point input, and curve evaluation, plus an Editor-host test harness.

## v1.0.4

### Added

- CSS `cubic-bezier()` support and configurable Bounce behavior.
- Global Reverse and Invert transforms for Bézier and function curves.

### Changed

- Organized transition selection and improved Points-list drag-and-drop and
  preset-modified feedback.

### Testing

- Added CSS linear and global-transform regression coverage, including
  persistence and Undo/Redo checks.

## v1.0.3

### Added

- Physics Spring and CSS `linear()` function transitions with editable
  parameters.
- Documentation for extending function transitions.

### Changed

- Generalized function-curve parameter handling, reset behavior, runtime
  updates, and Undo/Redo snapshots.
- Expanded Asset Store package validation.

## v1.0.2

### Added

- Expanded Bézier point editing with point-list reordering, property
  copy/paste, control locking, and Undo/Redo support.
- Automated Editor, runtime-update, and Tween-equivalence test coverage.

### Changed

- Improved preset geometry, interpolation reliability, Inspector editing, and
  live test-scene updates.

## v1.0.1

### Fixed

- Corrected release icon assets and included the easing library in selected
  Windows and Web exports.

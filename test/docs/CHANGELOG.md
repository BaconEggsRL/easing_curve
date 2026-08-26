# Changelog

Release entries are ordered newest to oldest. Add future releases above the
current top entry.

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

# Changelog

Release entries are ordered newest to oldest. Add future releases above the
current top entry.

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

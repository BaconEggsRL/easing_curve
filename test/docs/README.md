# Development testing

## Editor-host tests

The following tests require an Editor-host launch:

- `easing_curve_control_editability_test.gd`
- `easing_curve_editor_position_x_drag_test.gd`
- `easing_curve_linear_control_alias_test.gd`
- `easing_curve_points_list_reorder_editor_test.gd`
- `editor_undo_redo_test.gd`

Run an Editor-dependent test with:

```text
./test/run_godot.ps1 --editor --headless --path . --script res://test/<test_name>.gd
```

Plain `--headless` execution may not instantiate `EditorInspectorPlugin` and can
misleadingly report zero checks. It is not a valid result for these tests.

## Complete automated suite

Run every headless and Editor-host suite independently with:

```powershell
./test/run_all_tests.ps1
```

`test/run_godot.ps1` launches the configured Godot 4.7.1 console executable
with Windows native application-error dialogs suppressed for that test process
tree only. All automated Godot tests must use this wrapper; do not invoke Godot
directly for routine test validation. The wrapper supplies a unique,
sandbox-writable `--log-file` under `.godot/test_logs` unless the caller has
already supplied `--log-file`. Do not request privileged execution solely
because `user://logs` is inaccessible; only escalate if the wrapper encounters
a different sandbox restriction. It preserves Godot stdout, stderr, and exact
exit codes; a non-zero Godot exit remains a test failure. Direct Godot
execution remains valid for manual debugging. The runner returns a non-zero
exit code if any suite times out, exits unsuccessfully, lacks a PASS marker, or
logs a script error.

Under Godot 4.7 `--editor --headless`, `editor_undo_redo_test.gd` skips its
`FoldableContainer` fixture because it crashes in that environment and its
responsive-layout fixtures because they require a visible Editor layout. Verify
those fixtures in a visible Editor session instead.

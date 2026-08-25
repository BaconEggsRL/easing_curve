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
godot --editor --headless --path . --script res://test/<test_name>.gd
```

Plain `--headless` execution may not instantiate `EditorInspectorPlugin` and can
misleadingly report zero checks. It is not a valid result for these tests.

Under Godot 4.7 `--editor --headless`, `editor_undo_redo_test.gd` skips its
`FoldableContainer` fixture because it crashes in that environment and its
responsive-layout fixtures because they require a visible Editor layout. Verify
those fixtures in a visible Editor session instead.

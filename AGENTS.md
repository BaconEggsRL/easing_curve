When launching Godot directly from Codex, always pass --log-file with a
repository-local path under test/_temp/. Do not rely on Godot's default
user://logs location.

Use EASING_CURVE_GODOT_PATH when available.

If a direct headless test fails before script execution, verify that a
repository-local --log-file was supplied before falling back to editor-host
testing.

# SKILLS:

## Temporary test data

`test/_temp` is only for active test runs and unresolved failure diagnostics.
Remove each run's owned temporary data when it passes; remove obsolete failure
data after the issue is resolved. Preserve `.gdignore`. Do not retain successful
ad-hoc hosts or use `-KeepArtifacts` routinely. Export explicitly needed evidence
to `_exports/_validation` before cleanup. Tool downloads belong in `.cache`, not
`test/_temp`. Never delete another active run's data or unresolved evidence.

Use basic-programming-skill, review-code-smells, apply-clean-code, apply-software-patterns and apply-solid-principles when available.

When launching Godot directly from Codex, always pass --log-file with a
repository-local path under test/_temp/. Do not rely on Godot's default
user://logs location.

Use EASING_CURVE_GODOT_PATH when available.

If a direct headless test fails before script execution, verify that a
repository-local --log-file was supplied before falling back to editor-host
testing.

# SKILLS:

Use basic-programming-skill, review-code-smells, apply-clean-code, apply-software-patterns and apply-solid-principles when available.
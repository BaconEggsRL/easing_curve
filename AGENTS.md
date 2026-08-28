When Codex directly launches Godot in headless/script mode, always supply
--log-file with a repository-local temporary path. Do not rely on Godot's
default user://logs path.

A user:// permission failure occurring before test-script execution is an
environment failure, not a product/test failure. Retry using the repo-local
log path before falling back to an editor-host test.
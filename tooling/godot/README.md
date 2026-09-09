# Temporary Godot editor for issue #111645

This tooling corrects Godot 4.7.1's deferred extension-documentation callback using
`EditorHelp::doc` after editor cleanup. It changes no Easing Curve production code.
The patch is limited to the null-document guard in `EditorHelp::_gen_extensions_docs`.
Upstream report: https://github.com/godotengine/godot/issues/111645.

## Identity and selection

`editor-pin.json` owns the editor URL/SHA256, exact upstream source commit, patch
identity and explicit official export-template version. The candidate has a custom
4.7.1 build label, never an `official` label. A missing/incorrect hash is fatal
before any execution. There is no pinned-editor fallback or companion substitution.

The common launcher selects the pinned editor for `--editor`/`-e`, `--import` and
editor-driven exports. True runtime invocations keep the official executable.
Set `EASING_CURVE_EDITOR_GODOT_PATH` and `EASING_CURVE_EDITOR_GODOT_SHA256`, or pass
`-PinnedEditorPath` and `-PinnedEditorSha256` to `run_godot.ps1`. The names avoid
PowerShell interpreting Godot's `--editor` as a parameter abbreviation.

Windows and Web export runners accept `-ExportTemplateVersion`; the default comes
from the manifest. Official `4.7.1.stable` templates are independent of the patched
editor's custom version string. The editor is not included in addon archives.

## Build and qualification

`build_candidate.ps1` creates a repository-local source checkout and isolated
SCons environment, builds the unpatched control and patched editor with identical
options, and retains licenses, source/patch identity, logs, toolchain details,
binary hashes and matching PDBs. Both variants use clean builds to avoid stale
incremental version strings. Failed preliminary build outputs are preserved.

Qualification consumes the exact candidate bytes and compares a same-toolchain
unpatched control. A private draft release may transport the candidate to GitHub
runners; it is not published or immutable until qualification passes. Two fresh
Windows runners perform ten repetitions of each A-E fixture, with first-chance
ProcDump monitoring. Runner 1 also performs the full Windows, archive, Windows
export and Web export/runtime validations against official runtime/templates.
Live extension documentation and synthetic failure/selection tests are included.

The candidate's manifest hash is verified throughout qualification. All product
validation requires both process exit zero and semantic success. The deliberately
crashing control is evidence, not a successful product validation. Do not retry
failed validation into success. Diagnose failures and qualify a corrected candidate
or corrected harness in a new run, preserving previous results.

## Publication and activation

Only after the required qualification jobs pass, publish the exact qualified
executable (no rebuild), Godot MIT license/COPYRIGHT, patch text/hash, source commit,
build recipe/toolchain information, qualification evidence and matching symbols.
Download the hosted executable and verify it matches the qualified SHA256 before
activating CI. Never replace an asset at an existing tooling version.

Merge the qualified editor pin and affected strict runner changes atomically into
`dev`. Do not create a state where newly strict affected runners use known-broken
upstream 4.7.1. Package validation remains strict throughout. Qualification and
provenance artifacts remain distinct from the addon ZIP.

## Retirement

Qualify an official release containing the upstream fix, update the central editor
and template pins, then remove the temporary patch/build/download workflow. Retain
strict-exit handling and its regression tests permanently. If qualification fails,
do not publish/activate and do not restore failure tolerance.

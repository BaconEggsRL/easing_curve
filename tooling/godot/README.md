# Temporary Godot editor for issue #111645

This tooling corrects Godot 4.7.1's deferred extension-documentation callback using
`EditorHelp::doc` after editor cleanup. It changes no Easing Curve production code.
The patch is limited to the null-document guard in `EditorHelp::_gen_extensions_docs`.
Upstream report: https://github.com/godotengine/godot/issues/111645.

## Identity and selection

`editor-pin.json` owns the editor URL/SHA256, exact upstream source commit, patch
identity, candidate tag/asset/build labels, qualified build toolchain, historical
archive URL/SHA256, official runtime version and explicit export-template version.
Workflows read setup versions through `read_manifest.ps1`. The candidate has a custom
4.7.1 build label, never an `official` label. A missing/incorrect hash is fatal
before any execution. There is no pinned-editor fallback or companion substitution.

`install_editor.ps1` installs the editor and its checksum/provenance record in
`.cache/godot/pinned-editor`, an ignored tool cache independent of test output.
Clearing `test/_temp` does not remove the editor.

The common launcher selects the pinned editor for `--editor`/`-e`, `--import` and
editor-driven exports. True runtime invocations keep the official executable.
Set `EASING_CURVE_EDITOR_GODOT_PATH` and `EASING_CURVE_EDITOR_GODOT_SHA256`, or pass
`-PinnedEditorPath` and `-PinnedEditorSha256` to `run_godot.ps1`. The names avoid
PowerShell interpreting Godot's `--editor` as a parameter abbreviation.

The profiler uses the same executable-selection contract. Runtime selection uses
an explicit path, `EASING_CURVE_GODOT_PATH`, or `godot` on PATH; it has no developer
installation-directory default. Every Godot identity probe checks native exit status
before accepting version output and retains output/status on failure.

Windows and Web export runners accept `-ExportTemplateVersion`; the default comes
from the manifest. Official `4.7.1.stable` templates are independent of the patched
editor's custom version string. The editor is not included in addon archives.

## Build and qualification

`build_candidate.ps1` creates a repository-local source checkout and isolated
SCons environment, builds the unpatched control and patched editor with identical
options, and retains licenses, source/patch identity, logs, toolchain details,
binary hashes and matching PDBs. Both variants use clean builds to avoid stale
incremental version strings. Failed preliminary build outputs are preserved.

Supply a Python executable matching `build_toolchain.python_version`, for example
`./tooling/godot/build_candidate.ps1 -PythonPath <qualified-python.exe> -OutputName <fresh-name>`.
The recipe pins SCons, passes explicit MSVC/SDK selections, configures a dry run,
and verifies the resolved compiler/toolset and SDK include paths before compilation.
It records these resolved values in provenance and checks them again after building.
The qualified snapshot is Python 3.12.10, MSVC 14.5/toolset 14.51.36231, compiler
19.51.36256.0, and Windows SDK 10.0.26100.0. These pins were checked against the
retained SCons configuration from the original qualified build. Changing the recipe
does not rebuild or replace the published editor; any new executable still needs
its own hash and complete qualification.

Qualification consumes the exact candidate bytes and compares a same-toolchain
unpatched control. A private draft release may transport the candidate to GitHub
runners; it is not published or immutable until qualification passes. Two fresh
Windows runners perform ten repetitions of each A-E fixture, with first-chance
ProcDump monitoring. Runner 1 also performs the full Windows, archive, Windows
export and Web export/runtime validations against official runtime/templates.
Live extension documentation and synthetic failure/selection tests are included.

`download_historical_archive.ps1` downloads the exact historical ZIP from a separate
immutable tooling release and verifies its manifest SHA256 before making it available
for extraction. It replaces the expiring Actions artifact dependency without repacking
the archive. Candidate transfer archives are also checked before extraction.

`import-crash-diagnostics.yml` is manual-only historical tooling: it intentionally
uses the official editor to investigate the old failure and is not a normal CI gate.

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

Qualify an official release containing an equivalent or stronger fix against the
same fixtures, repetition counts, semantic checks, lifecycle, export/runtime and
documentation criteria. Keep the historical unpatched crash as control evidence;
the corrected official engine is not expected to reproduce it.

After qualification, update the manifest and replace the custom-editor installer
with verified official distribution acquisition. Then remove `build_candidate.ps1`,
`build_toolchain.ps1`, the patch, `qualify_candidate.ps1`, the historical download
helper, `qualify-godot-editor.yml`, `import-crash-diagnostics.yml`, and its diagnostic
runner. Remove temporary-only checks from `tooling_contract_test.ps1` at that point.
Preserve the immutable evidence releases and this qualification history.

Retain the common executable/identity/strict-exit contract, its permanent runner
regressions, and explicit official runtime/template selection. If qualification
fails, do not publish/activate and do not restore failure tolerance.

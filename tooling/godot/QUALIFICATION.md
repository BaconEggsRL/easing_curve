# Godot 4.7.1 documentation-lifetime correction: qualified candidate

Qualification completed on 2026-09-09 UTC, before publication or CI activation.

- Version: `4.7.1.stable.ec111645-p1.a13da4feb` (custom, not upstream official).
- Source commit: `a13da4feb8d8aefc283c3763d33a2f170a18d541`.
- Executable SHA256: `A7C0CF8F625A3B24991ED40F77DD1892C35E0DA2AB3185039DF2DAFD994C4272`.
- Patch SHA256: `2338C2925A01FBAEBF6ED417284B4D9EB7B7A1173BBD133C0CAF30F7AEB03603`.
- [Successful CI qualification](https://github.com/BaconEggsRL/easing_curve/actions/runs/34304514823), source checkout `ecf4149b9ed9c557d8fba8339bac51cbf5138738`.
- Two fresh Windows runners: `win25-vs2026`, image `20260824.214.3`.

| Fixture | Successful imports | Native extension loaded | Candidate dumps |
|---|---:|---|---:|
| A: empty | 20/20 | No | 0 |
| B: extension only | 20/20 | Yes | 0 |
| C: extension ignored | 20/20 | No | 0 |
| D: native bootstrap | 20/20 | Yes | 0 |
| E: exact historical archive | 20/20 | Yes | 0 |

Every candidate import exited 0 and completed initialization with a class cache.
Both same-toolchain unpatched controls reproduced `0xC0000005`. Local control
symbols resolved the crash to `DocTools::generate`,
`EditorHelp::_gen_extensions_docs`, and `Main::cleanup`.

Runner 1 additionally passed all 30 Windows suites; the exact historical and newly
generated archive lifecycles; Windows release export/runtime; Web debug/release
export/runtime; synthetic process/runner failure tests; and extension documentation
generation. Windows and Web export templates were explicitly official
`4.7.1.stable`; true runtime invocations used official Godot. Easing Curve native
libraries were taken from the historical release inputs and not rebuilt during
qualification. No Easing Curve production/native code was changed.

The first attempt, run `34304362152`, failed to acquire the private draft because
the token lacked access; no engine validation ran. Acquisition was isolated into
a dedicated job with draft-read access. The successful run tested the same frozen
candidate bytes. No failed product validation was retried into success.

The executable, matching PDB archive, Godot MIT license/COPYRIGHT, exact patch,
applied diff, build log and provenance are retained in the tooling release. Builds
used MSVC 14.5, Windows SDK 10.0.26100.0, Python 3.12.10 and SCons 4.11.1, with
`platform=windows target=editor arch=x86_64 production=yes lto=none debug_symbols=yes`.
The source diff contains only the three-line null-document guard. Failed preliminary
builds and an unqualified incremental build with stale version metadata were retained
locally; the qualified candidate came from a clean build with the correct custom label.

The manual qualification workflow is retained for a future replacement. It does
not run the 100-launch matrix on routine CI pushes. Strict process-exit handling
and its synthetic regression tests remain permanent.

## Publication and hosted verification

The [immutable tooling release](https://github.com/BaconEggsRL/easing_curve/releases/tag/tooling-godot-4.7.1-ec111645-p1)
was published at `2026-09-09T03:06:00Z`. GitHub confirmed `immutable: true`.
At `2026-09-09T03:06:24Z`, `install_editor.ps1` downloaded the public executable,
verified its SHA256 against the qualified candidate before execution, and confirmed
the expected custom version. The hosted hash was exactly
`A7C0CF8F625A3B24991ED40F77DD1892C35E0DA2AB3185039DF2DAFD994C4272`.
This verification preceded the atomic `dev` activation of the pin and strict runners.

## Normal CI activation follow-up

[The first activated run](https://github.com/BaconEggsRL/easing_curve/actions/runs/34305887138)
passed both native builds, all 30 Windows suites, Windows release export/runtime,
and Web debug/release export/runtime. The package job then stopped before archive
lifecycle validation: the diagnostic regression test passed its assertions but
leaked the deliberately simulated `-1073741819` child exit through `$LASTEXITCODE`.
Qualification launched that regression script in a separate PowerShell process;
normal CI invoked it inline, exposing the missing explicit test-success exit.

The regression script now returns zero only after all its crash-detection assertions
pass. An inline caller reproduced the failure before this correction and passed
afterward; runner hardening tests still rejected real simulated process crashes.
The failed CI run and logs remain preserved. This harness correction changes neither
the qualified editor bytes nor product acceptance rules.

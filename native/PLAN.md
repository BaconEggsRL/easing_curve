# Native Easing Curve Migration and Conditional Legacy Deprecation Plan

> Living plan and progress tracker. Last updated: 2026-09-03.
>
> Status values: **Verified**, **In progress**, **Blocked**, and **Not started**.
> A milestone is **Verified** only when every acceptance condition has evidence.

## 1. Executive assessment

Maintain two independent public APIs while the Native implementation matures:

- `NativeEasingCurve` and `NativeEasingCurvePoint`: the recommended, performance-focused GDExtension API.
- `EasingCurve` and `EasingCurvePoint`: the existing GDScript implementation, retained as the stable legacy and fallback API.

`EasingCurve` may eventually be deprecated, but deprecation is explicitly outside the first Native release. It can happen only after `NativeEasingCurve` is complete and verified to the same or better feature, editor, reliability, compatibility, and performance standards.

Deprecation does not mean immediate removal:

- The legacy API remains fully supported until the deprecation gate passes.
- Deprecation starts a compatibility period; it does not delete resources or break existing projects.
- Actual removal requires a separate future proposal, migration review, and release plan.
- No removal date is established by this plan.

Architecture:

- The two runtime APIs do not inherit from or delegate sampling to each other.
- Both can coexist in the same project and scene.
- A shared editor uses narrow backend adapters.
- Native receives new functionality and performance work.
- Legacy receives compatibility and correctness fixes while it remains the fallback.
- Legacy runtime `Callable` support remains available.
- Native uses explicit Callable baking and never invokes GDScript per sample.

## 2. Verified current-state baseline

### Verified

| Area | Current state |
|---|---|
| Branch | `native-v2-spike` at `d49b4e0` plus the current plan-tracking edits |
| Plan tracking | This file is the mutable source of truth for migration status and manual evidence |
| Automated tests | All 21 suites pass under Godot 4.7.1 |
| Native smoke tests | 471 checks pass |
| Legacy runtime tests | 1,380 checks pass |
| Serialization tests | 902 checks pass |
| Windows export | 471,040-byte release DLL loads built-in and custom Native resources in an isolated exported project |
| Native ABI | `godot-cpp` is pinned to `godot-4.4.1-stable`; one release DLL loads under Godot 4.4.1, 4.5.1, 4.6.1, and 4.7.1 |
| Legacy fallback | Complete legacy addon loads, samples, and serializes in an isolated project with no Native manifest or binary |
| Native standard set | All 12 Godot Tween transitions implemented directly in C++ |
| Native deterministic modes | Constant, Step, Power, Physics Spring, parameterized Back/Elastic/Spring, reverse, and invert are implemented directly in C++ |
| Native Callable policy | Explicit point baking is implemented; no Native sampling path invokes a Callable |
| Native custom solver | Compiled segments, sorting, monotonic controls, Newton/binary fallback, duplicate-X handling, and locality cache implemented |
| Ownership | Isolated point-array containers, indexed topology mutation, point identity preservation, and deep runtime duplication are implemented |
| Point state | Five handle modes, locks, force-linear flags, and atomic point/curve snapshots are implemented |
| Change propagation | Point changes invalidate Native compiled state; removed points disconnect; atomic restore emits one curve-level change |
| Native performance | Standard transitions are approximately 1.8–4.1× faster than Tween |
| Function performance | Native deterministic function modes are approximately 63–103× faster than legacy |
| Custom performance | Native custom Bézier is approximately 43–136× faster than legacy across 2-, 9-, and 65-point workloads |
| Performance regression gate | All 27 baseline cases pass the median/MAD noise-aware comparison |
| Editor boundary | Narrow legacy/native backend foundation and capability discovery are implemented and covered by 16 contract checks |
| Build automation | Pinned Windows/Web build script and GitHub Actions workflow are present; Windows release path is locally verified |
| Legacy status | Existing `EasingCurve` remains functional and comprehensively tested |

### Partially complete

- Native format version 2 and frozen IDs exist, but production migration behavior still needs explicit old/future-version policy and fixtures.
- Point parity covers the core state matrix, but remaining graph edge cases and full legacy differential coverage are incomplete.
- Windows release binaries build locally, but debug builds are blocked on the reference machine by Windows Security error 225.
- Web build entries and CI exist, but Emscripten is unavailable locally and neither Web build nor browser runtime has been verified.
- Native benchmarks cover 27 runtime cases but not every mode, signal/compilation path, or editor workload.
- The test scene can switch resource types, but the production editor cannot.
- The editor adapter is a foundation only; the production editor still uses concrete legacy types.

### Missing

- Verified Windows debug artifact and editor hot-reload workflow.
- WebAssembly build and browser runtime/export validation.
- Generated Jitter/Irregular modes, CSS modes, and extended Bounce parameters.
- Full Native graph, Inspector, preset, preview, and Undo/Redo support.
- Explicit optional conversion between resource types.
- Exact-ZIP allowlist packaging, checksums, metadata, and clean-project tests.
- Native support for the complete legacy platform matrix.
- Evidence sufficient to consider legacy deprecation.

## 3. Public API lifecycle

### Native API

`NativeEasingCurve` and `NativeEasingCurvePoint` are direct GDExtension `Resource` classes.

They own:

- Native transition sampling.
- Custom curve compilation.
- Point ownership and change propagation.
- Handle constraints and atomic mutations.
- Native serialization and version migration.
- Runtime duplication.
- Transition parameter validation.

Native must remain usable without a GDScript runtime wrapper.

### Legacy API

`EasingCurve` and `EasingCurvePoint` retain:

- Existing `class_name` values.
- Existing script and resource paths.
- Existing enum values.
- Existing serialization.
- Existing public methods and signals.
- Existing runtime Callable behavior.
- Full custom editor functionality.

Legacy must not depend on Native classes or binaries.

### Lifecycle stages

1. **Development:** Native is experimental; legacy is the production API.
2. **Initial Native release:** both are supported; Native is recommended for new Windows and Web projects; legacy remains the fallback.
3. **Parity qualification:** Native expands to all required workflows and platforms while legacy remains supported.
4. **Conditional deprecation:** `EasingCurve` is labeled deprecated only after every deprecation gate passes.
5. **Compatibility period:** deprecated legacy resources continue to load, edit, export, and migrate.
6. **Possible future removal:** requires a separate decision and is not authorized by this plan.

## 4. Native completion and deprecation gate

`EasingCurve` must not be deprecated until all of the following are true.

### Runtime parity

- Every documented, serializable legacy transition has a Native equivalent.
- All transition parameters, ease modes, transforms, endpoints, and validation behavior pass differential tests.
- Native point ownership, duplication, signals, and mutations meet or exceed legacy reliability.
- Every legacy workflow has exact parity or an explicitly approved replacement.
- Callable baking is verified as an acceptable replacement for Native users; legacy live Callables remain available during the compatibility period.

### Editor parity

- Native supports the complete Inspector and graph workflow.
- Presets, handles, locks, crossings, point lists, preview generation, save normalization, and Undo/Redo meet or exceed legacy behavior.
- Native editor performance is no worse than legacy beyond measured timing noise.
- Manual visible-editor testing reports no unresolved parity defects.

### Serialization and conversion

- Native has a stable, versioned production format.
- Standalone and embedded Native resources round-trip safely.
- Legacy-to-Native conversion preserves all representable state.
- Unsupported or baked behavior is reported before conversion.
- Conversions default to non-destructive side-by-side output.
- Users can retain or restore the original legacy resource.

### Testing and stability

- Native meets at least the same automated test coverage standards as legacy.
- Native passes every supported Godot-version and platform matrix job.
- No unresolved severity-one or severity-two Native defects remain.
- At least one stable Native release cycle completes without a migration, data-loss, editor-corruption, or exported-runtime blocker.
- Real project testing includes built-in, custom, generated, CSS, and converted curves.

### Performance

- Every standard Native transition remains faster than Tween on the reference system.
- Every comparable Native plugin mode remains faster than its legacy implementation.
- Native editor interaction meets or exceeds the legacy baseline within measured noise.
- No sampling path invokes Tween, GDScript, or a Callable.
- Performance reports are repeatable and archived.

### Platform coverage

- Native supports every platform still officially supported by the legacy plugin at the time deprecation is proposed, or the owner explicitly approves a documented exception.
- Windows and Web support alone are insufficient to deprecate legacy while legacy remains the supported path for other platforms.
- Missing or failed Native binaries cannot prevent a legacy-only project from loading.

### Documentation and user readiness

- The Native API reference is complete.
- Migration, Callable baking, backups, rollback, and platform requirements are documented.
- Release notes provide advance notice before the legacy deprecation label is applied.
- Deprecation does not introduce runtime warning spam or break exported projects.
- Any eventual removal timeline is handled by a separate plan.

## 5. Feature-parity matrix

| Capability | Legacy `EasingCurve` | `NativeEasingCurve` | Needed before Native release | Needed before legacy deprecation |
|---|---|---|---|---|
| Custom Bézier | Complete | Sampling complete | Editing parity | Yes |
| Standard Tween set | Complete | Complete | Differential tests | Yes |
| Constant | Complete | Complete | Differential/manual verification | Yes |
| Power | Complete | Complete | Differential/manual verification | Yes |
| Step | Complete | Complete | Differential/manual verification | Yes |
| Back parameters | Complete | Overshoot implemented | Complete remaining metadata and edge cases | Yes |
| Elastic parameters | Complete | Amplitude/period implemented | Complete remaining metadata and edge cases | Yes |
| Bounce parameters | Complete | Standard only | Extended form | Yes |
| Spring parameters | Complete | Frequency/decay implemented | Complete remaining metadata and edge cases | Yes |
| Physics Spring | Complete | Complete | Differential/manual verification | Yes |
| Jitter/Irregular | Complete | Missing | Generated Native data | Yes |
| CSS Linear | Complete | Missing | Parser and compiled data | Yes |
| CSS Cubic Bézier | Complete | Missing | Parser and solver | Yes |
| Reverse/invert | Complete | Complete | Manual/editor verification | Yes |
| Arbitrary Callable | Live runtime support | Explicit point baking implemented | Bake UI and user acceptance | Approved replacement |
| Point geometry | Complete | Complete | Extended mutation | Yes |
| Handle modes | Complete | Five modes implemented | Complete edge-case differential tests | Yes |
| Locks/force-linear | Complete | Persisted and enforced | Complete editor verification | Yes |
| Deep runtime copy | Complete | Complete for current fields | Extend with each new field | Yes |
| Inspector | Complete | Not integrated | Shared adapter | Yes |
| Graph editing | Complete | Not integrated | Shared adapter | Yes |
| Presets/preview/save | Complete | Not integrated | Shared adapter | Yes |
| Undo/Redo | Complete | Not integrated | Native snapshots | Yes |
| Windows | Complete | Release runtime/export proof; release DLL is the editor fallback | Debug proof and reproducible package | Yes |
| Web | Complete | Build configuration only | wasm32 build and browser export proof | Yes |
| Linux/macOS/Android | Legacy available | Missing | Deferred initially | Required or explicitly excepted |
| Packaging/CI | Legacy scripts exist | Build workflow present | Execute builds and add exact-ZIP pipeline | Full supported matrix |
| Stable field use | Established | Unproven | Initial release evidence | One stable release cycle |

## 6. Architecture decisions

### Independent runtime implementations

The legacy solver remains independent instead of becoming a Native façade. This preserves its value as a backup if the extension is unavailable or defective.

Shared behavior is maintained through:

- Golden sample fixtures.
- Differential tests.
- Shared mathematical reference data.
- Shared editor presentation.
- Optional conversion tools.

Runtime solver code is not shared across the C++/GDScript boundary.

### Native IDs and serialization

The legacy enum and serialization remain unchanged.

Native transition IDs are frozen independently:

| Native ID | Transition |
|---:|---|
| 0–11 | Godot Tween standard transitions |
| 100 | Custom Bézier |
| 101 | Constant |
| 102 | Jitter |
| 103 | Irregular |
| 104 | Step |
| 105 | Power |
| 106 | Physics Spring |
| 107 | CSS Linear |
| 108 | CSS Cubic Bézier |

Native production resources use `format_version = 2`. Conversion uses an explicit mapping table and never relies on enum ordinal equivalence.

### Shared editor adapters

The editor uses:

- `CurveEditorBackend`
- `LegacyCurveEditorBackend`
- `NativeCurveEditorBackend`

The adapter covers only editor concerns:

- Resource and backend identity.
- Capabilities and transition descriptors.
- Point-state access.
- Sampling for previews.
- Mutation commands.
- Snapshot capture and restore.
- Change notification.
- Preset and save-normalization operations.

Backend selection occurs once when a resource is inspected. Runtime users pay no adapter cost.

### Capability-driven UI

The shared editor queries capabilities such as:

- Runtime Callable support.
- Callable baking support.
- Available transitions and parameters.
- Handle-mode support.
- Conversion support.

This allows future Native-only features without requiring legacy implementations merely to maintain UI symmetry.

### Function modes

| Mode | Native strategy | Legacy policy |
|---|---|---|
| Constant, Power, Step | Direct C++ equations | Existing implementation retained |
| Back, Elastic, Bounce, Spring | Parameterized C++ equations | Existing implementation retained |
| Physics Spring | Direct C++ equation | Existing implementation retained |
| Jitter, Irregular | Persist generated data; Native compiled sampling | Existing implementation retained |
| CSS Linear | Boundary parser and Native segments | Existing implementation retained |
| CSS Cubic Bézier | Boundary parser and Native Bézier solver | Existing implementation retained |
| Reverse/invert | Apply in C++ | Existing implementation retained |
| Arbitrary Callable | Explicit point baking | Live Callable retained until any later removal decision |

### Fail-soft native availability

- Legacy scripts contain no static Native type references.
- Native editor scripts load conditionally.
- The plugin checks `ClassDB.class_exists("NativeEasingCurve")`.
- Legacy-only resources remain loadable and editable when Native is absent.
- Native resources report a clear missing-backend error.
- Native platform support is not overstated.

### Initial platforms

The first Native release targets:

- Windows x86_64.
- Web wasm32 non-threaded.

Build against the Godot 4.4 extension API and validate through Godot 4.7, following [Godot’s GDExtension compatibility guidance](https://docs.godotengine.org/en/latest/tutorials/scripting/cpp/gdextension_cpp_example.html).

Web exports enable Extension Support as required by [Godot’s Web export documentation](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_web.html).

Linux, macOS, Android, and threaded Web may be deferred from the first release, but this prevents legacy deprecation until equivalent coverage exists or an exception is explicitly approved.

## 7. Ordered milestones

### NATIVE-01 — Toolchain, platforms, and fallback feasibility

**Status:** **In progress.** Windows release, Godot 4.4–4.7 ABI loading, and legacy-only fallback are verified. Windows debug is blocked by Windows Security error 225. Web build/runtime remains unverified.

**Goal:** Prove Godot 4.4 compatibility, Windows/Web builds, and legacy-only fallback.

**Implementation:**

1. Pin stable Godot 4.4-compatible `godot-cpp`.
2. Build Windows and non-threaded Web debug/release libraries.
3. Add only tested manifest entries.
4. Create Native-only, legacy-only, and mixed-resource fixtures.
5. Make Native editor registration conditional.
6. Test Godot 4.4–4.7 loading and export behavior.

**Acceptance:** Legacy remains usable without Native; both APIs coexist when Native is present.

**Complexity:** Medium.

### NATIVE-02 — Freeze independent public contracts

**Status:** **In progress.** Native IDs, format version 2, indexed point APIs, atomic snapshots, and the initial adapter contract are implemented. Legacy reflection fixtures, conversion-result contracts, and production migration behavior remain.

**Goal:** Stabilize both APIs and Native format version 2.

**Implementation:**

1. Capture the legacy public contract through reflection tests.
2. Freeze Native classes, IDs, properties, methods, and signals.
3. Finalize index-based Native point APIs.
4. Define editor-adapter and conversion-result contracts.
5. Prove neither runtime depends on the other.

**Acceptance:** Both resource types save, load, duplicate, and coexist without inheritance or serialization ambiguity.

**Dependencies:** NATIVE-01.

**Complexity:** Medium.

### NATIVE-03 — Expand performance baselines

**Status:** **In progress.** Twenty-seven runtime cases, raw trials, median/MAD reporting, and a noise-aware gate are implemented. Complete ease coverage, signal/compilation amplification, and editor workloads remain.

**Goal:** Establish regression gates for both implementations.

**Coverage:**

- Every standard transition and ease.
- Custom curves with 2, 9, and 65 points.
- Sequential, reverse, and random sampling.
- Mutation, compilation, duplication, and signals.
- Editor adapter and interaction workloads.

**Acceptance:** Repeated reference runs reliably identify deliberate regressions.

**Dependencies:** NATIVE-01 and NATIVE-02.

**Complexity:** Medium.

### NATIVE-04 — Complete Native point parity

**Status:** **In progress.** Five handle modes, locks, force-linear state, indexed topology mutation, identity-preserving atomic state restore, serialization, and deep copy are implemented. Remaining graph edge cases and full legacy differential coverage must close before acceptance.

**Goal:** Support every existing graph mutation safely.

**Implementation:**

- Port handle modes, locks, and force-linear state.
- Add indexed topology mutation.
- Add identity-preserving atomic snapshot application.
- Extend serialization and deep duplication.
- Prevent recursive signal and compilation amplification.

**Acceptance:** Native passes the legacy point-state matrix and ownership tests.

**Dependencies:** NATIVE-02 and NATIVE-03.

**Complexity:** Large.

### NATIVE-05 — Complete deterministic Native transitions

**Status:** **In progress.** Constant, Power, Step, Physics Spring, parameterized Back/Elastic/Spring, and reverse/invert are implemented and differentially tested. Extended Bounce, complete metadata, and remaining edge cases are outstanding.

**Goal:** Port all equation-based modes.

**Implementation:**

- Constant, Power, Step, and Physics Spring.
- Parameterized Back, Elastic, Bounce, and Spring.
- Reverse/invert.
- Validation and parameter metadata.

**Acceptance:** Numerical parity passes and every Native mode beats its legacy counterpart.

**Dependencies:** NATIVE-04.

**Complexity:** Large.

### NATIVE-06 — Generated, CSS, and Callable-bake support

**Status:** **In progress.** Callable-to-points baking is implemented and verified not to retain callbacks. Jitter, Irregular, CSS Linear, and CSS Cubic Bézier remain.

**Goal:** Complete remaining Native runtime modes without per-sample callbacks.

**Implementation:**

- Persisted Jitter and Irregular data.
- CSS Linear parser and Native sampling.
- CSS Cubic Bézier parser and Native solving.
- Explicit configurable Callable-to-points baking.
- Preserve legacy live Callable behavior.

**Acceptance:** Every documented workflow has a Native representation or approved bake path.

**Dependencies:** NATIVE-04 and NATIVE-05.

**Complexity:** Large.

### NATIVE-07 — Extract the shared editor boundary

**Status:** **In progress.** The narrow backend base, factory, capability discovery, Legacy adapter, Native adapter foundation, and contract tests exist. No production editor workflow has been retargeted yet.

**Goal:** Decouple the existing editor from concrete legacy types without changing its behavior.

**Implementation:**

1. Add the narrow editor backend contract.
2. Implement the legacy adapter.
3. Retarget the editor to adapter operations.
4. Run all existing editor tests against the adapter.
5. Confirm no meaningful legacy performance regression.

**Acceptance:** Legacy behavior is unchanged through the new editor boundary.

**Dependencies:** NATIVE-02 and NATIVE-03.

**Complexity:** Large.

### NATIVE-08 — Add full Native editor support

**Status:** **Not started.**

**Goal:** Make Native resources first-class in the shared editor.

**Implementation:**

- Add the Native adapter.
- Integrate Inspector, graph, points, presets, previews, and save hooks.
- Use atomic mutations for gestures and Undo/Redo.
- Expose Callable baking.
- Apply capability-driven UI differences.

**Acceptance:** Shared editor contract tests pass against both backends.

**Dependencies:** NATIVE-04 through NATIVE-07.

**Complexity:** Very large.

### NATIVE-09 — Optional bidirectional conversion

**Status:** **Not started.**

**Goal:** Let users switch resource types without forced migration.

**Implementation:**

- Convert legacy to Native.
- Convert representable Native resources to legacy.
- Classify fields as exact, approximated, baked, or unsupported.
- Default to side-by-side output.
- Preserve source resources.
- Require explicit approval for lossy conversion.

**Acceptance:** Conversion never silently changes or discards behavior.

**Dependencies:** NATIVE-06 and NATIVE-08.

**Complexity:** Large.

### NATIVE-10 — Final runtime and editor certification

**Status:** **Not started.**

**Goal:** Certify the initial Native implementation.

**Acceptance:**

- All numerical tests pass.
- Native runtime performance gates pass.
- Legacy has no unexplained regressions.
- Editor performance remains within the accepted envelope.
- Raw reports are archived.

**Dependencies:** NATIVE-03 through NATIVE-09.

**Complexity:** Medium.

### NATIVE-11 — Reproducible CI and dual-API packaging

**Status:** **In progress.** Pinned build automation and Windows/Web build jobs exist. Exact-ZIP staging, checksums, metadata, artifact installation, and clean ZIP validation remain.

**Goal:** Produce one tested addon containing both APIs.

**Implementation:**

- Build Native binaries from pinned tagged sources.
- Stage package contents through an allowlist.
- Generate checksums and build metadata.
- Test the exact ZIP in clean legacy-only and mixed projects.
- Test Windows and Web exports from the ZIP.

**Acceptance:** Local ignored files cannot affect the artifact, and legacy remains independent.

**Dependencies:** NATIVE-01 and NATIVE-10.

**Complexity:** Large.

### NATIVE-12 — Initial dual-API release

**Status:** **Not started.**

**Goal:** Release Native for Windows and Web without deprecating legacy.

**Policy:**

- Native is recommended for new supported-platform projects.
- Legacy remains fully supported as the compatibility and fallback API.
- Both APIs retain full editor support.
- Release notes explicitly state that legacy is not yet deprecated.

**Acceptance:** Fresh and upgrading users can safely choose either resource.

**Dependencies:** NATIVE-01 through NATIVE-11.

**Complexity:** Medium.

### NATIVE-13 — Full-coverage qualification

**Status:** **Not started.**

**Goal:** Raise Native from initial-release quality to the same or better overall standard as legacy.

**Scope:**

- Add remaining legacy-supported platforms.
- Resolve post-release Native defects and migration gaps.
- Complete real-project validation.
- Re-run the full deprecation gate.
- Complete at least one stable Native release cycle.

**Acceptance:** Every condition in the Native completion and deprecation gate is independently evidenced.

**Dependencies:** NATIVE-12.

**Complexity:** Very large.

### NATIVE-14 — Conditional legacy deprecation

**Status:** **Not started and not authorized.** This milestone still requires all gates plus explicit owner approval.

**Goal:** Label `EasingCurve` deprecated only after NATIVE-13 is accepted.

**Implementation:**

1. Publish evidence that Native meets or exceeds legacy standards.
2. Announce the deprecation in documentation and release notes.
3. Keep legacy resources loadable, editable, and exportable.
4. Keep migration and rollback tooling available.
5. Avoid runtime warning spam.
6. Establish a compatibility period without scheduling removal.

**Acceptance:** Deprecation introduces no breakage and every deprecation gate remains passing.

**Dependencies:** NATIVE-13 and explicit owner approval.

**Complexity:** Medium.

### Future legacy removal

Removal is not included in NATIVE-14. If considered later, it requires:

- A separate proposal.
- Explicit owner approval.
- Usage and migration evidence.
- A defined compatibility window.
- A recovery path for archived projects.
- Independent release and rollback plans.

## 8. Manual user smoke test — first production-grade tranche

This smoke test verifies visible behavior and resource persistence that headless tests cannot fully establish. It is deliberately shorter than the automated matrix. Run it in a clean editor session before starting the next implementation tranche.

### Preconditions

1. Preserve or commit unrelated work before testing.
2. Use Godot 4.7.1 and open this repository as the project.
3. Build the verified editor fallback library with:

   ```powershell
   ./native/build_native.ps1 -Platform windows -Target template_release
   ```

4. The manifest intentionally uses this release DLL for Windows editor sessions until the debug artifact passes local security validation. Do not disable security software if a separate debug build reports Windows error 225; record that as **Blocked: debug artifact**.
5. In the Godot Output panel, confirm there are no missing-library, missing-class, parse, or resource-load errors.
6. Confirm **Create New Resource** offers all four public classes: `EasingCurve`, `EasingCurvePoint`, `NativeEasingCurve`, and `NativeEasingCurvePoint`.

### A. Standard transition parity

1. Open `res://addons/easing_curve/_test_scene/test.tscn`.
2. Select the root `TestScene`; confirm `Use Native Curve` is enabled and both Native and legacy resource properties are present.
3. Run the main scene and enable **Match Tween**.
4. Test every standard transition once with **Out** easing: Linear, Sine, Quint, Quart, Quad, Expo, Elastic, Cubic, Circ, Bounce, Back, and Spring.
5. Test Sine, Elastic, Back, and Spring with all four ease modes.
6. Toggle **Play Reverse**, then press **Restart** for at least Sine, Bounce, Back, and Spring.

Pass when the Native and Tween markers start and finish together, remain visually coincident except for negligible frame/render noise, and show no jump, stall, NaN position, crash, or Output error.

### B. Native deterministic modes and transforms

For each case below, stop the scene, edit the assigned `Native Curve` resource in the Inspector, run again, and observe at least two complete cycles:

- Constant with a non-default value.
- Step with 5 steps, then toggle its from-start behavior.
- Power with exponents below and above 1.
- Physics Spring with visibly different stiffness/damping values.
- Back with non-default overshoot.
- Elastic with non-default amplitude/period.
- Spring with non-default frequency/decay.
- Reverse and invert independently, then together.

Pass when each parameter causes a stable, repeatable, visibly appropriate change, endpoints remain correct for the selected transform, and restarting does not retain stale compiled behavior.

### C. Custom curve editing and ownership

1. Assign a saved `NativeEasingCurve` resource and set its transition to Custom.
2. Use at least three `NativeEasingCurvePoint` resources.
3. Exercise Free, Linear, Balanced, Mirrored, and Linked handle modes.
4. Toggle left/right force-linear and point locking.
5. Move a point and both controls, add a point, reorder or replace a point, and remove a point.
6. Run after each meaningful edit and confirm the motion changes without reopening the project.
7. After removing a point, edit that detached point resource and confirm the active curve does not change.

Pass when constraints behave predictably, one edit produces one visible refresh/restart, point order remains valid, removed points no longer affect the curve, and no edit causes a crash or recursive refresh loop.

### D. Save, reload, and coexistence

1. Save the Native curve as a side-by-side `.tres`; do not overwrite a legacy resource.
2. Record transition, ease, parameters, point positions, controls, handle modes, locks, and force-linear flags.
3. Close and reopen the editor, reload the resource, and compare every recorded field.
4. Run the scene with `Use Native Curve` enabled.
5. Disable `Use Native Curve`, assign a legacy custom curve, and run it.
6. Re-enable Native and confirm both resources retained their independent values.

Pass when the Native resource round-trips exactly, both APIs coexist in one scene, and switching backends does not mutate or replace either resource.

### E. Release export

1. Set the scene to a standard Native transition and export the **Windows Desktop** release preset.
2. Run the exported executable and exercise Match Tween, Reverse, Restart, and several standard transitions.
3. Repeat with a saved custom Native curve.
4. Repeat one export with `Use Native Curve` disabled to verify the legacy fallback remains shippable in the dual-API package.

Pass when all three exports start without missing-extension/resource errors and reproduce the editor behavior. Keep the export logs with the smoke-test record.

### Smoke-test record

Record results here rather than relying on memory:

| Date | Godot | Build/artifact | A | B | C | D | E | Notes/evidence |
|---|---|---|---|---|---|---|---|---|
| Pending | 4.7.1 | Windows x86_64 release editor fallback + release export | — | — | — | — | — | Manual run required |

Any crash, data loss, stale result after mutation, missing class, serialization mismatch, or exported-runtime failure blocks the next release qualification step. Visual differences should be recorded with the transition/ease/parameters and a screenshot or short capture.

## 9. Recommended next execution tranche

### Priority 1 — Close NATIVE-01 platform/toolchain evidence

1. Diagnose the Windows debug DLL security rejection without weakening machine security.
2. Produce and load a genuine debug DLL in the editor; verify hot reload separately from release export.
3. Run the Web CI build, retain the wasm artifacts, and test a non-threaded browser export.
4. Add a Windows debug-specific manifest entry only after that artifact is proven loadable; until then the verified release DLL remains the generic editor fallback.
5. Keep Web manifest entries only after the referenced debug and release artifacts are proven loadable.

This is first because an editor-native plugin cannot be considered feasible while its development artifact is blocked, and an unexecuted Web workflow is configuration rather than platform support.

### Priority 2 — Close NATIVE-02 and NATIVE-03 contracts

1. Add reflection fixtures for the complete legacy and current Native public contracts.
2. Define explicit behavior for absent, old, current, and future Native format versions.
3. Define the conversion-result data contract before implementing conversion.
4. Add benchmark cases for all ease modes, compile invalidation, signal amplification, snapshots, and the backend calls used by the first editor migration.
5. Archive a new baseline only after the manual smoke test and debug/release artifacts pass.

This prevents later runtime and editor work from accidentally changing serialized fields or performance expectations.

### Priority 3 — Retarget one legacy editor vertical slice

Move one complete workflow—resource selection, sampling preview, and point-list read access—through `LegacyCurveEditorBackend`. Keep the concrete legacy implementation available behind the adapter until behavior and timing tests pass. Then migrate mutation, snapshots, presets, and save normalization one workflow at a time.

This incremental adapter approach is preferred over a broad editor rewrite. It tests the boundary against real behavior and avoids growing an interface from speculative Native requirements.

### Priority 4 — Finish core Native runtime parity

1. Close remaining point-state edge cases and full legacy differential coverage (NATIVE-04).
2. Complete extended Bounce and transition metadata/validation (NATIVE-05).
3. Implement persisted Jitter/Irregular data and CSS Linear/Cubic Bézier parsing and sampling (NATIVE-06).
4. Run correctness and performance gates after each mode family, not after the whole group.

### Priority 5 — Native editor, conversion, and packaging

Proceed to NATIVE-08 through NATIVE-11 only after the shared legacy editor path is stable. Add Native editor support capability by capability, then non-destructive conversion, exact-ZIP staging, checksums, and clean-project installation/export tests.

The next recommended implementation session should therefore be **NATIVE-01 closeout plus NATIVE-02 format/reflection contracts**. The first editor vertical slice follows immediately after those gates; adding more adapter abstractions before that evidence would increase complexity without reducing current risk.

## 10. Definition of Done

### Initial Native release

The first release is complete when:

- Both APIs are public, documented, packaged, and usable together.
- Legacy remains independent and is not marked deprecated.
- Native has complete intended runtime and editor functionality for Windows and Web.
- Conversion is optional and non-destructive.
- Native performance, correctness, export, and package gates pass.
- The exact release ZIP works in clean projects.

### Legacy deprecation

Legacy deprecation is permitted only when:

- `NativeEasingCurve` is complete for all documented and approved replacement workflows.
- Native meets or exceeds legacy runtime, editor, serialization, testing, reliability, and performance standards.
- Native covers every officially supported legacy platform or an exception is explicitly approved.
- Migration and rollback are proven safe.
- At least one stable Native release cycle completes without critical blockers.
- The owner explicitly approves the deprecation after reviewing the evidence.

Deprecation does not authorize removal. `EasingCurve` remains available as a compatibility resource until a separate future plan explicitly changes that policy.

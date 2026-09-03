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
| Branch | `native-v2-spike` at `1d6afe1` plus the current shared-editor tranche |
| Plan tracking | This file is the mutable source of truth for migration status and manual evidence |
| Automated tests | All 23 suites pass under Godot 4.7.1 |
| Native smoke tests | 476 checks pass |
| Dual public API contract | Reflection fixtures freeze intended methods, properties, signals, enum/constant IDs, and Native format status across both resource APIs; 143 checks pass |
| Legacy runtime tests | 1,380 checks pass |
| Serialization tests | 902 checks pass |
| Windows export | 472,064-byte release DLL loads built-in and custom Native resources in an isolated exported project |
| Native ABI | `godot-cpp` is pinned to `godot-4.4.1-stable`; one release DLL loads under Godot 4.4.1, 4.5.1, 4.6.1, and 4.7.1 |
| Legacy fallback | Complete legacy addon loads, samples, and serializes in an isolated project with no Native manifest or binary |
| Native standard set | All 12 Godot Tween transitions implemented directly in C++ |
| Native deterministic modes | Constant, Step, Power, Physics Spring, parameterized Back/Elastic/Spring, reverse, and invert are implemented directly in C++ |
| Native Callable policy | Explicit point baking is implemented; no Native sampling path invokes a Callable |
| Native custom solver | Compiled segments, sorting, monotonic controls, Newton/binary fallback, duplicate-X handling, and locality cache implemented |
| Ownership | Isolated point-array containers, indexed topology mutation, point identity preservation, and deep runtime duplication are implemented |
| Point state | Five handle modes, locks, force-linear flags, and atomic point/curve snapshots are implemented |
| Change propagation | Point changes invalidate Native compiled state; removed points disconnect; atomic restore emits one curve-level change |
| Native resource versioning | Absent markers resolve to current v2; malformed, older, and future values are retained but fail closed for sampling; standalone, embedded, runtime-copy, and round-trip fixtures pass |
| Conversion result contract | Versioned result schema records source/target backends, output resource, messages, and per-field exact/approximated/baked/unsupported outcomes |
| Native performance | All 12 standard transitions across all four ease modes beat Tween in the expanded 48-case comparison; the current run measured approximately 1.5–4.1× faster |
| Function performance | Native deterministic function modes are approximately 63–103× faster than legacy |
| Custom performance | Native custom Bézier is approximately 43–136× faster than legacy across 2-, 9-, and 65-point workloads |
| Performance regression gate | The prior 27-case reference is retained. The expanded 63-case run completed, but a broad host slowdown failed the old absolute gate, so it has not been promoted to the new baseline |
| Editor boundary | The first production vertical slice is active for both APIs: backend selection, sampled graph/preview rendering, bulk point reads, selection, Native force-linear/lock controls, and atomic Native Undo/Redo. It is covered by 41 contract and 16 vertical-slice checks |
| Editor boundary performance | Three repeated 65-point runs show preview dispatch adds about 12–15 microseconds per 121-sample draw, bulk point reads and snapshots are near direct cost, and optimized Native atomic mutation adds about 6–7 microseconds per mutation |
| Native Web export | Non-threaded debug (339,080 bytes) and release (334,967 bytes) WASM libraries export and run in isolated headless-browser projects; built-in/custom resources load, sample, and deep-copy correctly |
| Build automation | Pinned Windows/Web build script, manifest preflight, and GitHub Actions build-plus-browser workflow are present; Windows release and local Web paths are verified |
| Manual smoke test | 2026-09-03: the first shared-editor slice passed startup, standard/custom rendering, selection, point options, Undo/Redo, persistence, Native Inspector previews, the Native FileSystem class icon, and legacy regression checks. The timing probe was deferred |
| Legacy status | Existing `EasingCurve` remains functional and comprehensively tested |

### Partially complete

- Point parity covers the core state matrix, but remaining graph edge cases and full legacy differential coverage are incomplete.
- Windows release binaries build locally, but debug builds are blocked on the reference machine by Windows Security error 225.
- Web build and browser runtime are locally verified; the updated GitHub Actions job and its retained artifacts still need an actual hosted run.
- Native runtime benchmarks cover 63 cases, including every standard transition/ease pair, but the expanded absolute baseline still needs repeatable quiet-host runs.
- Editor benchmarks cover the first adapter slice, snapshots, and mutation-plus-recompile; complete gesture, signal-amplification, preset, and save-normalization workloads remain.
- The production Inspector and Curve Editor can display/select both resource types and edit Native point options, but Native graph geometry is intentionally read-only in this first slice.

### Missing

- Verified Windows debug artifact and editor hot-reload workflow.
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
| Locks/force-linear | Complete | Persisted and enforced; current UI does not expose them | Add shared editor controls and complete manual verification | Yes |
| Deep runtime copy | Complete | Complete for current fields | Extend with each new field | Yes |
| Inspector | Complete | Not integrated | Shared adapter | Yes |
| Graph editing | Complete | Not integrated | Shared adapter | Yes |
| Presets/preview/save | Complete | Not integrated | Shared adapter | Yes |
| Undo/Redo | Complete | Not integrated | Native snapshots | Yes |
| Windows | Complete | Release runtime/export proof; release DLL is the editor fallback | Debug proof and reproducible package | Yes |
| Web | Complete | Non-threaded debug/release build and isolated browser runtime verified on Godot 4.7.1 | Hosted CI run and user-facing export rerun | Yes |
| Linux/macOS/Android | Legacy available | Missing | Deferred initially | Required or explicitly excepted |
| Packaging/CI | Legacy scripts exist | Build workflow present | Execute builds and add exact-ZIP pipeline | Full supported matrix |
| Stable field use | Established | v2 public/serialization contract frozen and fixture-tested | Initial release evidence | One stable release cycle |

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
- A project containing serialized Native resources requires the platform extension; Godot cannot deserialize those resources early enough for a runtime fallback.
- Missing Native support must therefore be prevented at packaging/export validation rather than handled as an in-scene fallback.
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

**Status:** **In progress.** Windows release, Godot 4.4–4.7 ABI loading, legacy-only fallback, and Godot 4.7.1 non-threaded Web debug/release browser runtime are verified. The manifest preflight enforces exact tested artifact names. Windows debug remains blocked by Windows Security error 225, and the updated hosted Web CI job has not yet produced retained evidence.

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

**Status:** **Verified.** Reflection fixtures freeze both intended public APIs. Native IDs, format version 2, indexed point APIs, atomic snapshots, adapter contracts, and the conversion-result schema are fixed. Absent, malformed, old, current, and future version behavior is covered by standalone, embedded, runtime-copy, and save/load fixtures. The isolated Native-only export and legacy-without-Native fixtures prove neither runtime depends on the other.

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

**Status:** **In progress.** Runtime coverage is expanded from 27 to 63 cases: all 12 standard transitions now exercise In, Out, In-Out, and Out-In, alongside deterministic functions, 2/9/65-point access patterns, mutation, and duplication. A targeted eight-case editor-backend benchmark measures preview sampling, bulk point reads, snapshots, and mutation-plus-recompile for both APIs. Three repeated editor runs were stable. The 63-case runtime report completed and every standard Native pair beat Tween, but the old absolute gate failed broadly during a host slowdown; a new baseline is intentionally deferred. Full gesture timing and a dedicated signal-amplification workload remain.

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

**Status:** **In progress.** The first production vertical slice is complete. The shared Curve Editor and preview generator select a backend once, then use it for sampling, value ranges, point reads, selection, and point-option state. The Inspector accepts both public resources. Native custom curves render and expose force-linear/lock controls through atomic point state; standard Native transitions use the shared sampled graph and hide point controls. Legacy mutation behavior remains unchanged. Remaining write-side graph gestures, point-list integration, presets, and save normalization still use legacy-specific paths.

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

**Status:** **In progress.** The first Native Inspector/graph slice supports sampled rendering, point/control visualization, point selection, force-linear, locks, preview generation, and atomic toolbar Undo/Redo. Geometry dragging, topology edits, point-list synchronization, presets, save hooks, and full gesture Undo/Redo remain.

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

**Status:** **In progress.** Pinned Windows/Web build jobs use the maintained Emscripten setup action and platform-specific manifest preflight; a dependent Windows job downloads those exact artifacts and runs isolated debug/release browser exports. Local exports pass. Hosted artifact evidence, exact-ZIP staging, checksums, metadata, artifact installation, and clean ZIP validation remain.

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
| 2026-09-03 | 4.7.1 | Windows x86_64 release editor fallback; Web export without wasm32 extension | Pass with observation | Pass | Partial | Partial | Blocked on Native Web | A: Circ, Cubic, Elastic, Expo, Quart, and Quint showed slight start jitter relative to Tween; legacy showed the same behavior. C/D: force-linear and lock state exist in Native but have no current UI controls, so they were not manually verified. E: Web reported no wasm32 library, then failed to deserialize `NativeEasingCurvePoint` from the exported test scene. |
| 2026-09-03 | 4.7.1 | Non-threaded wasm32 debug and release; isolated automated browser fixture | Not rerun | Not rerun | Automated runtime coverage only | Automated runtime coverage only | Pass (automated) | Both exports registered Native classes and loaded, sampled, and deep-copied built-in and custom Native resources in headless Chrome. User-facing scene/export validation remains to be rerun manually. |

### Shared-editor vertical-slice record

| Date | Godot | Startup/Inspector | Standard graph | Custom selection | Point options | Undo/Redo | Persistence | Previews | Legacy regression | Timing probe | Notes/evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-03 | 4.7.1 | Pass | Pass | Pass | Pass with note | Pass | Pass | Pass | Pass | Deferred | Force Linear is editable through the shared point toolbar and persisted correctly. Its C++ property is storage-only, so absence from the raw point Inspector is intentional. Generated Native Inspector previews and the Native `Curve.svg` FileSystem class icon both passed manual verification. |

Any crash, data loss, stale result after mutation, missing class, serialization mismatch, or exported-runtime failure blocks the next release qualification step. Visual differences should be recorded with the transition/ease/parameters and a screenshot or short capture.

Interpretation:

- The shared start jitter in A does not currently implicate the Native equations. Keep it as a diagnostic item and capture per-frame elapsed time/offset before changing either solver.
- The shared editor now exposes force-linear and lock operations, and the vertical-slice smoke test confirms their toolbar, Undo/Redo, and persistence behavior. Final NATIVE-04 manual acceptance still waits for Native geometry and topology editing.
- The original E failure was correctly treated as a Native Web blocker. The non-threaded wasm32 implementation now resolves that technical blocker in isolated debug and release browser fixtures without substituting the legacy API. Final visible-scene acceptance remains manual.

## 9. Recommended next execution tranche

### Priority 1 — Complete the write-side NATIVE-07 boundary

1. Add backend commands for point position/control gestures and indexed add/remove/reorder without exposing either concrete point class to shared editor code.
2. Move legacy graph mutations through those commands one gesture family at a time, preserving the existing pending-add, crossing, and right-drag-delete behavior.
3. Capture one snapshot at gesture start and one at commit. Do not capture or restore a whole curve on every mouse-motion event.
4. Retarget preset application and save normalization after graph mutation is stable.
5. Keep each legacy characterization suite passing after every migrated workflow.

The point mutation probe initially found a redundant whole-curve Native restore. Applying the already-atomic Native point state directly reduced the 65-point mutation workload from roughly 243–279 microseconds to 14–15 microseconds per edit batch iteration. The remaining adapter cost is small enough for toolbar edits; transaction-shaped gesture benchmarks should guide further work.

### Priority 2 — Extend the Native editor from options to geometry

1. Enable Native point/control dragging through the shared commands.
2. Add indexed Native point creation, deletion, and reorder to the graph and point list.
3. Synchronize graph and Inspector point-list selection.
4. Commit one Undo/Redo action per user gesture and verify point identity plus one curve-level change per atomic operation.
5. Rerun manual smoke items C and D once Native geometry and topology are writable.

### Priority 3 — Finish NATIVE-03 regression evidence

1. Add transaction-scale gesture and explicit signal-amplification workloads.
2. Rerun the 63-case runtime benchmark on a quiet reference host. The current report proves relative Native-versus-Tween performance, but its broad absolute slowdown is unsuitable as a baseline.
3. Archive the expanded runtime and editor baselines only after repeated runs pass the noise-aware gate.
4. Use the Match Tween timing probe to classify the shared start jitter before changing either solver.

### Priority 4 — Finish NATIVE-01 release evidence

1. Run the updated Web job in GitHub Actions and retain both exact `.nothreads.wasm` artifacts.
2. Rerun the user-facing Web test scene and record the visible result under smoke-test item E.
3. Diagnose the Windows debug DLL security rejection without weakening machine security, then verify debug editor loading and hot reload separately from release export.
4. Add a Windows debug-specific manifest entry only after that artifact is proven loadable; until then the verified release DLL remains the generic editor fallback.

### Priority 5 — Finish core Native runtime parity

1. Close remaining point-state edge cases and full legacy differential coverage (NATIVE-04).
2. Complete extended Bounce and transition metadata/validation (NATIVE-05).
3. Implement persisted Jitter/Irregular data and CSS Linear/Cubic Bézier parsing and sampling (NATIVE-06).
4. Run correctness and performance gates after each mode family, not after the whole group.

### Priority 6 — Native editor, conversion, and packaging

Proceed to NATIVE-08 through NATIVE-11 only after the shared legacy editor path is stable. Add Native editor support capability by capability, then non-destructive conversion, exact-ZIP staging, checksums, and clean-project installation/export tests.

The next recommended implementation session is therefore the **write-side NATIVE-07 gesture boundary**, followed immediately by Native geometry editing through the same commands. Keep snapshot capture at gesture boundaries so safety and Undo/Redo do not become per-frame costs.

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

# Native Easing Curve Migration and Conditional Legacy Deprecation Plan

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
| Branch | `native-v2-spike` at `b52eaa7` |
| Working tree | User-authored change exists in `res://addons/easing_curve/_test_scene/test.tscn`; implementation must preserve it |
| Automated tests | All 20 suites pass under Godot 4.7.1 |
| Native smoke tests | 369 checks pass |
| Legacy runtime tests | 1,380 checks pass |
| Serialization tests | 902 checks pass |
| Windows export | Release DLL loads built-in and custom Native resources in an isolated exported project |
| Native standard set | All 12 Godot Tween transitions implemented directly in C++ |
| Native custom solver | Compiled segments, sorting, monotonic controls, Newton/binary fallback, duplicate-X handling, and locality cache implemented |
| Ownership | Point-array container ownership and deep runtime duplication are implemented |
| Change propagation | Point changes invalidate Native compiled state; removed points disconnect |
| Native performance | Standard transitions are approximately 1.9–4.2× faster than Tween |
| Custom performance | Native custom Bézier is approximately 34× faster than legacy custom |
| Legacy status | Existing `EasingCurve` remains functional and comprehensively tested |

### Partially complete

- Native format versioning exists but is not a stable production migration boundary.
- Native points lack handle modes, locks, and force-linear behavior.
- Windows binaries build locally but are ignored and absent from clean archives.
- Native benchmarks do not cover every plugin mode, mutation path, point count, or editor workload.
- The test scene can switch resource types, but the production editor cannot.

### Missing

- Stable Godot 4.4-targeted native ABI.
- WebAssembly builds and browser runtime validation.
- Fail-soft legacy operation when Native is absent.
- Native plugin transition parity.
- Shared editor backend adapters.
- Full Native graph, Inspector, preset, preview, and Undo/Redo support.
- Explicit optional conversion between resource types.
- Reproducible native build, package, and release CI.
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
| Constant | Complete | Missing | Native equation | Yes |
| Power | Complete | Missing | Native equation | Yes |
| Step | Complete | Missing | Native equation | Yes |
| Back parameters | Complete | Default only | Native overshoot | Yes |
| Elastic parameters | Complete | Partial | Complete parameters | Yes |
| Bounce parameters | Complete | Standard only | Extended form | Yes |
| Spring parameters | Complete | Standard only | Extended form | Yes |
| Physics Spring | Complete | Missing | Native equation | Yes |
| Jitter/Irregular | Complete | Missing | Generated Native data | Yes |
| CSS Linear | Complete | Missing | Parser and compiled data | Yes |
| CSS Cubic Bézier | Complete | Missing | Parser and solver | Yes |
| Reverse/invert | Complete | Missing | Native transform | Yes |
| Arbitrary Callable | Live runtime support | Bake only | Explicit baking | Approved replacement |
| Point geometry | Complete | Complete | Extended mutation | Yes |
| Handle modes | Complete | Missing | Port five modes | Yes |
| Locks/force-linear | Complete | Missing | Persist and enforce | Yes |
| Deep runtime copy | Complete | Core complete | Include all fields | Yes |
| Inspector | Complete | Not integrated | Shared adapter | Yes |
| Graph editing | Complete | Not integrated | Shared adapter | Yes |
| Presets/preview/save | Complete | Not integrated | Shared adapter | Yes |
| Undo/Redo | Complete | Not integrated | Native snapshots | Yes |
| Windows | Complete | Runtime proof | Reproducible package | Yes |
| Web | Complete | Missing | wasm32 build | Yes |
| Linux/macOS/Android | Legacy available | Missing | Deferred initially | Required or explicitly excepted |
| Packaging/CI | Legacy scripts exist | Missing | Windows/Web pipeline | Full supported matrix |
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

## 8. Recommended first three milestones

Begin with:

1. **NATIVE-01 — Toolchain, platforms, and fallback feasibility**
2. **NATIVE-02 — Freeze independent public contracts**
3. **NATIVE-03 — Expand performance baselines**

These establish whether one package can provide a dependable backup API, whether Native has a stable independent contract, and whether subsequent work can be measured reliably.

## 9. Definition of Done

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

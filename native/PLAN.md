# Native Easing Curve Migration and Conditional Legacy Deprecation Plan

> Living plan and progress tracker. Last updated: 2026-09-04.
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
| Branch | `native-v2-spike` at `d4030ea` plus the current NATIVE-08 closeout worktree |
| Plan tracking | This file is the mutable source of truth for migration status and manual evidence |
| Automated tests | All 23 suites pass under Godot 4.7.1 |
| Native smoke tests | 1,030 checks pass, including deferred/no-op publication, resource-free live snapshots, transition-specific parameter visibility, extended Bounce, analytic and Bézier-preset parameter transactions, canonical preset geometry, direct point assignment, modified sampling, migration, and save normalization |
| Dual public API contract | Reflection fixtures freeze intended methods, properties, signals, enum/constant IDs, and Native format status across both resource APIs; 143 checks pass |
| Legacy runtime tests | 1,380 checks pass |
| Serialization tests | 902 checks pass |
| Windows export | The isolated release export loads built-in and custom Native resources; the final release DLL is 494,592 bytes |
| Native ABI | `godot-cpp` is pinned to `godot-4.4.1-stable`; one release DLL loads under Godot 4.4.1, 4.5.1, 4.6.1, and 4.7.1 |
| Legacy fallback | Complete legacy addon loads, samples, and serializes in an isolated project with no Native manifest or binary |
| Native standard set | All 12 Godot Tween transitions implemented directly in C++ |
| Native deterministic modes | Constant, Step, Power, Physics Spring, parameterized Back/Elastic/Bounce/Spring, reverse, and invert are implemented directly in C++ |
| Native Callable policy | Explicit point baking is implemented; no Native sampling path invokes a Callable |
| Native custom solver | Compiled segments, sorting, monotonic controls, Newton/binary fallback, duplicate-X handling, and locality cache implemented |
| Ownership | Isolated point-array containers, indexed topology mutation, point identity preservation, and deep runtime duplication are implemented |
| Point state | Five handle modes, locks, force-linear flags, and atomic point/curve snapshots are implemented |
| Change propagation | Point changes invalidate Native compiled state; removed points disconnect; atomic restore emits one curve-level change |
| Native resource versioning | Absent markers resolve to current v3; v2 remains loadable as the migration source, modified presets persist an explicit override marker, clean presets omit redundant geometry, and malformed/v1/future values fail closed |
| Conversion result contract | Versioned result schema records source/target backends, output resource, messages, and per-field exact/approximated/baked/unsupported outcomes |
| Native performance | All 12 standard transitions across all four ease modes beat Tween in the expanded 48-case comparison; the retained run measured approximately 1.8–4.0× faster |
| Function performance | Native deterministic function modes are approximately 62.7–104.2× faster than legacy |
| Custom performance | Native custom Bézier is approximately 42.3–134.2× faster than legacy across 2-, 9-, and 65-point workloads |
| Performance regression gate | The current isolated release gate passes all 64 relative comparisons, including extended Bounce at 1.741 ms Native versus 135.744 ms Legacy for 50,000 samples. Eight of 27 retained historical Native-only cases exceeded their combined noise envelopes; the baseline remains deliberately unpromoted pending a quiet reference-host run |
| Editor boundary | The shared boundary covers graph and Inspector point-list geometry/topology, identity-based point/property selection, cross-backend clipboard operations, deferred point and numeric parameter drag transactions—including Constant/Back geometry regeneration—lifecycle-safe row rebuilds, resource-free live publication, editable preset geometry, modified/reset state, and save normalization. The sampling hot path retains one cached analytic/compiled decision |
| Editor boundary performance | The benchmark covers ten adapter/direct cases, two signal cases, and four 65-point topology cases. The latest Native add/remove/reorder/snapshot run measured 27,847/11,110/19,026/14,509 µs versus legacy 90,130/50,271/68,427/68,070 µs; every topology gate passed its combined MAD envelope |
| Native Web export | Non-threaded debug (352,271 bytes) and release (348,383 bytes) WASM libraries build and export. A prior isolated browser run proved built-in/custom load, sample, and deep-copy behavior; the current local browser rerun is blocked by Chrome crashpad/IPC sandbox access and awaits hosted confirmation |
| Build automation | Pinned Windows/Web build jobs retain their artifacts. A Windows job downloads the release artifact and runs all 23 suites. Both Windows consumers now copy setup-Godot's resolved command to a validated temporary `.exe`; the latest hosted attempt failed in setup-Godot with an infrastructure CRC error before checkout, so corrected-job evidence remains pending |
| Manual smoke test | 2026-09-04: reported graph/list selection, live restart, stale-point, preset/function preview, and conditional-metadata issues are resolved with no further functional complaints. Persistence/no-restart behavior for the new default-handle selector still needs a visible editor restart check |
| Legacy status | Existing `EasingCurve` remains functional and comprehensively tested |

Release-runtime evidence (the retained historical cases are supplemented by the
current extended-Bounce comparison; the absolute baseline was not evaluated):

| Workload | Native | Comparator | Advantage |
|---|---:|---:|---:|
| 48 standard cases, 200,000 iterations | 5.183–8.957 ms | Tween 9.330–31.636 ms | 1.8–4.0× |
| Deterministic functions, 50,000 | 1.248–2.279 ms | Legacy 86.340–153.226 ms | 62.7–104.2× |
| Extended Bounce (6 bounces, 42.5 decay), 50,000 | 1.741 ms | Legacy 135.744 ms | 78.0× |
| Custom 2/9/65 points, 50,000 | 1.543–2.776 ms | Legacy 83.491–246.812 ms | 42.3–134.2× |
| 65-point mutation/sample, 4,000 | 30.032 ms | Legacy 325.832 ms | 10.8× |
| 65-point deep copies, 500 | 113.880 ms | Legacy 11,345.662 ms | 99.6× |

The generalized paired single-event editor characterization records Native
update-to-draw p99 at 0.985/1.206/1.244/1.716/2.113/2.977/3.654/5.661/7.468 ms
for 9/13/17/25/33/49/65/97/129 points. Neither backend crosses 16.667 ms in
that harness. The separate runtime characterization estimates roughly
219,000–297,000 Native random samples per 16.667 ms through 1,025 points; these
are linear batch estimates, not measured frame thresholds.

### Partially complete

- Point parity and shared graph/list topology coverage are complete for the MVP scope.
- Windows debug and release binaries build locally; exact hosted artifact validation remains pending.
- Web build and browser runtime are locally verified; the updated GitHub Actions job and its retained artifacts still need an actual hosted run.
- Native runtime benchmarks cover 64 cases, including every standard transition/ease pair and extended Bounce. The isolated three-run relative gate is green, but the retained absolute baseline is not stable enough to promote.
- Editor benchmarks cover adapter reads, snapshots, mutation-plus-recompile, transaction-shaped gestures, signal publication, 65-point topology, and shared-editor crossing at 9–129 points. The new default-handle preference still needs its visible restart-persistence check.
- The production Inspector and Curve Editor can display/select both resource types and edit Native point options, graph topology, point-list topology, and the ten Bézier-backed presets. Hosted live-debug and visible-editor confirmation remain.

### Missing

- Verified Windows debug artifact and editor hot-reload workflow.
- Generated Jitter/Irregular modes and CSS modes.
- Manual visible-editor restart-persistence certification for the new default-handle preference.
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
| Custom Bézier | Complete | Sampling and graph editing complete | Point-list/preset/save parity | Yes |
| Standard Tween set | Complete | Complete | Differential tests | Yes |
| Constant | Complete | Complete | Differential/manual verification | Yes |
| Power | Complete | Complete | Differential/manual verification | Yes |
| Step | Complete | Complete | Differential/manual verification | Yes |
| Back parameters | Complete | Overshoot implemented | Complete remaining metadata and edge cases | Yes |
| Elastic parameters | Complete | Amplitude/period implemented | Complete remaining metadata and edge cases | Yes |
| Bounce parameters | Complete | Count/decay implemented | Differential/manual verification | Yes |
| Spring parameters | Complete | Frequency/decay implemented | Complete remaining metadata and edge cases | Yes |
| Physics Spring | Complete | Complete | Differential/manual verification | Yes |
| Jitter/Irregular | Complete | Missing | Generated Native data | Yes |
| CSS Linear | Complete | Missing | Parser and compiled data | Yes |
| CSS Cubic Bézier | Complete | Missing | Parser and solver | Yes |
| Reverse/invert | Complete | Complete | Manual/editor verification | Yes |
| Arbitrary Callable | Live runtime support | Explicit point baking implemented | Bake UI and user acceptance | Approved replacement |
| Point geometry | Complete | Complete | Extended mutation | Yes |
| Handle modes | Complete | Five modes implemented | Complete edge-case differential tests | Yes |
| Default new-point handles | Five-mode shared editor preference | Same shared preference | Visible restart-persistence check | Yes |
| Locks/force-linear | Complete | Persisted, enforced, and exposed by shared graph controls | Complete manual verification | Yes |
| Deep runtime copy | Complete | Complete for current fields | Extend with each new field | Yes |
| Inspector | Complete | Shared graph and point list integrated with selection sync | Visible-editor live-edit verification | Yes |
| Graph editing | Complete | Add/delete/crossing/reorder and geometry integrated | Manual verification | Yes |
| Presets/preview/save | Complete | Ten Bézier presets editable; modified/reset and save normalization integrated | Visible-editor verification | Yes |
| Undo/Redo | Complete | Graph/list geometry, topology, and presets preserve exact point identity | Visible-editor verification | Yes |
| Windows | Complete | Release runtime/export proof; release DLL is the editor fallback | Debug proof and reproducible package | Yes |
| Web | Complete | Non-threaded debug/release build and isolated browser runtime verified on Godot 4.7.1 | Hosted CI run and user-facing export rerun | Yes |
| Linux/macOS/Android | Legacy available | Missing | Deferred initially | Required or explicitly excepted |
| Packaging/CI | Legacy scripts exist | Windows/Web jobs and downloaded-DLL behavior job exist; executable-copy fix added locally | Hosted green run and exact-ZIP pipeline | Full supported matrix |
| Stable field use | Established | v3 public/serialization contract and v2 migration fixture-tested | Initial release evidence | One stable release cycle |

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

Native production resources use `format_version = 3`. Version 3 records modified
preset geometry; version 2 remains a supported migration source. Conversion uses
an explicit mapping table and never relies on enum ordinal equivalence.

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
The `EditorSettings` preference
`easing_curve/curve_editor/default_new_point_handle_mode` belongs to the shared
editor, not either runtime resource. Both graph-click and point-list creation use
one editor factory that applies the validated preference before attachment.

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

**Status:** **In progress.** Windows debug/release builds, Windows release export, Godot 4.4–4.7 ABI loading, legacy-only fallback, and prior Godot 4.7.1 non-threaded Web debug/release browser runtime are verified. A Windows job downloads the release DLL and runs all 23 suites. Both Windows consumers now copy setup-Godot's resolved command to a validated temporary `.exe`, replacing the ineffective extensionless-link dereference. The latest hosted attempt failed inside setup-Godot with a CRC infrastructure error before checkout, so the corrected workflow still needs a hosted run. Current local Web exports succeed; Chrome launch remains blocked by crashpad/IPC sandbox access.

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

**Status:** **Verified.** Reflection fixtures freeze both intended public APIs. Native IDs, format version 3, indexed point APIs, atomic snapshots, adapter contracts, and the conversion-result schema are fixed. Absent, malformed, v1, v2 migration, current, and future version behavior is covered by standalone, embedded, runtime-copy, and save/load fixtures. The isolated Native-only export and legacy-without-Native fixtures prove neither runtime depends on the other.

**Goal:** Stabilize both APIs and the current Native format contract.

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

**Status:** **In progress.** Runtime coverage is expanded from 27 to 64 cases: all 12 standard transitions exercise In, Out, In-Out, and Out-In, alongside deterministic functions including extended Bounce, 2/9/65-point access patterns, mutation, and duplication. The runner creates an isolated project with no unrelated plugins or autoloads and evaluates the median of three release-library runs. The current evidence passes all 64 relative comparisons, including all 48 standard Native pairs versus Tween and every comparable Native function/custom mode versus GDScript. Extended Bounce measured 1.741 ms Native versus 135.744 ms Legacy for 50,000 samples. The retained absolute reference exceeds its noise envelope in 8 of 27 cases (`back_out`, `bounce_out`, `circ_out`, `cubic_out`, `elastic_out`, `expo_out`, `quad_out`, and `spring_out`), so the baseline remains deliberately unpromoted pending a quiet reference-host run. The editor benchmark's four 65-point topology workloads pass every combined-MAD gate. The separate 65–1,025-point runtime characterization is outside the historical baseline.

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

**Status:** **Verified.** Five handle modes, locks, force-linear state, indexed topology mutation, identity-preserving atomic state restore, serialization, deep copy, endpoint takeover, crossing, and detached-point disconnection are implemented and covered through the shared graph/list contract.

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

**Status:** **Verified.** Constant, Power, Step, Physics Spring, parameterized Back/Elastic/Bounce/Spring, and reverse/invert are implemented and differentially tested. Bounce count/decay preserve the exact standard path at their defaults and use the generalized deterministic equation otherwise. Numeric parameter slider edits—including Constant and Back geometry regeneration—preview locally and publish once on release; directly entered values publish immediately. The 64-case relative performance gate passes, including extended Bounce at approximately 78.0× the Legacy throughput.

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

**Status:** **Verified.** NATIVE-07C routes both graph and Native point-list geometry/topology through the existing backend. Native point edits use begin/finish transactions: local previews recompile during motion, while `changed` and `points_changed` publish once at commit. Each committed Native editor action also records a method on the edited Resource carrying the resource-free snapshot. The Resource is the action context, so the owning scene receives dirty history, and Godot's live debugger can replay the method in the running process without transporting `Array[Resource]`. Graph/list selection follows point identity across crossings, endpoint takeover, reorder, Undo, and Redo. Point-list reorder matches legacy by swapping x positions and translating both handles instead of shifting array entries. Native graph rendering uses backend points for pending-add and point-list previews, discards stale pending/detached preview resources, includes handles in Autofit, hides point controls in function modes, and avoids rebuilding the list for same-topology geometry edits. Automated coverage and the reported visible live-edit workflows pass.

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

**Status:** **In progress — feature-complete, certification pending.** Constant, Linear, Sine, Quad, Cubic, Quart, Quint, Expo, Circ, and Back expose canonical Bézier geometry in the shared graph/list editor. Editing preserves Transition/Ease identity, enables compiled geometry through a cached sampling-mode flag, displays modified/reset state, and persists overrides. Transition-specific metadata is conditionally visible for Constant, Back, Elastic, Bounce, Step, Power, Spring, and Physics Spring, matching the legacy Inspector policy. Numeric parameter slider motion previews locally and defers its Inspector/live-scene publication until release, including Constant and Back geometry regeneration; directly entered values publish immediately. Clean presets remain analytic and omit redundant points on save. Format v3 records modified presets while v2 standard resources retain analytic behavior and v2 Custom points remain usable. The shared **New point handles** control applies a persistent editor-only Free/Linear/Balanced/Mirrored/Linked default to both graph and list additions without touching resources or sampling. Compact Native property cells now match Legacy copy/paste and property-path behavior, including keyboard shortcuts and compatible cross-backend values. Deferred point-list completion is owned by the Inspector and resolved from curve/point identity, preventing freed-row callbacks and separating pending value edits from topology actions. Automated correctness, round-trip, normalization, relative performance, scaling, clipboard, and lifecycle coverage pass; its visible restart-persistence check, hosted CI, and a repeatable quiet-host absolute baseline remain.

**Deferred editor polish:** Native force-linear and lock state remain available in the selected-point graph toolbar. Duplicating those controls in each Native point-list row is intentionally deferred to a later feature update.

A future shared graph-zoom lock may add a control near the zoom strip. Its default locked mode would keep plain wheel input available to the Inspector; unlocked mode would allow plain-wheel graph zoom. Ctrl/Cmd+wheel over the graph and unmodified wheel input over the slider track would continue to zoom in either mode. The control and its persistence policy are deferred beyond this tranche.

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

**Status:** **In progress.** Pinned Windows/Web build jobs use the maintained Emscripten setup action and platform-specific manifest preflight and retain exact artifacts. A dependent Windows test job downloads the release DLL and runs all 23 suites. Both Windows consumers copy setup-Godot's resolved command to a validated temporary `.exe` before launching PowerShell runners. Local Windows release export passes. The corrected jobs still need hosted evidence; exact-ZIP staging, checksums, metadata, artifact installation, and clean ZIP validation remain.

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
4. Change **New point handles** through all five values. Add once from the button
   and once by graph click for each backend, then confirm the new points use the
   selected mode while existing points remain unchanged.
5. Toggle left/right force-linear and point locking.
6. Move a point and both controls, add a point, reorder or replace a point, and remove a point.
7. Run after each meaningful edit and confirm the motion changes without reopening the project.
8. Change only the new-point preference while the scene runs and confirm it does
   not restart. Restart the editor and confirm the preference persisted.
9. After removing a point, edit that detached point resource and confirm the active curve does not change.

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
| 2026-09-04 | 4.7.1 | Windows x86_64 release editor fallback | Not rerun | Not rerun | Pass for reported graph/list workflows | Pass for reported preset/live-edit workflows | Not rerun | Selection after handle-mode changes, live graph publication, stale-point cleanup, reverse/invert preview, preset reset, point-list swapping, endpoint takeover, handle-aware Autofit, and conditional metadata were manually exercised during NATIVE-07C/NATIVE-08 development with no remaining functional complaint. The new default-handle preference was added afterward and still needs its restart-persistence/no-live-restart check. |

Local browser rerun limitation (2026-09-04): both Web exports completed, but
Chrome could not start in the current sandbox because crashpad was denied
access. This is separate from the latest hosted `web-runtime` failure, which
occurred before Godot launch while resolving setup-Godot's extensionless
Windows symlink.

### Shared-editor vertical-slice record

| Date | Godot | Startup/Inspector | Standard graph | Custom selection | Point options | Undo/Redo | Persistence | Previews | Legacy regression | Timing probe | Notes/evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-03 | 4.7.1 | Pass | Pass | Pass | Pass with note | Pass | Pass | Pass | Pass | Deferred | Force Linear is editable through the shared point toolbar and persisted correctly. Its C++ property is storage-only, so absence from the raw point Inspector is intentional. Generated Native Inspector previews and the Native `Curve.svg` FileSystem class icon both passed manual verification. |

Any crash, data loss, stale result after mutation, missing class, serialization mismatch, or exported-runtime failure blocks the next release qualification step. Visual differences should be recorded with the transition/ease/parameters and a screenshot or short capture.

Interpretation:

- The shared start jitter in A does not currently implicate the Native equations. Keep it as a diagnostic item and capture per-frame elapsed time/offset before changing either solver.
- The shared editor exposes force-linear and lock operations, and automated coverage confirms Native point/control geometry, graph and point-list topology, deferred commit publication, preset override/reset behavior, save normalization, exact identity/selection restoration, and one-action gesture Undo/Redo. Reported visible live-edit and preset workflows pass; only the new preference's restart-persistence/no-live-restart check remains for NATIVE-08 certification.
- The original E failure was correctly treated as a Native Web blocker. The non-threaded wasm32 implementation now resolves that technical blocker in isolated debug and release browser fixtures without substituting the legacy API. Final visible-scene acceptance remains manual.

## 9. Recommended next execution tranche

### NATIVE-09 — Optional bidirectional conversion

**Description:** Add explicit, non-destructive conversion between Legacy and
Native curve resources. Preserve exact state where the target supports it,
clearly classify approximated, baked, and unsupported behavior, and never
silently replace the source resource.

**Implementation plan:**

1. Build conversion services around the frozen `curve_conversion_result.gd`
   schema and explicit transition/parameter mappings; keep runtime solvers
   independent.
2. Implement Legacy-to-Native conversion for standard, deterministic, Custom,
   and editable-preset curves, including point geometry, handles, locks,
   force-linear state, reverse/invert, and modified-preset identity.
3. Implement Native-to-Legacy conversion for exactly representable modes. Use
   explicit baking only where the user requests it and report fields that cannot
   be represented.
4. Add side-by-side Inspector actions with a preview/report step. Default the
   output to a new resource and require explicit confirmation before any lossy
   replacement.
5. Cover exact, approximated, baked, unsupported, canceled, saved/reloaded, and
   round-trip cases for standalone and embedded resources. Re-run the full
   23-suite, export, manifest, and relevant editor gates.

NATIVE-08 is the feature-complete MVP floor. Its remaining certification gates
continue in parallel: a visible restart-persistence/no-live-restart check for
the new preference, a hosted all-green Windows/Web run, and the quiet reference-
host historical baseline. NATIVE-01 and NATIVE-03 remain **In progress** until
the hosted and repeatable absolute evidence is green.

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

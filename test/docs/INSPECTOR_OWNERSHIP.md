# Inspector ownership follow-up

Reviewed and implemented on 2026-09-08 against `b7c4899`.

## Review and changes

The supplied follow-up identified two confirmed defects: the first graph/Points
root to exit disposed their shared context, and Native graph construction omitted
`presentation_owned`, allowing selection and right-delete gesture state into the
static per-resource caches.

Inspection also found that simply counting roots was insufficient. Native Points
called graph-node methods for edits, remove, reorder and transaction completion;
Legacy Points used the graph for Add Point and unguarded visual updates.

The context now keeps separate weak graph/Points root references. Each exit
detaches its own state. The final exit commits applied edits once, invalidates
deferred completions, releases input bindings and transaction callbacks, and
disposes the context. Points teardown leaves an active graph drag running.

Native graphs are presentation-owned. Native list selection callbacks belong to
the context, and a small resource-backend controller handles Points mutations
when its graph has detached. This controller retains no graph node; Undo retains
resource snapshots plus weak context selection restoration. The existing graph
editing path continues to handle edits while the graph exists.

Add Point's existing placement algorithm is shared through the editor backend.
Legacy visual updates tolerate a detached graph. Both surfaces can be rebuilt
while their sibling remains alive. Legacy deferred completion now checks a
request ID, and rebuilding a Native graph finishes pending list edits before
invalidating their completion requests.

Public resource APIs, serialization, transition IDs, Native metadata, defaults,
runtime sampling, and the inspector layout were not changed. No release,
version, tag, commit or publication was performed.

## Regression coverage

`test/scripts/unit/inspector_ownership_test.gd` is registered in
`test/runners/run_all_tests.ps1`, bringing the correctness manifest to 24 suites.

| Area | Executed checks |
| --- | --- |
| Different resources | Legacy/Legacy, Native/Native, Legacy/Native and Native/Legacy, editing each side after both are constructed |
| Mutations | Graph and actual list fields, list Handle Mode, graph Handle Mode, handle locks, Force Linear, reset, Add, remove and reorder; checks target changes and sibling isolation |
| Same resource | Native and Legacy sibling field synchronization, independent selection/transactions, exactly one Undo action, origin-only selection restoration |
| Teardown | Either root first, active graph drag during Points exit, pending text edits with/without queued completion, both roots in one frame, sibling destruction during an edit |
| Rebuild | Graph rebuilt with Points surviving; Points rebuilt with graph surviving; editing both replacements |
| Clipboard | Resource mismatch, removed point, actual identity/index change, captured menu paste in rendered mode, sibling isolation |
| Lifetime | Origin graph/context released while Undo history survives; Undo/Redo still changes the resource; deferred callbacks after disposal |
| Real inspectors | One registered Inspector plugin parsing two EditorInspectors; all four backend orders and both same-resource combinations; mouse/key events type into fields before and after a sibling preset rebuild |

The headless fixture substitutes only FoldableContainer section chrome because
Godot 4.7 cannot construct it under that display server. Graphs, point fields,
signals, resource backends and EditorUndoRedoManager are real. Rendered execution
uses the normal sections, real EditorInspectors, and viewport mouse/key delivery.
This is not a claim about physical OS input, every theme/DPI, or scene-tab history
routing.

## Execution evidence

Engine: `4.7.1.stable.official.a13da4feb`, selected by
`EASING_CURVE_GODOT_PATH`. All process logs and isolated copies are under
`test/_temp/`; every direct launch supplied `--log-file` there. Isolated copies
avoid the Native DLL lock held by an already-open editor.

- Before changes: all existing **23 suites passed**.
- Regression proof against the original implementation: **12 of 70 focused
  checks failed**, including first-root disposal, surviving controls, missing Undo
  actions after partial teardown, and inherited Native selection.
- Final correctness runner: **all 24 suites passed**, including **326 ownership
  checks** in the headless editor host.
- Final rendered suite: **362 checks passed**, with no GDScript errors or
  ownership assertion failures. A mixed Native/Legacy screenshot was inspected.
- The rendered baseline and changed code both emitted Godot's `current_window`
  diagnostic and graphics allocation/texture leak diagnostics during the
  standalone editor test lifecycle. Counts vary between runs. The Windows root
  certificate-store diagnostic also occurs in the baseline. These are retained
  in the logs, not represented as a clean editor diagnostic run or silently added
  to the correctness runner's allowlist.

Local evidence:

- `test/_temp/ownership-baseline.txt`
- `test/_temp/ownership-regression-baseline.txt`
- `test/_temp/ownership-validation-final.txt`
- `test/_temp/ownership-rendered-baseline.txt`
- `test/_temp/ownership-rendered-final.txt`
- `test/_temp/ownership-project/test/_temp/ownership-mixed.png`

Run the indexed headless coverage from the repository root:

```powershell
./test/runners/run_all_tests.ps1 --run
```

For rendered coverage, use a separate project copy if the editor already holds
the Native DLL. Pass that copy's absolute path as `--path`, omit `--headless`,
and run `res://test/scripts/unit/inspector_ownership_test.gd` with `--editor` and
an absolute repository-local `--log-file`. The suite captures its mixed-inspector
image under that copy's `test/_temp/`. Passing `--rendered-only` after Godot's `--`
runs just the real-Inspector input matrix; it does not replace the full suite.

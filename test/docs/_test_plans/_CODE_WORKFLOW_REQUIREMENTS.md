# CODE WORKFLOW REQUIREMENTS

## PURPOSE

This document defines the required workflow for planning, executing, validating,
and documenting release-oriented code work.

It replaces the separate responsibilities previously described by
`_CODE_PLAN_REQUIREMENTS.md` and `_CODE_REPORT_REQUIREMENTS.md`.

The workflow is designed around two generated document types:

1. this shared requirements document; and
2. one release code tracker per release, for example:
   `v1.0.9_CODE_TRACKER.md`.

Do not create separate release `CODE_PLAN` / `CODE_REPORT` pairs or separate
feature `CODE_PLAN` / `CODE_REPORT` pairs unless the user explicitly requests
that older format.

A release code tracker must contain both:

- a frozen planning/specification portion; and
- a mutable execution/progress portion.

The distinction between planning authority and execution history is important,
but it does not require separate files.


## CORE WORKFLOW PRINCIPLES

The workflow must preserve the following principles:

- Release goals come from the user. Do not invent release goals.
- Confirm the user's release goals before generating the initial release
  tracker.
- If no release goals have been supplied, state that rather than inventing a
  release plan.
- The approved release charter becomes the scope authority for the release.
- Each implementation item receives a stable Plan ID.
- Work is executed incrementally, one approved step at a time.
- Production code must not be changed before the corresponding execution step
  is approved.
- Use focused validation during development rather than running the complete
  release suite after every small sub-step.
- Run the complete release-gating suite at the closeout points required by this
  document.
- Preserve important failed-attempt, regression, diagnostic, and design-history
  information when it helps explain the final implementation.
- Distinguish production defects from test-fixture, tooling, hot-reload,
  environment, and known non-blocking diagnostics.
- Do not silently expand the scope of an approved work item.
- Do not automatically begin another work item after completing the requested
  item.


## DOCUMENT MODEL

### Requirements document

The shared requirements document is:

`test/docs/_test_plans/_CODE_WORKFLOW_REQUIREMENTS.md`

It defines the workflow and common validation rules. Generated release trackers
should reference these requirements rather than repeating procedural boilerplate.

### Release code tracker

Each release should normally have exactly one active tracker:

`test/docs/_test_plans/vX.Y.Z_CODE_TRACKER.md`

The tracker serves as both:

- the authoritative release plan/specification; and
- the execution progress/history document.

When the release is complete, archive the tracker with the rest of the release
records according to the project's archive convention.

### Do not create per-feature companion documents

Feature, cleanup, test, metadata, Undo/Redo, and other work items belong inside
the release tracker under stable Plan IDs.

For example, do not create:

- `AXIS_DRAG_01_CODE_PLAN.md`;
- `AXIS_DRAG_01_CODE_REPORT.md`.

Instead, create an `AXIS-DRAG-01` work-item section in the release tracker.

A separate document is only justified when the user explicitly requests it or
when a work item is genuinely independent of any release tracker.


## MUTABILITY MODEL

The tracker must clearly distinguish frozen planning information from mutable
execution information.

Recommended model:

| Section | Mutability |
| --- | --- |
| Release Charter | FROZEN after user approval |
| Work-item Specification | FROZEN once execution begins |
| Work-item Execution Plan | FROZEN once approved |
| Execution Dashboard | MUTABLE |
| Step Execution Results | APPEND / UPDATE |
| Plan Amendments | APPEND ONLY |
| Diagnostics / Follow-ups | APPEND / UPDATE |
| Release Closeout | MUTABLE until release completion |
| Current Handoff | MUTABLE |

Do not silently rewrite frozen scope, design decisions, non-goals, preservation
constraints, or acceptance criteria after execution has started.

If an approved plan must change, record the change in the Plan Amendments
section and preserve the original decision.


## REQUIRED TRACKER STRUCTURE

A release tracker should follow this general structure:

1. Release Charter [FROZEN]
   1.1. User-confirmed release goals
   1.2. Explicit non-goals
   1.3. Baseline audit
   1.4. Preservation / compatibility constraints
   1.5. Baseline code-smells / maintenance audit
   1.6. Planned execution order
   1.7. Release acceptance criteria
2. Execution Dashboard [MUTABLE]
3. Work Items [MUTABLE execution; frozen specifications]
4. Plan Amendments [APPEND ONLY]
5. Project Diagnostics / Follow-ups
6. Release Closeout
7. Current Handoff

The exact heading numbering can vary when needed, but the responsibilities above
must remain clear and easy for both humans and AI agents to parse.


## FRONTMATTER

Use YAML frontmatter for generated release trackers.

Recommended fields:

```yaml
---
document: vX.Y.Z_CODE_TRACKER.md
project: <project name>
release: X.Y.Z-dev
document_type: release-code-tracker
requirements: test/docs/_test_plans/_CODE_WORKFLOW_REQUIREMENTS.md
plan_status: draft | frozen | amended
execution_status: not_started | in_progress | blocked | complete
baseline_commit: <commit hash>
current_item: <Plan ID or none>
current_step: <step number or none>
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
---
```

Use repository-relative paths in frontmatter and document references.
Avoid unnecessary cross-document references.


## RELEASE CHARTER

### User-confirmed release goals

The release goals section is a high-level overview of goals explicitly supplied
or confirmed by the user.

Do not invent or add release goals merely because an audit identifies useful
maintenance work.

Audit findings that are not approved release goals can be recorded as deferred
or optional work items.

### Explicit non-goals

Record important work that must not be bundled into the release or into a
specific feature.

Non-goals are especially useful for preventing adjacent refactors from being
silently folded into feature work.

### Baseline audit

Perform a baseline audit when generating the release tracker.

At minimum record:

- current branch;
- latest commit hash;
- repository/worktree state;
- current development/plugin/application version where applicable;
- relevant engine/runtime/tool version;
- authoritative automated test command;
- automated baseline result;
- known baseline diagnostics or test limitations.

### Automated test baseline

Run the current authoritative automated suite unless the user explicitly asks
not to or the environment prevents it.

For the initial release baseline, include a concise table of registered suites,
execution mode where relevant, and PASS/FAIL result.

Record anomalies observed during the run.

Assess whether existing coverage is adequate for the planned release work and
identify material coverage gaps.

### Baseline refreshes during execution

Do not reproduce the complete suite table for every work item.

When refreshing the baseline before a later work item, normally record only:

- current commit;
- full-suite summary, such as `17/17 PASS`;
- changes since the release baseline;
- new or changed diagnostics;
- newly discovered coverage gaps.

Repeat the detailed per-suite table only when it materially changed or is needed
to explain a failure.

### Preservation / compatibility constraints

Record what must be preserved during the release.

Examples include:

- serialized data formats;
- enum numeric values;
- public classes, methods, properties, signals, constants, and signatures;
- Resource identity and ordering;
- notification behavior;
- Undo/Redo transaction boundaries;
- editor interaction behavior;
- test execution semantics;
- compatibility with previously supported engine/runtime versions.

Constraints should be concrete enough to guide regression testing.


## BASELINE CODE-SMELLS / MAINTENANCE AUDIT

Perform a comprehensive code-smells audit once at the release baseline when the
user requests a refactor/maintenance review or when maintenance planning is part
of the release goals.

Use the Refactoring.Guru code-smell catalog as a baseline taxonomy:

https://refactoring.guru/refactoring/smells

A catalog label alone is not sufficient evidence. Each actionable finding should
identify concrete repository evidence and practical risk/payoff.

### Finding IDs

Every actionable finding must receive a stable Plan ID, for example:

- `TEST-01`;
- `CLEANUP-01`;
- `METADATA-01`;
- `EDITOR-01`;
- `UNDO-01`.

Plan IDs must remain stable for the rest of the release.

Prefer uppercase IDs with hyphen separators.

Do not switch between variants such as `AXIS_DRAG_01`, `AXIS-DRAG-01`, and
`Axis-constrained dragging` once an ID has been assigned.

### Findings table

Provide an ordered findings table including at least:

- Plan ID;
- priority;
- finding summary;
- recommended disposition.

For actionable findings, provide enough detail to identify:

- affected files/components;
- smell/category;
- concrete evidence;
- why it matters;
- recommended improvement;
- expected payoff;
- rough effort/risk;
- tests/behavior to protect;
- dependencies or sequencing constraints.

Do not provide exact production code diffs in the baseline audit.

### Leave-alone findings

When an area appears structurally large or duplicated but should intentionally
remain unchanged, record that decision when it is important enough to prevent
future agents from repeatedly reopening it.

Explain the compatibility or architectural reason for leaving it alone.

### Feature-local review

Do not repeat the comprehensive repository-wide code-smells audit for each
feature/work item.

Before executing a work item, perform only a targeted architecture/risk review
for the code boundary being changed.

Feature-local findings may receive IDs when useful, for example:

- `AXIS-TEST-01`;
- `AXIS-STATE-01`.

Reference existing release findings rather than restating them in full.


## WORK ITEMS

Every implementation unit should be represented as a work item under a stable
Plan ID.

A work item can represent:

- a new feature;
- cleanup/refactoring;
- test infrastructure;
- metadata/configuration;
- bug fix;
- documentation directly tied to release engineering;
- validation or compatibility work.

### Work-item specification

Before implementation begins, the work item should contain a specification with
at least:

- Plan ID and title;
- status;
- objective;
- scope;
- explicit non-goals where useful;
- related architecture assessment;
- design decisions that must be settled before implementation;
- relevant release constraints/findings;
- validation / acceptance requirements;
- dependencies.

The work-item specification becomes frozen once execution begins.

### Exact code diffs do not belong in the work-item specification

The frozen specification describes what needs to be achieved and the important
constraints.

Do not place exact production diffs in the specification.

Exact proposed diffs belong in the step approval packet immediately before that
step is executed.


## EXECUTION DASHBOARD

The tracker must contain one authoritative execution summary table.

Recommended columns:

| Plan ID | Status | Current Step | Result / Summary | Commit |
| --- | --- | --- | --- | --- |

Recommended status vocabulary:

- `NOT STARTED`;
- `PLANNING`;
- `IN PROGRESS`;
- `PARTIAL`;
- `BLOCKED`;
- `CONDITIONAL`;
- `DEFERRED`;
- `NOT REQUIRED`;
- `COMPLETE`.

Avoid creating multiple later sections that restate the same completed/current
status in different words.

Detailed execution information should live under the corresponding work item.
The dashboard should link readers to that detail rather than duplicate it.

Also keep a compact current-state block near the dashboard containing:

- current Plan ID;
- current step;
- next approval gate;
- blocking issues;
- known non-blocking diagnostics.


## FORMAL EXECUTION PLAN

Before executing a work item, generate a formal execution plan inside that work
item.

The formal execution plan is a high-level ordered list of implementation steps.

Example:

```text
METADATA-01 Step 1 of 8 — Establish the zoom metadata contract
METADATA-01 Step 2 of 8 — Centralize EasingCurveEditor
METADATA-01 Step 3 of 8 — Centralize EasingCurveZoomSliderContainer
...
METADATA-01 Step 7 of 8 — Focused integration validation
METADATA-01 Step 8 of 8 — Release-gate closeout
```

Each step outline should identify:

- objective;
- expected files/components;
- high-level work;
- targeted validation;
- dependencies or special constraints.

The formal execution plan should not contain exact code diffs.

The user must review the formal execution plan before implementation begins.

Once approved, treat the execution-plan structure as frozen. If a materially
new step is required, record the change through the Plan Amendments process.


## STEP APPROVAL PACKET

Each execution step is a separate approval gate.

Immediately before executing a step, present to the user:

1. the exact files expected to change;
2. the exact proposed code diff or precise production edit for that step;
3. the targeted automated/manual validation to be run;
4. any newly discovered scope, dependency, risk, or deviation.

Do not modify production code until the user approves the step.

Test-only characterization steps also require approval when they are part of the
formal execution workflow, unless the user explicitly authorizes a broader batch.

After completing a step:

- record the result in the tracker;
- do not automatically execute the next step;
- present the next step for approval when appropriate.


## EXECUTION STEP SCOPE

Execution steps should be small and targeted.

Prefer independently reviewable slices that modify the minimum necessary files.

Do not combine unrelated cleanup, public API changes, serialization changes,
notification changes, or Undo/Redo framework changes into a feature step merely
because the same files are already being edited.

When a potential adjacent refactor is discovered:

- use an existing Plan ID if one already exists;
- otherwise record it as a new deferred/optional finding;
- do not silently include it in the active step.


## VALIDATION STRATEGY

### Focused validation during development

Use the most relevant focused automated tests after each implementation step.

Do not run the complete release suite after every sub-step unless:

- the step has broad cross-cutting risk;
- a regression indicates wider impact;
- the user requests it;
- the work-item plan explicitly requires it.

For production-code steps, normally also run:

- `git diff --check` or the repository-equivalent whitespace/diff integrity
  check;
- final diff inspection for the files changed by the step.

### Characterization before risky behavior changes

When changing behavior that is insufficiently covered, prefer adding focused
characterization at or before the change boundary.

Do not weaken existing tests merely to accommodate the implementation.

### Manual validation

Record manual/visible-editor validation when behavior cannot be reliably covered
by automation, including layout, focus, visual rendering, drag feel, and other
interactive behavior.

If tooling cannot perform a required manual interaction, state that clearly and
identify what remains for the user to verify.

### Work-item closeout

A work item that changes production behavior should normally close with:

- focused automated validation passing;
- `git diff --check` passing;
- final Git status/diff scope review;
- the authoritative full registered test suite passing;
- applicable manual validation passing or explicitly recording an approved
  outstanding issue;
- compatibility/serialization checks when the work item affects those areas;
- tracker execution log updated;
- commit/hash information recorded.

Do not duplicate the standard closeout boilerplate inside every work-item
specification. Work items should list only additional validation specific to that
item.

### Release closeout

Before the release is considered complete, perform the release acceptance gates
recorded in the Release Charter.

These commonly include:

- authoritative full suite passing;
- `git diff --check` passing;
- complete manual/visible-editor smoke where applicable;
- compatibility testing on claimed engine/runtime versions;
- serialization/resource inspection when relevant;
- package/export contents inspection;
- final Git status/diff review;
- final version/release metadata verification.


## TEST RESULT RECORDING

Record meaningful test results, including:

- test/suite name;
- PASS/FAIL;
- check count where available;
- process/runner exit result where relevant;
- material diagnostics.

Avoid repeatedly reproducing unchanged detailed suite tables.

When a full authoritative runner has strong pass criteria, document those
criteria once and then a later closeout may state the runner result concisely,
for example:

`17/17 registered suites PASS; runner exit 0; no timeout; no SCRIPT ERROR.`


## DIAGNOSTICS AND FOLLOW-UPS

Use stable IDs for recurring diagnostics when they are likely to be referenced
more than once.

Examples:

- `DIAG-01` — serialization temporary-directory/editor scan race;
- `DIAG-02` — known live-editor hot-reload error.

Each diagnostic should record:

- ID and title;
- classification;
- first observed context/date when useful;
- affected validation/work item;
- whether it is blocking;
- current action/disposition.

Once documented, later steps should reference the diagnostic ID instead of
repeating the full explanation unless its behavior changes.

Suggested classifications include:

- production defect;
- fixed execution regression;
- test-fixture defect;
- tooling artifact;
- hot-reload artifact;
- environment diagnostic;
- expected test behavior;
- known non-blocking limitation;
- deferred follow-up.

Do not erase useful failed-attempt information when it explains why the final
implementation or test differs from the original attempt.


## PLAN AMENDMENTS

Frozen planning information may change only through an explicit amendment.

The Plan Amendments section should be append-only.

Recommended table:

| Amendment ID | Date | Plan ID | Change | Reason | Approval |
| --- | --- | --- | --- | --- | --- |

Use amendment IDs such as `AMD-01`, `AMD-02`, etc.

An amendment should preserve enough information to understand:

- the original decision;
- what changed;
- why it changed;
- who/what approval authorized it.

Minor bookkeeping corrections, typo fixes, updated status fields, test counts,
and commit hashes do not require amendments when they do not alter frozen scope
or acceptance criteria.


## EXECUTION LOGGING

After each approved step, update the work item's execution log with:

- step status;
- approval state;
- exact files changed;
- concise implementation record;
- targeted validation results;
- manual/visible-editor result when applicable;
- diagnostics and classification;
- `git diff --check` / scope result where applicable;
- deviations from plan and corresponding amendment/approval;
- commit/hash information when committed;
- next approval gate.

Do not paste large unchanged code blocks into the execution history when a
concise description plus file/commit reference is sufficient.

Preserve exact code details when they are important to future debugging or
explain a regression/fix.


## GIT / COMMIT RECORDING

Record relevant commit hashes for completed steps or bounded work-item closeout.

When an intentionally empty marker commit is used, explicitly state that the
commit is a marker and identify where the actual production changelist landed.

Do not infer that a commit contains a production change merely because its name
matches the Plan ID.

At closeout, verify the final diff/status contains only approved work-item and
tracker changes.


## CURRENT HANDOFF

The final section of the active tracker must provide a compact handoff for the
next human or AI agent.

It should state only the current authoritative state, not re-summarize every
completed detail.

Recommended fields:

- completed Plan IDs;
- current Plan ID;
- current step;
- next approval gate;
- blocked by;
- known relevant diagnostics;
- deferred/conditional work;
- important `do not reopen` decisions;
- next release-gate action if applicable.

Detailed history remains under the work-item execution logs.


## AGENT CONTINUATION RULES

An AI agent continuing an existing release should:

1. Read `_CODE_WORKFLOW_REQUIREMENTS.md`.
2. Read the active release tracker.
3. Use the Execution Dashboard and Current Handoff to determine current state.
4. Read the active work-item specification and execution plan before proposing
   changes.
5. Treat completed items as closed unless a demonstrated regression requires
   reopening them.
6. Preserve the release compatibility constraints and explicit non-goals.
7. Work on exactly the requested/current approved step.
8. Present the step approval packet before modifying production code.
9. Use focused tests during development and the full suite at required closeout
   gates.
10. Record exact changed files, validation, diagnostics, and commits.
11. Stop after the approved/requested slice rather than automatically beginning
    the next item.


## RELEASE TRACKER CREATION RULES

When the user asks to generate a tracker for a new release:

1. Gather and confirm the user's release goals.
2. If goals are missing, do not invent them; state that the release goals are
   required before the tracker can be finalized.
3. Audit the current repository baseline.
4. Run the authoritative test baseline unless explicitly prohibited or
   unavailable.
5. Assess current test coverage.
6. Record preservation/compatibility constraints.
7. Perform the comprehensive release-level code-smells audit when appropriate.
8. Assign stable Plan IDs.
9. Recommend execution order.
10. Record release acceptance criteria.
11. Create the Execution Dashboard with all known work items initially
    classified.
12. Do not implement production code merely because the tracker was generated.


## REQUESTS TO PLAN A WORK ITEM

When the user asks to plan a specific Plan ID:

- do not modify production code;
- update/create that work item's frozen specification as needed;
- perform a targeted architecture/risk assessment rather than repeating the
  release-wide audit;
- refresh the baseline concisely if necessary;
- generate the formal high-level execution steps;
- list focused validation expectations;
- present the execution plan for user review;
- do not provide or apply exact code diffs until presenting an individual step
  for approval.


## REQUESTS TO EXECUTE A WORK ITEM OR STEP

When the user asks to execute a work item that has no approved formal execution
plan, create/present the execution plan first.

When the user asks to execute an already-planned step:

- inspect the current code/state relevant to that step;
- present the Step Approval Packet;
- wait for approval before modifying production code unless the user has already
  explicitly approved that exact step/diff;
- after execution, run the approved targeted validation;
- update the tracker;
- stop before the next step unless separately approved.


## SUMMARY OF AUTHORITATIVE SOURCES

For an active release, authority should be simple:

```text
_CODE_WORKFLOW_REQUIREMENTS.md
    -> defines HOW release code work is planned/executed/documented

vX.Y.Z_CODE_TRACKER.md
    -> defines WHAT this release contains and records WHAT HAS HAPPENED
```

Within the tracker:

```text
Release Charter
    -> release scope / constraints / acceptance authority

Work-item Specification
    -> individual Plan ID scope / design / acceptance authority

Formal Execution Plan
    -> approved ordered implementation steps

Step Execution Results
    -> mutable implementation history

Plan Amendments
    -> only valid mechanism for changing frozen scope/design

Execution Dashboard + Current Handoff
    -> current state authority
```

Do not create parallel documents that duplicate these responsibilities without
an explicit user request.

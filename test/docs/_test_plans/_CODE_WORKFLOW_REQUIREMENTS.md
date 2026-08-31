# CODE WORKFLOW REQUIREMENTS

## PURPOSE

This document defines the required workflow for planning, executing, validating,
and documenting release-oriented code work.

It replaces the separate responsibilities previously described by
`_CODE_PLAN_REQUIREMENTS.md` and `_CODE_REPORT_REQUIREMENTS.md`.

The normal document model is:

1. this shared workflow requirements document; and
2. one release code tracker per release, for example:
   `v1.0.9_CODE_TRACKER.md`.

Do not create separate release `CODE_PLAN` / `CODE_REPORT` pairs or separate
feature `CODE_PLAN` / `CODE_REPORT` pairs unless the user explicitly requests
that older format.

A release code tracker contains both:

- frozen planning/specification sections; and
- mutable execution/progress sections.

The planning/execution distinction remains authoritative even though both live
in one file.


## CORE PRINCIPLES

- Release goals come from the user. Do not invent release goals.
- Confirm the user's current-release goals before generating the tracker.
- If the user also supplies future-release goals, preserve them in the tracker
  as an explicitly non-current roadmap rather than discarding them or silently
  promoting them into the active release.
- If no release goals are supplied, state that instead of inventing a plan.
- The approved Release Charter is the scope authority for the active release.
- Each active implementation item receives a stable Plan ID.
- Work is executed incrementally, one approved step at a time.
- Production code must not be changed before the corresponding execution step
  is approved.
- Use focused validation during development rather than running the complete
  release suite after every small sub-step.
- Run the complete release-gating suite at the closeout points required here.
- Preserve useful failed-attempt, regression, diagnostic, and design-history
  information when it explains the final implementation.
- Distinguish production defects from test-fixture, tooling, hot-reload,
  environment, and known non-blocking diagnostics.
- Do not silently expand an approved work item.
- Do not automatically begin another work item after completing the requested
  item.


## DOCUMENT MODEL

### Requirements document

Authoritative workflow file:

`test/docs/_test_plans/_CODE_WORKFLOW_REQUIREMENTS.md`

Generated trackers should reference this document rather than repeat generic
workflow boilerplate.

### Release code tracker

Each active release should normally have exactly one tracker:

`test/docs/_test_plans/vX.Y.Z_CODE_TRACKER.md`

The tracker is both:

- the authoritative release plan/specification; and
- the execution progress/history record.

When the release is complete, archive the tracker according to the project's
release archive convention.

### No per-feature companion documents by default

Feature, cleanup, test, metadata, Undo/Redo, performance, and other work items
belong inside the release tracker under stable Plan IDs.

Do not normally create files such as:

- `AXIS_DRAG_01_CODE_PLAN.md`;
- `AXIS_DRAG_01_CODE_REPORT.md`.

Create an `AXIS-DRAG-01` work-item section in the release tracker instead.

A separate document is justified only when the user explicitly requests it or
when the work is genuinely independent of an active release tracker.


## MUTABILITY MODEL

The tracker must clearly distinguish frozen planning information from mutable
execution information.

| Section | Mutability |
| --- | --- |
| Release Charter | FROZEN after user approval |
| Future Release Roadmap | FROZEN as a record of supplied goals; amend when user changes it |
| Work-item Specification | FROZEN once execution begins |
| Work-item Execution Plan | FROZEN once approved |
| Execution Dashboard | MUTABLE |
| Step Execution Results | APPEND / UPDATE |
| Plan Amendments | APPEND ONLY |
| Diagnostics / Follow-ups | APPEND / UPDATE |
| Release Closeout | MUTABLE until release completion |
| Current Handoff | MUTABLE |

Do not silently rewrite frozen scope, design decisions, non-goals, preservation
constraints, acceptance criteria, or user-supplied roadmap decisions after work
has begun.

If a frozen decision changes, record the change in Plan Amendments and preserve
the original decision/history.


## REQUIRED TRACKER STRUCTURE

A release tracker should contain:

1. Release Charter [FROZEN]
   - user-confirmed current-release goals;
   - explicit non-goals;
   - baseline audit;
   - preservation / compatibility constraints;
   - planned execution order;
   - release acceptance criteria.
2. Future Release Roadmap [when supplied by the user]
3. Execution Dashboard [MUTABLE]
4. Work Items [mutable execution; frozen specifications]
5. Plan Amendments [APPEND ONLY]
6. Project Diagnostics / Follow-ups
7. Release Closeout
8. Current Handoff

The exact heading numbering may vary, but these responsibilities must remain
clear and easy for humans and AI agents to parse.


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
baseline_commit: <commit hash or pending>
current_item: <Plan ID or none>
current_step: <step number or none>
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
---
```

Use repository-relative paths in document references.
Avoid unnecessary cross-document references.


# RELEASE CHARTER

## User-confirmed current-release goals

Record a concise high-level list of goals explicitly supplied or confirmed by
the user.

Do not add an implementation or maintenance item merely because an audit finds
it useful. Audit findings not approved for the active release remain optional,
conditional, or deferred.

## Explicit non-goals

Record important work that must not be bundled into the active release or work
item.

This is particularly important when the user has already assigned adjacent
features to a future release.

## Baseline audit

Before implementation, record as much of the current baseline as the available
tooling can establish without modifying production code:

- branch;
- latest commit hash;
- repository/worktree state when available;
- current development/plugin/application version;
- relevant engine/runtime/tool version;
- authoritative automated test command/runner;
- registered suite inventory or count;
- fresh automated baseline result when executable;
- known baseline diagnostics or limitations.

If a baseline fact cannot be established with the available tools, mark it
`PENDING` or `UNAVAILABLE` and state why. Do not fabricate a value or substitute
a non-authoritative test command merely because it is easier to invoke.

## Automated test baseline

Run the current authoritative automated suite unless:

- the user explicitly asks not to;
- the current task explicitly stops before that stage; or
- the available environment cannot execute the authoritative runner.

For the initial release baseline, include a concise suite/mode/result table when
a fresh run is performed.

If a fresh run is not possible, identify the authoritative runner and make the
fresh baseline an explicit pending gate before production implementation.

Assess test-coverage adequacy during the release audit rather than assuming the
existing suite is sufficient.

## Baseline refreshes

Do not reproduce the complete suite table for every work item.

A later baseline refresh normally records only:

- current commit;
- full-suite summary;
- changes since the release baseline;
- changed diagnostics;
- newly discovered coverage gaps.

Repeat the detailed table only when materially changed or needed to explain a
failure.

## Preservation / compatibility constraints

Record what must be preserved during the release, including relevant:

- serialized formats and saved resources;
- enum numeric values;
- public classes, methods, properties, signals, constants, and signatures;
- Resource identity and ordering;
- notification behavior;
- Undo/Redo transaction boundaries;
- editor interaction behavior;
- test execution semantics;
- compatibility with supported engine/runtime versions.

Make constraints concrete enough to guide regression testing.


# FUTURE RELEASE ROADMAP

When the user supplies future-release goals or explicitly defers features to a
later version, include a dedicated Future Release Roadmap in the current
tracker.

The roadmap exists to preserve intentional release boundaries and design
context. It is not active-release authorization.

For each future item, record when provided or already agreed:

- target future release/version or `TBD`;
- stable roadmap/work-item ID when useful;
- user-stated goal;
- why it is deferred or separated from the active release;
- major architectural direction already agreed;
- dependencies on active-release work or other future items;
- important open design questions.

Rules:

- Do not promote a roadmap item into the active Execution Dashboard without
  explicit user approval.
- Do not implement roadmap items as opportunistic extras during current-release
  work.
- Do not over-specify a future implementation beyond decisions the user has
  supplied or approved.
- Preserve architectural conclusions already accepted by the user when they are
  important to avoiding future rework.
- If a later user decision changes the roadmap, update it through a Plan
  Amendment or clearly dated roadmap revision rather than silently erasing the
  prior boundary.
- Current work may deliberately reserve input space, APIs, or architecture for
  a future feature, but such reservation must not implement the future feature
  itself unless separately approved.


# RELEASE-LEVEL CODE-SMELLS / MAINTENANCE AUDIT

Perform a comprehensive release-level code-smells/architecture audit when the
user requests one or when maintenance review is an explicit release goal.

Use the Refactoring.Guru catalog as a baseline taxonomy when applicable:

https://refactoring.guru/refactoring/smells

A label alone is not evidence. Actionable findings must identify concrete code
and practical risk/payoff.

When performance review is part of the goal, also inspect likely bottlenecks and
avoidable work in relevant hot paths. Distinguish measured/observable concerns
from speculative micro-optimization.

When bug discovery is part of the goal, record concrete suspected defects
separately from architecture/refactor opportunities.

## Finding IDs

Every actionable active-release finding receives a stable Plan ID, for example:

- `TEST-01`;
- `CLEANUP-01`;
- `METADATA-01`;
- `EDITOR-01`;
- `PERF-01`;
- `BUG-01`.

Once assigned, keep the ID stable for the release.
Prefer uppercase hyphen-separated IDs.

## Findings table

Provide an ordered findings table including at least:

- Plan ID;
- priority;
- summary;
- recommended disposition.

For actionable findings, document enough to identify:

- affected files/components;
- smell/category;
- concrete evidence;
- why it matters;
- recommended improvement;
- expected payoff;
- rough effort/risk;
- tests/behavior to protect;
- dependencies/sequencing constraints.

Do not provide exact production diffs in the baseline audit.

## Leave-alone decisions

When structurally large or duplicated code should intentionally remain
unchanged, record that decision when useful to stop future agents repeatedly
reopening it.

## Feature-local reviews

Do not repeat the comprehensive repository-wide audit for every feature.
Before executing a work item, perform only a targeted architecture/risk review
for that boundary and reference existing release findings rather than restating
them.


# WORK ITEMS

Every active implementation unit is represented under a stable Plan ID.

A work item may represent:

- a new feature;
- cleanup/refactoring;
- performance work;
- test infrastructure;
- metadata/configuration;
- bug fix;
- release-engineering documentation;
- compatibility/validation work.

## Work-item specification

Before implementation begins, include:

- Plan ID and title;
- status;
- objective;
- scope;
- explicit non-goals where useful;
- architecture/risk assessment;
- design decisions that must be settled before implementation;
- relevant release constraints/findings;
- validation / acceptance requirements;
- dependencies.

The specification becomes frozen once execution begins.

Exact production diffs do not belong in the work-item specification. They
belong in the per-step approval packet.


# EXECUTION DASHBOARD

Keep one authoritative execution summary table.

Recommended columns:

| Plan ID | Status | Current Step | Result / Summary | Commit |
| --- | --- | --- | --- | --- |

Recommended statuses:

- `NOT STARTED`;
- `PLANNING`;
- `IN PROGRESS`;
- `PARTIAL`;
- `BLOCKED`;
- `CONDITIONAL`;
- `DEFERRED`;
- `NOT REQUIRED`;
- `COMPLETE`.

Do not create later sections that redefine the same status in different words.
Detailed history belongs under each work item.

Keep a compact current-state block near the dashboard:

- current Plan ID;
- current step;
- next approval gate;
- blocking issues;
- known non-blocking diagnostics.

Future-roadmap items do not belong in this active Execution Dashboard unless the
user explicitly promotes them into the current release.


# FORMAL EXECUTION PLAN

Before executing a work item, generate an ordered high-level execution plan
inside that work item.

Example:

```text
FEATURE-01 Step 1 of 6 — Characterize current behavior
FEATURE-01 Step 2 of 6 — Implement bounded domain change
FEATURE-01 Step 3 of 6 — Integrate editor UI
...
FEATURE-01 Step 6 of 6 — Closeout
```

Each step outline should identify:

- objective;
- expected files/components;
- high-level work;
- targeted validation;
- dependencies/special constraints.

Do not include exact code diffs in the formal execution plan.
The user reviews the plan before implementation begins.

Once approved, treat the execution-plan structure as frozen. Materially new
steps require a Plan Amendment.


# STEP APPROVAL PACKET

Each execution step is a separate approval gate.

Immediately before a step, present:

1. exact files expected to change;
2. exact proposed code diff or precise production edit;
3. targeted automated/manual validation;
4. newly discovered scope, dependency, risk, or deviation.

Do not modify production code until the user approves the step, unless the user
has already explicitly approved that exact step/diff or a broader batch.

After the step:

- record the result in the tracker;
- do not automatically execute the next step;
- present the next step for approval when appropriate.


# EXECUTION STEP SCOPE

Prefer small, independently reviewable slices that modify the minimum necessary
files.

Do not combine unrelated cleanup, public API changes, serialization changes,
notification changes, or Undo/Redo framework changes into a feature step merely
because the same files are already open.

When adjacent refactor work is discovered:

- use an existing Plan ID if one exists;
- otherwise record a new optional/deferred finding;
- do not silently include it in the active step.

Future-roadmap features are especially strict non-goals for current-release
implementation unless explicitly promoted.


# VALIDATION STRATEGY

## Focused validation during development

Use the most relevant focused automated tests after each implementation step.
Do not run the complete release suite after every sub-step unless:

- the step has broad cross-cutting risk;
- a regression indicates wider impact;
- the user requests it;
- the work-item plan explicitly requires it.

For production-code steps, normally also run:

- `git diff --check` or repository equivalent;
- final diff inspection for the files changed by the step.

## Characterization before risky changes

When behavior is insufficiently covered, add focused characterization at or
before the change boundary.
Do not weaken existing tests merely to accommodate an implementation.

## Manual validation

Record manual/visible-editor validation when automation cannot reliably cover
layout, focus, rendering, drag feel, or other interactive behavior.

If tooling cannot perform the required interaction, state exactly what remains
for the user to verify.

## Work-item closeout

A production-behavior work item normally closes with:

- focused automated validation passing;
- `git diff --check` passing;
- final Git status/diff scope review;
- authoritative full registered suite passing;
- immediately after that fully passing suite, `test/runners/run_all_tests.ps1
  --cleanup` passing, with temporary artifacts removed from `test/_temp` and
  its tracked `.gdignore` preserved;
- applicable manual validation passing or an explicitly approved outstanding
  issue;
- compatibility/serialization checks when relevant;
- tracker execution log updated;
- commit/hash information recorded.

Work-item specifications should list only validation specific to the item and
reference these shared closeout rules.

Run the cleanup command only after the final full suite has passed. If a suite
fails, crashes, times out, lacks expected results, or otherwise behaves
unexpectedly, preserve `test/_temp` artifacts for investigation. When rerunning
tests during diagnosis, cleanup remains deferred until the final fully passing
run.

## Release closeout

Before release completion, perform the Release Charter acceptance gates,
commonly including:

- authoritative full suite;
- cleanup of successful-suite temporary artifacts with
  `test/runners/run_all_tests.ps1 --cleanup`;
- `git diff --check`;
- complete visible-editor smoke where applicable;
- compatibility testing on claimed engine/runtime versions;
- serialization/resource inspection when relevant;
- package/export contents inspection;
- final Git status/diff review;
- version/release metadata verification.


# TEST RESULT RECORDING

Record meaningful results including:

- suite/test name;
- PASS/FAIL;
- check count where available;
- process/runner exit result where relevant;
- material diagnostics.

Avoid repeatedly reproducing unchanged detailed suite tables.

When the authoritative runner has strong pass criteria, document those criteria
once and later closeouts may use a concise summary such as:

`17/17 registered suites PASS; runner exit 0; no timeout; no SCRIPT ERROR.`


# DIAGNOSTICS AND FOLLOW-UPS

Use stable IDs for recurring diagnostics likely to be referenced repeatedly.

Examples:

- `DIAG-01` — serialization temporary-directory/editor scan race;
- `DIAG-02` — known live-editor hot-reload error.

Record:

- ID/title;
- classification;
- first observed context/date when useful;
- affected validation/work item;
- blocking status;
- current disposition.

Later steps should reference the ID rather than repeating the full explanation
unless behavior changes.

Suggested classifications:

- production defect;
- fixed execution regression;
- test-fixture defect;
- tooling artifact;
- hot-reload artifact;
- environment diagnostic;
- expected test behavior;
- known non-blocking limitation;
- deferred follow-up.

Do not erase failed-attempt history when it explains the final design or fix.


# PLAN AMENDMENTS

Frozen planning information changes only through an explicit amendment.
The section is append-only.

Recommended table:

| Amendment ID | Date | Plan ID / Roadmap ID | Change | Reason | Approval |
| --- | --- | --- | --- | --- | --- |

Use IDs such as `AMD-01`, `AMD-02`.

An amendment should preserve:

- original decision;
- what changed;
- why;
- user/approval context.

Minor bookkeeping corrections, status updates, test counts, and commit hashes do
not require amendments when they do not alter frozen scope or acceptance
criteria.


# EXECUTION LOGGING

After each approved step, update the work-item execution log with:

- step status;
- approval state;
- exact files changed;
- concise implementation record;
- targeted validation results;
- manual result when applicable;
- diagnostics/classification;
- diff/scope integrity result;
- deviations and amendment/approval references;
- commit/hash information;
- next approval gate.

Do not paste large unchanged code blocks when a concise description plus
file/commit reference is sufficient.


# GIT / COMMIT RECORDING

Record relevant commit hashes for completed steps or bounded closeout.

If an intentionally empty marker commit is used, state that explicitly and
identify where the production changelist actually landed.

Do not infer that a commit contains a production change solely because its
message matches a Plan ID.

At closeout, verify final diff/status contains only approved work-item and
tracker changes.


# CURRENT HANDOFF

The active tracker must end with a compact handoff containing only current
authoritative state:

- completed active Plan IDs;
- current Plan ID;
- current step;
- next approval gate;
- blocked by;
- known relevant diagnostics;
- deferred/conditional work;
- relevant future-roadmap boundary;
- important `do not reopen` decisions;
- next release-gate action when applicable.

Detailed history stays under the work-item logs.


# AGENT CONTINUATION RULES

An AI agent continuing a release should:

1. Read `_CODE_WORKFLOW_REQUIREMENTS.md`.
2. Read the active release tracker.
3. Use the Execution Dashboard and Current Handoff to determine state.
4. Read the active work-item specification/execution plan before proposing
   changes.
5. Treat completed items as closed unless a demonstrated regression requires
   reopening them.
6. Preserve release compatibility constraints and explicit non-goals.
7. Preserve future-release boundaries; do not implement roadmap items early.
8. Work on exactly the requested/current approved step.
9. Present the Step Approval Packet before production edits.
10. Use focused tests during development and the full suite at required
    closeout gates.
11. Record exact changed files, validation, diagnostics, and commits.
12. Stop after the approved/requested slice instead of automatically starting
    the next item.


# RELEASE TRACKER CREATION RULES

When the user asks to generate a tracker for a new release:

1. Gather and confirm current-release goals.
2. Gather any explicitly supplied future-release goals and agreed release
   boundaries.
3. If current goals are missing, do not invent them.
4. Record future goals in a separate roadmap; do not place them in active scope.
5. Audit the non-destructive repository baseline.
6. Run the authoritative test baseline unless prohibited, explicitly deferred,
   or unavailable through the current environment.
7. If the fresh baseline cannot run, record it as a pending pre-implementation
   gate rather than substituting a different runner.
8. Record preservation/compatibility constraints.
9. Perform the release-level code-smells/architecture/performance audit only
   when requested/appropriate and only at the stage authorized by the user.
10. Assign stable Plan IDs to active findings/work items.
11. Recommend execution order.
12. Record release acceptance criteria.
13. Create the Execution Dashboard with known active work items.
14. Do not implement production code merely because the tracker was generated.
15. If the user explicitly asks to stop before the audit, create the tracker
    with the audit item marked `NOT STARTED`, make it the next gate, and stop.


# REQUESTS TO PLAN A WORK ITEM

When asked to plan a specific Plan ID:

- do not modify production code;
- update/create the frozen specification;
- perform a targeted architecture/risk assessment rather than repeating the
  release-wide audit;
- refresh the baseline concisely if necessary;
- generate formal high-level execution steps;
- list focused validation expectations;
- present the plan for user review;
- do not provide/apply exact code diffs until presenting an individual step for
  approval.


# REQUESTS TO EXECUTE A WORK ITEM OR STEP

If a work item has no approved formal execution plan, present that plan first.

For an already-planned step:

- inspect current code/state relevant to the step;
- present the Step Approval Packet;
- wait for approval before production edits unless the exact step/diff is
  already explicitly approved;
- run approved targeted validation after execution;
- update the tracker;
- stop before the next step unless separately approved.


# SUMMARY OF AUTHORITATIVE SOURCES

```text
_CODE_WORKFLOW_REQUIREMENTS.md
    -> defines HOW release code work is planned/executed/documented

vX.Y.Z_CODE_TRACKER.md
    -> defines WHAT the active release contains,
       WHAT future boundaries were supplied,
       and WHAT HAS HAPPENED
```

Within the tracker:

```text
Release Charter
    -> active release scope / constraints / acceptance authority

Future Release Roadmap
    -> intentional non-current goals and architectural boundaries

Work-item Specification
    -> individual active Plan ID scope / design / acceptance authority

Formal Execution Plan
    -> approved ordered implementation steps

Step Execution Results
    -> mutable implementation history

Plan Amendments
    -> valid mechanism for changing frozen scope/design/roadmap decisions

Execution Dashboard + Current Handoff
    -> current active-state authority
```

Do not create parallel documents that duplicate these responsibilities without
an explicit user request.

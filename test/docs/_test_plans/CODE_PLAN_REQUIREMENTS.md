# CODE PLAN REQUIREMENTS

## PURPOSE

The code plan serves as a release guide for a specific release version (eg. v1.0.8).
It documents the current state of the repository, and gives a high-level overview of what is needed for this release.

The code plan is generated upon user request for a specific release version (eg; generate a code plan for v1.0.8).
The user should supply the release goals for the specified version.

If no release goals have been specified yet; state that rather than generating a plan with made-up release goals.
Also, explicitly confirm the user's release goals before generating the plan.


## GENERAL FORMAT

The layout / format of the code plan should follow the below general structure:

1. Release Goals
2. Baseline audit
2.1. Repository state
2.2. Automated test baseline audit
2.2.1. Test results
2.2.2. Test coverage assessment
2.3. Preservation / compatibility constraints
2.4. Code smells audit & methodology
2.4.1. Code smells findings
2.4.2. Recommended implementation order
3. New Features
3.1. New Feature 1
3.1.1. Current related architecture assessment
3.1.2. Feature design decisions to settle before implementation
3.1.3. Recommendations and rough execution plan
3.1.4. Any execution constraints from code smells audit
3.1.5. Validation & test requirements
4. Summary & closing remarks


## RELEASE GOALS

This section is a high-level overview of the user-supplier goals for this release cycle.
The agent should not invent or create any new release goals.


## BASELINE AUDIT

The agent should perform an audit of the current project / code baseline.
This audit includes a summary of the current repository state including the current branch and latest commit.
The audit should run the current automated test baseline, provide a table with PASS/FAIL results for each test, and overall test result.
After completing the test suite, it should note any anomolies observed in executing the current automated tests.
Then it should perform an audit of the current test coverage, to determine whether it is adequate or needs work.
Note any preservation / compatibility concerns (what must be preserved / what must not be changed) for regression testing of new features.


## CODE SMELLS AUDIT

The agent should perform a comprehensive code smells audit; using https://refactoring.guru/refactoring/smells as a baseline for audit methodology.
Provide a table listing any major findings from code smells audit; listing in order of highest priority.
Findings should be associated with a specific ID / tag (for example, TEST-01, CLEANUP-01, METADATA-01).
Recommend any upkeep required before implementing new features.

Also provide detailed explanations of each finding below the table--which scripts are impacted, what type of smell is it, etc.
These can be high-level overviews, with suggested implementation details, but not directly supplying exact code diffs.


## NEW FEATURES

Each new feature should be assigned a tag / ID, eg. FEATURE-01.

Analyze the user-supplied requests for new features or updates to existing features.
Assess the current architecture related to said feature.
Note any design decisions that must be settled before implementation.
Provide a rough plan of how to implement this feature.
Note any constraints from the code smells audit; if those should be completed first.


## PLAN EXECUTION

Do not provide exact code diffs within the code plan itself.
Instead, when executing a step of the code plan; execution sub-steps should be documented within the corresponding code report (see CODE_REPORT_REQUIREMENTS.md).
This applies to both code smell findings and features.

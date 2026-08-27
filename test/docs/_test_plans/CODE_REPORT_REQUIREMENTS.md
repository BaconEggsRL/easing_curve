# CODE REPORT REQUIREMENTS

## PURPOSE

The purpose of the code report is to document the agent's progress in implementing the code plan.
It contains more lower-level execution details than the code plan, and is designed to be modified during code plan execution.

The original code plan should not be modified during execution.
The code report should serve as the executive summary and log all important execution details.
The code report should retain important implementation details from executing the code plan that future agents can refer back to.

## PLAN EXECUTION SUMMARY

The code report should contain a table with each Plan ID from the Code Plan, along with current Status (Complete / Not Started / etc.)


## EXECUTION PLAN

A formal execution plan should be generated for each step ID of the code plan before execution.
This contains a detailed description of execution sub-steps required to complete the step ID from the code plan.
An example might look like:

```
METADATA-01 EXECUTION PLAN:
high level overview of files that need to change
---
METADATA-01 Step 1 of 8 — Establish the zoom metadata contract
script1.gd and script2.gd require change for specific reason to implement plan
targeted automated / manual validation test where neeeded; user to review suggested code diffs and approve before implementation

METADATA-01 Step 2 of 8 — Centralize EasingCurveEditor
script3.gd and script4.gd require change for specific reason to implement plan
targeted automated / manual validation test where neeeded; user to review suggested code diffs and approve before implementation
...
METADATA-01 Step 7 of 8 — Focused integration validation
METADATA-01 Step 8 of 8 — Release-gate closeout
```

Targeted validation sub-steps can be included as necessary; however do not run a full test suite after each sub-step unless it is required.
Only run targeted tests as needed.

The user should review each step of the execution plan before it is implemented.
Do not start any step of the execution plan without user approval.
Always present the next step for approval before running it or making any changes to production code.

### EXECUTION PLAN SCOPE

Each step of the execution plan should implement small, targeted script updates where needed.
So the execution plan should detail exact files & code diffs for each step.

### REQUESTS FOR EXECUTION PLANS

When receiving a user request to generate a new execution plan:
- Do not modify any production code yet.
- Only present the formal execution plan for the requests code plan ID, listing a high level overview of each sub-step (not exact code diffs.)
- Code diffs & validation tests will be presented in each sub-step when they are presented for execution approval.
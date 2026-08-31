---
name: quota-aware-runner
description: Use when a software task should combine included-quota auto-resume, adaptive Sol/Terra/Luna routing, milestone checkpoints, and fresh final verification in one independently installed Skill.
---

# Quota-Aware Workflow Runner

Run this ordered contract from this installed Skill directory (`SKILL_ROOT`). Do not resolve scripts or assets through sibling Skills. Preserve the user's original goal byte-for-byte as `ORIGINAL_GOAL`, and preserve the parent task's sandbox and approval settings.

## 1. Run preflight exactly once

Before other substantive work, invoke the bundled preflight once and only once. When trusted metadata provides the exact canonical lowercase thread UUID and the current project is a Git repository, run:

```powershell
python "$SKILL_ROOT/scripts/preflight.py" --thread-id "$THREAD_ID" --project "$PROJECT" --goal "$ORIGINAL_GOAL"
```

When the user opts out, run `python "$SKILL_ROOT/scripts/preflight.py" --opt-out`. When any required context is missing, omit only the missing arguments, include `--goal "$ORIGINAL_GOAL"`, and accept `SKIPPED` without prompting or guessing. Save a returned `job_id` as `JOB_ID`. Always retain the canonical `billing_policy=included_only`; never consume credits or use API-key billing as a fallback.

## 2. Bootstrap and route

Read `$CODEX_HOME/sol-luna-handoff.json`, where `CODEX_HOME` defaults to `~/.codex`. Accept schemaVersion `1` with executionProfile `adaptive` or `sol-luna`, record it as the active profile, and treat a missing configuration as `adaptive`. If an existing document is malformed or unsupported, return `NEEDS_CONTEXT` with the exact configuration problem before routing.

Check for `sol_planner`, `sol_compact_planner`, `luna_scout`, `terra_executor`, `luna_executor`, and `luna_fast_executor`. If any is unavailable, run the agents-only bootstrap `& "$SKILL_ROOT/scripts/install-agents.ps1"`; it installs or reuses the six definitions and never writes global `AGENTS.md` or the execution-profile configuration. Until a new task exposes them, use the fallback contracts below. Then apply the complete bundled deterministic routing contract in this document and emit its single profile-aware final route line.

## 3. Checkpoint after routing

If preflight returned `JOB_ID`, immediately record the selected tier, Scout, Planner, Executor, files in scope, and next action:

```powershell
python "$SKILL_ROOT/scripts/checkpoint.py" --job-id "$JOB_ID" --set "COMPLETED=Routing selected" --set "CURRENT_STATE=<ROUTE>" --set "FILES_CHANGED=<FILES>" --set "TEST_RESULTS=Not run" --set "NEXT_ACTION=<IMPLEMENTATION>" --set "DO_NOT_REPEAT=Do not rerun preflight or routing"
```

## 4. Checkpoint after implementation

After the selected executor completes and its focused checks finish, record changed files, exact command results, failed attempts, and the bounded next verification action. Never replace evidence with a success claim.

```powershell
python "$SKILL_ROOT/scripts/checkpoint.py" --job-id "$JOB_ID" --set "COMPLETED=Implementation complete" --set "CURRENT_STATE=<IMPLEMENTATION_REPORT>" --set "FILES_CHANGED=<FILES>" --set "TEST_RESULTS=<COMMANDS_AND_EXIT_CODES>" --set "NEXT_ACTION=Fresh acceptance verification" --set "DO_NOT_REPEAT=<CONFIRMED_WORK>"
```

## 5. Verify, checkpoint, and finish

Run fresh acceptance checks and the route's required verification. For Tier 3, mandatory high-reasoning Sol verification must return `VERIFIED`. Checkpoint the verification evidence. Only after every acceptance criterion has fresh evidence, set the terminal status:

```powershell
python "$SKILL_ROOT/scripts/checkpoint.py" --job-id "$JOB_ID" --set "COMPLETED=Fresh verification passed" --set "CURRENT_STATE=DONE" --set "FILES_CHANGED=<FILES>" --set "TEST_RESULTS=<FRESH_EVIDENCE>" --set "NEXT_ACTION=NONE" --set "DO_NOT_REPEAT=Task complete"
python "$SKILL_ROOT/scripts/checkpoint.py" --job-id "$JOB_ID" --set "AUTO_RESUME_STATUS=DONE"
```

If preflight returned `SKIPPED`, follow the same routing and evidence sequence without checkpoint commands.

## Bundled Sol–Luna routing contract

## Deterministic routing

Follow this state machine in order. Scout is the only delegation allowed before the final route is emitted.

### State 1 - classify Tier

Classify in this exact order: Tier 3, Tier 1, then Tier 2.

| Tier | Exact predicate |
| --- | --- |
| **Tier 3** | Select if **any** Tier 3 predicate below is true. |
| **Tier 1** | Select only if **all** are true: at most 2 expected changed files; at most 100 expected changed lines; exactly 1 subsystem; an explicit acceptance condition; and no Tier 3 predicate. Unknown file, line, subsystem, or acceptance bounds fail this Tier 1 test. |
| **Tier 2** | Default to Tier 2 when Tier 3 is false and any Tier 1 condition is false. This includes bounded work of 3 to 8 files and bounded cross-component integration. |

Tier 3 predicates are: more than 8 expected changed files; security; authentication; authorization or permissions; cryptography; data migration; a destructive operation; deployment; a public API; concurrency; a dependency migration; architecture or an architectural decision; ambiguous requirements or scope that cannot be bounded before editing; or an explicit user request for full verification.

Do not infer low risk from missing information. Resolve it with the conditional Scout when applicable; otherwise the ambiguity predicate selects Tier 3.

### State 2 - decide and run Scout

Tier 1 always records `Scout: no` and skips Scout without evaluating the Conditional Scout triggers, even when supplied diagnostics exceed 500 lines or another discovery trigger appears applicable. For Tier 2 and Tier 3 only, apply the Conditional Scout triggers below. When Scout is required, dispatch `luna_scout` and wait for its compressed evidence. Otherwise record that Scout was skipped. Do not emit the final route line before Scout has completed or been skipped.

### State 3 - decide Planner from Scout evidence

Use the task brief plus the completed Scout report, when present. Tier 1 selects `none`. Tier 2 selects `compact` only when a planning trigger below applies and otherwise selects `none`. Tier 3 always selects `full`.

### State 4 - decide Executor

Tier 1 selects `luna` in both profiles. In the `adaptive` profile, Tier 2 uses `luna_executor` by default and applies the closed Terra exception set below, while Tier 3 always selects `terra`. In the `sol-luna` profile, Tier 2 and Tier 3 always select `luna_executor`; never select `terra_executor` while `sol-luna` is active.

### State 5 - emit the final route

Emit exactly one final route line immediately before Planner or Executor delegation:

`Route: Tier N - {reason}; Profile: adaptive|sol-luna; Scout: yes|no; Planner: none|compact|full; Executor: luna|terra`

After emitting the line, delegate the selected Planner when it is `compact` or `full`, then delegate the selected Executor. Include the active profile in every executor brief. Treat the emitted line as the unique final routing decision for that routing pass; only an upgrade starts a new pass.

## Conditional Scout for Tier 2 and Tier 3

These triggers apply only to Tier 2 and Tier 3. Tier 1 remains Scout-free.

Use `luna_scout` when any one of these discovery conditions is true:

- relevant files or key symbols are not located and the search must cross more than one subsystem;
- diagnostic logs, traces, or error material contain more than 500 lines;
- the modules crossed by the call chain are unclear;
- a planner would otherwise need a broad repository search.

Skip Scout when the exact files, symbols, constraints, and acceptance criteria are known. The Scout is read-only and returns at most **250 output tokens** containing only candidate paths and symbols, the shortest call chain, key evidence, and remaining unknowns. Store raw search and log output in a task-local file and pass only its path plus the compressed report.

## Tier behavior

### Tier 1: direct Luna

In both `adaptive` and `sol-luna`, Tier 1 uses `luna_fast_executor`. Set `Scout: no; Planner: none; Executor: luna`. Dispatch `luna_fast_executor` with task-local instructions, relevant paths, the active profile, the acceptance condition, and focused checks. It implements, runs the checks, inspects the diff, and self-verifies. Skip Sol, Scout, and Terra.

### Tier 2: conditional planning and execution

Run `luna_scout` only when a Conditional Scout trigger applies. Run `sol_compact_planner` only when at least one of these planning triggers applies:

- after Scout, the root cause still requires a choice among multiple candidate approaches;
- the change crosses multiple subsystems with ordering or dependency relationships;
- compatibility constraints or a new cross-file invariant exist;
- the acceptance criteria permit multiple implementations with material tradeoffs.

The compact plan must fit within **400 output tokens** and contain only scope and non-goals, ordered steps, affected files, checks, and acceptance criteria. If no planning trigger applies, the coordinator creates an explicit task brief and records `Planner: none`. **Skip Sol.**

#### Profile: adaptive

The default Tier 2 executor is `luna_executor` when the scope is bounded, the implementation strategy is explicit, and the result is independently verifiable. Bounded means the permitted subsystems and interfaces plus the stopping condition are known. Independently verifiable means runnable checks or observable acceptance evidence exist; it does not mean the work requires zero implementation judgment. Multi-file work, business logic, and ordinary local debugging do not by themselves select Terra.

Select `terra_executor` directly only when the task already requires at least one of these six Terra exceptions before execution:

1. cross-subsystem or cross-file invariant derivation;
2. shared-interface judgment;
3. ambiguous root cause;
4. integration uncertainty;
5. major refactor;
6. unknown failure requiring non-local diagnosis.

Do not use Terra as a fallback. If no named Terra exception exists but bounded scope, an explicit implementation strategy, or independent verification is not yet established, do not select an executor yet:

- when a Tier 2 planning trigger applies, apply the compact-planning triggers and run `sol_compact_planner`, then re-evaluate the Luna/Terra boundary from the binding plan;
- when facts required to establish one of the three Luna conditions are missing, return `NEEDS_CONTEXT` naming the exact missing condition and facts;
- when the boundary remains ambiguous before editing, apply the existing Tier 3 ambiguity predicate and restart routing as Tier 3.

Only a named Terra exception permits a Tier 2 route to `terra_executor`.

Known failures that can be diagnosed inside the bounded local scope remain with Luna. Luna may resolve ordinary implementation details and local diagnostic decisions within the brief or plan; it does not redesign, broaden scope, change shared-interface semantics without direction, or pursue non-local unknown failures.

If Luna first discovers a Terra exception or required scope expansion, it must stop before expanding scope or making further edits and return `UPGRADE_NEEDED`. Preserve the current diff and report the triggering exception, evidence, changed files, check evidence, and the next decision needed. The coordinator permits only one Luna-to-Terra executor switch for a Tier 2 routing pass. It sends the original task brief or binding plan, Luna report, current diff, and check evidence to `terra_executor`, then must reuse the same `terra_executor` for the remaining implementation and ordinary corrections. Do not switch back to Luna or start another Terra for the same executor upgrade.

Discovery of a Tier 3 predicate remains a tier upgrade under the existing routing rules, not an executor handoff.

Invoke `sol_planner` with high reasoning for verification only when at least one evidence trigger occurs:

- a fresh required check fails;
- discovered scope expands beyond the task brief or plan;
- the executor reports a remaining concern;
- acceptance evidence is incomplete;
- the resulting diff diverges from the task brief or plan.

With no evidence trigger, the main executor's fresh checks, diff inspection, and self-review complete the route.

#### Profile: sol-luna

Tier 2 always uses `luna_executor`. The six Terra exceptions remain evidence for compact Sol planning, binding decisions, or evidence-triggered Sol verification; they never authorize a Terra executor switch in this profile. If Luna discovers a missing binding decision or scope beyond the brief or plan, it stops before further edits and returns `UPGRADE_NEEDED` with preserved evidence for Sol replanning or tier reclassification. A Tier 3 predicate still upgrades the tier. Never select `terra_executor` or request a Luna-to-Terra handoff while `sol-luna` is active.

Use the same evidence triggers above for optional Tier 2 Sol verification. With no trigger, Luna's fresh checks, diff inspection, and self-review complete the route.

### Tier 3: full Sol-Executor-Sol

Run `luna_scout` first only when a Conditional Scout trigger applies. Dispatch `sol_planner` with high reasoning to read the user requirements, compressed Scout evidence when present, and necessary files, then produce the root cause or architecture, constraints, ordered plan, checks, and acceptance criteria.

In the `adaptive` profile, Tier 3 uses `terra_executor` as its main executor. In the `sol-luna` profile, Tier 3 uses `luna_executor` as its main executor. Tier 3 therefore always retains full `sol_planner` planning and mandatory high-reasoning verification, regardless of profile. Only under `adaptive`, a fully bounded, independently parallel, mechanical leaf task that reduces total context may use **at most one additional Luna worker**.

Then send the active profile, plan, acceptance criteria, executor report, diff summary, and fresh evidence to `sol_planner` for mandatory high-reasoning verification. In `sol-luna`, Terra exceptions are planning and verification evidence, and the coordinator never selects `terra_executor`.

The verifier returns `VERIFIED` or a bounded numbered findings list naming the failed criterion, evidence, and required correction.

## Shared controls

- Keep exactly one active main executor at a time. Under `adaptive`, a permitted Tier 2 Luna-to-Terra handoff replaces Luna rather than adding a second active executor. Under `sol-luna`, no Terra handoff is reachable. Terra and Luna implementation reports each fit within **300 output tokens**, excluding raw command output stored in task-local files. Each report contains changed files, a concise summary, commands and exit status, self-review, and remaining concerns or `NONE`.
- Exchange Scout, plan, and execution evidence through task-local files. Pass only relevant paths and compressed summaries between agents.
- Sol reads compressed evidence and necessary files; it does not perform broad repository traversal, raw-log screening, routine coding, or ordinary test-failure repair loops.
- If scope or risk crosses a higher-tier predicate, stop and upgrade before further edits. Never downgrade after editing starts.
- Send ordinary implementation corrections to the same active executor and count them under one task brief or plan. The correction count continues across the handoff and does not reset merely because Luna was replaced by Terra. After 2 correction rounds under one task brief or plan, replan before any further correction and reset the count only after the new plan is accepted:
  - for Tier 2 work with `Planner: none`, invoke `sol_compact_planner` before any further correction and use its output as the new binding plan;
  - for work already governed by a compact or full plan, return to the applicable Sol planner;
  - for Tier 1, return `UPGRADE_NEEDED`, reclassify as at least Tier 2, and invoke `sol_compact_planner` before any further correction. Never continue repeated Tier 1 corrections on the direct brief.
- `NEEDS_CONTEXT` names the exact missing facts. `UPGRADE_NEEDED` is returned before further editing when the current route is insufficient.
- Claim completion only from fresh evidence satisfying every acceptance criterion.

## Fallback dispatch contracts

When a named custom agent is unavailable, dispatch a fresh agent with the matching configuration and contract:

- `sol_planner`: `gpt-5.6-sol`, high reasoning, read-only; full planning or verification contract.
- `sol_compact_planner`: `gpt-5.6-sol`, medium reasoning, read-only; the 400-token compact-plan contract.
- `luna_scout`: `gpt-5.6-luna`, low reasoning, read-only; the 250-token discovery-evidence contract.
- `terra_executor`: `gpt-5.6-terra`, medium reasoning, workspace-write; Tier 2 Terra-exception or Tier 3 execution, including a single evidence-preserving Luna handoff, with a 300-token report.
- `luna_executor`: `gpt-5.6-luna`, medium reasoning, workspace-write; default bounded, explicit, independently verifiable Tier 2 execution plus all Tier 2 and Tier 3 execution under `sol-luna`, with a profile-aware stop-before-edit contract and a 300-token report.
- `luna_fast_executor`: `gpt-5.6-luna`, low reasoning, workspace-write; Tier 1 direct execution and self-verification contract with a 300-token report.

Reuse the same main executor for correction rounds and preserve the selected tier's Scout, planning, execution, and verification rules.

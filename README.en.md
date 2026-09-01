# Resume Codex tasks after quota resets—and route every job to Sol, Luna, or Terra automatically

**The problem it solves:** Long tasks interrupted by a ChatGPT usage window force you to remember progress and re-prompt. Complex tasks also tend to use one agent for both planning and execution, wasting reasoning budget and weakening verification. This pack adds **exact resume, risk-based routing, and milestone checkpoints** to Codex.

> **Default routing: Sol plans and verifies; Luna executes.** The `sol-luna` profile is used when no configuration file exists. Terra routing is available only after explicitly selecting `adaptive` with `install --profile adaptive` from the standalone `sol-luna-handoff` repository.

[中文](README.md) · [English](README.en.md)

## Install in one command

```bash
npx skills add shangzhimingge/codex-workflow-skills --skill '*' --agent codex --yes
```

> Requires Node.js 22.20+, Codex, and Python 3.9+. Custom-agent bootstrap also requires PowerShell 5.1+ or PowerShell 7+.

## 30-second demo

1. After installation, start a new Codex task and enter:

   ```text
   Add a /health endpoint to this project, add tests, and verify it. If the usage window interrupts the task, continue after the reset.
   ```

2. The Skill preflights the task identity and emits a route like:

   ```text
   Route: Tier 2 - bounded, testable change; Profile: sol-luna; Scout: no; Planner: compact; Executor: luna
   ```

3. Codex checkpoints routing, implementation, and verification. If the included usage window interrupts the run, it continues from the same thread, turn task, and Git root after reset instead of reconstructing progress from scratch.

## Before and after

| Scenario | Before | After |
| --- | --- | --- |
| Usage window exhausted | Save progress, wait, and restate context manually | Detect the interruption and resume the exact task after reset |
| Small change | May still launch heavyweight planning | Luna implements and verifies directly |
| Complex change | One agent guesses while editing | Sol plans; Luna or Terra executes based on risk |
| Final delivery | “It should be done” | Fresh checks verify the result and are saved in a checkpoint |

## Three Skills, one clear job each

| Skill | Product promise | Install it when |
| --- | --- | --- |
| `codex-auto-resume` | **Continue the right Codex task after a usage-window reset.** Registers the real thread UUID, turn task, and Git root, with a daemon, watchdog, and checkpoints. | You need resume without agent routing |
| `sol-luna-handoff` | **Plan with Sol, execute quickly with Luna, and use Terra only when needed.** Deterministically selects Tier 1/2/3 from scope and risk. | You need planning/execution routing without resume |
| `quota-aware-runner` | **Install resume, routing, checkpoints, and final verification as one workflow.** Bundles the Auto Resume runtime and all six agent definitions. | You want the complete workflow out of the box |

Each Skill installs independently. `quota-aware-runner` does not depend on the other two Skills in this pack.

## How it works

### 1. Exact resume instead of a vague re-prompt

`codex-auto-resume` runs one preflight for every user turn and subagent trigger turn. Its registration key is `actual_thread_id + task_id + git_root`. A shared daemon starts on demand only after an eligible preflight registers or reuses a task; on Windows it launches hidden and detached instead of opening a startup CMD window. After the daemon detects a usage-limit interruption, the task enters `WAITING_RESET`; when the window returns, child and parent tasks resume in leaf-first order. Runtime billing remains fixed to `billing_policy=included_only`.

Missing required context or an explicit opt-out returns `SKIPPED`. External or unrelated Git changes made while waiting move the task to `NEEDS_USER`, preventing an old checkpoint from being applied to new code.

### 2. Make the fast executor the default

`sol-luna-handoff` and `quota-aware-runner` share the same Luna-first v1.6.0 routing contract:

- **Tier 1:** A small, explicit change goes straight to Luna for implementation and verification.
- **Tier 2:** Bounded, explicit, independently verifiable work still defaults to Luna; compact Sol planning runs only when useful.
- **Tier 3:** High-risk or ambiguous work keeps full Sol planning and Sol review, with Luna executing by default.

Tier 2 moves to Terra only for six explicit exceptions: cross-subsystem or cross-file invariant derivation, shared-interface judgment, ambiguous root cause, integration uncertainty, major refactoring, or an unknown failure requiring non-local diagnosis. The handoff preserves the diff and check evidence, and each Tier 2 route permits at most one Luna-to-Terra switch.

The execution profile is read from `$CODEX_HOME/sol-luna-handoff.json` and defaults to `sol-luna` when the file is missing. This default retains optional compact Sol planning for Tier 2 and sends all Tier 2/3 execution to Luna; Tier 3 still has full Sol planning and mandatory Sol verification. To enable the six Terra exceptions and Terra-backed Tier 3 route, explicitly run the standalone repository's `install --profile adaptive` command.

### 3. Connect routing, changes, and acceptance with checkpoints

`quota-aware-runner` always follows this order:

```text
Auto Resume preflight
  → six-agent bootstrap and Sol–Luna routing
  → routing checkpoint
  → implementation and focused checks
  → implementation checkpoint
  → fresh acceptance verification
  → verification checkpoint and DONE
```

## Installation options

### Interactive selection

```bash
npx skills add shangzhimingge/codex-workflow-skills
```

This opens the Skill selector. For a deterministic, non-interactive installation of all three Skills into Codex, use the one-line command at the top of this page.

### Install one Skill

```bash
npx skills add shangzhimingge/codex-workflow-skills --skill codex-auto-resume --agent codex --yes
npx skills add shangzhimingge/codex-workflow-skills --skill sol-luna-handoff --agent codex --yes
npx skills add shangzhimingge/codex-workflow-skills --skill quota-aware-runner --agent codex --yes
```

### Install into every supported agent

```bash
npx skills add shangzhimingge/codex-workflow-skills --all
```

`--all` is shorthand for `--skill '*' --agent '*' --yes`. It installs into every supported agent; prefer the Codex-scoped command at the top when Codex is your only target.

## What happens on first run

`sol-luna-handoff` and `quota-aware-runner` check for six agents: `sol_planner`, `sol_compact_planner`, `luna_scout`, `terra_executor`, `luna_executor`, and `luna_fast_executor`. If any are missing, they run `scripts/install-agents.ps1` from the installed Skill directory.

Both honor `CODEX_HOME` and check every conflict before writing. `sol-luna-handoff` idempotently maintains its managed block in global `AGENTS.md` and the execution profile; `quota-aware-runner` installs agents only and leaves global `AGENTS.md` and profile state untouched. New agents are usually selectable from the next task; the current task uses the bundled fallback contracts.

## Local verification

```bash
python tools/sync-composite.py --check
python -m unittest discover -s tests -p "test_*.py" -v
node tests/skills-cli-smoke.mjs
```

Also run on Windows:

```powershell
powershell -NoProfile -File tests/install-agents.tests.ps1
powershell -NoProfile -File tests/composite-install.tests.ps1
```

## Update and uninstall

```bash
# Update installed Skills
npx skills update codex-auto-resume sol-luna-handoff quota-aware-runner

# Remove one Skill
npx skills remove --skill quota-aware-runner --yes

# Remove all three Skills in this pack
npx skills remove --skill codex-auto-resume sol-luna-handoff quota-aware-runner --yes
```

Maintainer workflows are documented in [`docs/design.md`](docs/design.md); pinned upstream versions are recorded in [`docs/upstream-provenance.json`](docs/upstream-provenance.json).

## License

MIT © 2026 shangzhimingge. Merged content comes from [`shangzhimingge/codex-auto-resume`](https://github.com/shangzhimingge/codex-auto-resume) and [`shangzhimingge/sol-luna-handoff`](https://github.com/shangzhimingge/sol-luna-handoff).

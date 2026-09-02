# Codex Workflow Skills Pack: design

## Purpose

This repository publishes three discoverable, independently installable Skills:

- `codex-auto-resume` preserves the existing automatic continuation runtime and public name.
- `sol-luna-handoff` preserves the existing deterministic Sol/Terra/Luna router and public name.
- `quota-aware-runner` composes both behaviors in one isolated-install entry point.

The repository is a skills.sh Skill Pack. Repository-root tooling supports development of the pack; it is not part of the runtime contract installed for an individual Skill.

## Canonical and derived ownership

`skills/codex-auto-resume` and `skills/sol-luna-handoff` are the canonical imported implementations. Their public names, entry points, state formats, routing contract, six agent definitions, and managed-block markers remain stable. The Auto Resume tree matches its pinned upstream except for the recorded `SKILL.md` loaded-path adaptation; the Sol–Luna tree is a complete byte-identical import. Both pins are recorded in `docs/upstream-provenance.json`.

`skills/quota-aware-runner` owns its `SKILL.md`, `agents/openai.yaml`, and agents-only `scripts/install-agents.ps1`. Its auto-resume runtime and six agent definitions are generated copies. `tools/sync-composite.py` is the sole supported way to refresh the derived files.

## Sync invariants

The sync tool copies bytes without text normalization:

1. every file below `skills/codex-auto-resume/scripts` into `skills/quota-aware-runner/scripts`;
2. every file below `skills/sol-luna-handoff/assets` into `skills/quota-aware-runner/assets`.

Generated trees contain no `SKILL.md`, and tests require byte parity with the canonical source. The composite's pack-owned bootstrap installs or reuses only the six byte-identical Agent TOMLs. It never reads or writes global `AGENTS.md`, so it neither installs a dangling `$sol-luna-handoff` activation rule nor competes for the canonical `SOL-LUNA-HANDOFF` managed block. `python tools/sync-composite.py --check` fails when a generated file is missing, stale, or unexpected.

The composite-owned `SKILL.md` keeps its quota/preflight/checkpoint prefix, but its routing tail from `## Deterministic routing` through EOF must exactly equal the canonical Sol–Luna routing tail. This gives the standalone and composite Skills the same Luna-first 1.6.0 boundary. The default `sol-luna` profile sends Tier 2 and Tier 3 execution to Luna while preserving full Sol planning and mandatory Sol verification for Tier 3. The explicit `adaptive` profile keeps bounded, explicit, independently verifiable work on Luna and permits only the closed six Terra exceptions to select Terra directly, with one evidence-preserving Luna→Terra handoff per Tier 2 routing pass.

## Activation order

`quota-aware-runner` has one ordered contract:

1. call its bundled auto-resume preflight exactly once with the untouched original goal;
2. read the shared execution profile, defaulting a missing configuration to `sol-luna` while honoring a persisted `adaptive`, then bootstrap only the six custom agents when any definition is unavailable, without global activation or profile changes;
3. apply the bundled Sol–Luna deterministic routing contract;
4. checkpoint after routing, implementation, and fresh verification;
5. set `AUTO_RESUME_STATUS=DONE` only after every acceptance criterion has fresh evidence.

Auto Resume v1.5.2 retains the v1.5.0 preflight across user, automatic-resume, and subagent turns and across Git roots, ordinary directories, and per-thread managed directories. The registration key remains `actual_thread_id + task_id + workspace_root`; missing or conflicting identity, explicit opt-out, or runtime damage still produce `SKIPPED`. The shared daemon starts on demand only after qualified registration or reuse. Windows rate-limit probes use a hidden kill-on-close Job Object as their primary containment boundary and a PID plus process-creation-identity descendant snapshot for pre-attachment children or assignment failures. Cleanup orders Job termination, hidden tree and identity-safe process fallback, root wait, bounded descendant drain, and final handle close; cleanup errors preserve an earlier RPC error. POSIX probes retain their own sessions and TERM-to-KILL group cleanup. Daemon and watchdog lock recovery requires PID plus process identity and compare-before-unlink, while genuine permission errors remain errors. The daemon publishes its verified identity and initial heartbeat before its first scan so a slow scan cannot break the startup handshake.

## Isolated installs

Each top-level Skill resolves runtime paths from the actual loaded `SKILL.md` directory, including project-local skills.sh copies. The composite never imports a sibling Skill and therefore continues to provide the Python runtime and six-agent bootstrap when selected alone. Its bootstrap deliberately leaves global activation ownership to canonical `sol-luna-handoff`. There are exactly three discoverable `SKILL.md` files in the repository—one at each Skill root.

## Updating upstream content

1. Replace the appropriate canonical mirror with the complete pinned upstream Skill tree and update `docs/upstream-provenance.json`, including its deterministic Git-index tree digest. For Auto Resume, apply only the recorded `SKILL.md` loaded-path adaptation after import.
2. For Sol–Luna, replace the composite-owned routing tail from `## Deterministic routing` through EOF with the canonical routing tail.
3. Run `python tools/sync-composite.py` to refresh derived runtime and agent assets.
4. Run `python tools/sync-composite.py --check`, the provenance/routing-tail parity tests, the Python and PowerShell suites, and the skills.sh smoke tests.
5. Review generated-file parity, the repository diff, and that the Auto Resume mirror matches the pinned upstream except for its recorded `SKILL.md` path adaptation before release work.

## Provenance and licensing

The two canonical Skills originate from `shangzhimingge/codex-auto-resume` and `shangzhimingge/sol-luna-handoff`, both under the MIT License and the same 2026 copyright notice. Exact source commits, source paths, versions, mirror modes, and deterministic tree digests are recorded in `docs/upstream-provenance.json`. The pack retains that root MIT license. Generated composite copies have the same provenance and license.

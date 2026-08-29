# Codex Workflow Skills Pack: design

## Purpose

This repository publishes three discoverable, independently installable Skills:

- `codex-auto-resume` preserves the existing automatic continuation runtime and public name.
- `sol-luna-handoff` preserves the existing deterministic Sol/Terra/Luna router and public name.
- `quota-aware-runner` composes both behaviors in one isolated-install entry point.

The repository is a skills.sh Skill Pack. Repository-root tooling supports development of the pack; it is not part of the runtime contract installed for an individual Skill.

## Canonical and derived ownership

`skills/codex-auto-resume` and `skills/sol-luna-handoff` are the canonical imported implementations. Their public names, entry points, state formats, routing contract, six agent definitions, and managed-block markers remain stable.

`skills/quota-aware-runner` owns its `SKILL.md`, `agents/openai.yaml`, and agents-only `scripts/install-agents.ps1`. Its auto-resume runtime and six agent definitions are generated copies. `tools/sync-composite.py` is the sole supported way to refresh the derived files.

## Sync invariants

The sync tool copies bytes without text normalization:

1. every file below `skills/codex-auto-resume/scripts` into `skills/quota-aware-runner/scripts`;
2. every file below `skills/sol-luna-handoff/assets` into `skills/quota-aware-runner/assets`.

Generated trees contain no `SKILL.md`, and tests require byte parity with the canonical source. The composite's pack-owned bootstrap installs or reuses only the six byte-identical Agent TOMLs. It never reads or writes global `AGENTS.md`, so it neither installs a dangling `$sol-luna-handoff` activation rule nor competes for the canonical `SOL-LUNA-HANDOFF` managed block. `python tools/sync-composite.py --check` fails when a generated file is missing, stale, or unexpected.

## Activation order

`quota-aware-runner` has one ordered contract:

1. call its bundled auto-resume preflight exactly once with the untouched original goal;
2. bootstrap only the six custom agents when any definition is unavailable, without global activation changes;
3. apply the bundled Sol–Luna deterministic routing contract;
4. checkpoint after routing, implementation, and fresh verification;
5. set `AUTO_RESUME_STATUS=DONE` only after every acceptance criterion has fresh evidence.

Missing trusted thread metadata or a non-Git project produces the canonical `SKIPPED` preflight outcome and does not prevent routing.

## Isolated installs

Each top-level Skill resolves runtime paths from the actual loaded `SKILL.md` directory, including project-local skills.sh copies. The composite never imports a sibling Skill and therefore continues to provide the Python runtime and six-agent bootstrap when selected alone. Its bootstrap deliberately leaves global activation ownership to canonical `sol-luna-handoff`. There are exactly three discoverable `SKILL.md` files in the repository—one at each Skill root.

## Updating upstream content

1. Update the appropriate canonical tree while preserving its public compatibility contract.
2. Run `python tools/sync-composite.py`.
3. Run `python tools/sync-composite.py --check`, the Python and PowerShell suites, and the skills.sh smoke tests.
4. Review generated-file parity and the repository diff before release work.

## Provenance and licensing

The two canonical Skills originate from `shangzhimingge/codex-auto-resume` and `shangzhimingge/sol-luna-handoff`, both under the MIT License and the same 2026 copyright notice. The pack retains that root MIT license. Generated composite copies have the same provenance and license.

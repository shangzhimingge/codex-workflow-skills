import hashlib
import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SOL = ROOT / "skills" / "sol-luna-handoff"
COMPOSITE = ROOT / "skills" / "quota-aware-runner"
AUTO = ROOT / "skills" / "codex-auto-resume"
ROUTING_MARKER = "## Deterministic routing"
SOL_COMMIT = "322d106facaccfb7f78d6a5b0f67f0b1c810f4ea"
SOL_TREE_SHA256 = "164f8325b78527cf1aa0eff8427807cb2e8d8d84160df89f2e73504781e2986f"
AUTO_COMMIT = "bb2ab03851877f7ff7745dc7878552525add82d5"
AUTO_TREE_SHA256 = "7fefb788e01f0c0242e6a40f0d0ebd35534d8599119a2b8335f69dd8c61ca9c8"
CANONICAL_FILES = {
    "SKILL.md",
    "agents/openai.yaml",
    "assets/global-agents.md",
    "assets/luna-executor.toml",
    "assets/luna-fast-executor.toml",
    "assets/luna-scout.toml",
    "assets/sol-compact-planner.toml",
    "assets/sol-planner.toml",
    "assets/terra-executor.toml",
    "scripts/install-agents.ps1",
}
TERRA_EXCEPTIONS = (
    "cross-subsystem or cross-file invariant derivation",
    "shared-interface judgment",
    "ambiguous root cause",
    "integration uncertainty",
    "major refactor",
    "unknown failure requiring non-local diagnosis",
)


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    files = (
        path
        for path in root.rglob("*")
        if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"
    )
    for path in sorted(files, key=lambda item: item.relative_to(root).as_posix()):
        digest.update(path.relative_to(root).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def git_index_tree_digest(root: Path) -> str:
    prefix = root.relative_to(ROOT).as_posix() + "/"
    tracked = subprocess.check_output(
        ["git", "ls-files", "-z", "--", prefix],
        cwd=ROOT,
    ).decode("utf-8").split("\0")
    entries = []
    for repository_path in tracked:
        if not repository_path:
            continue
        if not repository_path.startswith(prefix):
            raise AssertionError(f"tracked path outside tree: {repository_path}")
        relative_path = repository_path[len(prefix) :]
        blob = subprocess.check_output(
            ["git", "show", f":{repository_path}"],
            cwd=ROOT,
        )
        entries.append((relative_path, blob))

    digest = hashlib.sha256()
    for relative_path, blob in sorted(entries):
        digest.update(relative_path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(blob)
        digest.update(b"\0")
    return digest.hexdigest()


class SolLunaContractTests(unittest.TestCase):
    def test_canonical_import_is_the_pinned_complete_tree(self):
        actual_files = {
            path.relative_to(SOL).as_posix()
            for path in SOL.rglob("*")
            if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"
        }
        self.assertEqual(CANONICAL_FILES, actual_files)
        self.assertEqual(SOL_TREE_SHA256, tree_digest(SOL))

    def test_luna_first_boundary_is_closed_and_evidence_preserving(self):
        skill = (SOL / "SKILL.md").read_text(encoding="utf-8")
        for condition in ("scope is bounded", "implementation strategy is explicit", "independently verifiable"):
            self.assertIn(condition, skill)
        for exception in TERRA_EXCEPTIONS:
            self.assertIn(exception, skill)
        self.assertIn("The default Tier 2 executor is `luna_executor`", skill)
        self.assertIn("Only a named Terra exception permits a Tier 2 route to `terra_executor`", skill)
        self.assertIn("only one Luna-to-Terra executor switch", skill)
        self.assertIn("Preserve the current diff", skill)
        self.assertIn("correction count continues across the handoff", skill)
        self.assertNotIn("Choose `terra_executor` for every other Tier 2 task", skill)

    def test_executor_prompts_enforce_the_same_boundary_and_handoff(self):
        luna = (SOL / "assets" / "luna-executor.toml").read_text(encoding="utf-8")
        terra = (SOL / "assets" / "terra-executor.toml").read_text(encoding="utf-8")
        for condition in ("bounded", "explicit", "independently verifiable"):
            self.assertIn(condition, luna)
        for exception in TERRA_EXCEPTIONS:
            self.assertIn(exception, luna)
        self.assertIn("UPGRADE_NEEDED", luna)
        self.assertIn("stop before expanding scope or making further edits", luna)
        self.assertIn("Luna report, current diff, and check evidence", terra)
        self.assertIn("remain the same executor", terra)

    def test_composite_routing_tail_and_agent_assets_match_canonical(self):
        canonical = (SOL / "SKILL.md").read_text(encoding="utf-8")
        composite = (COMPOSITE / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn(ROUTING_MARKER, canonical)
        self.assertIn(ROUTING_MARKER, composite)
        self.assertEqual(
            canonical[canonical.index(ROUTING_MARKER) :],
            composite[composite.index(ROUTING_MARKER) :],
        )
        for source in sorted((SOL / "assets").rglob("*")):
            if source.is_file():
                target = COMPOSITE / "assets" / source.relative_to(SOL / "assets")
                self.assertTrue(target.is_file(), target)
                self.assertEqual(source.read_bytes(), target.read_bytes(), target)

    def test_machine_readable_provenance_and_versions_are_consistent(self):
        provenance = json.loads((ROOT / "docs" / "upstream-provenance.json").read_text(encoding="utf-8"))
        sol = provenance["upstreams"]["sol-luna-handoff"]
        self.assertEqual("https://github.com/shangzhimingge/sol-luna-handoff", sol["repository"])
        self.assertEqual(SOL_COMMIT, sol["commit"])
        self.assertEqual("1.4.0", sol["skillVersion"])
        self.assertEqual(SOL_TREE_SHA256, sol["treeSha256"])
        auto = provenance["upstreams"]["codex-auto-resume"]
        self.assertEqual("https://github.com/shangzhimingge/codex-auto-resume", auto["repository"])
        self.assertEqual(AUTO_COMMIT, auto["commit"])
        self.assertEqual("skill/codex-auto-resume", auto["sourcePath"])
        self.assertEqual("pack-path-adjusted", auto["mirrorMode"])
        self.assertEqual("1.3.0", auto["skillVersion"])
        self.assertEqual(AUTO_TREE_SHA256, auto["treeSha256"])
        self.assertEqual(auto["skillVersion"], (AUTO / "VERSION").read_text(encoding="utf-8").strip())
        package = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))
        self.assertEqual("1.2.0", package["version"])

    def test_docs_describe_luna_first_canonical_and_composite_parity(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        design = (ROOT / "docs" / "design.md").read_text(encoding="utf-8")
        for text in (readme, design):
            self.assertIn("Luna-first", text)
            self.assertIn("1.4.0", text)
            self.assertIn("six Terra exceptions", text)
        self.assertIn("routing tail", design)
        self.assertIn("upstream-provenance.json", design)

    def test_auto_resume_tree_matches_the_pinned_index_digest(self):
        self.assertEqual(AUTO_TREE_SHA256, git_index_tree_digest(AUTO))


if __name__ == "__main__":
    unittest.main()

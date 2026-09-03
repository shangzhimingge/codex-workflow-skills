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
SOL_COMMIT = "17f01bd1250c9ed719a44a838b64172a32ba24da"
SOL_TREE_SHA256 = "7433d000650a6bc5c605d579243bedce99a0dda135867cb110d6d12b4b9efe6c"
AUTO_COMMIT = "db9f450a9f5c05a33abfbbd1258e8257ddfa5fb7"
AUTO_TREE_SHA256 = "69c73d20d80482f7397c083b35d33d7b43ef6a965d4a992caaeb13550a4dd6a5"
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

    def test_default_sol_luna_profile_is_closed_and_preserves_sol_review(self):
        skill = (SOL / "SKILL.md").read_text(encoding="utf-8")
        luna = (SOL / "assets" / "luna-executor.toml").read_text(encoding="utf-8")
        installer = (SOL / "scripts" / "install-agents.ps1").read_text(encoding="utf-8")
        self.assertIn("$CODEX_HOME/sol-luna-handoff.json", skill)
        self.assertIn("Profile: adaptive|sol-luna", skill)
        self.assertIn("Tier 2 and Tier 3 always select `luna_executor`", skill)
        self.assertIn("mandatory high-reasoning verification", skill)
        self.assertIn("never select `terra_executor` while `sol-luna` is active", skill)
        self.assertIn("do not request a Terra handoff", luna)
        self.assertIn("ValidateSet('adaptive', 'sol-luna')", installer)
        self.assertIn("[string]$Profile = 'sol-luna'", installer)
        self.assertIn("sol-luna-handoff.json", installer)
        self.assertIn("missing configuration as `sol-luna`, the default profile", skill)

    def test_v140_agent_allowlist_covers_lf_and_crlf_exact_upgrades(self):
        installer = (SOL / "scripts" / "install-agents.ps1").read_text(encoding="utf-8")
        for digest in (
            "0C229A4CECAAFB49E25F4692D135B13ADFBEDB29B49E0CF1370C0EA619C65F6E",
            "05388D699131011FE00D09F7D9751EADD51473CDC1E6B9B2F8A944B3CC68DD15",
            "0E28C2F9ADA075DBD227505BE63F7F2712D16DD9065056062CC1C524DA1C6FD5",
            "4FEAE9C04F1D3D79F9D739F5850962B59EF8DFBB004B784EE69CC20932AE6D9D",
            "71EAC578F0925EB11C358E2AD1C65A69BD784966A16A798DFBD05A71F97F87D3",
            "49BAA5F4707F6F97117A106BC6380E63CD71D4A5EE79DE4257B9F0742D18C16A",
            "0903CA65A7383DF809F0F35C628E6D83B799552F83FE2867B07C65609B238891",
            "27C613C0ADA5C041EC073DE1DC54926DE80C949691D74C5D1836AFE88A7BF909",
        ):
            self.assertIn(digest, installer)

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
        self.assertEqual("1.6.0", sol["skillVersion"])
        self.assertEqual(SOL_TREE_SHA256, sol["treeSha256"])
        auto = provenance["upstreams"]["codex-auto-resume"]
        self.assertEqual("https://github.com/shangzhimingge/codex-auto-resume", auto["repository"])
        self.assertEqual(AUTO_COMMIT, auto["commit"])
        self.assertEqual("skill/codex-auto-resume", auto["sourcePath"])
        self.assertEqual("pack-path-adjusted", auto["mirrorMode"])
        self.assertEqual("1.5.4", auto["skillVersion"])
        self.assertEqual(AUTO_TREE_SHA256, auto["treeSha256"])
        self.assertEqual(auto["skillVersion"], (AUTO / "VERSION").read_text(encoding="utf-8").strip())
        package = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))
        self.assertEqual("1.4.4", package["version"])

    def test_docs_describe_luna_first_canonical_and_composite_parity(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        english = (ROOT / "README.en.md").read_text(encoding="utf-8")
        design = (ROOT / "docs" / "design.md").read_text(encoding="utf-8")
        for text in (readme, english, design):
            self.assertIn("Luna-first", text)
            self.assertIn("1.6.0", text)
            self.assertIn("six Terra exceptions", text)
            self.assertIn("sol-luna", text)
        for text in (readme[:1800], english[:1800]):
            self.assertIn("sol-luna", text)
            self.assertIn("--profile adaptive", text)
        self.assertIn("routing tail", design)
        self.assertIn("upstream-provenance.json", design)

    def test_docs_describe_v154_lock_state_machine_and_job_containment(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        english = (ROOT / "README.en.md").read_text(encoding="utf-8")
        design = (ROOT / "docs" / "design.md").read_text(encoding="utf-8")
        self.assertIn("v1.5.4", readme)
        self.assertIn("非 Git", readme)
        self.assertIn("workspace_root", readme)
        self.assertIn("Job Object", readme)
        self.assertIn("创建身份", readme)
        self.assertIn("PID + 进程身份", readme)
        self.assertIn("首次扫描前", readme)
        self.assertIn("v1.5.4", english)
        self.assertIn("non-Git", english)
        self.assertIn("kill-on-close Job Object", english)
        self.assertIn("creation-identity descendant snapshot", english)
        self.assertIn("named Mutex", english)
        self.assertIn("PID plus process identity", english)
        self.assertIn("initial daemon heartbeat", english)
        self.assertIn("ordinary directories", design)
        self.assertIn("managed directories", design)
        self.assertIn("TERM-to-KILL", design)
        self.assertIn("bounded descendant drain", design)
        self.assertIn("disappears before its read", design)
        self.assertIn("compare-before-unlink", design)
        self.assertIn("initial heartbeat", design)

    def test_auto_resume_tree_matches_the_pinned_index_digest(self):
        self.assertEqual(AUTO_TREE_SHA256, git_index_tree_digest(AUTO))


if __name__ == "__main__":
    unittest.main()

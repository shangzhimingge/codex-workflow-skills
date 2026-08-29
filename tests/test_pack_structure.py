import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SKILLS = ROOT / "skills"
EXPECTED = {"codex-auto-resume", "sol-luna-handoff", "quota-aware-runner"}
AUTO_ENTRIES = {"auto_resume.py", "preflight.py", "register.py", "checkpoint.py", "daemon.py", "watchdog.py"}
SOL_AGENTS = {
    "sol-planner.toml",
    "sol-compact-planner.toml",
    "luna-scout.toml",
    "terra-executor.toml",
    "luna-executor.toml",
    "luna-fast-executor.toml",
}


class PackStructureTests(unittest.TestCase):
    def test_exactly_three_discoverable_skills_and_names_match(self):
        discovered = list(ROOT.rglob("SKILL.md"))
        self.assertEqual(3, len(discovered), discovered)
        self.assertEqual(EXPECTED, {path.parent.name for path in discovered})
        for path in discovered:
            text = path.read_text(encoding="utf-8")
            match = re.match(r"\A---\nname:\s*([^\n]+)\n", text)
            self.assertIsNotNone(match, path)
            self.assertEqual(path.parent.name, match.group(1).strip())

    def test_utf8_without_bom_and_relative_paths_stay_in_pack(self):
        for path in ROOT.rglob("*"):
            if not path.is_file() or ".git" in path.parts:
                continue
            data = path.read_bytes()
            self.assertFalse(data.startswith(b"\xef\xbb\xbf"), path)
            if path.suffix.lower() in {".md", ".py", ".ps1", ".toml", ".yaml", ".yml", ".json", ".mjs"}:
                data.decode("utf-8")
        for skill in EXPECTED:
            self.assertTrue((SKILLS / skill).resolve().is_relative_to(ROOT.resolve()))

    def test_license_and_required_assets(self):
        license_text = (ROOT / "LICENSE").read_text(encoding="utf-8")
        self.assertIn("MIT License", license_text)
        auto_scripts = SKILLS / "codex-auto-resume" / "scripts"
        self.assertTrue(AUTO_ENTRIES <= {p.name for p in auto_scripts.iterdir() if p.is_file()})
        sol_assets = SKILLS / "sol-luna-handoff" / "assets"
        self.assertTrue(SOL_AGENTS <= {p.name for p in sol_assets.iterdir() if p.is_file()})
        composite_assets = SKILLS / "quota-aware-runner" / "assets"
        self.assertTrue(SOL_AGENTS <= {p.name for p in composite_assets.iterdir() if p.is_file()})

    def test_generated_composite_is_in_sync(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "sync-composite.py"), "--check"],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.assertEqual(0, result.returncode, result.stdout)

    def test_composite_contract_order_and_isolated_preflight(self):
        skill = (SKILLS / "quota-aware-runner" / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("## Bundled Sol–Luna routing contract", skill)
        installer = (SKILLS / "quota-aware-runner" / "scripts" / "install-agents.ps1").read_text(encoding="utf-8")
        self.assertNotIn("BEGIN SOL-LUNA-HANDOFF MANAGED BLOCK", installer)
        self.assertNotIn("$globalAgentsPath", installer)
        ordered = [
            "## 1. Run preflight exactly once",
            "## 2. Bootstrap and route",
            "## 3. Checkpoint after routing",
            "## 4. Checkpoint after implementation",
            "## 5. Verify, checkpoint, and finish",
        ]
        positions = [skill.index(marker) for marker in ordered]
        self.assertEqual(positions, sorted(positions))
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ.copy()
            env["CODEX_HOME"] = tmp
            entry = SKILLS / "quota-aware-runner" / "scripts" / "preflight.py"
            result = subprocess.run(
                [sys.executable, str(entry), "--goal", "isolated fixture"],
                cwd=tmp,
                env=env,
                text=True,
                encoding="utf-8",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn('"outcome": "SKIPPED"', result.stdout)

    def test_auto_resume_uses_the_loaded_skill_path_and_readme_scopes_pack_install(self):
        skill = (SKILLS / "codex-auto-resume" / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("$SKILL_ROOT = Split-Path -Parent (Resolve-Path $LOADED_SKILL_MD)", skill)
        self.assertNotIn('$HOME ".codex"', skill)
        self.assertNotIn('skills/codex-auto-resume/SKILL.md', skill)
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("--skill '*' --agent codex --yes", readme)
        self.assertIn("--skill '*' --agent '*' --yes", readme)


if __name__ == "__main__":
    unittest.main()

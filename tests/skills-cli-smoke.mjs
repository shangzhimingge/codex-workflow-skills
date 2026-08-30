import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const expectedAll = new Set(["codex-auto-resume", "sol-luna-handoff", "quota-aware-runner"]);
const npx = process.platform === "win32" ? "npx.cmd" : "npx";
const base = process.env.CODEX_SMOKE_TMP_ROOT
  ? fs.mkdtempSync(path.join(path.resolve(process.env.CODEX_SMOKE_TMP_ROOT), "skills-cli-"))
  : fs.mkdtempSync(path.join(os.tmpdir(), "skills-cli-"));

function findInstalledSkills(directory) {
  const found = new Map();
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      if (entry.name === ".git") continue;
      const candidate = path.join(current, entry.name);
      if (entry.isDirectory()) visit(candidate);
      else if (entry.isFile() && entry.name === "SKILL.md") {
        const name = path.basename(path.dirname(candidate));
        found.set(name, [...(found.get(name) ?? []), candidate]);
      }
    }
  };
  visit(directory);
  return found;
}

function runCase(name, args, expected) {
  const project = path.join(base, name);
  fs.mkdirSync(project, { recursive: true });
  execFileSync("git", ["init", "-q"], { cwd: project, stdio: "inherit" });
  execFileSync(npx, ["--yes", "skills", "add", root, ...args, "--copy"], {
    cwd: project,
    stdio: "inherit",
    shell: process.platform === "win32",
    env: { ...process.env, NO_COLOR: "1", FORCE_COLOR: "0" },
  });
  const installed = findInstalledSkills(project);
  assert.deepEqual(new Set(installed.keys()), expected, `${name}: installed Skill set`);
  for (const files of installed.values()) {
    assert.equal(files.length, 1, `${name}: one Codex copy per Skill`);
    const relative = path.relative(project, files[0]).split(path.sep).join("/");
    assert.match(relative, /^\.agents\/skills\/[^/]+\/SKILL\.md$/, `${name}: Codex-only scope`);
  }
  return installed;
}

function assertLunaFirstCopy(installed, skill) {
  const skillRoot = path.dirname(installed.get(skill)[0]);
  const skillText = fs.readFileSync(path.join(skillRoot, "SKILL.md"), "utf8");
  assert.match(skillText, /The default Tier 2 executor is `luna_executor`/, `${skill}: Luna-first marker`);
  assert.match(skillText, /only one Luna-to-Terra executor switch/, `${skill}: single-handoff marker`);
  assert.doesNotMatch(skillText, /Choose `terra_executor` for every other Tier 2 task/, `${skill}: no catch-all Terra`);
  for (const name of ["luna-executor.toml", "terra-executor.toml"]) {
    const installedAsset = fs.readFileSync(path.join(skillRoot, "assets", name));
    const canonicalAsset = fs.readFileSync(path.join(root, "skills", "sol-luna-handoff", "assets", name));
    assert.deepEqual(installedAsset, canonicalAsset, `${skill}: ${name} canonical bytes`);
  }
}

try {
  const all = runCase("all", ["--skill", "*", "--agent", "codex", "--yes"], expectedAll);
  assertLunaFirstCopy(all, "sol-luna-handoff");
  assertLunaFirstCopy(all, "quota-aware-runner");
  for (const skill of expectedAll) {
    const installed = runCase(skill, ["--skill", skill, "--agent", "codex", "--yes"], new Set([skill]));
    if (skill === "sol-luna-handoff" || skill === "quota-aware-runner") {
      assertLunaFirstCopy(installed, skill);
    }
    if (skill === "codex-auto-resume") {
      const unrelated = path.join(base, "unrelated-execution");
      fs.mkdirSync(unrelated, { recursive: true });
      const skillRoot = path.dirname(installed.get(skill)[0]);
      const output = execFileSync(process.env.PYTHON ?? "python", [
        path.join(skillRoot, "scripts", "preflight.py"), "--goal", "installed local fixture",
      ], { cwd: unrelated, encoding: "utf8" });
      assert.equal(JSON.parse(output).outcome, "SKIPPED", "project-local preflight from unrelated cwd");
    }
  }
  console.log("PASS Codex-scoped pack, individual installs, and unrelated-cwd preflight");
} finally {
  fs.rmSync(base, { recursive: true, force: true });
}

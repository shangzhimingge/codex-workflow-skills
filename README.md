# 额度重置后自动续跑 Codex 任务，并自动选择 Sol、Luna 或 Terra

**它解决什么问题：** 长任务被 ChatGPT 用量窗口打断后要靠人记住进度、重新提示；复杂任务又常把规划和执行交给同一个 Agent，既浪费推理预算，也缺少稳定验收。本包把**精确续作、按风险路由、里程碑检查点**装进 Codex。

[中文](README.md) · [English](README.en.md)

## 一句话安装

```bash
npx skills add shangzhimingge/codex-workflow-skills --skill '*' --agent codex --yes
```

> 需要 Node.js 22.20+、Codex、Python 3.9+；自定义 Agent bootstrap 还需要 PowerShell 5.1+ 或 PowerShell 7+。

## 30 秒演示

1. 安装后，新建一个 Codex 任务并输入：

   ```text
   为当前项目新增 /health 接口，补测试并验证；如果用量窗口中断，重置后继续。
   ```

2. Skill 自动预检任务身份，并给出类似路线：

   ```text
   Route: Tier 2 - bounded, testable change; Scout: no; Planner: compact; Executor: luna
   ```

3. Codex 记录路由、实施和验证检查点。若 included usage window 中断，窗口恢复后从同一 thread、同一 turn task 和同一 Git 根继续，而不是从头猜进度。

## 使用前后对比

| 场景 | 使用前 | 使用后 |
| --- | --- | --- |
| 用量窗口耗尽 | 手动保存进度、等待、重新描述上下文 | 识别中断并在重置后恢复精确任务 |
| 小改动 | 也可能启动重型规划 | Luna 直接执行并验证 |
| 复杂改动 | 一个 Agent 边猜边改 | Sol 规划，Luna 或 Terra 按风险执行 |
| 最终交付 | “应该完成了” | 用新鲜检查结果验收，并写入检查点 |

## 三个 Skills，各自解决一个问题

| Skill | 一句话定位 | 适合何时安装 |
| --- | --- | --- |
| `codex-auto-resume` | **用量窗口重置后，继续正确的 Codex 任务。** 按真实 thread UUID、turn task 与 Git 根注册，维护 daemon、watchdog 与检查点。 | 只需要自动续作，不需要 Agent 路由 |
| `sol-luna-handoff` | **让 Sol 规划，让 Luna 快速执行，必要时才交给 Terra。** 按范围和风险确定性选择 Tier 1/2/3。 | 只需要规划/执行分工，不需要自动续作 |
| `quota-aware-runner` | **一次安装，把续作、路由、检查点和最终验证串起来。** 自带 Auto Resume 运行时和六个 Agent 定义。 | 希望开箱即用的完整工作流 |

三者都可独立安装；`quota-aware-runner` 不依赖同包中的另外两个 Skill。

## 工作原理

### 1. 精确续作，不靠模糊提示

`codex-auto-resume` 为每个用户 turn 和子代理 trigger turn 各执行一次预检，以 `actual_thread_id + task_id + git_root` 作为注册键。daemon 发现用量限制中断后进入 `WAITING_RESET`，窗口恢复时按叶子优先顺序继续子代理与父任务。运行时固定为 `billing_policy=included_only`。

缺少必要上下文或显式 opt-out 时返回 `SKIPPED`；等待期间出现外部或不同谱系的 Git 变更时进入 `NEEDS_USER`，避免把旧检查点应用到新代码。

### 2. 让便宜、快速的执行器成为默认

`sol-luna-handoff` 与 `quota-aware-runner` 使用相同的 Luna-first v1.4.0 路由：

- **Tier 1：** 小而明确的改动，由 Luna 直接实施和验证。
- **Tier 2：** 范围有界、策略明确、可独立验证时仍默认 Luna；需要时先由精简 Sol 规划。
- **Tier 3：** 安全、架构、部署、迁移等高风险或高歧义任务，由完整 Sol 规划、Terra 执行、Sol 复核。

Tier 2 只有在六类明确例外（six Terra exceptions）下才升级到 Terra：跨子系统/跨文件不变量推导、共享接口判断、根因不明、集成不确定、大型重构、需要非局部诊断的未知失败。升级前保留 diff 与检查证据；每条 Tier 2 路线最多一次 Luna→Terra handoff。

### 3. 用检查点把路线、改动和验收连起来

`quota-aware-runner` 固定执行：

```text
Auto Resume 预检
  → 六 Agent bootstrap 与 Sol–Luna 路由
  → 路由检查点
  → 实施与聚焦检查
  → 实施检查点
  → 新鲜验收验证
  → 验证检查点与 DONE
```

## 安装方式

### 交互选择

```bash
npx skills add shangzhimingge/codex-workflow-skills
```

该命令会打开 Skill 选择器。若要无交互地把三个 Skills 安装到 Codex，请使用首页的一句话安装命令。

### 只安装一个 Skill

```bash
npx skills add shangzhimingge/codex-workflow-skills --skill codex-auto-resume --agent codex --yes
npx skills add shangzhimingge/codex-workflow-skills --skill sol-luna-handoff --agent codex --yes
npx skills add shangzhimingge/codex-workflow-skills --skill quota-aware-runner --agent codex --yes
```

### 安装到全部受支持的 agents

```bash
npx skills add shangzhimingge/codex-workflow-skills --all
```

`--all` 是 `--skill '*' --agent '*' --yes` 的简写。它会安装到全部受支持的 agents；只使用 Codex 时，优先使用首页的 Codex 定向命令。

## 首次运行会发生什么

`sol-luna-handoff` 和 `quota-aware-runner` 会检查六个 Agent：`sol_planner`、`sol_compact_planner`、`luna_scout`、`terra_executor`、`luna_executor`、`luna_fast_executor`。缺失时，它们从已安装 Skill 目录运行 `scripts/install-agents.ps1`。

两者都遵循 `CODEX_HOME`，并在写入前检查冲突。`sol-luna-handoff` 幂等维护自己的全局 `AGENTS.md` 托管块；`quota-aware-runner` 只安装 agents，不改全局 `AGENTS.md`。新 Agent 通常从下一个任务开始可选，当前任务使用内置 fallback contract。

## 本地验证

```bash
python tools/sync-composite.py --check
python -m unittest discover -s tests -p "test_*.py" -v
node tests/skills-cli-smoke.mjs
```

Windows 上额外运行：

```powershell
powershell -NoProfile -File tests/install-agents.tests.ps1
powershell -NoProfile -File tests/composite-install.tests.ps1
```

## 更新与卸载

```bash
# 更新已安装 Skills
npx skills update codex-auto-resume sol-luna-handoff quota-aware-runner

# 卸载单项
npx skills remove --skill quota-aware-runner --yes

# 卸载本包三个 Skills
npx skills remove --skill codex-auto-resume sol-luna-handoff quota-aware-runner --yes
```

维护者流程见 [`docs/design.md`](docs/design.md)，固定上游版本见 [`docs/upstream-provenance.json`](docs/upstream-provenance.json)。

## License

MIT © 2026 shangzhimingge。合并内容源自 [`shangzhimingge/codex-auto-resume`](https://github.com/shangzhimingge/codex-auto-resume) 与 [`shangzhimingge/sol-luna-handoff`](https://github.com/shangzhimingge/sol-luna-handoff)。

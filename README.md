# Codex Workflow Skills

一个兼容优先的 skills.sh Skill Pack（Pack v1.2.0）：保留 `codex-auto-resume` 与 `sol-luna-handoff` 的公共名称，并提供可独立安装的组合 Skill `quota-aware-runner`。

## 安装

前置条件：Node.js 22.20+（与当前 skills CLI 的声明一致）、Codex、Python 3.9+。使用 Sol–Luna 自定义 Agent 时还需要 PowerShell 5.1+ 或 PowerShell 7+。

### 交互选择

裸命令会打开交互式 Skill 选择器，可在界面中选择一个、多个或全部 Skills；它不代表无交互的确定性整包安装：

```bash
npx skills add shangzhimingge/codex-workflow-skills
```

### Codex 定向的确定性整包安装

明确选择全部三个 Skills、仅安装到 Codex，并跳过确认：

```bash
npx skills add shangzhimingge/codex-workflow-skills --skill '*' --agent codex --yes
```

`--all` 是 skills CLI 对 `--skill '*' --agent '*' --yes` 的简写，会把全部 Skills 安装到全部受支持的 agents。确实需要跨全部 agents 安装时可选用：

```bash
npx skills add shangzhimingge/codex-workflow-skills --all
```

### 只安装一个 Skill

```bash
npx skills add shangzhimingge/codex-workflow-skills --skill codex-auto-resume
npx skills add shangzhimingge/codex-workflow-skills --skill sol-luna-handoff
npx skills add shangzhimingge/codex-workflow-skills --skill quota-aware-runner
```

可按 skills CLI 约定追加 `--agent codex --yes`，用于指定 Codex 并跳过确认。

## 包含内容

| Skill | 用途 | 独立安装内容 |
| --- | --- | --- |
| `codex-auto-resume` | 在真实 ChatGPT 用量窗口重置后按精确线程 UUID 续作 | v1.3.0 Python 标准库运行时、入口脚本、检查点与守护进程逻辑 |
| `sol-luna-handoff` | 按风险与范围确定性选择 Tier 1/2/3 及 Sol、Terra、Luna 路线 | 六个 Agent 定义、全局托管块、原子安装脚本 |
| `quota-aware-runner` | 一次预检后路由，在实施与验证里程碑维护检查点 | 内嵌 Auto Resume 运行时与六 Agent bootstrap，不依赖同包其他 Skill |

### Luna-first v1.4.0 路由

独立的 `sol-luna-handoff` 与组合的 `quota-aware-runner` 都携带相同的 Luna-first v1.4.0 路由契约。Tier 2 在范围有界、实现策略明确、结果可独立验证时默认交给 Luna；多文件改动、业务逻辑和有界的本地调试本身不会触发 Terra。

Terra 只处理六类明确例外（six Terra exceptions）：跨子系统或跨文件不变量推导、共享接口判断、根因不明确、集成行为不确定、大型重构、需要非局部诊断的未知失败。Luna 首次发现其中一项时，会在扩大范围前返回 `UPGRADE_NEEDED`，保留当前 diff 与检查证据；每个 Tier 2 路由过程只允许一次 Luna→Terra handoff，修正轮次计数跨 handoff 延续。

## 首次运行

### Sol–Luna bootstrap

`sol-luna-handoff` 与 `quota-aware-runner` 会先检查以下六个 Agent：`sol_planner`、`sol_compact_planner`、`luna_scout`、`terra_executor`、`luna_executor`、`luna_fast_executor`。如果缺失，Skill 从自身目录运行 `scripts/install-agents.ps1`。两者都遵循 `CODEX_HOME` 并在写入前检查全部冲突。canonical `sol-luna-handoff` 还幂等维护自己的全局 `AGENTS.md` 托管块；`quota-aware-runner` 使用 agents-only bootstrap，绝不改动全局 `AGENTS.md`，因此单项安装不会留下兄弟 Skill 引用。新 Agent 通常在新任务中可选；当前任务使用 Skill 内的 fallback contract。

### Auto Resume 预检

内含 `codex-auto-resume v1.3.0`。它为每个用户 turn 与子代理 trigger turn 分别预检和注册，以实际线程、turn task 与 Git 根作为任务身份；daemon 可发现漏注册任务，并按叶子优先顺序恢复子代理与父任务。上下文缺失或显式 opt-out 返回 `SKIPPED`。运行时固定使用 `billing_policy=included_only`，并通过实际加载的 Skill 目录解析全部脚本。

### 组合顺序

`quota-aware-runner` 固定执行：一次 Auto Resume 预检 → 六 Agent bootstrap 与 Sol–Luna 路由 → 路由检查点 → 实施检查点 → 新鲜验收验证 → 验证检查点 → `DONE`。单独选择它时仍包含所需运行时与 Agent 资产。

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

维护者更新规范与派生文件的流程见 [`docs/design.md`](docs/design.md)，机器可读的固定上游版本见 [`docs/upstream-provenance.json`](docs/upstream-provenance.json)。仓库根安装工具仅服务于 Pack 开发，不属于 skills.sh 的单 Skill 运行时契约。

## License

MIT © 2026 shangzhimingge。合并内容源自 [`shangzhimingge/codex-auto-resume`](https://github.com/shangzhimingge/codex-auto-resume) 与 [`shangzhimingge/sol-luna-handoff`](https://github.com/shangzhimingge/sol-luna-handoff)。

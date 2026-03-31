# HyperLoop 项目简报

## 1. 项目概述

HyperLoop 是一个多 Agent 自改进开发循环工具（v5.3），以 Claude Code Plugin 形式运行。核心架构：Claude Code 做决策（BDD 规格、任务拆解、裁决解读），`hyper-loop.sh` Bash 脚本做编排（tmux 进程管理、Writer 启动、评分收集、和议计算）。技术栈为 Bash + Python3 + tmux，依赖 Codex CLI（Writer）、Claude CLI（Tester + Reviewer B + 任务拆解）、Gemini CLI（Reviewer A）。目标用户是需要无人值守代码改进循环的开发者。

## 2. 架构约束

- **角色分离**：Orchestrator（Claude Code）只做决策，不写业务代码；Writer（Codex exec）只改代码，不评分；Tester 只验证不改代码；Reviewer 只评分不改代码
- **进程模型**：Writer 以 `codex exec --dangerously-bypass-approvals-and-sandbox` 非交互模式运行，每个 Writer 一个后台子进程（非 tmux），通过 stdin 注入完整 prompt
- **Worktree 隔离**：每个 Writer 在 `/tmp/hyper-loop-worktrees-rN/taskM` 的独立 git worktree 中工作，合并到 `hyper-loop/rN-integration` 分支后再进 main
- **上下文传递**：通过文件路径传递（不传文本内容），核心上下文在 `_hyper-loop/context/`，Writer 复制到 `_ctx/`
- **Hook 强制执行**：`PreToolUse(Edit|Write)` hook 拦截对 .svelte/.rs/.ts/.js/.py 等业务代码的直接修改；`SessionStart` hook 注入 Orchestrator 规则；`Stop` hook 阻止有未裁决分歧时退出
- **3 Reviewer 合议**：Gemini（reviewer-a）+ Claude（reviewer-b）+ Codex（reviewer-c）并行评审，取中位数，一票否决（< 4.0），分歧 > 2.0 交用户裁决
- **超时机制**：Writer 15 分钟、Tester 10 分钟、每个 Reviewer 5 分钟
- **连续 5 轮失败自动回退**到历史最佳轮次的 git sha

## 3. 编码规范

- 本项目无 CLAUDE.md，以下规范从脚本和模板中提取：
- **Bash 严格模式**：`set -euo pipefail` 全局启用
- **构建验证**：`bash -n scripts/hyper-loop.sh`（语法检查）
- **macOS 兼容**：无 `timeout` 命令时用 `gtimeout` 或自定义 fallback
- **安全读取 verdict.env**：不用 `source`，用 `grep '^KEY=' | cut -d= -f2` 提取值，防止 "command not found" 错误
- **函数输出纪律**：非返回值的 echo/git 命令加 `>&2`，stdout 只用于返回值传递
- **Python3 用于 JSON 处理**：评分提取、verdict 计算、模板渲染均用内联 Python3
- **清理容错**：清理函数用 `(set +e; ...) || true` 包裹，不能因清理失败终止循环
- **HyperLoop 元数据文件**（DONE.json、WRITER_INIT.md、TASK.md、_writer_prompt.md、_ctx/）必须在 `git add -A` 之前删除，防止多 Writer squash merge 冲突

## 4. 当前重点（BDD 场景摘要）

共 17 个 BDD 场景，核心验证目标：**hyper-loop.sh 能无人值守跑 50 轮不崩溃**。

### 关键场景分组

**循环控制**
- S001: `loop N` 命令跑满 N 轮后正常退出，results.tsv 有 N 行记录
- S014: STOP 文件优雅退出（exit 0 + 删除 STOP）
- S016: macOS timeout 兼容（gtimeout fallback）

**Writer 生命周期**
- S002: auto_decompose 生成 task*.md（失败时降级生成默认 task1.md）
- S003: worktree 创建 + Codex trust 配置 + 后台启动
- S004: Writer 完成后元数据清理 → git add -A → commit → squash merge 到 integration
- S005: diff 审计拦截越界修改（改了 TASK.md 未指定的文件 → 拒绝合并）
- S006: Writer 超时 15 分钟 → DONE.json status=timeout
- S017: 多 Writer 同文件冲突处理（元数据预清理，真实冲突 merge --abort + deferred）

**评审与裁决**
- S007: Tester 启动并在 15 分钟内生成报告（超时生成空报告）
- S008: 3 Reviewer 并行启动（Gemini + Claude + Codex），10 分钟内各生成 scores JSON
- S009: 和议 — 中位数计算，ACCEPTED 条件为 > prev_median
- S010: 一票否决 — 任一 score < 4.0 → REJECTED_VETO
- S011: Tester P0 否决 — 报告含 P0+fail → REJECTED_TESTER_P0
- S012: verdict.env 安全读取（不 source，不崩 bash）

**容错与回退**
- S013: 连续 5 轮失败 → 回退到 archive/ 中最佳轮次的 git sha
- S015: worktree 清理（删除 /tmp 目录 + 删除临时分支 + 关闭 tmux window）

### 评估契约

- 通过阈值：7.5
- 客观指标 80%：bash -n 语法检查 + BDD 场景通过率
- 主观维度 20%：代码可读性 + 错误处理完整性（上限 7.0）

## 5. 设计意图

- **"决策归你，编排归脚本"**：Claude Code 的认知能力（理解需求、拆解任务、解读评分）与脚本的机械执行能力（进程管理、文件操作、超时控制）解耦，各司其职
- **BDD 驱动验证**：每个功能有明确的 Given/When/Then，Tester 逐条验证，Reviewer 基于客观证据评分——不凭感觉
- **多 LLM 合议消除偏见**：3 个不同 LLM（Gemini/Claude/Codex）独立评分取中位数，防止单一模型的系统性偏差
- **不可绕过的 Hook 纪律**：PreToolUse hook 在 Claude 思考之前就拦截，不给它"这次我自己来"的机会
- **档案库 + 回退**：每轮归档 git sha + 评分 + 报告，连续失败时回退到最佳状态而非原地打转——灵感来自 HyperAgents 的 "stepping stones" 和 autoresearch 的 "never stop"
- **Writer 沙箱约束**：diff 审计确保 Writer 只改任务指定的文件，越界修改直接拒绝合并

## 6. 文件地图

### 核心脚本（最常修改）
| 文件 | 说明 |
|------|------|
| `scripts/hyper-loop.sh` | 编排主脚本（所有命令：loop/round/init/resume-from/status） |

### Hook 系统
| 文件 | 说明 |
|------|------|
| `hooks/hooks.json` | Hook 路由配置（SessionStart/PreToolUse/Stop） |
| `hooks/pre-write-guard.sh` | 拦截 Orchestrator 直接修改业务代码 |
| `hooks/session-start.sh` | 注入 Orchestrator 规则到 Claude Code |
| `hooks/stop-guard.sh` | 阻止有未裁决分歧时退出 |

### Agent 定义
| 文件 | 说明 |
|------|------|
| `agents/reviewer.md` | Reviewer agent 角色定义（评分规则 + JSON 输出格式） |
| `agents/tester.md` | Tester agent 角色定义（三层自动化 + 截图管理） |

### 模板（Phase 0 渲染，注入到各 Agent）
| 文件 | 说明 |
|------|------|
| `templates/WRITER_INIT.md` | Writer 初始化模板（占位符 → 实际值） |
| `templates/TESTER_INIT.md` | Tester 初始化模板（三层工具体系 + 报告格式） |
| `templates/REVIEWER_INIT.md` | Reviewer 初始化模板（评分公式 + JSON schema） |
| `templates/ORCHESTRATOR_CHECKLIST.md` | Orchestrator 每轮检查清单 |

### Skill 与 Plugin 配置
| 文件 | 说明 |
|------|------|
| `skills/hyper-loop/SKILL.md` | HyperLoop skill 定义（完整 Phase 0-2 流程） |
| `.claude-plugin/plugin.json` | Claude Code plugin 元数据 |
| `commands/hyper-loop.md` | `/hyper-loop` slash command 定义 |
| `commands/brainstorm.md` | `/brainstorm` slash command 定义 |
| `commands/hyper-loop-monitor.md` | `/hyper-loop-monitor` 监控命令定义 |

### 运行时产物目录（不需修改，但需理解）
| 路径 | 说明 |
|------|------|
| `_hyper-loop/project-config.env` | 项目配置（构建命令、启动命令等） |
| `_hyper-loop/bdd-specs.md` | BDD 行为规格（锁定后不轻易改） |
| `_hyper-loop/contract.md` | 评估契约（锁定） |
| `_hyper-loop/context/` | 上下文包（所有 agent 读这里） |
| `_hyper-loop/tasks/round-N/` | 每轮任务文件 + verdict.env + patch/stat |
| `_hyper-loop/results.tsv` | 累计评分记录（轮次/中位数/分数/决策） |

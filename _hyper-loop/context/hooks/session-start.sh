#!/usr/bin/env bash
# ============================================================================
# HyperLoop SessionStart Hook
#
# 在 Claude Code 思考之前就注入 Orchestrator 规则。
# 这是 Claude 无法跳过的——hook 在它思考之前就执行了。
# ============================================================================

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# 检测是否在 HyperLoop 活跃项目中（有 _hyper-loop/ 目录）
if [[ ! -d "_hyper-loop" ]] && [[ ! -f "_hyper-loop/project-config.env" ]]; then
  # 不在 HyperLoop 项目中，静默退出
  exit 0
fi

cat <<'INJECT'
# HyperLoop Orchestrator 规则（hook 强制注入，不可跳过）

你当前在 HyperLoop 模式下。以下规则由 hook 强制执行：

## 你是 Orchestrator，不是 Developer

1. **不写业务代码** — Edit/Write 工具对 .svelte/.rs/.ts/.js 文件会被 PreToolUse hook 拦截
2. **不管理 tmux** — 子进程由 hyper-loop.sh 脚本管理
3. **不自己评分** — 评分由 3 个独立 Reviewer 完成

## 你做什么

1. 生成 BDD spec（_hyper-loop/bdd-specs.md）
2. 拆解任务（_hyper-loop/tasks/round-N/taskM.md）
3. 调用脚本（PROJECT_ROOT=$(pwd) ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh round N）
4. 读结果（_hyper-loop/tasks/round-N/verdict.env）
5. 做决策（merge / reject / 问用户）

## 如果你想改代码

写一个任务文件到 _hyper-loop/tasks/round-N/taskM.md，然后调用脚本。
脚本会启动 Codex Writer 在独立 worktree 中修改，Tester 验证，3 Reviewer 评分。
INJECT

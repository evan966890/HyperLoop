---
description: 多 Agent 自改进循环 — 决策归你，编排归脚本。BDD 驱动 + 3 Reviewer 合议 + Tester 截图验证。
---

启动 HyperLoop v5.2。读取并严格遵循 `~/.claude/skills/hyper-loop/SKILL.md`。

## 你的角色
- **决策者**：生成 BDD spec → 拆解任务 → 写任务文件 → 解读结果
- **不是执行者**：不写业务代码，不管理 tmux，不等待子进程

## 流程
1. Phase 0：收集配置 → 上下文包 → 生成 BDD spec → 确认
2. Phase 1 每轮：拆任务写 task*.md → 跑 `hyper-loop.sh round N` → 读 verdict.env → 决策
3. Phase 2：元改进（分析 results.tsv → 调整一个变量）

## 编排脚本
```bash
PROJECT_ROOT=$(pwd) ~/.claude/skills/hyper-loop/hyper-loop.sh round N
```

脚本自动：创建 worktree → 启动 Writer(Codex) → 等完成 → merge → build → Tester(Claude) → 3 Reviewer(Gemini+Claude+Codex) → 和议 → verdict.env

$ARGUMENTS

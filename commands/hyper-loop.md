---
description: 全上下文多 Agent 循环 — Codex×50 worktree 并行写码 + Gemini 全文档评审 + Claude 编排
---

启动 HyperLoop v4。读取并严格遵循 `~/.claude/skills/hyper-loop/SKILL.md`。

## 核心原则
- **上下文先行**：Writer/Reviewer 启动前必须注入 BMAD 全套文档
- **Worktree 隔离**：每个 Writer 在独立 git worktree 中工作
- **进程常驻**：Codex/Gemini 是交互式会话，不是一次性命令
- **最多 50 并行**：问题拆解为子任务，每个子任务一个 tmux pane + worktree
- **最终分 = min(Claude, Gemini)**

## 启动流程
1. 检查 codex / gemini / tmux / git worktree
2. Phase 0：对齐 → 收集 BMAD 全套文档构建上下文包 → 功能清单 → 评估契约
3. 生成 WRITER_SYSTEM.md 和 REVIEWER_SYSTEM.md（含完整文档）
4. 启动常驻 Gemini reviewer pane
5. Phase 1：拆任务 → 创建 N 个 worktree+writer → 并行修复 → 合并 → 构建 → 双评 → 决策
6. Phase 2/3：元改进 / 归档

$ARGUMENTS

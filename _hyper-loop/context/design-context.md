# HyperLoop Skill 自优化上下文

## 这个 Skill 是什么
HyperLoop 是一个 Claude Code skill（`/hyper-loop`），用于自动化"试用 App → 发现问题 → 修复 → 验证"的循环。

## 文件结构
```
~/.claude/skills/hyper-loop/
├── SKILL.md                          # 主流程定义（当前 v4）
├── templates/
│   ├── WRITER_INIT.md                # 给 Codex Writer 的初始化文档模板
│   ├── REVIEWER_INIT.md              # 给 Gemini Reviewer 的初始化文档模板
│   └── ORCHESTRATOR_CHECKLIST.md     # 给 Claude Orchestrator 的检查清单模板
└── logs/                             # 会话日志
```

## 设计来源
1. **Karpathy AutoResearch** — 棘轮循环、不可变评估者、results.tsv、单变量实验
2. **Meta HyperAgents** — 元认知自改进、策略进化
3. **2026-03-29 教训** — 30 轮 AI 自写自审只改 CSS 自评 9.5，用户说"全是垃圾"

## 核心架构：三权分立
- **Claude (Orchestrator)**: 编排、感知（Peekaboo/Agent Browser）、评分、决策。不写代码。
- **Codex (Writer)**: 在独立 worktree 中写代码。每个 Writer 注入 BMAD 全套文档。最多 50 并行。
- **Gemini (Reviewer)**: 独立评分、对照设计文档。注入 PRD 全文 + 设计文档全文。
- **最终分 = min(Claude, Gemini)**，差异 > 2 分须用户裁决。

## 关键防线
1. 功能优先级锁死（P0→P1→P2→P3）
2. 前 5 轮必须 FUNC 类型修复
3. 主观分上限 7.0（用户确认前）
4. 客观指标权重 80%
5. 连续 3 个 VISUAL 触发元改进
6. 所有子进程必须 bypass 模式（codex --full-auto, gemini --yolo, claude --dangerously-skip-permissions）
7. 每个 Writer 在独立 git worktree 中工作

## 本次优化目标
确保这个 skill 真的能：
1. 长时间无人值守运行
2. 自动进化——每轮循环的质量真的在提升
3. 无限对齐用户的原始设计文档
4. 三个 CLI 子进程能稳定常驻、接受任务、返回结果
5. 会话日志完整记录每个子进程的输入输出

## 已知问题/需要审查的点
- tmux pane 输出捕获是否可靠？（capture-pane 有 buffer 限制）
- Codex `--file` 参数是否真的能把文件内容当 prompt？需要验证实际 CLI 行为
- Gemini `--system-prompt` 参数是否存在？需要验证
- worktree 并行合并时冲突处理流程是否完整
- 上下文包过大时 Codex/Gemini 会不会截断？需要估算 token 数
- Ralph Loop 嵌套 HyperLoop 是否真的可行
- Phase 2 元改进的触发和执行是否具体到可执行
- 评分 JSON 格式 Gemini 是否能稳定输出

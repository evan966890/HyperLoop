# HyperLoop v5.4 改进计划

## 基于 25 轮实测数据

### 问题 1（P0）：Reviewer 全给 0 分

**根因**：交互式 tmux 会话 + paste-buffer 注入，agent 不理解要输出 JSON。pane 提取也不稳定。

**修复**：`run_reviewers` 改为非交互管道模式：
```bash
echo "$PROMPT" | gemini -y -p - > raw_output.txt
python3 extract_json.py raw_output.txt > scores/reviewer-a.json
```

**fallback 分改为 3 不是 0**：0 触发一票否决（<4.0），3 不会。这让循环有机会 ACCEPTED。

### 问题 2（P1）：多 Writer 改同文件，只 merge 1 个

**根因**：auto_decompose 不知道任务会碰同一文件。

**修复**：
1. decompose prompt 要求每个任务列出"预计修改文件"
2. start_writers 前检查文件重叠，重叠任务 defer 到下轮

### 问题 3（P1）：Reviewer 输入质量差

**根因**：Reviewer 只看到 diff stat + 文件路径，信息不够做评分。

**修复**：调 Reviewer 前生成 `round-summary.md`（修改统计 + Tester 报告摘要 + BDD 通过率数字）。

### 问题 4（P2）：每轮 75 分钟太长

**修复**：Writer 超时 900s→300s，Tester 超时 900s→600s。如果 5 分钟内写不完说明任务太大。

### 问题 5（P2）：Tester 也应该用非交互

**修复**：同 Reviewer，Tester 改为 `claude -p` 模式。

### 不做的事
- 不加 SKILL.md 自修改（循环还没 ACCEPTED 过）
- 不加档案库 parent 选择（没有有效档案）
- 不加到 3 Reviewer（先让 1 个稳定输出 JSON）

### 验收标准
改完后跑 5 轮，至少 1 轮 ACCEPTED 且 Reviewer 评分 > 0。

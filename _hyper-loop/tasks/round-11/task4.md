## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] _hyper-loop/context/bdd-specs.md 中多个场景的描述与实际代码实现不一致，导致 Tester 需要做"功能等价"推理来判定 PASS，增加误判风险。

不一致清单：

1. **S003** "Codex 进程在 tmux window 中启动"——实际代码用后台 subshell + `codex exec`（scripts/hyper-loop.sh start_writers 函数 L227-234），不用 tmux window

2. **S007** "Tester Claude 子进程在 tmux 中启动"——实际代码用非交互 `claude -p` 管道模式（run_tester 函数 L449-451），不用 tmux

3. **S008** "3 个 Reviewer 在 tmux 中启动（Gemini + Claude + Codex）" + "如果文件不存在，从 pane 输出提取 JSON"——实际代码用并行 subshell + 管道模式（run_reviewers 函数 L504-524），Python 从 stdout 提取 JSON（L480-496），文件不存在时用 fallback score 5（L533-537）

### 相关文件
- _hyper-loop/context/bdd-specs.md (S003, S007, S008 三个场景)

### 修复策略

1. 先读 scripts/hyper-loop.sh 中 start_writers、run_tester、run_reviewers 三个函数的实际实现，确认当前行为

2. 逐个更新 BDD 场景描述，使其准确反映当前实现：

**S003 修改：**
- "Codex 进程在 tmux window 中启动" → "Codex 进程在后台子进程中启动（codex exec 非交互模式）"

**S007 修改：**
- "Tester Claude 子进程在 tmux 中启动" → "Tester 在非交互管道模式中运行（claude -p 管道模式）"
- 保留"15 分钟内生成"和"超时时生成空报告而非崩溃"的要求

**S008 修改：**
- "3 个 Reviewer 在 tmux 中启动（Gemini + Claude + Codex）" → "3 个 Reviewer 在并行子进程中启动（Gemini + Claude + Codex）"
- "如果文件不存在，从 pane 输出提取 JSON" → "通过 Python 从 stdout 管道提取 JSON；如果提取失败或文件不存在，fallback 给中立分 5"

3. 确保修改后的 BDD 场景仍然是可测试的行为规格，保留功能性验收要求

### 约束
- 只修 _hyper-loop/context/bdd-specs.md
- 不改 scripts/hyper-loop.sh 或其他文件
- 保留所有场景 ID（S001-S017）不变
- 保留功能性验收要求（超时处理、score 字段、报告生成等），只更新执行方式描述

### 验收标准
- S003: BDD 描述与 start_writers 实现一致
- S007: BDD 描述与 run_tester 实现一致
- S008: BDD 描述与 run_reviewers 实现一致
- Tester 不再需要做"功能等价"推理来判定 PASS

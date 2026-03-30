## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] `run_tester` 和 `run_reviewers` 引用的 INIT 文件路径不存在，导致 Tester/Reviewer Agent 启动后无角色定义。这是连续 16 轮 0.0 分的根本原因。

脚本中引用的路径：
- `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md`（run_tester, line ~384）
- `${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md`（run_reviewers, line ~459）

实际存在的文件：
- `_hyper-loop/context/agents/tester.md`
- `_hyper-loop/context/agents/reviewer.md`

### 相关文件
- scripts/hyper-loop.sh（line 383-384: run_tester 中 start_agent 调用；line 458-460: run_reviewers 中 start_agent 调用）

### 修复方案
修改 `scripts/hyper-loop.sh` 中两处 `start_agent` 调用的 INIT 文件路径：

1. `run_tester` 函数中（约 line 383-384）：
   ```
   # 旧：
   start_agent "tester" "claude --dangerously-skip-permissions" \
     "${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md" "$ROUND"
   # 新：
   start_agent "tester" "claude --dangerously-skip-permissions" \
     "${PROJECT_ROOT}/_hyper-loop/context/agents/tester.md" "$ROUND"
   ```

2. `run_reviewers` 函数中（约 line 459）：
   ```
   # 旧：
   start_agent "$NAME" "$CLI" \
     "${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md" "$ROUND"
   # 新：
   start_agent "$NAME" "$CLI" \
     "${PROJECT_ROOT}/_hyper-loop/context/agents/reviewer.md" "$ROUND"
   ```

### 约束
- 只修 scripts/hyper-loop.sh 中上述两处路径
- 不改 start_agent 函数本身
- 不改 INIT 文件内容

### 验收标准
引用 BDD 场景 S007（Tester 启动并生成报告）和 S008（3 Reviewer 启动并产出评分）：Agent 启动时引用的 INIT 文件必须存在且包含角色定义。

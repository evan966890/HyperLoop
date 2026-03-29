## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] S013 回退逻辑在"全部 REJECTED"时不触发 — `BEST_ROUND` 始终为 0。

`cmd_loop` 中 `BEST_ROUND` 仅在 ACCEPTED 决策时更新 (L896-899)。如果从未 ACCEPTED，`BEST_ROUND` 保持初始值 0。当连续 5 轮失败触发回退检查 (L911) 时，条件 `BEST_ROUND -gt 0` 不满足，回退不执行。

BDD S013 要求"archive/round-2 得分最高时回退到 Round 2"，但当前代码不扫描归档找最佳轮次。

修复方案：在 REJECTED 分支 (L901-903) 也追踪当前轮次的 median，更新 BEST_ROUND/BEST_MEDIAN；或在回退触发时（BEST_ROUND==0），扫描所有 archive/round-*/verdict.env 找 median 最高的轮次作为回退目标。

### 相关文件
- _hyper-loop/context/hyper-loop.sh L835-837 (BEST_ROUND/BEST_MEDIAN 初始化)
- _hyper-loop/context/hyper-loop.sh L888-903 (ACCEPTED/REJECTED 分支)
- _hyper-loop/context/hyper-loop.sh L910-921 (回退逻辑)

### 约束
- 只修改 _hyper-loop/context/hyper-loop.sh
- 只修改 cmd_loop 函数中的回退逻辑相关代码
- 不改变 ACCEPTED 分支的行为
- 保留 `CONSECUTIVE_REJECTS` 计数器逻辑不变

### 验收标准
引用 BDD 场景 S013（连续 5 轮失败自动回退）：
- 当所有轮次均为 REJECTED 时，BEST_ROUND 仍能正确指向 median 最高的轮次
- 连续 5 轮 REJECTED 后能触发回退（即使从未 ACCEPTED）
- `bash -n _hyper-loop/context/hyper-loop.sh` 通过

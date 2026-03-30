## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1-2] 连续失败回退在无 ACCEPTED 轮次时永不触发

`BEST_ROUND` 仅在 DECISION=ACCEPTED 时更新 (L885-888)。若循环从未接受过任何轮次，`BEST_ROUND` 保持初始值 0。L900 的回退条件 `BEST_ROUND -gt 0` 永不满足，即使连续 5 轮全部被拒绝，回退逻辑也不触发，循环空转。

BDD S013 要求：results.tsv 有 5 行 REJECTED 且 archive 中有得分最高的轮次时，代码应回退到该轮的 git sha。

修复方案：在每轮结束后（不论 ACCEPTED 还是 REJECTED），都比较当前 MEDIAN 与 BEST_MEDIAN，更新 BEST_ROUND/BEST_MEDIAN。同时在回退触发但 BEST_ROUND=0 时（无有效 archive），记录循环开始前的初始 sha 作为回退点。

### 相关文件
- scripts/hyper-loop.sh (L878-910, cmd_loop 内的 BEST_ROUND 更新和回退逻辑)
- scripts/hyper-loop.sh (L825-837, cmd_loop 初始化部分，BEST_ROUND/BEST_MEDIAN/INITIAL_SHA)

### 约束
- 只修 cmd_loop 函数中 BEST_ROUND 追踪和回退触发逻辑
- 不改 compute_verdict、record_result 等其他函数
- BEST_ROUND/BEST_MEDIAN 变量语义从"最佳 ACCEPTED 轮次"改为"所有轮次中 median 最高"
- 在 cmd_loop 开头记录 INITIAL_SHA，回退时若 BEST_ROUND=0 则用 INITIAL_SHA
- 不改 CSS

### 验收标准
引用 BDD S013: 连续 5 轮全部 REJECTED 时，回退到 median 最高轮次的 git sha；若无有效 archive，使用循环开始前的初始 sha 回退。`bash -n` 通过

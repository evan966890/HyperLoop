## 修复任务: TASK-5
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 4 轮连续 REJECTED_VETO（results.tsv 全部 0.0 分）— 诊断并修复评分流程

results.tsv 显示 4 轮全部为 `REJECTED_VETO`，中位数和所有评分均为 0.0。这意味着 Reviewer 从未产出有效评分，或评分提取逻辑有问题。需要排查以下环节：

1. Reviewer 启动和评分 JSON 生成是否正常
2. `compute_verdict` 从评分文件提取分数的逻辑是否正确
3. `record_result` 写入 results.tsv 的逻辑是否正确

这不是一个单一 bug，而是需要排查评分管线端到端的健壮性。

### 相关文件
- scripts/hyper-loop.sh (run_reviewers 函数、compute_verdict 函数、record_result 函数)
- _hyper-loop/results.tsv

### 修复方案
1. 检查 `run_reviewers` 中 Reviewer prompt 是否正确引导 Reviewer 输出 JSON 格式评分
2. 检查 `compute_verdict` 的评分提取逻辑（jq/grep 解析）是否健壮
3. 检查 `record_result` 写入 TSV 的字段拼接是否正确
4. 确保当 Reviewer 未产出有效 JSON 时有合理的 fallback（如默认 0.0 而非崩溃）

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 不改变评分契约（contract.md 定义的阈值和维度）

### 验收标准
引用 BDD 场景 S008：3 Reviewer 启动并产出评分
引用 BDD 场景 S009：和议计算正确
引用 BDD 场景 S010：一票否决（score < 4.0）

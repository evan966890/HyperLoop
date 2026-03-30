## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] Reviewer fallback 分数与日志文本不一致。

`run_reviewers()` L479 写入 JSON `"score":5`，但 L480 日志打印 "fallback to score 3"。实际给了 5 分但日志显示 3 分，排查评分问题时会被误导。

### 相关文件
- scripts/hyper-loop.sh (L476-482, run_reviewers 函数的 fallback 逻辑)

### 约束
- 只修 scripts/hyper-loop.sh
- 统一为 score 5（中立分），修改日志文本使其与 JSON 一致
- 不改 CSS

### 验收标准
- S008: fallback JSON 中的 score 值与日志输出的数字一致（均为 5）

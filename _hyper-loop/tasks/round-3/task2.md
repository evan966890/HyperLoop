## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] Reviewer fallback 分数与日志输出不一致。L479 的 fallback JSON 写入 `"score":5`，但 L480 的 echo 输出 `"fallback to score 3"`。运维人员看日志会被误导。

需要统一：JSON 已写 score 5（中立分），日志应改为 `"fallback to score 5"`。

### 相关文件
- scripts/hyper-loop.sh (L476-482)

### 约束
- 只修改 L480 的 echo 输出文本，将 "score 3" 改为 "score 5"
- 不改动 fallback JSON 的 score 值（5 分是设计意图：中立分）
- 不改动其他代码
- 修改后 `bash -n scripts/hyper-loop.sh` 必须通过

### 验收标准
引用 BDD 场景 S008: fallback 生成的 JSON score 字段值与日志输出的分数一致

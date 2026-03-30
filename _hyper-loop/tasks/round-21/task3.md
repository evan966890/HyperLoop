## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] S013 回退逻辑设计缺陷：BEST_ROUND 仅在 ACCEPTED 时更新（Line 907-910）。当前 20 轮全部 REJECTED，BEST_ROUND 始终为 0，Line 922 的 `[[ "$BEST_ROUND" -gt 0 ]]` 永远为 false，回退逻辑永远不触发。

BDD 规格 S013 要求"得分最高的轮次"，不限于 ACCEPTED。需要改为追踪所有轮次的最高分。

### 相关文件
- scripts/hyper-loop.sh (Line 900-935: verdict 处理和回退逻辑)

### 约束
- 只修改 verdict 处理区域的 BEST_ROUND/BEST_MEDIAN 追踪逻辑
- ACCEPTED 轮次的合并逻辑不变
- 回退时使用 archive/round-N/git-sha.txt 的逻辑不变

### 验收标准
- 无论 ACCEPTED 还是 REJECTED，只要 MEDIAN > BEST_MEDIAN，都更新 BEST_ROUND
- 连续 5 轮 REJECTED 且 BEST_ROUND > 0 时，回退触发
- `bash -n scripts/hyper-loop.sh` PASS
- 引用 BDD 场景 S013（连续 5 轮失败自动回退）

## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P2] 两个代码质量问题:

1. cmd_status() 函数重复定义（约697行和约957行），第一个定义成为死代码。

2. 连续失败回退逻辑在全零分时失效（约907-922行）。当所有轮次得分都是 0.0 时:
   - BEST_ROUND 始终为 0（因为 `float('0.0') > float('0.0')` 为 false）
   - 回退条件 `[BEST_ROUND -gt 0]` 永远不满足
   - 连续 10 轮全部 0.0 分，回退机制从未触发

   修复方案: 当 BEST_ROUND == 0 且 CONSECUTIVE_REJECTS >= 5 时，应该仍然触发回退行为（例如重置 CONSECUTIVE_REJECTS 并记录日志，因为没有历史最佳可回退时至少避免无意义循环）。或者在追踪最佳轮次时使用 `>=` 而非 `>` 比较，确保第一轮的 0.0 也被记录。

### 相关文件
- scripts/hyper-loop.sh (697行: 第一个 cmd_status 定义; 957行: 第二个 cmd_status 定义; 907-922行: 回退逻辑中 BEST_ROUND 追踪)

### 约束
- 只修 scripts/hyper-loop.sh
- 删除第一个 cmd_status() 定义（约697行，约6行）
- 修复回退逻辑: 第一轮时无条件设 BEST_ROUND=1, BEST_MEDIAN=$MEDIAN（确保至少有个基准值）
- 不改 CSS，不新建文件

### 验收标准
引用 BDD 场景 S013: 连续 5 轮失败后能正确触发回退（即使全部是 0.0 分）

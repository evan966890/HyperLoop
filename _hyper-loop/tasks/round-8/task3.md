## 修复任务: TASK-3
### 上下文
先读 _hyper-loop/context/ 下所有文件。重点理解 cmd_loop 函数中 BEST_ROUND、BEST_MEDIAN、CONSECUTIVE_REJECTS 的使用逻辑。
### 问题
[P1] 连续 5 轮失败自动回退机制存在两个缺陷：

**P1-3: BEST_ROUND 只追踪 ACCEPTED 轮次**
- 位置：`scripts/hyper-loop.sh:903-907`
- BEST_ROUND/BEST_MEDIAN 只在 `DECISION == "ACCEPTED"` 时更新
- 如果连续 5 轮全部 REJECTED（无一 ACCEPTED），BEST_ROUND 保持 0
- 回退条件 `BEST_ROUND > 0`（行919）永远不满足
- 修复：REJECTED 轮次也应追踪最高分，作为"最不差"的回退候选

**P1-4: CONSECUTIVE_REJECTS 不持久化**
- 位置：`scripts/hyper-loop.sh:843`
- `CONSECUTIVE_REJECTS` 是内存变量，初始化为 0
- 如果 loop 被中断后重启，应从 results.tsv 尾部统计连续 REJECTED 行数来恢复
- 修复：在 `cmd_loop` 初始化阶段（行 835-845），从 results.tsv 的末尾向前计算连续 REJECTED 数量，同时扫描所有历史轮次找出 BEST_ROUND

### 相关文件
- scripts/hyper-loop.sh (行 835-845, cmd_loop 初始化)
- scripts/hyper-loop.sh (行 897-911, ACCEPTED/REJECTED 分支)
- scripts/hyper-loop.sh (行 918-929, 回退逻辑)

### 约束
- 只修改 scripts/hyper-loop.sh
- 回退逻辑改动不能影响 ACCEPTED 分支的合并行为
- 不改 CSS

### 验收标准
- S013: 连续 5 轮失败后，即使没有 ACCEPTED 轮次，也能回退到得分最高的 REJECTED 轮次的 git sha
- S013: loop 重启后，CONSECUTIVE_REJECTS 从 results.tsv 恢复而非重置为 0

## 修复任务: TASK-4
### 上下文
先读 _hyper-loop/context/ 下所有文件。
### 问题
[P1-1] BEST_ROUND 只在 ACCEPTED 分支内追踪，连续全 reject 时回退机制失效。

位置 line 906-910：BEST_ROUND/BEST_MEDIAN 追踪逻辑仅在 `if DECISION == ACCEPTED` 分支内。当所有轮次都被 reject 时（如当前 17 轮全 REJECTED_VETO），BEST_ROUND 始终为 0，回退条件 `BEST_ROUND > 0` 永不满足，连续 5+ 轮失败也不触发回退。

修复：将 BEST_ROUND/BEST_MEDIAN 追踪逻辑移到 if/else 外面，对所有轮次（含 rejected）追踪最高 median。这样即使全 reject，也能回退到相对最好的那一轮。

[P1-2] cmd_status 函数在 line 697 和 line 957 重复定义，后者覆盖前者。

修复：删除 line 697 开始的旧版 cmd_status（约 10 行），只保留 line 957 的完整版本。
### 相关文件
- scripts/hyper-loop.sh (line 697-707 旧 cmd_status; line 896-915 BEST_ROUND 追踪逻辑)
### 约束
- 只修改 scripts/hyper-loop.sh
- BEST_ROUND 追踪：移到 if/else 外部（ACCEPTED/REJECTED 分支之后），对所有有 MEDIAN 的轮次比较
- cmd_status：删除 line 697 开始的旧定义（到下一个函数定义前）
### 验收标准
引用 BDD 场景 S013: 连续 5 轮失败后能找到最佳轮次并回退

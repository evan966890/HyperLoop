## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 连续失败回退逻辑 bug — 全零分时 BEST_ROUND 永远为 0，回退永远不触发

在 `cmd_loop()` 中（lines 895-935）：

1. BEST_ROUND/BEST_MEDIAN 追踪（lines 906-910）只在 `ACCEPTED` 分支内执行。当所有轮次都是 REJECTED 时，BEST_ROUND 始终为 0。
2. 回退条件（line 922）要求 `BEST_ROUND -gt 0`，所以全零分时永远不触发回退。
3. 结果：results.tsv 显示连续 11 轮 REJECTED_VETO + 0.0 分，但回退机制从未触发。

修复方案：
- 在 REJECTED 分支中也追踪 BEST_ROUND/BEST_MEDIAN（选中位数最高的轮次作为"最不差"的）
- 如果所有轮次都是 0.0 分（即没有有意义的"最佳轮次"），连续 5 轮失败后应重置 CONSECUTIVE_REJECTS 计数器避免无效回退，并记录警告日志

### 相关文件
- scripts/hyper-loop.sh (lines 893-935)

### 约束
- 只修 scripts/hyper-loop.sh 中 cmd_loop() 函数的决策处理和回退逻辑部分
- 不改其他函数
- 不改 CSS
- 修改范围：lines 893-935

### 验收标准
引用 BDD 场景 S013 (连续 5 轮失败自动回退)
- 当存在非零分的历史最佳轮次时，连续 5 轮失败后正确回退到该轮
- 当所有历史轮次都是 0.0 分时，不执行无意义的回退，但重置计数器并输出警告
- `bash -n scripts/hyper-loop.sh` 语法检查通过

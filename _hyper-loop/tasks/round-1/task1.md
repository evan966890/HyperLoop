## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] `merge_writers` 函数的所有 debug `echo` 输出到 stdout，但调用方使用 `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获 stdout。导致 `INTEGRATION_WT` 变量包含多行垃圾文本（如 "合并 Writer 产出..." 等），而不是纯路径。后续 `build_app "$INTEGRATION_WT"` 因为 `cd` 到错误路径而必定失败。

这是整个循环最致命的 bug：merge 之后的 build、test、review 全部无法执行。

### 相关文件
- scripts/hyper-loop.sh (行 296-358, merge_writers 函数)

### 修复方案
将 `merge_writers` 中所有 debug/progress echo 改为输出到 stderr (`>&2`)，只保留最后一行 `echo "$INTEGRATION_WT"` 输出到 stdout 作为返回值。

具体要改的行：
- `echo "合并 Writer 产出..."` → 加 `>&2`
- `echo "  ⚠ ${TASK_NAME}: status=${STATUS}, 跳过"` → 加 `>&2`
- `echo "  ✗ ${TASK_NAME}: diff 审计失败..."` → 加 `>&2`
- `echo "  ✓ ${TASK_NAME} merged"` → 加 `>&2`
- `echo "  ✗ ${TASK_NAME} conflict, deferred"` → 加 `>&2`
- `echo "合并完成: ${MERGED} merged, ${FAILED} failed/skipped"` → 加 `>&2`
- 最后 `echo "$INTEGRATION_WT"` 保持 stdout 不变

### 约束
- 只修 scripts/hyper-loop.sh 的 merge_writers 函数
- 不改逻辑，只改 echo 的输出方向
- 不改 CSS

### 验收标准
引用 BDD 场景 S001: 循环跑满 N 轮后正常退出（不崩溃）
引用 BDD 场景 S004: squash merge 到 integration 分支成功
验证：`INTEGRATION_WT=$(merge_writers 1)` 后 `echo "$INTEGRATION_WT"` 应只输出一个纯路径

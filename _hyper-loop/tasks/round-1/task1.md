## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] merge_writers() 的状态 echo 污染 stdout，导致 INTEGRATION_WT 变量捕获到多行文本而非纯路径。

cmd_loop 第 854 行 `INTEGRATION_WT=$(merge_writers "$ROUND")` 会把 merge_writers 的所有 stdout 捕获。
但 merge_writers 在第 311、321、329、350、354、359 行用 echo 打印状态消息，
最后第 360 行 `echo "$INTEGRATION_WT"` 才输出真正的路径。

结果 INTEGRATION_WT 变成多行文本，之后 `build_app "$INTEGRATION_WT"` 的 `cd "$BUILD_DIR"` 必然失败。
这是 25 轮连续 BUILD_FAILED → REJECTED_VETO 的根本原因。

同理，audit_writer_diff（第 242-296 行）的 echo 也应改为 stderr，避免未来被调用者捕获。

### 相关文件
- scripts/hyper-loop.sh (第 298-361 行: merge_writers 函数)
- scripts/hyper-loop.sh (第 242-296 行: audit_writer_diff 函数)

### 修复方案
将 merge_writers 和 audit_writer_diff 内所有状态 echo 加 `>&2`，只保留 merge_writers 最后一行 `echo "$INTEGRATION_WT"` 到 stdout。

merge_writers 需改的行（加 >&2）：
- 第 311 行: "合并 Writer 产出..."
- 第 321 行: "⚠ status=..., 跳过"
- 第 329 行: "✗ diff 审计失败"
- 第 350 行: "✓ merged"
- 第 354 行: "✗ conflict, deferred"
- 第 359 行: "合并完成: N merged, N failed/skipped"

audit_writer_diff 需改的行（加 >&2）：
- 第 253 行: "⚠ TASK.md 没有指定相关文件"
- 第 261 行: "⚠ Writer 没有改任何文件"
- 第 289 行: "✗ Diff 审计失败"
- 第 290 行: echo -e "$VIOLATIONS"
- 第 294 行: "✓ Diff 审计通过"

### 约束
- 只修 scripts/hyper-loop.sh
- 只改 merge_writers 和 audit_writer_diff 的 echo 输出方向
- 不改逻辑、返回值或函数签名

### 验收标准
引用 BDD 场景 S004: squash merge 到 integration 分支成功（不是 "already up to date"）
引用 BDD 场景 S005: diff 审计拦截越界修改 — 返回非零退出码
引用 BDD 场景 S001: 循环跑满 N 轮后正常退出（不崩溃）

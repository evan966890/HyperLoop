## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件，特别是 hyper-loop.sh 和 bdd-specs.md。

### 问题
[P0-Critical] `merge_writers` 函数将状态信息和返回值都输出到 stdout，导致调用方 `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获到多行垃圾文本而非纯路径。

具体机制：
- `merge_writers` 内有多处 `echo` 输出状态（"合并 Writer 产出..."、"✓ task1 merged"、"合并完成..."）
- 最后一行 `echo "$INTEGRATION_WT"` 输出集成 worktree 路径
- 调用方 `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获了**全部 stdout**
- 后续 `build_app "$INTEGRATION_WT"` 执行 `cd "$BUILD_DIR"` 时，路径是多行文本 → cd 失败 → set -e 导致脚本崩溃

**这是脚本无法完成完整一轮循环的根本原因。**

### 相关文件
- scripts/hyper-loop.sh (行 296-358: merge_writers 函数)
- _hyper-loop/context/hyper-loop.sh (同步修改)

### 修复方案
将 `merge_writers` 中所有状态信息输出重定向到 stderr（`>&2`），只保留最后一行 `echo "$INTEGRATION_WT"` 输出到 stdout。

需要改的行：
- 行 308: `echo "合并 Writer 产出..."` → 加 `>&2`
- 行 318: `echo "  ⚠ ${TASK_NAME}: status=${STATUS}, 跳过"` → 加 `>&2`
- 行 325: `echo "  ✗ ${TASK_NAME}: diff 审计失败，拒绝合并"` → 加 `>&2`
- 行 347: `echo "  ✓ ${TASK_NAME} merged"` → 加 `>&2`
- 行 351: `echo "  ✗ ${TASK_NAME} conflict, deferred"` → 加 `>&2`
- 行 356: `echo "合并完成: ${MERGED} merged, ${FAILED} failed/skipped"` → 加 `>&2`
- 行 357: `echo "$INTEGRATION_WT"` → 保持不变（这是返回值）

### 约束
- 只修 scripts/hyper-loop.sh 和 _hyper-loop/context/hyper-loop.sh 中的 merge_writers 函数
- 不改函数签名和逻辑，只改 echo 的输出目标
- 两个文件保持完全一致

### 验收标准
- S004: squash merge 到 integration 分支成功
- S001: 循环跑满 N 轮后正常退出（不崩溃）
- `bash -n scripts/hyper-loop.sh` 通过

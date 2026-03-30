## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] merge_writers 的 echo 日志污染 stdout，导致 `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获多行字符串（首行是"合并 Writer 产出..."而非路径），`build_app "$INTEGRATION_WT"` 执行 `cd` 时必然失败。每一轮 build 阶段都会崩溃，整个循环无法正常运行。
### 相关文件
- scripts/hyper-loop.sh (L299-361, merge_writers 函数)
  - L311: `echo "合并 Writer 产出..."` → 需改为 `>&2`
  - L321: `echo "  ⚠ ${TASK_NAME}: status=${STATUS}, 跳过"` → 需改为 `>&2`
  - L328: `echo "  ✗ ${TASK_NAME}: diff 审计失败，拒绝合并"` → 需改为 `>&2`
  - L350: `echo "  ✓ ${TASK_NAME} merged"` → 需改为 `>&2`
  - L354: `echo "  ✗ ${TASK_NAME} conflict, deferred"` → 需改为 `>&2`
  - L359: `echo "合并完成: ${MERGED} merged, ${FAILED} failed/skipped"` → 需改为 `>&2`
  - L360: `echo "$INTEGRATION_WT"` → 保留在 stdout（这是唯一应输出到 stdout 的行）
### 约束
- 只修改 scripts/hyper-loop.sh 中 merge_writers 函数
- 不改 CSS
- 不改函数签名和返回逻辑
- 仅将日志类 echo 重定向到 stderr，路径输出保留 stdout
### 验收标准
引用 BDD 场景 S004: merge_writers 返回值仅含 integration worktree 路径，build_app 能正确 cd 进去

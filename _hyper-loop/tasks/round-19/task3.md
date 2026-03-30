## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P2] `cleanup_round` 函数未清理 WORKTREE_BASE 父目录 `/tmp/hyper-loop-worktrees-rN/`。当所有 worktree 被删除后，空目录仍然残留在 /tmp 下，违反 S015 规格要求。

### 相关文件
- scripts/hyper-loop.sh (line 589-610, cleanup_round 函数)

### 约束
- 只修 scripts/hyper-loop.sh
- 只在 cleanup_round 函数的 subshell 末尾（`cp` 行之后、`) || true` 之前）添加 `rmdir "$WORKTREE_BASE" 2>/dev/null || true`
- 不改其他函数

### 验收标准
引用 BDD 场景 S015: worktree 清理
- Round 完成后 `/tmp/hyper-loop-worktrees-rN/` 目录不存在
- bash -n scripts/hyper-loop.sh 通过

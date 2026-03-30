## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] **S015: cleanup_round 不删除 worktree 基目录，空目录残留**

`cleanup_round` 函数 (约 line 600-609) 中，`git worktree remove` 只删除子目录 (`task*`, `integration`)，但 `/tmp/hyper-loop-worktrees-rN/` 基目录本身残留为空目录。BDD S015 要求 "cleanup_round 被调用后 /tmp/hyper-loop-worktrees-rN/ 不存在"。

### 相关文件
- scripts/hyper-loop.sh (cleanup_round 函数，约 line 595-615)
### 约束
- 只修 scripts/hyper-loop.sh 的 cleanup_round 函数
- 在 worktree 移除循环结束后、函数末尾(但在 `cp verdict.env` 之前)追加 `rm -rf "$WORKTREE_BASE" 2>/dev/null`
- 不改其他函数
### 验收标准
- cleanup_round 执行后 `$WORKTREE_BASE` 目录不存在
- 引用 BDD 场景 S015（worktree 清理：/tmp/hyper-loop-worktrees-rN/ 不存在）

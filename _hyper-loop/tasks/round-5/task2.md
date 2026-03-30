## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `cleanup_round` 函数只删除了 `/tmp/hyper-loop-worktrees-rN/` 下的子目录（task*, integration），但未删除父目录本身，导致空目录残留。BDD S015 要求该目录在清理后不存在。
### 相关文件
- scripts/hyper-loop.sh (line 562-583: cleanup_round 函数)
### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 在 cleanup_round 的 subshell 中，worktree remove 循环之后、cp verdict.env 之前，加 `rm -rf "${WORKTREE_BASE}" 2>/dev/null` 删除父目录
- 保持容错风格（不能因删除失败终止脚本）
### 验收标准
引用 BDD 场景 S015: cleanup_round 调用后 `/tmp/hyper-loop-worktrees-rN/` 不存在

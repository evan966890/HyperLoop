## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] WORKTREE_BASE 父目录未清理，S015 FAIL

cleanup_round 函数（line 563-583）通过 `git worktree remove` 删除了各子目录（task*、integration），分支也被 `branch -D` 删除，tmux windows 也被关闭。但 `/tmp/hyper-loop-worktrees-rN/` 空目录本身未被删除，BDD S015 要求该目录不存在。

### 相关文件
- scripts/hyper-loop.sh (line 562-583, cleanup_round 函数)

### 约束
- 只修 scripts/hyper-loop.sh 中 cleanup_round 函数
- 在 subshell 内、worktree remove 循环之后加 `rmdir`
- 不改 CSS

### 验收标准
- cleanup_round 执行完成后 `/tmp/hyper-loop-worktrees-rN/` 目录不存在
- rmdir 失败不会导致脚本崩溃（需 2>/dev/null 或 || true）
- 引用 BDD 场景 S015

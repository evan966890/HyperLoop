## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] cleanup_round()（L563-583）只移除 task*/integration 子 worktree，未删除基目录 `/tmp/hyper-loop-worktrees-rN/` 本身。BDD S015 要求该目录不存在。
### 相关文件
- scripts/hyper-loop.sh (L562-583, cleanup_round 函数)
### 约束
- 只修 scripts/hyper-loop.sh
- 只改 cleanup_round 函数内部
- 用 rmdir 或 rm -rf 删除基目录，确保只在子目录都已清理后执行
- 不改 CSS
### 验收标准
引用 BDD 场景 S015: cleanup_round 被调用后，/tmp/hyper-loop-worktrees-rN/ 不存在，hyper-loop/rN-* 分支被删除，tmux writer windows 被关闭。

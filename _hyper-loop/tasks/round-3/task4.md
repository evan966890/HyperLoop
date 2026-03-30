## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[Minor] cleanup_round 函数清理了 worktree 子目录和分支，但遗留了父目录 `/tmp/hyper-loop-worktrees-rN/`。多轮运行后 /tmp/ 下会堆积空目录。
### 相关文件
- scripts/hyper-loop.sh (L562-583, cleanup_round 函数)
### 修复方案
在 worktree remove 循环之后、subshell 结束之前，添加一行清理父目录：
```bash
rmdir "${WORKTREE_BASE}" 2>/dev/null || true
```
使用 `rmdir`（而非 `rm -rf`）确保只删除空目录，如果目录非空则安全跳过。
### 约束
- 只修改 scripts/hyper-loop.sh 中 cleanup_round 函数
- 只加一行 rmdir，不改现有清理逻辑
- 不改 CSS
### 验收标准
引用 BDD 场景 S015: Round N 完成后 `/tmp/hyper-loop-worktrees-rN/` 目录不存在

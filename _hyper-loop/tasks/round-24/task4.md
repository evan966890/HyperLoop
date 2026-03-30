## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 两个独立的代码清洁问题：

1. **cmd_status() 重复定义** (line 697-703 和 line 957-970): 函数定义了两次，后者覆盖前者。第一处 (line 697-703) 是简版实现，第二处 (line 957-970) 是增强版（含最佳轮次显示）。第一处为死代码，应删除。

2. **WORKTREE_BASE 目录未清理** (cleanup_round, line 589-610): 函数只清理 worktree 内容（task*/integration），但不删除 `/tmp/hyper-loop-worktrees-rN/` 目录本身。运行 50 轮后 /tmp 下积累 50 个空目录。应在 cleanup_round 的 subshell 末尾（`done` 之后、`)` 之前）加 `rmdir "$WORKTREE_BASE" 2>/dev/null || true`。

### 相关文件
- scripts/hyper-loop.sh (line 697-703 删除; line 589-610 补充 rmdir)
### 约束
- 删除 line 697-703 的第一个 cmd_status() 定义（共 7 行）
- 在 cleanup_round 的 subshell 内、`cp verdict.env` 之后加一行 `rmdir "$WORKTREE_BASE" 2>/dev/null || true`
- 不改动其他逻辑
- 不改 CSS
### 验收标准
引用 BDD 场景 S015: cleanup_round 完成后 `/tmp/hyper-loop-worktrees-rN/` 目录不存在
附加验证: `grep -c 'cmd_status()' scripts/hyper-loop.sh` 应返回 1（只有一处定义）

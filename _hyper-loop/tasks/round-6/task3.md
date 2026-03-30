## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 两个路径/清理相关 bug：

1. **P1-002 worktree 父目录未清理**: `cleanup_round` (L563-583) 移除各 worktree 后，`/tmp/hyper-loop-worktrees-rN/` 空父目录残留，多轮运行后 /tmp 下累积大量空目录。

2. **P1-004 archive_round 引用错误路径**: L770 `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 但实际文件在 `_hyper-loop/context/bdd-specs.md`，复制静默失败（因 `|| true`），归档不完整。

### 相关文件
- scripts/hyper-loop.sh (L562-583, cleanup_round 函数)
  - L582 之后（`) || true` 之前）加入: `rmdir "${WORKTREE_BASE}" 2>/dev/null || true`
- scripts/hyper-loop.sh (L770, archive_round 函数)
  - L770: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` → 改为 `cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md"`
### 约束
- 只修改 scripts/hyper-loop.sh 中 cleanup_round 和 archive_round 函数
- 不改 CSS
- rmdir 而非 rm -rf，确保只删空目录
### 验收标准
引用 BDD 场景 S015: cleanup_round 后 `/tmp/hyper-loop-worktrees-rN/` 目录不存在

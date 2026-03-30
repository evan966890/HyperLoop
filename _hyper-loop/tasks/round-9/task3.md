## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] git worktree add 静默失败——前轮崩溃残留导致 Writer 无法启动但不报错

L124:
```bash
git -C "$PROJECT_ROOT" worktree add "$WT" -b "$BRANCH" 2>/dev/null
```

如果前一轮因崩溃残留了同名 worktree 或分支，此命令静默失败（stderr 被丢弃）。Writer 后续操作找不到 worktree 目录，但不会有明确的错误提示。

### 相关文件
- scripts/hyper-loop.sh (L117-137, start_writers 函数)

### 修复方案
1. 在 for 循环之前加 worktree prune：
```bash
git -C "$PROJECT_ROOT" worktree prune 2>/dev/null || true
```

2. 在 for 循环中 worktree add 之前，清理可能的同名残留分支，并检测创建失败：
```bash
# 清理可能残留的同名分支
git -C "$PROJECT_ROOT" branch -D "$BRANCH" 2>/dev/null || true
# 创建 worktree，失败时跳过该 task
if ! git -C "$PROJECT_ROOT" worktree add "$WT" -b "$BRANCH" 2>&1; then
  echo "  ✗ worktree 创建失败: $WT" >&2
  continue
fi
```

### 约束
- 只修 scripts/hyper-loop.sh 中 start_writers 函数
- 不改 CSS
### 验收标准
引用 BDD 场景 S003: worktree 创建成功；前轮残留时能自动清理并重建

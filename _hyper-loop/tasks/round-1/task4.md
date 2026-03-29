## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件，特别是 hyper-loop.sh 和 bdd-specs.md。

### 问题
[P0] `cleanup_round` 未完全清理 worktree 目录 + `cmd_status` 重复定义

**问题 A — S015 违规：worktree 目录残留**
- `cleanup_round`（行 587-603）通过 `git worktree remove` 逐个删除 task 和 integration worktree
- 但父目录 `/tmp/hyper-loop-worktrees-rN/` 本身未被删除
- S015 要求："Then /tmp/hyper-loop-worktrees-rN/ 不存在"
- 累积运行多轮后，/tmp 下会残留大量空目录

当前代码缺失行（在 for 循环后添加）：
```bash
rm -rf "$WORKTREE_BASE" 2>/dev/null || true
```

**问题 B — cmd_status 重复定义**
- `cmd_status` 在行 686-692 定义了一次（简单版）
- 行 946-958 又定义了一次（增强版，含"最佳轮次"显示）
- bash 中后定义覆盖前定义，所以行 686-692 是死代码
- 死代码增加维护困惑，应删除第一个定义

### 相关文件
- scripts/hyper-loop.sh (行 587-603: cleanup_round 函数; 行 686-692: 第一个 cmd_status)
- _hyper-loop/context/hyper-loop.sh (同步修改)

### 修复方案
1. 在 `cleanup_round` 的 for 循环后（行 601 之后、行 602 之前），添加：
   ```bash
   rm -rf "$WORKTREE_BASE" 2>/dev/null || true
   ```

2. 删除行 686-692 的第一个 `cmd_status` 定义（保留行 946-958 的增强版）

### 约束
- 只修 scripts/hyper-loop.sh 和 _hyper-loop/context/hyper-loop.sh
- 不改 cleanup_round 的其他逻辑
- 两个文件保持完全一致

### 验收标准
- S015: cleanup_round 后 /tmp/hyper-loop-worktrees-rN/ 不存在
- S015: hyper-loop/rN-* 分支被删除（已有逻辑，确认不受影响）
- `bash -n scripts/hyper-loop.sh` 通过

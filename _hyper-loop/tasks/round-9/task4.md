## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] S015 worktree 清理 PARTIAL PASS — cleanup_round 遗留分支未完全删除

Round 8 Tester 报告标记 S015 为 PARTIAL PASS。根据 BDD 规格 S015 要求：
1. `/tmp/hyper-loop-worktrees-rN/` 不存在 ✓
2. `hyper-loop/rN-*` 分支被删除 — 可能未完全清理
3. tmux writer windows 被关闭 ✓

当前 cleanup_round（line 591-606）在 subshell 中遍历 worktree 并删除分支，但：
- line 597 只遍历 `${WORKTREE_BASE}/task*` 和 `integration`，如果 worktree 已被前面的 merge 流程删除（worktree remove），则循环无法获取其 branch name
- 需要额外清理 `hyper-loop/rN-*` 模式的残留分支

### 相关文件
- scripts/hyper-loop.sh (line 586-607)

### 约束
- 只修 scripts/hyper-loop.sh 中 cleanup_round 函数
- 保持 subshell + `set +e` 容错结构
- 不改其他函数

### 验收标准
引用 BDD 场景 S015（worktree 清理）
- cleanup_round 执行后，`git branch | grep "hyper-loop/rN-"` 返回空
- 即使 worktree 目录已不存在，残留分支也被清理
- 清理失败不终止循环（保持 `|| true` 容错）

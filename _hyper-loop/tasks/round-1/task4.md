## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] cleanup_round 未删除 WORKTREE_BASE 父目录 + context/hyper-loop.sh 与 scripts/ 版本不同步。

问题 A: cleanup_round（第 562-583 行）遍历子目录逐个 worktree remove，
  但最后没有 `rm -rf ${WORKTREE_BASE}`。
  BDD S015 要求 "Round N 完成后 /tmp/hyper-loop-worktrees-rN/ 不存在"。

问题 B: _hyper-loop/context/hyper-loop.sh 是旧版本（v5.3），
  而 scripts/hyper-loop.sh 已是 v5.4+。
  Writer 在 worktree 中读 _ctx/hyper-loop.sh（context 副本），
  如果看到旧代码会基于错误理解做修改。

### 相关文件
- scripts/hyper-loop.sh (第 562-583 行: cleanup_round 函数)
- _hyper-loop/context/hyper-loop.sh (整个文件需要与 scripts/ 同步)

### 修复方案
1. 在 cleanup_round subshell 末尾（第 582 行 `) || true` 前）加入：
   ```bash
   rm -rf "${WORKTREE_BASE}" 2>/dev/null
   ```

2. 将 scripts/hyper-loop.sh 内容复制覆盖 _hyper-loop/context/hyper-loop.sh：
   ```bash
   cp scripts/hyper-loop.sh _hyper-loop/context/hyper-loop.sh
   ```

### 约束
- 只修 scripts/hyper-loop.sh 的 cleanup_round 函数
- 只修 _hyper-loop/context/hyper-loop.sh（用 scripts/ 版本覆盖）
- 不改其他函数

### 验收标准
引用 BDD 场景 S015: worktree 清理 — /tmp/hyper-loop-worktrees-rN/ 不存在
引用 BDD 场景 S003: _ctx/ 目录被复制到 worktree（Writer 看到正确代码）
验证：`diff scripts/hyper-loop.sh _hyper-loop/context/hyper-loop.sh` 无差异

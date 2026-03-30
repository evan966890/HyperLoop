## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `build_app` 用 `cd` 改变全局 cwd：line 367 的 `cd "$BUILD_DIR"` 改变了整个 shell 进程的工作目录。当 `cleanup_round` 删除该 worktree 后，进程 cwd 变为悬空（deleted directory）。虽然当前代码全用绝对路径暂时不出错，但任何未来的相对路径使用都会静默失败，是一个定时炸弹。

### 相关文件
- scripts/hyper-loop.sh (363-376)

### 修复方向
用 subshell 隔离 cwd 变更：
```bash
build_app() {
  local BUILD_DIR="$1"
  echo "构建 App..."
  (
    cd "$BUILD_DIR"
    eval "${CACHE_CLEAN:-true}" 2>/dev/null || true
    if eval "${BUILD_CMD:-echo 'no BUILD_CMD'}"; then
      echo "  ✓ 构建成功"
    else
      echo "  ✗ 构建失败"
      exit 1
    fi
  )
}
```
注意：subshell 中 `exit 1` 等价于 `return 1`（从调用者角度看返回码一致）。

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 不改函数签名和返回值语义

### 验收标准
引用 BDD 场景 S007 / S015：构建完成后，cleanup_round 删除 worktree 不影响后续操作
- `build_app` 返回后，`pwd` 仍然是调用前的目录
- 构建成功返回 0，失败返回 1（行为不变）

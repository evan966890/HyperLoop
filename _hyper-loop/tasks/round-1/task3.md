## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件，特别是 hyper-loop.sh 和 bdd-specs.md。

### 问题
[P0] `build_app` 函数使用裸 `cd "$BUILD_DIR"` 永久改变了脚本工作目录，导致后续所有函数在错误的 CWD 下执行。

具体机制：
- 行 364: `cd "$BUILD_DIR"` 将 CWD 切换到 integration worktree
- `build_app` 返回后，CWD 不会自动恢复
- 后续 `run_tester`、`run_reviewers`、`compute_verdict`、`record_result`、`cleanup_round` 都在错误的 CWD 下执行
- 虽然大部分路径使用 `$PROJECT_ROOT` 绝对路径，但 `eval "${BUILD_CMD}"` 中的相对路径（如 `bash -n scripts/hyper-loop.sh`）依赖 CWD
- 在 `cmd_loop` 中，build_app 后 CWD 变成 integration worktree，而 `cleanup_round` 会删除该 worktree → CWD 指向已删除目录 → 下一轮的命令可能失败

当前代码：
```bash
build_app() {
  local BUILD_DIR="$1"
  echo "构建 App..."
  cd "$BUILD_DIR"        # ← CWD 永久改变
  eval "${CACHE_CLEAN:-true}" 2>/dev/null || true
  if eval "${BUILD_CMD:-echo 'no BUILD_CMD'}"; then
```

### 相关文件
- scripts/hyper-loop.sh (行 361-373: build_app 函数)
- _hyper-loop/context/hyper-loop.sh (同步修改)

### 修复方案
用子 shell 包裹整个 build_app 函数体，确保 cd 不泄露到调用方：

```bash
build_app() {
  local BUILD_DIR="$1"
  echo "构建 App..." >&2
  (
    cd "$BUILD_DIR"
    eval "${CACHE_CLEAN:-true}" 2>/dev/null || true
    if eval "${BUILD_CMD:-echo 'no BUILD_CMD'}"; then
      echo "  ✓ 构建成功" >&2
      exit 0
    else
      echo "  ✗ 构建失败" >&2
      exit 1
    fi
  )
}
```

注意：子 shell 的 exit code 会自动传递给调用方的 `if ! build_app`。
同时将 echo 改为 `>&2`，避免潜在的 stdout 捕获问题。

### 约束
- 只修 scripts/hyper-loop.sh 和 _hyper-loop/context/hyper-loop.sh 中的 build_app 函数
- 不改函数签名和返回值语义
- 两个文件保持完全一致

### 验收标准
- S001: 循环跑满 N 轮后正常退出（不崩溃）——build 后 CWD 不变
- S007: Tester 在 build 后正常启动
- `bash -n scripts/hyper-loop.sh` 通过

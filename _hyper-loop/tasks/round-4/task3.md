## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `build_app()` 函数 (line 367) 使用裸 `cd "$BUILD_DIR"` 改变全局工作目录。

当前代码 line 364-376:
```bash
build_app() {
  local BUILD_DIR="$1"
  echo "构建 App..."
  cd "$BUILD_DIR"
  eval "${CACHE_CLEAN:-true}" 2>/dev/null || true
  if eval "${BUILD_CMD:-echo 'no BUILD_CMD'}"; then
    echo "  ✓ 构建成功"
    return 0
  else
    echo "  ✗ 构建失败"
    return 1
  fi
}
```

`build_app` 返回后脚本工作目录变为 BUILD_DIR。目前后续代码恰好都用绝对路径所以不出问题，但这是安全隐患 — 任何新增的相对路径代码都会在错误目录执行。

### 相关文件
- scripts/hyper-loop.sh (line 364-376)

### 修复方案
将 `build_app()` 的函数体包在 subshell 中隔离 `cd`：
```bash
build_app() {
  local BUILD_DIR="$1"
  echo "构建 App..."
  (
    cd "$BUILD_DIR"
    eval "${CACHE_CLEAN:-true}" 2>/dev/null || true
    if eval "${BUILD_CMD:-echo 'no BUILD_CMD'}"; then
      echo "  ✓ 构建成功"
      exit 0
    else
      echo "  ✗ 构建失败"
      exit 1
    fi
  )
}
```
subshell 中用 `exit` 代替 `return`，外层通过 `$?` 获取退出码。

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 不改 build_app 的外部调用方式（仍然 `if ! build_app "$DIR"; then ...`）
- 确保 `bash -n` 通过

### 验收标准
引用 BDD 场景 S001: 循环跑满后正常退出（不因工作目录错误崩溃）

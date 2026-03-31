## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P2] 代码质量：废弃函数残留 + `build_app` 的 `cd` 未隔离

1. **废弃函数残留**（~line 59-98）：`start_agent` 和 `kill_agent` 是旧版 tmux 交互模式的遗留。
   当前 Writer 已改为 `codex exec` 非交互模式（`start_writers`），Tester/Reviewer 用 `claude -p` 管道。
   这两个函数没有任何调用方，是死代码。

2. **`build_app` 的裸 `cd`**（~line 412）：`cd "$BUILD_DIR"` 改变了整个脚本的工作目录。
   虽然后续函数都用 `$PROJECT_ROOT` 绝对路径，但这是一个潜在的陷阱。
   应用子 shell 隔离：
   ```bash
   build_app() {
     local BUILD_DIR="$1"
     echo "构建 App..."
     (
       cd "$BUILD_DIR"
       eval "${CACHE_CLEAN:-true}" 2>/dev/null || true
       eval "${BUILD_CMD:-echo 'no BUILD_CMD'}"
     )
     local RC=$?
     if [[ $RC -eq 0 ]]; then
       echo "  ✓ 构建成功"
     else
       echo "  ✗ 构建失败"
     fi
     return $RC
   }
   ```

**影响**: 代码可读性降低（评审者看到废弃代码会扣分），`cd` 泄漏影响鲁棒性。

### 相关文件
- scripts/hyper-loop.sh (行 59-98, `start_agent`/`kill_agent` 函数)
- scripts/hyper-loop.sh (行 409-421, `build_app` 函数)

### 修复策略
1. 用 grep 确认 `start_agent` 和 `kill_agent` 在脚本中没有任何调用：
   ```bash
   grep -n 'start_agent\|kill_agent' scripts/hyper-loop.sh
   ```
   只应出现在函数定义处。如果有调用方，不要删除。
2. 删除 `start_agent` 函数（~line 59-93）和 `kill_agent` 函数（~line 95-98）
3. 用子 shell `( )` 包裹 `build_app` 中的 `cd` + `eval` 语句，并用子 shell 退出码作为返回值
4. 运行 `bash -n scripts/hyper-loop.sh` 确认语法正确

### 约束
- 只修 scripts/hyper-loop.sh 的两个区域：
  - 行 59-98（删除废弃函数）
  - 行 409-421（`build_app` 子 shell 隔离）
- 不改其他函数
- 不加新功能

### 验收标准
- `bash -n scripts/hyper-loop.sh` 通过
- `grep -c 'start_agent\|kill_agent' scripts/hyper-loop.sh` 输出 0
- `build_app` 执行后不改变调用者的 working directory
- BDD S003: Writer worktree 创建不受影响（确认 start_agent 确实无调用方）

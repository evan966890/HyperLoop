## 修复任务: TASK-5
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `build_app()` L367 执行 `cd "$BUILD_DIR"` 污染主进程工作目录。当 `cleanup_round()` 删除该 worktree 目录后，主进程 CWD 变成悬空目录，后续轮次使用相对路径会出错。

### 相关文件
- scripts/hyper-loop.sh (L364-375, build_app 函数)

### 约束
- 只修 scripts/hyper-loop.sh
- 方案：将 build_app 函数体包裹在 subshell `( )` 中执行，或在函数末尾 `cd "$PROJECT_ROOT"`
- 不改 CSS

### 验收标准
- S001: 多轮循环不崩溃 — build_app 执行后主进程 CWD 仍为 PROJECT_ROOT
- S015: cleanup_round 删除 worktree 后脚本正常继续下一轮

## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] `build_app()` 使用 `cd "$BUILD_DIR"` (第 364 行) 永久改变 shell 工作目录，但从不恢复。

在 `cmd_loop()` 中，`build_app` 成功后脚本继续在 integration worktree 目录下运行。
随后 `cleanup_round` 删除该 worktree，导致 shell 的 CWD 指向一个已不存在的目录。
下一轮循环虽然大部分用绝对路径，但任何相对路径操作（包括子进程默认 CWD）都会失败。
这是导致多轮循环不稳定的潜在根因之一。

### 相关文件
- scripts/hyper-loop.sh (第 361-372 行, `build_app` 函数)

### 约束
- 只修 `build_app` 函数
- 不改函数签名和返回值语义
- 不改 CSS

### 验收标准
- S001: 循环跑满 3 轮后正常退出（不崩溃）
- `build_app` 返回后，`pwd` 仍为调用前的目录（用 subshell 包裹或 pushd/popd）

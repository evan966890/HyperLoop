## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `cmd_status()` 函数重复定义两次（L670-676 和 L932-944），bash 中后定义覆盖前定义，第一个是死代码。

### 相关文件
- scripts/hyper-loop.sh (L670-676, 第一个 cmd_status 定义)
- scripts/hyper-loop.sh (L932-944, 第二个 cmd_status 定义，功能更完整)

### 约束
- 只修 scripts/hyper-loop.sh
- 删除 L670-676 的第一个定义，保留 L932-944 的第二个定义（功能更完整，含最佳轮次显示）
- 不改 CSS

### 验收标准
- 脚本中只有一个 `cmd_status()` 定义
- `bash -n scripts/hyper-loop.sh` 通过

## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] cmd_status 函数重复定义（L694 和 L954），第一个是死代码

`cmd_status` 在脚本中定义了两次：
- 第一次（L694-700）：简化版，只显示 tmux windows 和 results.tsv
- 第二次（L954-966）：完整版，额外显示"最佳轮次"

Bash 中后定义覆盖前定义，所以功能不受影响。但第一个定义是死代码，增加维护混乱。

### 相关文件
- scripts/hyper-loop.sh (L694-700)

### 约束
- 只删除 L694-700 的第一个 `cmd_status` 定义
- 保留 L954-966 的第二个（完整）定义不动
- 不改 CSS
- 删除后用 `bash -n` 确认语法正确

### 验收标准
- 脚本中只有一个 `cmd_status` 函数定义
- `bash -n scripts/hyper-loop.sh` 通过
- 执行 `hyper-loop.sh status` 功能不变（仍显示 tmux、results.tsv、最佳轮次）

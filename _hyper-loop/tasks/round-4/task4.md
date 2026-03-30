## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `cmd_status()` 函数在 line 670 和 line 930 重复定义。bash 后定义覆盖前定义，line 670-676 版本是死代码。

第一个定义 (line 670-676): 简版，只显示 tmux windows 和 results.tsv
第二个定义 (line 930-942): 完整版，额外显示"最佳轮次"

Bash 后定义覆盖前定义所以功能不受影响，但死代码影响可维护性和可读性。

### 相关文件
- scripts/hyper-loop.sh (line 670-676)

### 修复方案
删除 line 670-676 的第一个 `cmd_status()` 定义（含其前后空行），保留 line 930-942 的完整版本不动。

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 只删除第一个 cmd_status 定义，不动第二个
- 确保 `bash -n` 通过

### 验收标准
引用 BDD 场景 S001: 脚本中只有一个 `cmd_status` 定义，`hyper-loop.sh status` 功能不变

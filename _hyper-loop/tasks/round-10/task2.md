## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1-002] cmd_status() 函数被定义了两次，第一个成为死代码

第 697-703 行定义了一个简单版 `cmd_status()`，第 957-969 行定义了一个更完整的版本
（含"最佳轮次"显示）。Bash 后定义覆盖前定义，第一个永远不会被执行。

### 相关文件
- scripts/hyper-loop.sh (第 697-703 行: 第一个 cmd_status 定义 — 需删除)
- scripts/hyper-loop.sh (第 957-969 行: 第二个 cmd_status 定义 — 保留)

### 约束
- 只改 scripts/hyper-loop.sh
- 删除第 697-703 行的第一个 `cmd_status()` 定义（含函数体）
- 保留第 957-969 行的第二个定义不动
- 不改其他逻辑、不改 CSS

### 验收标准
- `grep -c 'cmd_status()' scripts/hyper-loop.sh` 结果为 1（只剩一个定义）
- `bash -n scripts/hyper-loop.sh` 语法检查通过
- 引用 BDD 场景 S001: 循环仍能正常运行（status 命令不受影响）

## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] 两个独立 bug：

**Bug A: 连续失败回退永远不触发（BEST_ROUND=0 时）**

`cmd_loop()` 行 922 的回退条件：
```bash
if [[ "$CONSECUTIVE_REJECTS" -ge 5 ]] && [[ "$BEST_ROUND" -gt 0 ]]; then
```
当没有任何轮次被 ACCEPTED 过时，`BEST_ROUND` 保持初始值 0，条件永远不满足。
12 轮连续失败后循环仍然继续无意义地运行。

修复：当 `BEST_ROUND=0` 且连续失败 >= 5 时，输出警告日志但不执行回退（因为没有可回退的状态），
同时重置 `CONSECUTIVE_REJECTS=0` 避免每轮都输出警告。

**Bug B: cmd_status 重复定义**

`cmd_status()` 在行 697-703 和行 957-969 定义了两次。第二次覆盖第一次。
第一次定义（697-703）是死代码，应删除。

### 相关文件
- scripts/hyper-loop.sh (行 697-703, 第一个 cmd_status)
- scripts/hyper-loop.sh (行 920-932, 连续失败回退逻辑)

### 约束
- 只修上述两处
- 不改 CSS
- 不改其他函数

### 验收标准
- 连续 5+ 轮失败且 BEST_ROUND=0 时：不崩溃、输出警告、重置计数器
- `cmd_status` 只有一个定义
- `bash -n scripts/hyper-loop.sh` 语法通过
- 引用 BDD 场景 S013（连续 5 轮失败自动回退）、S001（loop 命令启动死循环）

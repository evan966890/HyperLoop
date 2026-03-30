## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] Tester 无法读取角色定义文件，导致 Tester 完全无法正常工作。
`run_tester()` 调用 `start_agent` 时传入的 INIT 文件路径为 `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md`，但该文件实际位于 `${PROJECT_ROOT}/_hyper-loop/context/templates/TESTER_INIT.md`。

Tester 收到的注入消息让它读取一个不存在的文件，因此无法获取角色定义，导致整个测试流程失效。这是连续 19 轮全部 0 分的两个根因之一。

### 相关文件
- scripts/hyper-loop.sh (第 383-384 行，`run_tester` 函数中 `start_agent` 的第三个参数)

### 约束
- 只修 scripts/hyper-loop.sh
- 只改 `run_tester` 函数中 `start_agent` 调用的 INIT 路径参数
- 不改其他函数、不重构

### 验收标准
引用 BDD 场景 S007: Tester 启动并生成报告
- `start_agent "tester"` 的 INIT 参数指向 `${PROJECT_ROOT}/_hyper-loop/context/templates/TESTER_INIT.md`
- 该文件确实存在于磁盘

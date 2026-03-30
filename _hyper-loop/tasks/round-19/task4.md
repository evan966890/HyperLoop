## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P2] 两处代码清理问题：
1. `run_tester` 超时消息（line 421）写 "10 分钟" 但实际超时是 900s = 15 分钟，应改为 "15 分钟"
2. `cmd_status` 函数重复定义：line 697-703 是死代码（被 line 957 的同名函数覆盖），应删除

### 相关文件
- scripts/hyper-loop.sh (line 421, run_tester 超时消息)
- scripts/hyper-loop.sh (line 697-703, 重复的 cmd_status 函数)

### 约束
- 只修 scripts/hyper-loop.sh
- line 421: 将 "10 分钟" 改为 "15 分钟"
- line 697-703: 删除第一个 cmd_status 函数定义（保留 line 957 的完整版）
- 不改其他函数

### 验收标准
引用 BDD 场景 S007: Tester 启动并生成报告（超时消息准确性）
- 超时消息与实际超时时间一致（15 分钟）
- 无重复函数定义
- bash -n scripts/hyper-loop.sh 通过

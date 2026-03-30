## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] STOP 文件优雅退出不符合 BDD 规格要求。
BDD S014 要求 "脚本正常退出（exit 0）"，但当前实现在检测到 STOP 文件后仅使用 `break` 跳出 while 循环，然后函数自然结束。虽然效果上等价于 exit 0（因为 break 后没有其他逻辑会导致非零退出），但严格来说不符合规格的 "exit 0" 要求。

应在 `break` 后增加显式 `exit 0`，或在循环结束后、函数末尾加 `exit 0`，以明确保证退出码为 0。

### 相关文件
- scripts/hyper-loop.sh (第 851-854 行，`cmd_loop` 函数中 STOP 文件检查逻辑)

### 约束
- 只修 scripts/hyper-loop.sh
- 只改 STOP 文件检测后的退出逻辑
- 不影响正常循环结束的退出行为

### 验收标准
引用 BDD 场景 S014: STOP 文件优雅退出
- 检测到 STOP 文件后脚本以 exit code 0 退出
- STOP 文件被删除
- 正常跑满 N 轮的场景不受影响

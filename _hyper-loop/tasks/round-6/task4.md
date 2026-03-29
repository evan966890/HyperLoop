## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1-5] `cmd_round` 格式框缺少右侧 `║`（第 640 行）+ [P1-4] timeout polyfill 死代码（第 17-21 行）

两个小问题合并修复：

1. 第 640 行 `echo "║  HyperLoop Round $ROUND 开始      "` 缺少右侧 `║` 闭合符，导致 box 画框不完整。应改为 `echo "║  HyperLoop Round $ROUND 开始      ║"`。

2. 第 17-21 行定义了 macOS timeout polyfill 函数，但脚本中所有超时控制均由 polling loop + sleep 实现，`timeout` 函数从未被实际调用。应在注释中标注此函数的用途，或在至少一个合适位置实际使用它（如 Writer/Tester 超时等待中），消除死代码。推荐方案：添加注释说明保留原因（为将来扩展准备，且 S016 BDD 要求 timeout 可用）。

### 相关文件
- scripts/hyper-loop.sh (行 17-21, 640)

### 约束
- 只修 scripts/hyper-loop.sh
- 格式框修复需保证 `╔`、`║`、`╚` 三行宽度对齐
- timeout polyfill 仅加注释说明，不改功能逻辑

### 验收标准
引用 BDD 场景 S016: macOS timeout 兼容（timeout 函数仍可用）
- `bash -n scripts/hyper-loop.sh` 通过
- 格式框视觉对称

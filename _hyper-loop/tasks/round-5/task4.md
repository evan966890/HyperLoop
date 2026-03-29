## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `timeout` 函数定义但从未使用（第 17-21 行）+ `cmd_round` 格式框不完整（第 639-641 行）

两个独立的小问题合并处理：

1. 脚本定义了 macOS 兼容的 `timeout` polyfill，但实际的超时控制（Writer、Tester、Reviewer）全部使用 polling loop + sleep 实现，从未调用 `timeout` 函数。这是死代码。

2. `cmd_round` 函数中的 Unicode box drawing 格式框缺少右侧 `║` 关闭符：
   ```
   echo "║  HyperLoop Round $ROUND 开始      "
   ```
   应为：
   ```
   echo "║  HyperLoop Round $ROUND 开始      ║"
   ```

### 相关文件
- scripts/hyper-loop.sh (第 17-21 行：timeout polyfill)
- scripts/hyper-loop.sh (第 640 行：格式框)

### 修复方案
1. 保留 `timeout` polyfill（BDD S016 要求"timeout 函数可用"），但添加注释说明当前仅作为 polyfill 备用，未被直接调用。
2. 补全第 640 行右侧 `║`。

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- timeout polyfill 不删除（BDD S016 要求其存在）

### 验收标准
引用 BDD 场景 S016：macOS timeout 兼容 — timeout 函数仍然可用
引用 BDD 场景 S001：loop 命令启动死循环 — 格式输出正确

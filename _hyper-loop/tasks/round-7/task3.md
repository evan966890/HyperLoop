## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] `cmd_status()` 函数重复定义 — L686-692 和 L946-958 各有一份。

bash 使用后定义的版本 (L946)，L686 的旧版本被静默覆盖。L946 版本功能更完整（多了"最佳轮次"显示），所以实际行为正确。但重复定义是代码腐化，维护者可能修错版本。

### 相关文件
- _hyper-loop/context/hyper-loop.sh L686-692 (旧 cmd_status，需删除)
- _hyper-loop/context/hyper-loop.sh L946-958 (新 cmd_status，保留)

### 约束
- 只修改 _hyper-loop/context/hyper-loop.sh
- 删除 L686-692 的旧 `cmd_status()` 定义（含前面的空行）
- 不修改 L946 版本的内容
- 不改动其他函数

### 验收标准
引用 BDD 场景 S001（loop 命令启动死循环 — 脚本整体健壮性）：
- `grep -c 'cmd_status()' _hyper-loop/context/hyper-loop.sh` 输出 1（只有一处定义）
- `bash -n _hyper-loop/context/hyper-loop.sh` 通过
- `hyper-loop.sh status` 仍正常输出（含"最佳轮次"行）

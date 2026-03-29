## 修复任务: TASK-4
### 上下文
先读 _hyper-loop/context/ 下所有文件。
### 问题
[P1] cmd_status 函数重复定义，第一个版本成为死代码。

- 第一个定义：`scripts/hyper-loop.sh:694-700`
- 第二个定义：`scripts/hyper-loop.sh:954-970`（估计行号）
- bash 使用最后定义的版本，所以行 694-700 的版本永远不会被执行
- 两个版本功能不同：第二个版本更完整（包含最佳轮次显示），应保留第二个，删除第一个

### 相关文件
- scripts/hyper-loop.sh (行 694-700, 第一个 cmd_status 定义 — 删除)
- scripts/hyper-loop.sh (行 954 起, 第二个 cmd_status 定义 — 保留)

### 约束
- 只修改 scripts/hyper-loop.sh
- 只删除第一个定义（行 694-700），保留第二个
- 确保删除后相邻代码的空行整洁
- 不改 CSS

### 验收标准
- `bash -n scripts/hyper-loop.sh` 通过
- `grep -c 'cmd_status()' scripts/hyper-loop.sh` 返回 1
- 脚本运行时 `hyper-loop.sh status` 仍可正常输出

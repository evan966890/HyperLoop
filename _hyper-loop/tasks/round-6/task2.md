## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1-1] `cmd_status` 函数重复定义（第 694 行和第 954 行）

`cmd_status` 被定义了两次。Bash 后定义覆盖前定义，第一个（第 694 行）是死代码。第二个（第 954 行）功能更完整（多了"最佳轮次"展示）。应删除第一个定义。

### 相关文件
- scripts/hyper-loop.sh (行 694-700: 第一个定义，应删除)
- scripts/hyper-loop.sh (行 954-966: 第二个定义，保留)

### 约束
- 只修 scripts/hyper-loop.sh
- 删除第 694-700 行的第一个 `cmd_status` 定义
- 保留第 954 行的第二个定义不动

### 验收标准
- `bash -n scripts/hyper-loop.sh` 通过
- `grep -c 'cmd_status()' scripts/hyper-loop.sh` 返回 1

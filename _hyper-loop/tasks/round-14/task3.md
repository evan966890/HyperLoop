## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] cmd_status 重复定义

`cmd_status()` 函数在脚本中定义了两次：
- 第一次约 line 700（简版：只显示 tmux windows 和 results.tsv）
- 第二次约 line 995（增强版：还显示最佳轮次）

第二次定义覆盖第一次，第一次成为死代码。应删除第一个定义，保留功能更完整的第二个。

### 相关文件
- scripts/hyper-loop.sh (第一个 cmd_status 函数，约 line 697-704)

### 约束
- 只删除第一个 `cmd_status()` 定义（约 line 697-704 的 5-6 行）
- 保留第二个 `cmd_status()` 定义不动
- 不改其他函数
- 不改 CSS

### 验收标准
- `bash -n scripts/hyper-loop.sh` 通过
- `grep -c 'cmd_status()' scripts/hyper-loop.sh` 返回 1（只有一个定义）
